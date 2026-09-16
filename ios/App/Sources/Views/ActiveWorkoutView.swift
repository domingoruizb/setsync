import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §4: live table of the active
/// session's `WorkoutSet`s, ordered by `timestamp`. `session` is a live
/// SwiftData model instance (not a separate `@Query`), so `session.sets`
/// keeps updating in place as `GarminSyncService` inserts new sets.
///
/// Tapping a row's exercise name opens `ExercisePickerView` (Task 4.2).
/// The "Copy Down" replicate button (Task 4.3) appears on the last row
/// with an assigned exercise, when at least one later row is unlabeled.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let session: WorkoutSession

    @State private var setPendingExerciseSelection: WorkoutSet?

    private var orderedSets: [WorkoutSet] {
        session.sets.sorted { $0.timestamp < $1.timestamp }
    }

    // specs/modules/02-ios-core-and-sync.md §4: "Solo presente en la
    // última serie con exercise != nil si existe al menos una serie
    // posterior con exercise == nil." Since this is the *last* labeled
    // row, any row after it is unlabeled by definition — so the only
    // extra condition needed is "a row exists after it at all."
    private var replicateSourceIndex: Int? {
        guard let lastLabeledIndex = orderedSets.lastIndex(where: { $0.exercise != nil }) else {
            return nil
        }
        return lastLabeledIndex < orderedSets.count - 1 ? lastLabeledIndex : nil
    }

    var body: some View {
        List {
            if orderedSets.isEmpty {
                Text("Esperando series de tu reloj…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, set in
                    setRow(ordinal: index + 1, index: index, set: set)
                }
            }
        }
        .navigationTitle("Entrenamiento Activo")
        .toolbar {
            // Field-test finding: if the watch's SESSION_EVENT: STOP never
            // arrives (BLE drop, app killed on the watch, etc.), there was
            // previously no way to end the session from the phone at all.
            ToolbarItem(placement: .primaryAction) {
                Button("Finalizar Entrenamiento") {
                    finishWorkout()
                }
            }
        }
        .sheet(item: $setPendingExerciseSelection) { set in
            ExercisePickerView(workoutSet: set)
        }
    }

    // Manual, Bluetooth-independent equivalent of the watch's
    // SESSION_EVENT: STOP handling (GarminSyncService.handleSessionEvent) —
    // same effect (status = .completed, endDate set), triggered locally.
    private func finishWorkout() {
        session.endDate = Date()
        session.status = .completed
        try? modelContext.save()
        dismiss()
    }

    private func setRow(ordinal: Int, index: Int, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Serie \(ordinal)")
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
                Text(set.exercise?.name ?? "Seleccionar ejercicio…")
                    .font(.subheadline)
                    .foregroundStyle(set.exercise == nil ? .secondary : .primary)
            }
            .buttonStyle(.plain)

            if index == replicateSourceIndex {
                Button {
                    copyDown(from: index)
                } label: {
                    Label("Copiar hacia abajo", systemImage: "arrow.turn.right.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    // specs/modules/02-ios-core-and-sync.md §4: propagates the source
    // row's exercise to every subsequent orphan (exercise == nil) set,
    // stopping at the first already-labeled set or the end of the list.
    // Reps/weightKg are never touched (invariant). Persisted immediately.
    private func copyDown(from sourceIndex: Int) {
        guard let exercise = orderedSets[sourceIndex].exercise else { return }
        for set in orderedSets[(sourceIndex + 1)...] {
            guard set.exercise == nil else { break }
            set.exercise = exercise
        }
        try? modelContext.save()
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
