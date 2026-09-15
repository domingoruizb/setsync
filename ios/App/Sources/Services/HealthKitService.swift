import Foundation
import HealthKit
import SwiftData

/// specs/modules/02-ios-core-and-sync.md §3: read-only HealthKit snapshot
/// (steps, active/basal energy) for "today," persisted into
/// DailySummaryMetrics. Meant to be queried on demand (app open /
/// DashboardView, per §3 "Frecuencia") — not wired into any View yet, since
/// DashboardView is Task 3.4.
///
/// Defensive by design: every entry point checks
/// `HKHealthStore.isHealthDataAvailable()` first, every HealthKit call uses
/// `try?`/optional-binding instead of propagating errors, and a failed or
/// unauthorized individual statistic silently contributes 0 rather than
/// blocking the other two or crashing — this is a best-effort dashboard
/// feature, not a critical path.
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

    /// Requests read-only authorization for the three quantity types.
    /// Never throws or crashes: on a device/simulator without HealthKit,
    /// or if the user denies access, `completion(false)` is called instead.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        let readTypes: Set<HKObjectType> = [stepCountType, activeEnergyType, basalEnergyType]
        healthStore.requestAuthorization(toShare: [], read: readTypes) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
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
