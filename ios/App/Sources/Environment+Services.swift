import SwiftUI

/// Custom environment key for `GeminiExerciseClassifier`, the one plain
/// (non-`ObservableObject`) service injected once in `SetSyncApp` — it
/// doesn't need `@EnvironmentObject`'s change-publishing, just DI.
/// `HealthKitService` used to have a matching key here too; removed along
/// with the service itself when `TodayView`'s weekly-dashboard redesign
/// dropped the daily steps/calories summary that was its only consumer.

private struct GeminiExerciseClassifierKey: EnvironmentKey {
    static let defaultValue: GeminiExerciseClassifier? = nil
}

extension EnvironmentValues {
    var geminiExerciseClassifier: GeminiExerciseClassifier? {
        get { self[GeminiExerciseClassifierKey.self] }
        set { self[GeminiExerciseClassifierKey.self] = newValue }
    }
}
