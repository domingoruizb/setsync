import Foundation

/// Exports a completed `WorkoutSession` as a Training Center Database
/// (TCX) XML file — Strava's own upload flow
/// (strava.com/upload/select, and the mobile app's "+" → "Add Activity" →
/// "Upload Activity File") accepts `.tcx`/`.gpx` files natively, with no
/// API key, OAuth flow, or app entitlement of any kind, from any iPhone
/// regardless of how the app itself is signed.
///
/// Replaces an Apple Health/HealthKit export that was built and then
/// discarded: a provisioning profile generated from a free/personal-team
/// Apple ID (this app's actual sideloading path, via Sideloadly) never
/// gets the `com.apple.developer.healthkit` entitlement granted by Apple
/// at all, so HealthKit access was blocked at the OS level regardless of
/// any app-side fix. A plain exported file needs no entitlement to work.
enum TCXExportService {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func fileName(for session: WorkoutSession) -> String {
        "SetSync_\(fileNameDateFormatter.string(from: session.startDate)).tcx"
    }

    /// Writes the generated TCX XML to a fresh temporary file and returns
    /// its URL, ready to hand to `ShareLink`. Re-generating (and
    /// overwriting) the same-named file on every call is deliberate and
    /// harmless — this is a small, deterministic text file, not a
    /// resource worth caching.
    static func exportFile(for session: WorkoutSession) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: session))
        try xmlString(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // specs-equivalent structure for this task: a single Activity/Lap
    // pair (Sport="Other", since this is strength training, not a
    // GPS-tracked cardio activity type). Element order inside <Lap>
    // (TotalTimeSeconds, DistanceMeters, Calories, Intensity,
    // TriggerMethod, Track, Notes) follows the TCX v2 XSD's required
    // sequence — Strava's parser has historically been lenient about
    // this, but there's no reason to rely on that leniency when getting
    // the order right costs nothing.
    static func xmlString(for session: WorkoutSession) -> String {
        let startDate = session.startDate
        // Falls back to startDate (a zero-duration lap) rather than
        // crashing/producing malformed XML if this is ever called on a
        // session with no endDate yet — TCX requires well-formed
        // start/end times regardless.
        let endDate = session.endDate ?? startDate
        let totalSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let startString = iso8601Formatter.string(from: startDate)
        let endString = iso8601Formatter.string(from: endDate)
        let notes = escapeXML(summary(for: session))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Other">
              <Id>\(startString)</Id>
              <Lap StartTime="\(startString)">
                <TotalTimeSeconds>\(totalSeconds)</TotalTimeSeconds>
                <DistanceMeters>0</DistanceMeters>
                <Calories>0</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
                  <Trackpoint>
                    <Time>\(startString)</Time>
                  </Trackpoint>
                  <Trackpoint>
                    <Time>\(endString)</Time>
                  </Trackpoint>
                </Track>
                <Notes>\(notes)</Notes>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // "Exercise: N series, N reps, peso máx. N kg, volumen N kg" per
    // exercise (in the order first performed), plus a total-volume line —
    // exactly the content this task asked for (ejercicios, series,
    // repeticiones, peso utilizado, volumen total), as the Lap's <Notes>.
    private static func summary(for session: WorkoutSession) -> String {
        let orderedSets = session.sets.sorted { $0.timestamp < $1.timestamp }
        guard !orderedSets.isEmpty else {
            return "Entrenamiento de fuerza registrado con SetSync."
        }

        struct ExerciseTotals {
            let name: String
            var setCount = 0
            var totalReps = 0
            var maxWeightKg = 0.0
            var volumeKg = 0.0
        }

        var order: [UUID] = []
        var totalsByExerciseId: [UUID: ExerciseTotals] = [:]
        var totalVolumeKg = 0.0

        for set in orderedSets {
            totalVolumeKg += Double(set.reps) * set.weightKg
            guard let exercise = set.exercise else { continue }
            if totalsByExerciseId[exercise.id] == nil {
                order.append(exercise.id)
                totalsByExerciseId[exercise.id] = ExerciseTotals(name: exercise.name.capitalized)
            }
            let previousMaxWeightKg = totalsByExerciseId[exercise.id]?.maxWeightKg ?? 0
            totalsByExerciseId[exercise.id]?.setCount += 1
            totalsByExerciseId[exercise.id]?.totalReps += set.reps
            totalsByExerciseId[exercise.id]?.maxWeightKg = max(previousMaxWeightKg, set.weightKg)
            totalsByExerciseId[exercise.id]?.volumeKg += Double(set.reps) * set.weightKg
        }

        var lines = order.compactMap { id -> String? in
            guard let totals = totalsByExerciseId[id] else { return nil }
            let maxWeight = String(format: "%.1f", totals.maxWeightKg)
            return "\(totals.name): \(totals.setCount) series, \(totals.totalReps) reps, peso máx. \(maxWeight) kg, volumen \(Int(totals.volumeKg)) kg"
        }
        lines.append("Volumen total: \(Int(totalVolumeKg)) kg")
        return lines.joined(separator: "\n")
    }
}
