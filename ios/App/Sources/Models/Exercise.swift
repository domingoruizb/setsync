import Foundation
import SwiftData

/// specs/01-system-spec.md §1.1, extended in Task 6.1
/// (specs/modules/04-history-and-navigation.md §2): `primaryMuscle` became
/// `primaryMuscles: [MuscleGroup]` (plural), `category`/`isCustom` were
/// added, and `createdAt` was dropped (never used by any built feature).
/// Breaking SwiftData schema change accepted with data loss (no
/// SchemaMigrationPlan) — user-confirmed pre-launch decision.
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup]
    var isCustom: Bool

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "",
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        isCustom: Bool
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.isCustom = isCustom
    }
}
