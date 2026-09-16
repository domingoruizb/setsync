import SwiftUI

/// specs/modules/04-history-and-navigation.md §3: lets the user persist a
/// `GEMINI_API_KEY` for `GeminiExerciseClassifier` when no environment
/// variable is set (the only source available on a sideloaded build,
/// which has no Xcode scheme to inject one). Not wired into any
/// navigation yet — becomes part of the "Watch / Settings" tab's content
/// in Task 6.3, kept standalone/complete here in the meantime, consistent
/// with how every other service's UI in this project was built before its
/// own wiring task (e.g. GarminSyncService.selectDevice() since Task 3.2).
struct GeminiAPISettingsView: View {
    @State private var apiKey: String = GeminiAPIKeyStore.storedKey() ?? ""
    @State private var didSave = false

    var body: some View {
        Form {
            Section {
                SecureField("Gemini API Key", text: $apiKey)
                Button("Save") {
                    GeminiAPIKeyStore.save(apiKey)
                    didSave = true
                }
            } header: {
                Text("AI Exercise Classification")
            } footer: {
                Text("Used to automatically suggest muscle groups for new exercises. Get a free key at Google AI Studio.")
            }
        }
        .navigationTitle("Gemini API Key")
        .alert("Saved", isPresented: $didSave) {
            Button("OK", role: .cancel) {}
        }
    }
}
