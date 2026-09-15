import SwiftData
import SwiftUI

@main
struct SetSyncApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var garminSyncService: GarminSyncService
    private let healthKitService: HealthKitService

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: WorkoutSession.self, WorkoutSet.self, Exercise.self, DailySummaryMetrics.self
            )
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        modelContainer = container

        // Both services share the container's main context so writes from
        // either one are visible to @Query in DashboardView without a
        // separate cross-context sync step.
        let context = container.mainContext
        _garminSyncService = StateObject(wrappedValue: GarminSyncService(modelContext: context))
        healthKitService = HealthKitService(modelContext: context)
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(garminSyncService)
                .environment(\.healthKitService, healthKitService)
                .onOpenURL { url in
                    // specs/modules/02-ios-core-and-sync.md §2 step 1: Garmin
                    // Connect Mobile calls back into the `setsync-ciq` scheme
                    // (Task 3.1) after device selection.
                    garminSyncService.handleOpenURL(url)
                }
        }
        .modelContainer(modelContainer)
    }
}
