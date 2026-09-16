import SwiftData
import SwiftUI

/// specs/modules/04-history-and-navigation.md §1/§3: "Exercises" tab —
/// the full catalog (pre-seeded + custom), searchable, navigating to
/// `ExerciseHistoryView` (extended into `ExerciseDetailView` in Task 6.4).
struct ExercisesListView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                NavigationLink {
                    ExerciseHistoryView(exercise: exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name.capitalized)
                        if !exercise.category.isEmpty {
                            Text(exercise.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Exercises")
        }
    }
}
