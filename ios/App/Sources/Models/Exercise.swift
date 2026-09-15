import Foundation
import SwiftData

/// specs/01-system-spec.md §1.1
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var primaryMuscle: MuscleGroup
    var secondaryMuscles: [MuscleGroup]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.createdAt = createdAt
    }
}
