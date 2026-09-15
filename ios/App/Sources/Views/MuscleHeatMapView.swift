import SwiftUI

/// specs/modules/03-ai-and-muscle-map.md §2: reactive muscle heat map for
/// today's activation. A pure/stateless component — the caller (`DashboardView`)
/// computes `scores` via `MuscleHeatMapView.muscleScores(from:)` and passes
/// them in, so this view has no data-fetching of its own.
///
/// Each muscle group renders as a modular vector shape (`RoundedRectangle`)
/// rather than a hand-drawn anatomical body silhouette: there is no local
/// Xcode/SwiftUI preview in this environment to visually verify a custom
/// `Path`-based body outline, so a schematic grid of labeled regions — one
/// of the forms `specs/modules/03-ai-and-muscle-map.md` §2 explicitly
/// allows ("formas modulares... subcomponentes anatómicos") — is the
/// honest, verifiable choice here over an unverifiable silhouette.
///
/// **Known gap, not implemented (out of this task's explicit scope):**
/// module spec §2's "Interactividad" bullet (tapping a muscle opens a
/// floating card with its name/accumulated sets/exercises) — flagged here
/// rather than silently dropped.
struct MuscleHeatMapView: View {
    let scores: [MuscleGroup: Double]

    @State private var selectedBodyView: BodyView = .anterior

    enum BodyView: String, CaseIterable, Identifiable {
        case anterior = "Anterior"
        case posterior = "Posterior"
        var id: String { rawValue }
    }

    // Every MuscleGroup case (specs/01-system-spec.md §3.1) appears in
    // exactly one of these two lists.
    private static let anteriorGroups: [MuscleGroup] = [
        .deltoidAnterior, .chestUpper, .chestMiddle, .chestLower,
        .biceps, .forearms, .absUpper, .absLower, .obliques,
        .quadriceps, .adductors
    ]

    private static let posteriorGroups: [MuscleGroup] = [
        .trapsUpper, .trapsMiddle, .rhomboids, .deltoidLateral, .deltoidPosterior,
        .lats, .lowerBack, .tricepsLongHead, .tricepsLateralHead,
        .glutes, .hamstrings, .calves
    ]

    private var visibleGroups: [MuscleGroup] {
        selectedBodyView == .anterior ? Self.anteriorGroups : Self.posteriorGroups
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Body view", selection: $selectedBodyView) {
                ForEach(BodyView.allCases) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(visibleGroups, id: \.self) { muscle in
                    muscleTile(for: muscle)
                }
            }
        }
    }

    private func muscleTile(for muscle: MuscleGroup) -> some View {
        let score = scores[muscle] ?? 0
        return RoundedRectangle(cornerRadius: 8)
            .fill(MuscleGroup.heatColor(forScore: score))
            .frame(height: 56)
            .overlay(
                Text(displayName(for: muscle))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(4)
            )
    }

    private func displayName(for muscle: MuscleGroup) -> String {
        muscle.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // specs/01-system-spec.md §3.2: Score = 1.0 per set for the primary
    // muscle, 0.4 for each secondary muscle. Sets without an assigned
    // exercise (specs/01-system-spec.md §4: "entra con exercise = nil")
    // contribute nothing until labeled.
    static func muscleScores(from sets: [WorkoutSet]) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for set in sets {
            guard let exercise = set.exercise else { continue }
            scores[exercise.primaryMuscle, default: 0] += 1.0
            for secondary in exercise.secondaryMuscles {
                scores[secondary, default: 0] += 0.4
            }
        }
        return scores
    }
}
