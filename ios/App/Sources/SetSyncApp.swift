import SwiftData
import SwiftUI

@main
struct SetSyncApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var garminSyncService: GarminSyncService
    private let healthKitService: HealthKitService
    private let geminiExerciseClassifier: GeminiExerciseClassifier

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
        // either one are visible to @Query in the tab views without a
        // separate cross-context sync step. healthKitService is built
        // first now: GarminSyncService takes it as a dependency so it can
        // auto-export a session to Apple Health the instant the watch's
        // own SESSION_EVENT: STOP arrives.
        let context = container.mainContext
        let health = HealthKitService(modelContext: context)
        healthKitService = health
        _garminSyncService = StateObject(wrappedValue: GarminSyncService(modelContext: context, healthKitService: health))
        geminiExerciseClassifier = GeminiExerciseClassifier()

        // specs/modules/04-history-and-navigation.md §2: one-time pre-seed
        // of the exercise catalog, no-op once it's non-empty.
        ExerciseLibrarySeeder.seedIfNeeded(context: context)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(garminSyncService)
                .environment(\.healthKitService, healthKitService)
                .environment(\.geminiExerciseClassifier, geminiExerciseClassifier)
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
