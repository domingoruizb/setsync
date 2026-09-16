import SwiftUI

/// Custom environment keys for the plain (non-`ObservableObject`) services
/// injected once in `SetSyncApp` — `HealthKitService`/`GeminiExerciseClassifier`
/// don't need `@EnvironmentObject`'s change-publishing, just DI. Extracted
/// out of `DashboardView`/`TodayView` in Task 6.3 now that more than one
/// tab's views depend on them.

private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitService? = nil
}

private struct GeminiExerciseClassifierKey: EnvironmentKey {
    static let defaultValue: GeminiExerciseClassifier? = nil
}

extension EnvironmentValues {
    var healthKitService: HealthKitService? {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }

    var geminiExerciseClassifier: GeminiExerciseClassifier? {
        get { self[GeminiExerciseClassifierKey.self] }
        set { self[GeminiExerciseClassifierKey.self] = newValue }
    }
}
