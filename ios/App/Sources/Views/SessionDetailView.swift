import SwiftUI

/// specs/modules/04-history-and-navigation.md §4/§5: session header (start/
/// end/duration), sets grouped by exercise, and — added in Task 6.5 — this
/// session's Muscle Map plus an activation-count legend. §4's set/header
/// content was already built in Task 6.3 (extended here, not rebuilt, same
/// incremental pattern as `ExerciseHistoryView` (Task 5.3) →
/// `ExerciseDetailView` (Task 6.4)).
struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthKitService) private var healthKitService

    let session: WorkoutSession

    @State private var setPendingEdit: WorkoutSet?
    @State private var isSavingToHealth = false
    @State private var healthSaveErrorMessage: String?

    private var orderedSets: [WorkoutSet] {
        session.sets.sorted { $0.timestamp < $1.timestamp }
    }

    // specs/modules/04-history-and-navigation.md §5: same stimulus formula
    // and 6-level color scale as the Dashboard's "today" map (Task 5.2),
    // just scoped to this session's sets instead of today's.
    private var sessionMuscleScores: [MuscleGroup: Double] {
        AnatomicalBodyView.muscleScores(from: orderedSets)
    }

    private struct MuscleStimulation: Identifiable {
        let muscle: MuscleGroup
        let setCount: Int
        var id: MuscleGroup { muscle }
    }

    // Legend: "veces que se estimuló cada grupo muscular" — a plain count
    // of sets that touched each muscle (primary or secondary), distinct
    // from sessionMuscleScores' weighted 1.0/0.4 totals used for color.
    private var muscleStimulationCounts: [MuscleStimulation] {
        var counts: [MuscleGroup: Int] = [:]
        for set in orderedSets {
            guard let exercise = set.exercise else { continue }
            for muscle in exercise.primaryMuscles + exercise.secondaryMuscles {
                counts[muscle, default: 0] += 1
            }
        }
        return counts
            .map { MuscleStimulation(muscle: $0.key, setCount: $0.value) }
            .sorted { $0.setCount > $1.setCount }
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

            Section {
                healthSyncRow
            }

            ForEach(groupedByExercise) { group in
                Section(group.exercise?.name.capitalized ?? "Sin etiquetar") {
                    ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                        Button {
                            setPendingEdit = set
                        } label: {
                            setRow(ordinal: index + 1, set: set)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        deleteSets(in: group, at: offsets)
                    }
                }
            }

            // specs/modules/04-history-and-navigation.md §5: Muscle Map +
            // legend for this session only.
            Section("Mapa Muscular") {
                AnatomicalBodyView(scores: sessionMuscleScores)
            }

            if !muscleStimulationCounts.isEmpty {
                Section("Activación Muscular") {
                    ForEach(muscleStimulationCounts) { entry in
                        HStack {
                            Text(entry.muscle.displayName)
                            Spacer()
                            Text("\(entry.setCount) serie(s)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .omitted))
        .sheet(item: $setPendingEdit) { set in
            SetEditView(set: set)
        }
        .alert(
            "No se pudo guardar en Apple Health",
            isPresented: Binding(
                get: { healthSaveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { healthSaveErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthSaveErrorMessage ?? "")
        }
    }

    // Three states: already synced (green checkmark, no action), session
    // still in progress (nothing to export yet — HealthKitService itself
    // requires an endDate), or a button to save now. Manual entry point
    // alongside the automatic triggers in GarminSyncService/ActiveWorkoutView
    // — e.g. if the session was edited after those already ran, or if the
    // automatic save silently failed (permissions, offline) and the user
    // wants to retry from here.
    @ViewBuilder
    private var healthSyncRow: some View {
        if session.isSyncedToHealth {
            Label("Sincronizado con Salud", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if session.endDate == nil {
            Label("Termina el entrenamiento para guardarlo en Salud", systemImage: "heart.text.square")
                .foregroundStyle(.secondary)
        } else {
            Button {
                saveToHealth()
            } label: {
                HStack {
                    Label("Guardar en Apple Health", systemImage: "heart.text.square")
                    if isSavingToHealth {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSavingToHealth)
        }
    }

    private func saveToHealth() {
        guard let healthKitService else {
            healthSaveErrorMessage = "Apple Health no está disponible en este dispositivo."
            return
        }
        isSavingToHealth = true
        healthKitService.saveWorkout(session: session) { result in
            isSavingToHealth = false
            if case .failure(let error) = result {
                // The exact HealthKit-reported reason (missing
                // authorization, invalid sample, etc.), not a generic
                // message — HealthKitService.SaveWorkoutError already
                // logs the same detail to the console via `print`.
                healthSaveErrorMessage = error.localizedDescription
            }
        }
    }

    // Removes the tapped-to-delete/swiped sets directly from the
    // modelContext; `session.sets` (a `@Model` relationship) and every
    // computed property derived from it here (orderedSets,
    // groupedByExercise, sessionMuscleScores, muscleStimulationCounts)
    // recompute on the next body evaluation, which SwiftData triggers
    // automatically after the save below.
    private func deleteSets(in group: ExerciseGroup, at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(group.sets[index])
        }
        try? modelContext.save()
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Inicio")
                Spacer()
                Text(session.startDate.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            if let endDate = session.endDate {
                HStack {
                    Text("Fin")
                    Spacer()
                    Text(endDate.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Duración")
                    Spacer()
                    Text(formattedDuration(endDate.timeIntervalSince(session.startDate)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // specs/modules/04-history-and-navigation.md §4: ordinal, reps, kg,
    // set duration and rest duration — the two durations are new in Task
    // 6.5 (Task 6.3's version only showed reps/weight).
    private func setRow(ordinal: Int, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Serie \(ordinal)")
                Spacer()
                Text("\(set.reps) reps")
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(set.weightKg, specifier: "%.1f") kg")
            }

            HStack {
                Label(formattedSeconds(set.setDurationSeconds), systemImage: "stopwatch")
                Spacer()
                Label(formattedSeconds(set.restDurationSeconds), systemImage: "bed.double")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formattedSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
