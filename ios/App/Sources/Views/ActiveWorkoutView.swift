import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §4: live table of the active
/// session's `WorkoutSet`s, ordered by `timestamp`. `session` is a live
/// SwiftData model instance (not a separate `@Query`), so `session.sets`
/// keeps updating in place as `GarminSyncService` inserts new sets.
///
/// Tapping a row's exercise name opens `ExercisePickerView` (Task 4.2). A
/// reserved comment marks exactly where Task 4.3's "Copy Down" button will
/// slot in — not implemented here.
struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @State private var setPendingExerciseSelection: WorkoutSet?

    private var orderedSets: [WorkoutSet] {
        session.sets.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        List {
            if orderedSets.isEmpty {
                Text("Waiting for sets from your watch…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, set in
                    setRow(ordinal: index + 1, set: set)
                }
            }
        }
        .navigationTitle("Active Workout")
        .sheet(item: $setPendingExerciseSelection) { set in
            ExercisePickerView(workoutSet: set)
        }
    }

    private func setRow(ordinal: Int, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Set \(ordinal)")
                    .font(.headline)
                Spacer()
                Text("\(set.reps) reps")
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(set.weightKg, specifier: "%.1f") kg")
            }

            HStack {
                Label(formattedDuration(set.setDurationSeconds), systemImage: "stopwatch")
                Spacer()
                Label(formattedDuration(set.restDurationSeconds), systemImage: "bed.double")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Task 4.2: searchable exercise dropdown with inline creation.
            Button {
                setPendingExerciseSelection = set
            } label: {
                Text(set.exercise?.name ?? "Select exercise…")
                    .font(.subheadline)
                    .foregroundStyle(set.exercise == nil ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            // Task 4.3: "Copy Down" button goes here — visible only on the
            // last set with exercise != nil when a later set has
            // exercise == nil (specs/modules/02-ios-core-and-sync.md §4).
        }
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
