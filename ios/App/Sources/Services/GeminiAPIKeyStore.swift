import Foundation

/// specs/modules/04-history-and-navigation.md §3: persists a user-entered
/// Gemini API key (from the future Settings tab, Task 6.3) so
/// `GeminiExerciseClassifier` has a fallback when `GEMINI_API_KEY` isn't
/// set in the environment — the only source available on a sideloaded
/// build, which has no Xcode scheme to inject an env var into.
///
/// `UserDefaults` over `Keychain` (offered as an alternative): this app is
/// a single-user, never-distributed sideload, so Keychain's stronger-but-
/// untestable-here Security-framework API surface isn't worth the risk of
/// writing it with no local Swift compiler to check it against.
enum GeminiAPIKeyStore {
    private static let defaultsKey = "GeminiAPIKey"

    static func storedKey() -> String? {
        UserDefaults.standard.string(forKey: defaultsKey)
    }

    static func save(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
