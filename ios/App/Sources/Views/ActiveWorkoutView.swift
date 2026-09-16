import SwiftData
import SwiftUI

/// specs/modules/02-ios-core-and-sync.md §4: live table of the active
/// session's `WorkoutSet`s, ordered by `timestamp`. `session` is a live
/// SwiftData model instance (not a separate `@Query`), so `session.sets`
/// keeps updating in place as `GarminSyncService` inserts new sets.
///
/// Tapping a row opens `SetEditView` (reps/weight/exercise, with delete),
/// which itself opens `ExercisePickerView` (Task 4.2) to reassign the
/// exercise. Rows also support swipe-to-delete directly. The "Copy Down"
/// replicate button (Task 4.3) appears on the last row with an assigned
/// exercise, when at least one later row is unlabeled.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let session: WorkoutSession

    @State private var setPendingEdit: WorkoutSet?

    // Manual end-date editing: deliberately *not* written straight to
    // `session.endDate` as the user types, unlike `startDateBinding`
    // below — this task's exact rule is "if a manual end time was given,
    // use it; otherwise use Date() *at the moment the session is
    // finished*," so the manual value only needs to exist locally until
    // `finishWorkout()` decides what to commit. Seeded from any
    // `endDate` the session might already have (reopening an oddly
    // already-completed session, or restoring after the app relaunches)
    // so the toggle/picker reflect real state rather than always
    // resetting to "off."
    @State private var hasManualEndDate: Bool
    @State private var manualEndDate: Date

    init(session: WorkoutSession) {
        self.session = session
        _hasManualEndDate = State(initialValue: session.endDate != nil)
        _manualEndDate = State(initialValue: session.endDate ?? Date())
    }

    private var orderedSets: [WorkoutSet] {
        session.sets.sorted { $0.timestamp < $1.timestamp }
    }

    // Live-bound, unlike the end date above: "por defecto viene
    // inicializado con la fecha en la que se pulsó '+'; si el usuario no
    // lo toca, esa será su hora de inicio" — i.e. there's no separate
    // "confirm" step for the start time, it's just always the session's
    // real startDate, editable in place at any time.
    private var startDateBinding: Binding<Date> {
        Binding(
            get: { session.startDate },
            set: { newValue in
                session.startDate = newValue
                try? modelContext.save()
            }
        )
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
            Section {
                sessionSummaryHeader
            }

            // Manual/retroactive entry: lets a session logged without a
            // paired Garmin (or entered after the fact) carry the real
            // start/end times instead of whenever the "+" tab happened to
            // be tapped.
            Section("Horario") {
                DatePicker("Inicio", selection: startDateBinding, displayedComponents: [.date, .hourAndMinute])

                Toggle("Especificar hora de fin", isOn: $hasManualEndDate)

                if hasManualEndDate {
                    DatePicker(
                        "Fin",
                        selection: $manualEndDate,
                        in: session.startDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section {
                Button {
                    addSet()
                } label: {
                    Label("Añadir Serie", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if orderedSets.isEmpty {
                Text("Esperando series de tu reloj…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderedSets.enumerated()), id: \.element.id) { index, set in
                    setRow(ordinal: index + 1, index: index, set: set)
                }
                .onDelete { offsets in
                    deleteSets(at: offsets)
                }
            }
        }
        .navigationTitle("Entrenamiento Activo")
        .toolbar {
            // A close affordance is only strictly necessary when this
            // view is presented full-screen (from the "+" tab, which has
            // no back button of its own), but it's harmless and
            // consistent to show it everywhere this view appears.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
            }
            // Field-test finding: if the watch's SESSION_EVENT: STOP never
            // arrives (BLE drop, app killed on the watch, etc.), there was
            // previously no way to end the session from the phone at all.
            ToolbarItem(placement: .primaryAction) {
                Button("Finalizar Entrenamiento") {
                    finishWorkout()
                }
            }
        }
        .sheet(item: $setPendingEdit) { set in
            SetEditView(set: set)
        }
    }

    // Session summary card at the top of the list: start time ("Inicio:
    // HH:mm", a fixed 24h format regardless of the device's locale/12-24h
    // setting, per this task's explicit format) and a live elapsed-time
    // counter. `Text(_:style: .timer)` is SwiftUI's native live-updating
    // timer text — it recomputes and redraws itself every second on its
    // own, without a manual `Timer`/`@State` tick driving the whole view's
    // body, and already formats as MM:SS or H:MM:SS once past an hour.
    private var sessionSummaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("En curso")
                    .font(.headline)
                Text("Inicio: \(Self.startTimeFormatter.string(from: session.startDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.startDate, style: .timer)
                .font(.title2)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private static let startTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // offsets index into `orderedSets`, the exact same array/order the
    // ForEach above was built from, so they map 1:1 onto its elements.
    private func deleteSets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(orderedSets[index])
        }
        try? modelContext.save()
    }

    // Manual, Bluetooth-independent equivalent of the watch's
    // SESSION_EVENT: STOP handling (GarminSyncService.handleSessionEvent):
    // uses the manually-specified end time if the user set one via the
    // "Horario" section above, otherwise falls back to right now — same
    // effect either way (status = .completed, endDate set), triggered
    // locally.
    private func finishWorkout() {
        session.endDate = hasManualEndDate ? manualEndDate : Date()
        session.status = .completed
        try? modelContext.save()
        dismiss()
    }

    // Manual set entry, for logging without a paired Garmin (or
    // retroactively): pre-fills the new set from the last existing one
    // (same exercise/reps/weight) so entering several sets of the same
    // exercise back-to-back only needs a weight/rep tweak, not re-picking
    // the exercise every time; an empty session just gets zeroed
    // defaults. `detectedAutomatically: false` distinguishes it from a
    // Garmin-sourced set (not read anywhere today, but keeps the
    // provenance honest). Manual sessions have no accelerometer/rest
    // timer, so both durations are simply 0 rather than a fabricated
    // guess — "en las sesiones manuales se omiten los descansos
    // forzados."
    private func addSet() {
        let previous = orderedSets.last
        let newSet = WorkoutSet(
            exercise: previous?.exercise,
            reps: previous?.reps ?? 0,
            weightKg: previous?.weightKg ?? 0,
            setDurationSeconds: 0,
            restDurationSeconds: 0,
            detectedAutomatically: false,
            timestamp: Date()
        )
        modelContext.insert(newSet)
        session.sets.append(newSet)
        try? modelContext.save()
    }

    // Tapping the row (everything but "Copy Down") opens the full
    // reps/weight/exercise edit sheet (`SetEditView`) — "Copy Down" stays
    // a sibling button rather than being nested inside the same Button,
    // since SwiftUI doesn't support a tappable control inside another
    // tappable control's label.
    private func setRow(ordinal: Int, index: Int, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                setPendingEdit = set
            } label: {
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
                    .foregroundStyle(.primary)

                    HStack {
                        Label(formattedDuration(set.setDurationSeconds), systemImage: "stopwatch")
                        Spacer()
                        Label(formattedDuration(set.restDurationSeconds), systemImage: "bed.double")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(set.exercise?.name ?? "Seleccionar ejercicio…")
                        .font(.subheadline)
                        .foregroundStyle(set.exercise == nil ? .secondary : .primary)
                }
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

    // Reverted from the earlier "propagate to every subsequent orphan set"
    // behavior back to the original spec wording (specs/modules/02-ios-core-and-sync.md
    // §4: "Asigna currentSet.exercise a nextSet.exercise") — this task's
    // explicit request: assign only to the single immediately-following
    // set, not cascade through every later unlabeled one at once.
    // `orderedSets[sourceIndex + 1]` is guaranteed unlabeled already,
    // since `replicateSourceIndex` only ever points at the *last* labeled
    // row — mutating it makes IT the new last-labeled row on the next
    // body evaluation, so `replicateSourceIndex`/the "Copiar hacia abajo"
    // button move onto it automatically (or disappear, if it was also the
    // last row, or the row after it already has an exercise), with no
    // extra state to manage. Reps/weightKg are never touched (invariant).
    // Persisted immediately via the same shared modelContext every other
    // mutation in this app already saves through.
    private func copyDown(from sourceIndex: Int) {
        guard let exercise = orderedSets[sourceIndex].exercise else { return }
        orderedSets[sourceIndex + 1].exercise = exercise
        try? modelContext.save()
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
