import SwiftData
import SwiftUI

/// Task 5.3: no dedicated spec subsection exists for this view — scope was
/// fixed directly with the user against the models already frozen in
/// Task 1.2 (`Exercise`, `WorkoutSet`). Per-exercise history grouped by
/// day, with PR and most-recent volume highlighted in the header.
struct ExerciseHistoryView: View {
    let exercise: Exercise

    @Query private var allSets: [WorkoutSet]

    private var exerciseSets: [WorkoutSet] {
        allSets
            .filter { $0.exercise?.id == exercise.id }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // Progression indicator 1: all-time max weight for this exercise.
    private var personalRecordKg: Double? {
        exerciseSets.map(\.weightKg).max()
    }

    // Progression indicator 2: reps × weight of the single most recent set.
    private var mostRecentVolumeKg: Double? {
        guard let mostRecent = exerciseSets.first else { return nil }
        return Double(mostRecent.reps) * mostRecent.weightKg
    }

    private struct DayGroup: Identifiable {
        let date: Date
        let sets: [WorkoutSet]
        var id: Date { date }
    }

    private var groupedByDay: [DayGroup] {
        let groups = Dictionary(grouping: exerciseSets) { Calendar.current.startOfDay(for: $0.timestamp) }
        return groups
            .map { DayGroup(date: $0.key, sets: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                progressionHeader
            }

            if groupedByDay.isEmpty {
                Text("No history yet for this exercise")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedByDay) { day in
                    Section(formattedDate(day.date)) {
                        ForEach(day.sets) { set in
                            HStack {
                                Text("\(set.reps) reps")
                                Spacer()
                                Text("\(set.weightKg, specifier: "%.1f") kg")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("\(day.sets.count) set(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.name.capitalized)
    }

    private var progressionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(personalRecordKg.map { String(format: "%.1f kg", $0) } ?? "—")
                    .font(.title3)
                    .bold()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Recent volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(mostRecentVolumeKg.map { String(format: "%.0f kg", $0) } ?? "—")
                    .font(.title3)
                    .bold()
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
