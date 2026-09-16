import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §4 "Selector de ejercicio": a
/// searchable list of existing `Exercise`s with an inline "create new"
/// fallback. Presented as a sheet from `ActiveWorkoutView`; assigns the
/// chosen/created exercise directly onto `workoutSet` and persists it.
///
/// Task 6.2: the inline single-muscle quick-picker was replaced by
/// `ExerciseCreationView` (AI classification + editable chips + preview),
/// presented as its own sheet on top of this one.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let workoutSet: WorkoutSet

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var isPresentingCreation = false

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // `.localizedStandardContains` (not `.localizedCaseInsensitiveContains`)
    // so searching with or without accents finds the same results — e.g.
    // "sentadilla" must match "sentadilla" regardless of tildes, and a
    // search like "peso muerto" should find it whether or not the user's
    // keyboard/autocorrect added diacritics. It's also case-insensitive,
    // matching the previous behavior.
    private var filteredExercises: [Exercise] {
        guard !trimmedSearchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedStandardContains(trimmedSearchText) }
    }

    // specs/modules/02-ios-core-and-sync.md §4: "Opción directa: 'Crear
    // nuevo ejercicio' si la búsqueda no arroja resultados" — shown
    // whenever the trimmed search text has no exact (accent/case-
    // insensitive) match among existing exercises.
    private var showsCreateOption: Bool {
        !trimmedSearchText.isEmpty &&
            !exercises.contains { $0.name.compare(trimmedSearchText, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if showsCreateOption {
                    Section {
                        Button {
                            isPresentingCreation = true
                        } label: {
                            Text("Crear \u{201C}\(trimmedSearchText)\u{201D}…")
                        }
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
                                    // Shows only the first primary muscle
                                    // in this compact row; the full set is
                                    // visible in ExerciseCreationView/
                                    // ExerciseDetailView.
                                    Text(exercise.primaryMuscles.first.map(\.displayName) ?? "—")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            // Task 5.3/6.4: history/detail entry point,
                            // separate from the row's select action.
                            NavigationLink {
                                ExerciseDetailView(exercise: exercise)
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Buscar ejercicio...")
            .navigationTitle("Seleccionar Ejercicio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingCreation) {
                ExerciseCreationView(initialName: trimmedSearchText) { exercise in
                    modelContext.insert(exercise)
                    select(exercise)
                }
            }
        }
    }

    private func select(_ exercise: Exercise) {
        workoutSet.exercise = exercise
        try? modelContext.save()
        dismiss()
    }
}
