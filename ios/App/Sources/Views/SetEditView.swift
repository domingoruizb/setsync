import SwiftUI

/// Edit sheet for an existing `WorkoutSet`: reps, weight, and reassigning
/// its exercise (via the existing `ExercisePickerView`, presented as a
/// nested sheet — the same stacked-sheet pattern already used by
/// `ExerciseCreationView` on top of `ExercisePickerView`). Reachable by
/// tapping a set row in both `SessionDetailView` (finished sessions) and
/// `ActiveWorkoutView` (the in-progress session).
///
/// No separate "recalculate metrics" step exists here on purpose: every
/// derived metric that depends on sets (`ExerciseDetailView`'s PR/est.
/// 1RM/total sets/reps, `TodayView`/`SessionDetailView`'s muscle maps) is
/// already a computed property over a live `@Query` or a `@Model`
/// relationship, so saving a mutation through the same shared
/// `modelContext` used everywhere else in this app is sufficient —
/// SwiftData's own change tracking re-evaluates those `@Query`s and
/// observed relationships automatically. Adding a dedicated recompute
/// service on top would duplicate logic that is already reactive by
/// construction.
struct SetEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let set: WorkoutSet

    @State private var reps: Int
    @State private var weightText: String
    @State private var isPresentingExercisePicker = false
    @State private var showsDeleteConfirmation = false

    init(set: WorkoutSet) {
        self.set = set
        _reps = State(initialValue: set.reps)
        _weightText = State(initialValue: String(format: "%.1f", set.weightKg))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ejercicio") {
                    Button {
                        isPresentingExercisePicker = true
                    } label: {
                        HStack {
                            Text(set.exercise?.name.capitalized ?? "Sin ejercicio")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Repeticiones") {
                    Stepper("\(reps) reps", value: $reps, in: 0...200)
                }

                Section("Peso (kg)") {
                    TextField("Peso", text: $weightText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button("Eliminar serie", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Editar Serie")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar") { save() }
                }
            }
            .sheet(isPresented: $isPresentingExercisePicker) {
                ExercisePickerView(workoutSet: set)
            }
            .alert("¿Eliminar esta serie?", isPresented: $showsDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) { performDelete() }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
        }
    }

    private func save() {
        set.reps = reps
        if let parsedWeight = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
            set.weightKg = parsedWeight
        }
        try? modelContext.save()
        dismiss()
    }

    private func performDelete() {
        modelContext.delete(set)
        try? modelContext.save()
        dismiss()
    }
}
