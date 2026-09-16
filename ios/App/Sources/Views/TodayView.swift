import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §1, restructured in Task 6.3
/// (specs/modules/04-history-and-navigation.md §1): "Today" tab — daily
/// HealthKit summary, the active session's banner, and today's muscle
/// activation. Renamed from `DashboardView`; Garmin pairing/status moved
/// out to `SettingsView` (Tab 4).
struct TodayView: View {
    @Environment(\.healthKitService) private var healthKitService

    @Query(sort: \DailySummaryMetrics.date, order: .reverse)
    private var dailyMetrics: [DailySummaryMetrics]

    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    @Query(sort: \WorkoutSet.timestamp)
    private var allSets: [WorkoutSet]

    private var todayMetrics: DailySummaryMetrics? {
        dailyMetrics.first { Calendar.current.isDateInToday($0.date) }
    }

    private var activeSession: WorkoutSession? {
        sessions.first { $0.status == .inProgress }
    }

    // specs/modules/03-ai-and-muscle-map.md §2 (Task 5.2 decision): scored
    // over today's WorkoutSets, matching the "Today" section above rather
    // than a single session or an all-time total.
    private var todaysMuscleScores: [MuscleGroup: Double] {
        let todaysSets = allSets.filter { Calendar.current.isDateInToday($0.timestamp) }
        return MuscleHeatMapView.muscleScores(from: todaysSets)
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

                Section("Muscle Activation") {
                    MuscleHeatMapView(scores: todaysMuscleScores)
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
