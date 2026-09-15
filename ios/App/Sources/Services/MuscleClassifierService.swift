import Foundation

/// specs/modules/03-ai-and-muscle-map.md §1: classifies a new `Exercise`'s
/// muscle activation via Gemini 1.5 Flash (Google AI Studio REST API, free
/// tier). Uses plain `URLSession` — no SDK — per this task's explicit
/// instruction to avoid CI linking issues.
final class MuscleClassifierService {

    struct ClassificationResult {
        let primaryMuscleGroup: MuscleGroup
        let secondaryMuscleGroups: [MuscleGroup]
    }

    private static let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    )!

    private let apiKey: String?
    private let urlSession: URLSession

    // Read once from the environment at launch. Deliberately just one
    // source (no auxiliary Bundle/plist lookup): keeping this to a single,
    // simple mechanism avoids adding an untestable second code path (no
    // local Xcode to verify a Bundle-resource read) for a "nice to have."
    // A local run can supply GEMINI_API_KEY via the Xcode scheme's
    // environment variables; it is never committed to the repo.
    init(apiKey: String? = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    /// Never throws and never leaves the caller without a decision: returns
    /// `nil` if the API key is missing/empty, the request fails (offline,
    /// quota, timeout, non-2xx), or the response can't be parsed into at
    /// least a valid primary muscle group. Callers should keep whatever
    /// `primaryMuscle` is already assigned when this returns `nil`.
    func classify(exerciseName: String) async -> ClassificationResult? {
        guard let apiKey, !apiKey.isEmpty else {
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

    // specs/modules/03-ai-and-muscle-map.md §1.1 (system prompt + allowed
    // taxonomy) and this task's exact `generationConfig`/`response_schema`.
    private func requestBody(exerciseName: String) -> [String: Any] {
        let prompt = """
        Clasifica el ejercicio de fuerza proporcionado dentro de la taxonomía muscular estandarizada.
        Responde ÚNICAMENTE con un objeto JSON válido con las claves "primaryMuscleGroup" (un solo identificador)
        y "secondaryMuscleGroups" (array de identificadores).

        Taxonomía permitida:
        chest_upper, chest_middle, chest_lower, lats, traps_upper, traps_middle, rhomboids,
        lower_back, deltoid_anterior, deltoid_lateral, deltoid_posterior, biceps,
        triceps_long_head, triceps_lateral_head, forearms, abs_upper, abs_lower, obliques,
        quadriceps, hamstrings, glutes, calves, adductors.

        Ejercicio: \(exerciseName)
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
                        "primaryMuscleGroup": ["type": "STRING"],
                        "secondaryMuscleGroups": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"]
                        ]
                    ],
                    "required": ["primaryMuscleGroup", "secondaryMuscleGroups"]
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
            let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
            let primaryRaw = inner["primaryMuscleGroup"] as? String,
            let primary = MuscleGroup(safeRawValue: primaryRaw)
        else {
            return nil
        }

        let secondaryRaw = inner["secondaryMuscleGroups"] as? [String] ?? []
        let secondary = secondaryRaw.compactMap { MuscleGroup(safeRawValue: $0) }

        return ClassificationResult(primaryMuscleGroup: primary, secondaryMuscleGroups: secondary)
    }
}

// specs/modules/03-ai-and-muscle-map.md §1: maps the model's raw string
// output onto the frozen MuscleGroup taxonomy (specs/01-system-spec.md
// §3.1) case-insensitively and tolerant of stray whitespace/separators,
// since an LLM's exact formatting is never guaranteed even with a JSON
// response schema (the schema constrains shape, not the string's value).
private extension MuscleGroup {
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
