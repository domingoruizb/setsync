import ConnectIQ
import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §1: root screen — daily summary
/// (steps/calories), the active session's live set list, and Garmin
/// pairing status/action.
struct DashboardView: View {
    @EnvironmentObject private var garminSyncService: GarminSyncService
    @Environment(\.healthKitService) private var healthKitService

    @Query(sort: \DailySummaryMetrics.date, order: .reverse)
    private var dailyMetrics: [DailySummaryMetrics]

    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    private var todayMetrics: DailySummaryMetrics? {
        dailyMetrics.first { Calendar.current.isDateInToday($0.date) }
    }

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    dailySummaryContent
                }

                Section("Active Session") {
                    activeSessionContent
                }

                Section("Garmin Watch") {
                    garminStatusContent
                }
            }
            .navigationTitle("SetSync")
            .onAppear {
                requestHealthDataAndSync()
            }
            .refreshable {
                await refreshHealthData()
            }
        }
    }

    // specs/modules/02-ios-core-and-sync.md §1 "Resumen diario".
    @ViewBuilder
    private var dailySummaryContent: some View {
        if let metrics = todayMetrics {
            HStack {
                metricTile(title: "Steps", value: "\(metrics.stepCount)")
                metricTile(title: "Active kcal", value: String(format: "%.0f", metrics.activeEnergyBurnedKcal))
                metricTile(title: "Resting kcal", value: String(format: "%.0f", metrics.restingEnergyBurnedKcal))
            }
        } else {
            Text("No health data yet")
                .foregroundStyle(.secondary)
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // specs/modules/02-ios-core-and-sync.md §1 "estado de sesión": a
    // compact banner: tapping it opens the full live set table
    // (ActiveWorkoutView, Task 4.1).
    @ViewBuilder
    private var activeSessionContent: some View {
        if let session = activeSession {
            NavigationLink {
                ActiveWorkoutView(session: session)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session in progress")
                            .font(.headline)
                        Text("\(session.sets.count) set(s) so far")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            Text("No active session")
                .foregroundStyle(.secondary)
        }
    }

    // specs/modules/02-ios-core-and-sync.md §2 step 1 (pairing entry point).
    @ViewBuilder
    private var garminStatusContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(garminSyncService.pairedDevice?.friendlyName ?? "No device paired")
                if let status = garminSyncService.deviceStatus {
                    Text(String(describing: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Pair") {
                garminSyncService.selectDevice()
            }
        }
    }

    private func requestHealthDataAndSync() {
        healthKitService?.requestAuthorization { _ in
            healthKitService?.syncTodaySnapshot()
        }
    }

    private func refreshHealthData() async {
        await withCheckedContinuation { continuation in
            guard let healthKitService else {
                continuation.resume()
                return
            }
            healthKitService.syncTodaySnapshot {
                continuation.resume()
            }
        }
    }
}

// MARK: - HealthKitService environment injection

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitService? = nil
}

// MARK: - MuscleClassifierService environment injection

private struct MuscleClassifierServiceKey: EnvironmentKey {
    static let defaultValue: MuscleClassifierService? = nil
}

extension EnvironmentValues {
    var healthKitService: HealthKitService? {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }

    var muscleClassifierService: MuscleClassifierService? {
        get { self[MuscleClassifierServiceKey.self] }
        set { self[MuscleClassifierServiceKey.self] = newValue }
    }
}
