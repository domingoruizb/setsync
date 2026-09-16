import SwiftUI

/// specs/modules/04-history-and-navigation.md §4: session header (start/
/// end/duration) and sets grouped by exercise. Deliberately minimal for
/// Task 6.3 (navigation restructure) — Task 6.5 extends this same view
/// with the per-session Muscle Map and activation legend, the same
/// incremental pattern `ExerciseHistoryView` (Task 5.3) → `ExerciseDetailView`
/// (Task 6.4) already follows, rather than building a throwaway stub now.
struct SessionDetailView: View {
    let session: WorkoutSession

    private var orderedSets: [WorkoutSet] {
        session.sets.sorted { $0.timestamp < $1.timestamp }
    }

    private struct ExerciseGroup: Identifiable {
        // Stable placeholder id for the "no exercise assigned" bucket —
        // never regenerated per-access, unlike a fresh `UUID()` would be.
        private static let unlabeledGroupID = UUID()

        let exercise: Exercise?
        let sets: [WorkoutSet]
        var id: UUID { exercise?.id ?? ExerciseGroup.unlabeledGroupID }
    }

    private var groupedByExercise: [ExerciseGroup] {
        let groups = Dictionary(grouping: orderedSets) { $0.exercise?.id }
        return groups
            .map { _, sets in
                ExerciseGroup(exercise: sets.first?.exercise, sets: sets.sorted { $0.timestamp < $1.timestamp })
            }
            .sorted { ($0.sets.first?.timestamp ?? .distantPast) < ($1.sets.first?.timestamp ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                headerContent
            }

            ForEach(groupedByExercise) { group in
                Section(group.exercise?.name.capitalized ?? "Unlabeled") {
                    ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                            Spacer()
                            Text("\(set.reps) reps")
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("\(set.weightKg, specifier: "%.1f") kg")
                        }
                    }
                }
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .omitted))
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Start")
                Spacer()
                Text(session.startDate.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            if let endDate = session.endDate {
                HStack {
                    Text("End")
                    Spacer()
                    Text(endDate.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(formattedDuration(endDate.timeIntervalSince(session.startDate)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
