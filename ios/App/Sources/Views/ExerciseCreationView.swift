import SwiftUI

/// specs/modules/04-history-and-navigation.md §3: full custom-exercise
/// creation flow. Attempts AI classification automatically on appearance;
/// on failure shows a specific, descriptive inline message (missing API
/// key vs. network/server error vs. an unparsable response) instead of one
/// generic alert, with a shortcut into `GeminiAPISettingsView` for the
/// missing-key case and a retry button otherwise — either way the
/// `MuscleChipPicker`s stay usable for manual selection, so classification
/// failing never blocks saving the exercise. The same chips remain
/// editable after a successful AI classification too — its result is a
/// starting point, never a locked-in answer. Presented as a sheet from
/// `ExercisePickerView` (itself already a sheet — a stacked sheet, which
/// SwiftUI supports).
struct ExerciseCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.geminiExerciseClassifier) private var classifier

    let initialName: String
    let onSave: (Exercise) -> Void

    @State private var category = ""
    @State private var primarySelection: Set<MuscleGroup> = []
    @State private var secondarySelection: Set<MuscleGroup> = []
    @State private var isClassifying = false
    @State private var classificationFailure: GeminiExerciseClassifier.ClassificationFailure?
    @State private var isPresentingAPIKeySettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ejercicio") {
                    Text(initialName.capitalized)
                        .font(.headline)
                    TextField("Categoría (opcional)", text: $category)
                }

                if isClassifying {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Clasificando con IA…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let failure = classificationFailure {
                    Section {
                        Label(message(for: failure), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        if case .missingAPIKey = failure {
                            Button("Configurar clave API de Gemini") {
                                isPresentingAPIKeySettings = true
                            }
                        } else {
                            Button("Reintentar clasificación") {
                                Task { await runClassification() }
                            }
                        }
                    }
                }

                Section("Vista previa") {
                    previewGrid
                    legend
                }

                MuscleChipPicker(title: "Músculos primarios", selection: $primarySelection)

                MuscleChipPicker(title: "Músculos secundarios", selection: $secondarySelection)
            }
            .navigationTitle("Nuevo Ejercicio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar") {
                        save()
                    }
                    .disabled(primarySelection.isEmpty)
                }
            }
            .task {
                await runClassification()
            }
            .sheet(isPresented: $isPresentingAPIKeySettings) {
                NavigationStack {
                    GeminiAPISettingsView()
                }
            }
        }
    }

    private func message(for failure: GeminiExerciseClassifier.ClassificationFailure) -> String {
        switch failure {
        case .missingAPIKey:
            return "No hay una clave API de Gemini configurada. Añádela en Ajustes o selecciona los músculos manualmente abajo."
        case .requestFailed(let details):
            return "No se pudo contactar con el servicio de IA (\(details)). Selecciona los músculos manualmente abajo."
        case .unparsableResponse:
            return "La IA devolvió una respuesta que no se pudo interpretar. Selecciona los músculos manualmente abajo."
        }
    }

    // Not AnatomicalBodyView's real accumulated-score coloring (there is no
    // training data for an exercise that doesn't exist yet) — a simpler,
    // dedicated 3-state preview: primary / secondary / unselected.
    private var previewGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
            ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                previewTile(for: muscle)
            }
        }
    }

    private func previewTile(for muscle: MuscleGroup) -> some View {
        let color: Color
        if primarySelection.contains(muscle) {
            color = .orange
        } else if secondarySelection.contains(muscle) {
            color = .yellow
        } else {
            color = Color(white: 0.85)
        }
        return RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(height: 36)
            .overlay(
                Text(muscle.displayName)
                    .font(.system(size: 8))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
                    .padding(2)
            )
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendEntry(color: .orange, label: "Primario")
            legendEntry(color: .yellow, label: "Secundario")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendEntry(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func runClassification() async {
        guard let classifier else {
            classificationFailure = .missingAPIKey
            return
        }
        classificationFailure = nil
        isClassifying = true
        let outcome = await classifier.classify(exerciseName: initialName)
        isClassifying = false

        switch outcome {
        case .success(let result):
            primarySelection = Set(result.primaryMuscles)
            secondarySelection = Set(result.secondaryMuscles)
        case .failure(let failure):
            classificationFailure = failure
        }
    }

    private func save() {
        let exercise = Exercise(
            name: initialName.lowercased(),
            category: category,
            primaryMuscles: Array(primarySelection),
            secondaryMuscles: Array(secondarySelection),
            isCustom: true
        )
        onSave(exercise)
        dismiss()
    }
}
