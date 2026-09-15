import Foundation
import SwiftData

/// specs/01-system-spec.md §1.2
@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var reps: Int
    var weightKg: Double
    var setDurationSeconds: Int
    var restDurationSeconds: Int
    var detectedAutomatically: Bool
    var timestamp: Date

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        reps: Int,
        weightKg: Double,
        setDurationSeconds: Int,
        restDurationSeconds: Int,
        detectedAutomatically: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.exercise = exercise
        self.reps = reps
        self.weightKg = weightKg
        self.setDurationSeconds = setDurationSeconds
        self.restDurationSeconds = restDurationSeconds
        self.detectedAutomatically = detectedAutomatically
        self.timestamp = timestamp
    }
}
