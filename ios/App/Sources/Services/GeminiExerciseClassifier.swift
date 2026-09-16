import Foundation

/// specs/modules/04-history-and-navigation.md §3: classifies a new
/// `Exercise`'s muscle activation via Gemini 1.5 Flash (Google AI Studio
/// REST API, free tier). Evolved from Task 5.1's `MuscleClassifierService`:
/// the result is now `primary`/`secondary` arrays, matching
/// `Exercise.primaryMuscles`/`secondaryMuscles` (Task 6.1) instead of a
/// single primary muscle. Still plain `URLSession` — no SDK — per Task
/// 5.1's original instruction to avoid CI linking issues.
final class GeminiExerciseClassifier {

    struct ClassificationResult {
        let primaryMuscles: [MuscleGroup]
        let secondaryMuscles: [MuscleGroup]
    }

    private static let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    )!

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // Read fresh on every call, not captured once at init: the user can
    // save/change the key in Settings (Task 6.3) during the app's
    // lifetime, and that must take effect on the very next classification
    // without restarting the app or reconstructing this object.
    private var currentAPIKey: String? {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? GeminiAPIKeyStore.storedKey()
    }

    /// Never throws and never leaves the caller without a decision:
    /// returns `nil` on a missing/empty key, a failed request (offline,
    /// quota, timeout, non-2xx), or a response with no mappable primary
    /// muscle. Callers should fall back to manual chip selection (Task
    /// 6.2's `MuscleChipPicker`) when this returns `nil`.
    func classify(exerciseName: String) async -> ClassificationResult? {
        guard let apiKey = currentAPIKey, !apiKey.isEmpty else {
            return nil
        }

        let url = Self.endpoint.appending(queryItems: [URLQueryItem(name: "key", value: apiKey)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(exerciseName: exerciseName))

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return parseResult(from: data)
        } catch {
            return nil
        }
    }

    // specs/modules/04-history-and-navigation.md §3: `generationConfig`'s
    // `response_mime_type`/`response_schema` fields are snake_case,
    // verified directly against Google's REST API reference
    // (ai.google.dev/api/generate-content) during this task — a later
    // camelCase suggestion was not applied, since it would have silently
    // broken structured output on the raw REST body a plain URLSession
    // sends. "primary"/"secondary" are this project's own response-schema
    // property names, not a Google-mandated shape.
    private func requestBody(exerciseName: String) -> [String: Any] {
        let prompt = """
        Classify the given strength exercise (its name may be written in any language) against this fixed muscle taxonomy. Respond ONLY with a valid JSON object with keys "primary" (array of identifiers) and "secondary" (array of identifiers).

        Allowed taxonomy:
        chest_upper, chest_middle, chest_lower, lats, traps_upper, traps_middle, rhomboids,
        lower_back, deltoid_anterior, deltoid_lateral, deltoid_posterior, biceps,
        triceps_long_head, triceps_lateral_head, forearms, abs_upper, abs_lower, obliques,
        quadriceps, hamstrings, glutes, calves, adductors.

        Exercise: \(exerciseName)
        """

        return [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_schema": [
                    "type": "OBJECT",
                    "properties": [
                        "primary": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"]
                        ],
                        "secondary": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"]
                        ]
                    ],
                    "required": ["primary", "secondary"]
                ]
            ]
        ]
    }

    private func parseResult(from data: Data) -> ClassificationResult? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String,
            let innerData = text.data(using: .utf8),
            let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any]
        else {
            return nil
        }

        let primaryRaw = inner["primary"] as? [String] ?? []
        let secondaryRaw = inner["secondary"] as? [String] ?? []
        let primary = primaryRaw.compactMap { MuscleGroup(safeRawValue: $0) }
        let secondary = secondaryRaw.compactMap { MuscleGroup(safeRawValue: $0) }

        guard !primary.isEmpty else {
            return nil
        }

        return ClassificationResult(primaryMuscles: primary, secondaryMuscles: secondary)
    }
}

// Moved from Task 5.1's MuscleClassifierService.swift: maps the model's
// raw string output onto the frozen MuscleGroup taxonomy
// (specs/01-system-spec.md §3.1) case-insensitively and tolerant of stray
// whitespace/separators, since a JSON response schema constrains shape,
// not the string's actual value.
extension MuscleGroup {
    init?(safeRawValue rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        guard let match = MuscleGroup(rawValue: normalized) else {
            return nil
        }
        self = match
    }
}
