import Foundation
import SwiftData

/// specs/modules/04-history-and-navigation.md §2: pre-loads ~25 common
/// strength exercises with `primaryMuscles`/`secondaryMuscles` already
/// assigned (`isCustom = false`, no AI classification needed), inserted
/// once when the catalog is empty. Categories are a free-form grouping
/// (Push/Pull/Legs/Core), not part of the frozen `MuscleGroup` taxonomy.
enum ExerciseLibrarySeeder {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            return
        }

        for entry in library {
            context.insert(entry.makeExercise())
        }
        try? context.save()
    }

    private struct SeedEntry {
        let name: String
        let category: String
        let primaryMuscles: [MuscleGroup]
        let secondaryMuscles: [MuscleGroup]

        func makeExercise() -> Exercise {
            Exercise(
                name: name,
                category: category,
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles,
                isCustom: false
            )
        }
    }

    // specs/01-system-spec.md §1.1: names stored lowercase.
    private static let library: [SeedEntry] = [
        // Push
        SeedEntry(name: "bench press", category: "Push", primaryMuscles: [.chestMiddle], secondaryMuscles: [.tricepsLongHead, .tricepsLateralHead, .deltoidAnterior]),
        SeedEntry(name: "incline bench press", category: "Push", primaryMuscles: [.chestUpper], secondaryMuscles: [.deltoidAnterior, .tricepsLongHead]),
        SeedEntry(name: "overhead press", category: "Push", primaryMuscles: [.deltoidAnterior], secondaryMuscles: [.tricepsLongHead, .trapsUpper]),
        SeedEntry(name: "dumbbell shoulder press", category: "Push", primaryMuscles: [.deltoidAnterior], secondaryMuscles: [.deltoidLateral, .tricepsLateralHead]),
        SeedEntry(name: "lateral raise", category: "Push", primaryMuscles: [.deltoidLateral], secondaryMuscles: []),
        SeedEntry(name: "triceps pushdown", category: "Push", primaryMuscles: [.tricepsLateralHead], secondaryMuscles: [.tricepsLongHead]),
        SeedEntry(name: "dips", category: "Push", primaryMuscles: [.chestLower], secondaryMuscles: [.tricepsLongHead, .deltoidAnterior]),

        // Pull
        SeedEntry(name: "pull-up", category: "Pull", primaryMuscles: [.lats], secondaryMuscles: [.biceps, .rhomboids]),
        SeedEntry(name: "barbell row", category: "Pull", primaryMuscles: [.lats], secondaryMuscles: [.rhomboids, .trapsMiddle, .biceps]),
        SeedEntry(name: "seated cable row", category: "Pull", primaryMuscles: [.rhomboids], secondaryMuscles: [.lats, .trapsMiddle, .biceps]),
        SeedEntry(name: "lat pulldown", category: "Pull", primaryMuscles: [.lats], secondaryMuscles: [.biceps, .rhomboids]),
        SeedEntry(name: "face pull", category: "Pull", primaryMuscles: [.deltoidPosterior], secondaryMuscles: [.trapsMiddle, .rhomboids]),
        SeedEntry(name: "barbell curl", category: "Pull", primaryMuscles: [.biceps], secondaryMuscles: [.forearms]),
        SeedEntry(name: "dumbbell hammer curl", category: "Pull", primaryMuscles: [.biceps], secondaryMuscles: [.forearms]),

        // Legs
        SeedEntry(name: "deadlift", category: "Legs", primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes, .lowerBack, .trapsUpper, .forearms]),
        SeedEntry(name: "romanian deadlift", category: "Legs", primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes, .lowerBack]),
        SeedEntry(name: "back squat", category: "Legs", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings, .adductors]),
        SeedEntry(name: "front squat", category: "Legs", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes]),
        SeedEntry(name: "leg press", category: "Legs", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings]),
        SeedEntry(name: "walking lunge", category: "Legs", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings, .adductors]),
        SeedEntry(name: "standing calf raise", category: "Legs", primaryMuscles: [.calves], secondaryMuscles: []),
        SeedEntry(name: "hip thrust", category: "Legs", primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings]),

        // Core
        SeedEntry(name: "plank", category: "Core", primaryMuscles: [.absUpper], secondaryMuscles: [.absLower, .obliques]),
        SeedEntry(name: "hanging leg raise", category: "Core", primaryMuscles: [.absLower], secondaryMuscles: [.obliques]),
        SeedEntry(name: "cable woodchopper", category: "Core", primaryMuscles: [.obliques], secondaryMuscles: [.absUpper])
    ]
}
