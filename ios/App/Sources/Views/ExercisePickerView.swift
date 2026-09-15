import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §4 "Selector de ejercicio": a
/// searchable list of existing `Exercise`s with an inline "create new"
/// fallback. Presented as a sheet from `ActiveWorkoutView`; assigns the
/// chosen/created exercise directly onto `workoutSet` and persists it.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.muscleClassifierService) private var muscleClassifierService

    let workoutSet: WorkoutSet

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var newExerciseMuscle: MuscleGroup = .chestUpper

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredExercises: [Exercise] {
        guard !trimmedSearchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    // specs/modules/02-ios-core-and-sync.md §4: "Opción directa: 'Crear
    // nuevo ejercicio' si la búsqueda no arroja resultados" — shown
    // whenever the trimmed search text has no exact (case-insensitive)
    // match among existing exercises.
    private var showsCreateOption: Bool {
        !trimmedSearchText.isEmpty &&
            !exercises.contains { $0.name.caseInsensitiveCompare(trimmedSearchText) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if showsCreateOption {
                    Section {
                        createExerciseRow
                    }
                }

                Section {
                    ForEach(filteredExercises) { exercise in
                        HStack {
                            Button {
                                select(exercise)
                            } label: {
                                HStack {
                                    Text(exercise.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(displayName(for: exercise.primaryMuscle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            // Task 5.3: history/detail entry point,
                            // separate from the row's select action.
                            NavigationLink {
                                ExerciseHistoryView(exercise: exercise)
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var createExerciseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                createAndAssign()
            } label: {
                Text("Create \u{201C}\(trimmedSearchText)\u{201D}…")
            }

            Picker("Primary muscle", selection: $newExerciseMuscle) {
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    Text(displayName(for: muscle)).tag(muscle)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func select(_ exercise: Exercise) {
        workoutSet.exercise = exercise
        try? modelContext.save()
        dismiss()
    }

    // specs/01-system-spec.md §1.1: Exercise.name is stored lowercase.
    private func createAndAssign() {
        let exercise = Exercise(
            name: trimmedSearchText.lowercased(),
            primaryMuscle: newExerciseMuscle
        )
        modelContext.insert(exercise)
        select(exercise)
        classifyMuscleGroups(for: exercise)
    }

    // specs/modules/03-ai-and-muscle-map.md §1: fired only on Exercise
    // creation (never for selecting an existing one), asynchronously, in
    // the background — the sheet has already dismissed by the time this
    // resolves. If the service has no key, is offline, or fails to parse
    // a valid response, `classify` returns nil and the manually-picked
    // `newExerciseMuscle` this exercise was created with is left as-is.
    private func classifyMuscleGroups(for exercise: Exercise) {
        guard let muscleClassifierService else { return }
        Task {
            guard let result = await muscleClassifierService.classify(exerciseName: exercise.name) else {
                return
            }
            exercise.primaryMuscle = result.primaryMuscleGroup
            exercise.secondaryMuscles = result.secondaryMuscleGroups
            try? modelContext.save()
        }
    }

    private func displayName(for muscle: MuscleGroup) -> String {
        muscle.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
