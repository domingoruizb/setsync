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

    // specs/01-system-spec.md §1.1: names stored lowercase. Refactor
    // "Localización al Español": names/categories are now common Spanish
    // gym terminology — this only affects newly seeded catalogs (seeding
    // is a one-time, empty-catalog-only operation), existing installs
    // keep whatever English names they already persisted.
    private static let library: [SeedEntry] = [
        // Empuje
        SeedEntry(name: "press de banca", category: "Empuje", primaryMuscles: [.chestMiddle], secondaryMuscles: [.tricepsLongHead, .tricepsLateralHead, .deltoidAnterior]),
        SeedEntry(name: "press de banca inclinado", category: "Empuje", primaryMuscles: [.chestUpper], secondaryMuscles: [.deltoidAnterior, .tricepsLongHead]),
        SeedEntry(name: "press militar", category: "Empuje", primaryMuscles: [.deltoidAnterior], secondaryMuscles: [.tricepsLongHead, .trapsUpper]),
        SeedEntry(name: "press de hombro con mancuernas", category: "Empuje", primaryMuscles: [.deltoidAnterior], secondaryMuscles: [.deltoidLateral, .tricepsLateralHead]),
        SeedEntry(name: "elevaciones laterales", category: "Empuje", primaryMuscles: [.deltoidLateral], secondaryMuscles: []),
        SeedEntry(name: "extensión de tríceps en polea", category: "Empuje", primaryMuscles: [.tricepsLateralHead], secondaryMuscles: [.tricepsLongHead]),
        SeedEntry(name: "fondos en paralelas", category: "Empuje", primaryMuscles: [.chestLower], secondaryMuscles: [.tricepsLongHead, .deltoidAnterior]),

        // Tracción
        SeedEntry(name: "dominadas", category: "Tracción", primaryMuscles: [.lats], secondaryMuscles: [.biceps, .rhomboids]),
        SeedEntry(name: "remo con barra", category: "Tracción", primaryMuscles: [.lats], secondaryMuscles: [.rhomboids, .trapsMiddle, .biceps]),
        SeedEntry(name: "remo sentado en polea", category: "Tracción", primaryMuscles: [.rhomboids], secondaryMuscles: [.lats, .trapsMiddle, .biceps]),
        SeedEntry(name: "jalón al pecho", category: "Tracción", primaryMuscles: [.lats], secondaryMuscles: [.biceps, .rhomboids]),
        SeedEntry(name: "jalón facial", category: "Tracción", primaryMuscles: [.deltoidPosterior], secondaryMuscles: [.trapsMiddle, .rhomboids]),
        SeedEntry(name: "curl de bíceps con barra", category: "Tracción", primaryMuscles: [.biceps], secondaryMuscles: [.forearms]),
        SeedEntry(name: "curl martillo con mancuernas", category: "Tracción", primaryMuscles: [.biceps], secondaryMuscles: [.forearms]),

        // Piernas
        SeedEntry(name: "peso muerto convencional", category: "Piernas", primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes, .lowerBack, .trapsUpper, .forearms]),
        SeedEntry(name: "peso muerto rumano", category: "Piernas", primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes, .lowerBack]),
        SeedEntry(name: "sentadilla trasera", category: "Piernas", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings, .adductors]),
        SeedEntry(name: "sentadilla frontal", category: "Piernas", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes]),
        SeedEntry(name: "prensa de piernas", category: "Piernas", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings]),
        SeedEntry(name: "zancadas caminando", category: "Piernas", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes, .hamstrings, .adductors]),
        SeedEntry(name: "elevación de talones de pie", category: "Piernas", primaryMuscles: [.calves], secondaryMuscles: []),
        SeedEntry(name: "empuje de cadera", category: "Piernas", primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings]),

        // Abdomen
        SeedEntry(name: "plancha", category: "Abdomen", primaryMuscles: [.absUpper], secondaryMuscles: [.absLower, .obliques]),
        SeedEntry(name: "elevación de piernas colgado", category: "Abdomen", primaryMuscles: [.absLower], secondaryMuscles: [.obliques]),
        SeedEntry(name: "leñador en polea", category: "Abdomen", primaryMuscles: [.obliques], secondaryMuscles: [.absUpper])
    ]
}
