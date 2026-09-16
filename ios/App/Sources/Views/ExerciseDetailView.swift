import SwiftData
import SwiftUI

/// specs/modules/04-history-and-navigation.md §4: per-exercise progression
/// and history. Renamed/extended from Task 5.3's `ExerciseHistoryView`
/// (same day-grouped history + PR + recent volume) with the two stats
/// Task 6.4 adds: estimated max 1RM and all-time total sets/reps.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Query private var allSets: [WorkoutSet]

    private var exerciseSets: [WorkoutSet] {
        allSets
            .filter { $0.exercise?.id == exercise.id }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // PR / Top Weight: all-time max weight for this exercise.
    private var personalRecordKg: Double? {
        exerciseSets.map(\.weightKg).max()
    }

    // Recent volume: reps × weight of the single most recent set (Task 5.3).
    private var mostRecentVolumeKg: Double? {
        guard let mostRecent = exerciseSets.first else { return nil }
        return Double(mostRecent.reps) * mostRecent.weightKg
    }

    // specs/modules/04-history-and-navigation.md §4: Epley formula,
    // weight * (1 + reps / 30), evaluated per set — the max across all
    // sets, not necessarily the same set as the raw PR (a heavier single
    // rarely beats a slightly lighter set done for more reps).
    private var estimatedOneRepMaxKg: Double? {
        exerciseSets.map { $0.weightKg * (1 + Double($0.reps) / 30.0) }.max()
    }

    private var totalSets: Int {
        exerciseSets.count
    }

    private var totalReps: Int {
        exerciseSets.reduce(0) { $0 + $1.reps }
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
                Text("Sin historial para este ejercicio todavía")
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
                        Text("\(day.sets.count) series")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.name.capitalized)
    }

    private var progressionHeader: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(title: "Peso máx.", value: personalRecordKg.map { String(format: "%.1f kg", $0) })
            statTile(title: "1RM est.", value: estimatedOneRepMaxKg.map { String(format: "%.1f kg", $0) })
            statTile(title: "Series totales", value: totalSets > 0 ? "\(totalSets)" : nil)
            statTile(title: "Reps totales", value: totalReps > 0 ? "\(totalReps)" : nil)
            statTile(title: "Volumen reciente", value: mostRecentVolumeKg.map { String(format: "%.0f kg", $0) })
        }
    }

    private func statTile(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.title3)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
