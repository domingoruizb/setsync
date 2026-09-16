import Foundation
import SwiftData

/// specs/modules/04-history-and-navigation.md §2: pre-loads ~25 common
/// strength exercises with `primaryMuscles`/`secondaryMuscles` already
/// assigned (`isCustom = false`, no AI classification needed).
///
/// The catalog was originally seeded in English, then translated to
/// Spanish in code — but that translation only ever affected *newly*
/// seeded catalogs (`seedIfNeeded` only inserted when the table was
/// completely empty), so an install that had already seeded before the
/// translation kept its English names permanently in its local SQLite
/// store. Rather than asking to reinstall the app (losing every recorded
/// session/set — completely unacceptable, unlike the one-time
/// accept-data-loss call made for the `Exercise` schema change back in
/// Task 6.1, which had no session history to lose yet), this does an
/// in-place migration: existing `Exercise` rows are fetched and renamed
/// directly (never deleted/recreated), so `id` and every `WorkoutSet`'s
/// `exercise` relationship stay exactly as they were — only the `name`
/// string changes on the same object.
enum ExerciseLibrarySeeder {
    static func seedIfNeeded(context: ModelContext) {
        migrateEnglishNamesToSpanish(context: context)
        insertMissingLibraryEntries(context: context)
    }

    // In-place rename, not delete-and-reinsert: mutating `exercise.name`
    // on the same fetched object preserves its `id` and every
    // `WorkoutSet.exercise` back-reference untouched. Scoped to
    // `!isCustom` only — a user-created exercise that happens to share
    // one of these English names (e.g. they deliberately typed "Bench
    // Press") is left alone, since this migration exists to fix this
    // project's own seed data, not to rewrite anything the user typed.
    // Naturally idempotent and cheap on every later launch: once a row's
    // `name` is already the Spanish value, it no longer matches any
    // dictionary key, so this becomes a same-cost no-op comparison pass.
    private static func migrateEnglishNamesToSpanish(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        guard let existingExercises = try? context.fetch(descriptor), !existingExercises.isEmpty else {
            return
        }

        var didChange = false
        for exercise in existingExercises where !exercise.isCustom {
            let normalizedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let spanishName = englishToSpanishNames[normalizedName], exercise.name != spanishName {
                exercise.name = spanishName
                didChange = true
            }
        }

        if didChange {
            try? context.save()
        }
    }

    // Covers both a fresh install (catalog empty, everything gets
    // inserted) and a partially-migrated one (only whatever's missing by
    // name gets added) — unlike the old `seedIfNeeded`, which skipped
    // seeding entirely once the table held even one row.
    private static func insertMissingLibraryEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existingNames = Set((try? context.fetch(descriptor))?.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? [])

        var didInsert = false
        for entry in library where !existingNames.contains(entry.name) {
            context.insert(entry.makeExercise())
            didInsert = true
        }

        if didInsert {
            try? context.save()
        }
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

    // Maps this catalog's original English seed names (lowercase, as they
    // were stored before the Spanish-localization refactor) to their
    // Spanish replacement — the exact same 1:1 correspondence used when
    // the `library` array below was first translated, so an existing
    // install ends up with identical names to a fresh install's seed.
    private static let englishToSpanishNames: [String: String] = [
        "bench press": "press de banca",
        "incline bench press": "press de banca inclinado",
        "overhead press": "press militar",
        "dumbbell shoulder press": "press de hombro con mancuernas",
        "lateral raise": "elevaciones laterales",
        "triceps pushdown": "extensión de tríceps en polea",
        "dips": "fondos en paralelas",
        "pull-up": "dominadas",
        "barbell row": "remo con barra",
        "seated cable row": "remo sentado en polea",
        "lat pulldown": "jalón al pecho",
        "face pull": "jalón facial",
        "barbell curl": "curl de bíceps con barra",
        "dumbbell hammer curl": "curl martillo con mancuernas",
        "deadlift": "peso muerto convencional",
        "romanian deadlift": "peso muerto rumano",
        "back squat": "sentadilla trasera",
        "front squat": "sentadilla frontal",
        "leg press": "prensa de piernas",
        "walking lunge": "zancadas caminando",
        "standing calf raise": "elevación de talones de pie",
        "hip thrust": "empuje de cadera",
        "plank": "plancha",
        "hanging leg raise": "elevación de piernas colgado",
        "cable woodchopper": "leñador en polea"
    ]

    // specs/01-system-spec.md §1.1: names stored lowercase. Names/
    // categories are common Spanish gym terminology.
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
