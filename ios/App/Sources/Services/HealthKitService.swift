import Foundation
import HealthKit
import SwiftData

/// specs/modules/02-ios-core-and-sync.md §3: read-only HealthKit snapshot
/// (steps, active/basal energy) for "today," persisted into
/// DailySummaryMetrics, queried on demand (app open / TodayView).
///
/// Post-launch addition: also writes completed workouts to Apple Health
/// (`saveWorkout(session:)`) so a free HealthKit-reading app — Strava's own
/// Health sync, specifically, now that its direct upload API requires a
/// paid subscription — can pick them up with no third-party integration
/// of SetSync's own, matching this project's zero-cost stance.
///
/// Defensive by design: every entry point checks
/// `HKHealthStore.isHealthDataAvailable()` first, every HealthKit call uses
/// `try?`/optional-binding instead of propagating errors, and a failed or
/// unauthorized individual statistic silently contributes 0 rather than
/// blocking the other two or crashing — this is a best-effort feature, not
/// a critical path, for both reading and writing.
final class HealthKitService {

    private let healthStore = HKHealthStore()
    private let modelContext: ModelContext

    // specs/modules/02-ios-core-and-sync.md §3: the three read-only
    // quantity types. `quantityType(forIdentifier:)` is the long-standing
    // HealthKit API (unlike the newer `HKQuantityType(.stepCount)` sugar,
    // it's guaranteed available at this project's iOS 17.0 deployment
    // target); force-unwrapped since these are well-known built-in
    // identifiers Apple guarantees resolve to a non-nil type.
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Requests read-only authorization for the three quantity types plus
    /// write authorization for `HKWorkoutType.workoutType()` (needed by
    /// `saveWorkout(session:)` below), and — critically — is what makes
    /// SetSync appear at all under Ajustes → Privacidad y seguridad →
    /// Salud → Acceso y dispositivos: an app is only listed there once it
    /// has actually called `requestAuthorization` at least once, so this
    /// must run unconditionally at launch (called from `RootTabView.task`)
    /// rather than only lazily the first time a save is attempted. Never
    /// throws or crashes: on a device/simulator without HealthKit,
    /// `completion(false)` is called instead. `success` here only reflects
    /// whether the request itself resolved, not which individual
    /// permissions were granted for the *read* types (HealthKit
    /// deliberately never reports read grant-vs-deny, for privacy) — but
    /// share/write authorization status (checked explicitly in
    /// `saveWorkout` below) is reliably introspectable, since the app is
    /// the one creating that data.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        let readTypes: Set<HKObjectType> = [stepCountType, activeEnergyType, basalEnergyType]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if let error {
                print("[HealthKitService] requestAuthorization (launch) failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    enum SaveWorkoutError: LocalizedError {
        case notAvailable
        case sessionNotFinished
        case authorizationDenied
        case underlying(Error?)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Health no está disponible en este dispositivo."
            case .sessionNotFinished:
                return "Termina el entrenamiento antes de guardarlo en Salud."
            case .authorizationDenied:
                return "SetSync no tiene permiso para escribir en Salud. Actívalo en Ajustes → Privacidad y seguridad → Salud → SetSync → Datos y acceso."
            case .underlying(let error):
                return error?.localizedDescription ?? "Error desconocido al guardar en Salud."
            }
        }
    }

    /// Writes a completed `WorkoutSession` to Apple Health as an
    /// `HKWorkout` (`.traditionalStrengthTraining`), so any app that reads
    /// from HealthKit — Strava's own free Health sync included, now that
    /// its direct API requires a paid subscription — can pick it up
    /// without SetSync needing its own paid/third-party integration.
    /// Guards against duplicates via `session.isSyncedToHealth` (set only
    /// after `healthStore.save` actually succeeds) and against saving an
    /// unfinished session (`endDate == nil`). Safe to call from either the
    /// automatic finish-workout trigger or the manual button in
    /// `SessionDetailView` — calling it again on an already-synced session
    /// is a same-cost no-op, not a second HKWorkout.
    ///
    /// Always (re-)requests authorization immediately before attempting
    /// the save, per Apple's own guidance, instead of only trusting an
    /// earlier one-time request elsewhere in the app (`RootTabView.task`):
    /// calling `requestAuthorization` again when already authorized just
    /// invokes its completion immediately with no UI, so this is safe and
    /// cheap on every call, and removes any dependency on that earlier
    /// call having actually run/succeeded first.
    func saveWorkout(session: WorkoutSession, completion: ((Result<Void, SaveWorkoutError>) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(.failure(.notAvailable))
            return
        }
        guard !session.isSyncedToHealth else {
            completion?(.success(()))
            return
        }
        guard let endDate = session.endDate else {
            completion?(.failure(.sessionNotFinished))
            return
        }

        let workoutType = HKObjectType.workoutType()
        healthStore.requestAuthorization(toShare: [workoutType], read: []) { [weak self] _, authError in
            guard let self else { return }
            if let authError {
                print("[HealthKitService] saveWorkout requestAuthorization failed: \(authError.localizedDescription)")
            }

            guard self.healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
                print("[HealthKitService] workout share authorization status: \(self.healthStore.authorizationStatus(for: workoutType).rawValue) (not .sharingAuthorized)")
                DispatchQueue.main.async {
                    completion?(.failure(.authorizationDenied))
                }
                return
            }

            let metadata: [String: Any] = [
                HKMetadataKeyWorkoutBrandName: "SetSync",
                HKMetadataKeyIndoorWorkout: true,
                // Not a standard HealthKit metadata key — Apple has no
                // official "workout notes" field, and there's no
                // guarantee any given reading app (including Strava)
                // surfaces an arbitrary metadata string as its own
                // activity description. Included on a best-effort basis
                // regardless, since it costs nothing to attach.
                "SetSyncWorkoutSummary": self.workoutSummary(for: session)
            ]

            let workout = HKWorkout(
                activityType: .traditionalStrengthTraining,
                start: session.startDate,
                end: endDate,
                duration: endDate.timeIntervalSince(session.startDate),
                totalEnergyBurned: nil,
                totalDistance: nil,
                metadata: metadata
            )

            self.healthStore.save(workout) { success, saveError in
                if let saveError {
                    print("[HealthKitService] save(workout:) failed: \(saveError.localizedDescription)")
                }
                DispatchQueue.main.async {
                    if success {
                        session.isSyncedToHealth = true
                        try? self.modelContext.save()
                        completion?(.success(()))
                    } else {
                        completion?(.failure(.underlying(saveError)))
                    }
                }
            }
        }
    }

    // "Exercise: N series, N reps, N kg" per exercise (in the order first
    // performed), plus a total-volume line — a plain-text summary of
    // exactly what this task asked for (ejercicios, series, repeticiones,
    // volumen total). Sets with no assigned exercise are skipped (nothing
    // meaningful to name), but still count toward the total volume below.
    private func workoutSummary(for session: WorkoutSession) -> String {
        let orderedSets = session.sets.sorted { $0.timestamp < $1.timestamp }
        guard !orderedSets.isEmpty else {
            return "Entrenamiento de fuerza registrado con SetSync."
        }

        struct ExerciseTotals {
            let name: String
            var setCount = 0
            var totalReps = 0
            var volumeKg = 0.0
        }

        var order: [UUID] = []
        var totalsByExerciseId: [UUID: ExerciseTotals] = [:]
        var totalVolumeKg = 0.0

        for set in orderedSets {
            totalVolumeKg += Double(set.reps) * set.weightKg
            guard let exercise = set.exercise else { continue }
            if totalsByExerciseId[exercise.id] == nil {
                order.append(exercise.id)
                totalsByExerciseId[exercise.id] = ExerciseTotals(name: exercise.name.capitalized)
            }
            totalsByExerciseId[exercise.id]?.setCount += 1
            totalsByExerciseId[exercise.id]?.totalReps += set.reps
            totalsByExerciseId[exercise.id]?.volumeKg += Double(set.reps) * set.weightKg
        }

        var lines = order.compactMap { id -> String? in
            guard let totals = totalsByExerciseId[id] else { return nil }
            return "\(totals.name): \(totals.setCount) series, \(totals.totalReps) reps, \(Int(totals.volumeKg)) kg"
        }
        lines.append("Volumen total: \(Int(totalVolumeKg)) kg")
        return lines.joined(separator: "\n")
    }

    /// specs/modules/02-ios-core-and-sync.md §3: queries today's totals and
    /// persists/updates the `DailySummaryMetrics` snapshot for today.
    func syncTodaySnapshot(completion: (() -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?()
            return
        }

        let group = DispatchGroup()
        var stepCount = 0.0
        var activeEnergyKcal = 0.0
        var restingEnergyKcal = 0.0

        group.enter()
        queryDailyTotal(for: stepCountType, unit: .count()) { value in
            stepCount = value
            group.leave()
        }

        group.enter()
        queryDailyTotal(for: activeEnergyType, unit: .kilocalorie()) { value in
            activeEnergyKcal = value
            group.leave()
        }

        group.enter()
        queryDailyTotal(for: basalEnergyType, unit: .kilocalorie()) { value in
            restingEnergyKcal = value
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.persistSnapshot(
                stepCount: Int(stepCount),
                activeEnergyKcal: activeEnergyKcal,
                restingEnergyKcal: restingEnergyKcal
            )
            completion?()
        }
    }

    // specs/modules/02-ios-core-and-sync.md §3: "HKStatisticsQuery
    // acumulado desde las 00:00:00 hasta el instante actual" (local time).
    private func queryDailyTotal(
        for type: HKQuantityType,
        unit: HKUnit,
        completion: @escaping (Double) -> Void
    ) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            guard error == nil, let sum = statistics?.sumQuantity() else {
                completion(0)
                return
            }
            completion(sum.doubleValue(for: unit))
        }

        healthStore.execute(query)
    }

    // Update-in-place if today's snapshot already exists, otherwise insert
    // a new one — `date` is the local midnight for today, matching
    // DailySummaryMetrics' unique-per-day key.
    private func persistSnapshot(stepCount: Int, activeEnergyKcal: Double, restingEnergyKcal: Double) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailySummaryMetrics>()
        let existing = (try? modelContext.fetch(descriptor))?.first { $0.date == today }

        if let existing {
            existing.stepCount = stepCount
            existing.activeEnergyBurnedKcal = activeEnergyKcal
            existing.restingEnergyBurnedKcal = restingEnergyKcal
        } else {
            let snapshot = DailySummaryMetrics(
                date: today,
                stepCount: stepCount,
                activeEnergyBurnedKcal: activeEnergyKcal,
                restingEnergyBurnedKcal: restingEnergyKcal
            )
            modelContext.insert(snapshot)
        }

        try? modelContext.save()
    }
}
