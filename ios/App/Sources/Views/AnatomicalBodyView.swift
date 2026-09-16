import SwiftUI

/// specs/modules/03-ai-and-muscle-map.md §2: anterior/posterior anatomical
/// body diagram reactive to per-muscle scores.
///
/// **Revision history on this exact component:** Task 5.2 first built a
/// tile grid (no reference image, no local SwiftUI preview to verify a
/// hand-drawn `Path`). Two later revisions replaced the tiles with
/// hand-authored geometry — first rigid primitives, then hand-placed
/// smoothed landmark curves — and both were reported as visually
/// unacceptable ("poco anatómico", "cajas y palos"). The root cause was
/// the same both times: authoring anatomy by hand, in code, with no
/// rendering feedback, does not produce a convincing human figure. This
/// revision stops trying to author anatomy at all and instead renders
/// **real vector path data** vendored from a real, openly licensed
/// anatomical illustration — see `BodyAtlasData.swift` for the exact
/// source/license — parsed from raw SVG `d` strings via
/// `SVGPathParser.swift`. The shapes themselves are therefore no longer
/// this project's own approximation; only the taxonomy mapping (which of
/// ~35 real anatomical regions correspond to which score-tracked
/// `MuscleGroup`s) and the coloring are.
struct AnatomicalBodyView: View {
    let scores: [MuscleGroup: Double]

    @State private var selectedSide: Side = .anterior

    enum Side: String, CaseIterable, Identifiable {
        case anterior = "Anterior"
        case posterior = "Posterior"
        var id: String { rawValue }
    }

    // The vendored data's shared SVG viewBox is "0 0 1448 1448", with the
    // front figure occupying local x-range 0...724 and the back figure
    // occupying 724...1448 (see BodyAtlasData.swift) — each side is its
    // own 724x1448 box.
    private static let designWidth: CGFloat = 724
    private static let designHeight: CGFloat = 1448

    // Body regions this dataset draws that aren't part of the tracked
    // MuscleGroup taxonomy (head, hair, hands, feet, ankles, knees, shin,
    // neck) render in a fixed light neutral tone, distinct from the
    // frozen heat scale's own 0-score color (a dark near-black, designed
    // for the old tile grid) — "gris claro neutro" for parts of the body
    // this app simply doesn't score, not "this muscle has zero stimulus".
    private static let decorativeColor = Color(white: 0.86)

    var body: some View {
        VStack(spacing: 12) {
            Picker("Vista corporal", selection: $selectedSide) {
                ForEach(Side.allCases) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)

            GeometryReader { proxy in
                let xOffset: CGFloat = selectedSide == .anterior ? 0 : Self.designWidth
                let transform = designTransform(for: proxy.size, xOffset: xOffset)
                let regions = selectedSide == .anterior ? BodyAtlasData.front : BodyAtlasData.back

                ZStack {
                    ForEach(regions, id: \.slug) { region in
                        let color = fillColor(forSlug: region.slug, side: selectedSide)
                        ForEach(Array(region.paths.enumerated()), id: \.offset) { _, d in
                            SVGPathParser.path(from: d)
                                .applying(transform)
                                .fill(color)
                        }
                    }
                }
            }
            .aspectRatio(Self.designWidth / Self.designHeight, contentMode: .fit)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity)
        }
    }

    private func designTransform(for size: CGSize, xOffset: CGFloat) -> CGAffineTransform {
        let scale = min(size.width / Self.designWidth, size.height / Self.designHeight)
        let dx = (size.width - Self.designWidth * scale) / 2
        let dy = (size.height - Self.designHeight * scale) / 2
        return CGAffineTransform(translationX: -xOffset, y: 0)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private func fillColor(forSlug slug: String, side: Side) -> Color {
        let groups = muscleGroups(forSlug: slug, side: side)
        guard !groups.isEmpty else { return Self.decorativeColor }
        let score = groups.map { scores[$0] ?? 0 }.max() ?? 0
        return MuscleGroup.heatColor(forScore: score)
    }

    // Maps each of the vendored dataset's own anatomical slugs onto the
    // frozen MuscleGroup taxonomy. A muscle visible from both views (e.g.
    // a calf's front sliver, a deltoid's rear cap) uses the same
    // underlying score in either view — anatomically the same muscle,
    // just two different vantage points on it, unlike the previous
    // revision's rule that pinned every region to exactly one side.
    // "deltoids" is the one slug whose target MuscleGroup genuinely
    // differs by view (front vs. lateral/rear head of the shoulder), so
    // it alone branches on `side`. A region's aggregate score is the max
    // across its constituent MuscleGroups, for the same reason as always:
    // one heavily-trained sub-muscle should read as hot without dilution.
    private func muscleGroups(forSlug slug: String, side: Side) -> [MuscleGroup] {
        switch slug {
        case "chest": return [.chestUpper, .chestMiddle, .chestLower]
        case "obliques": return [.obliques]
        case "abs": return [.absUpper, .absLower]
        case "biceps": return [.biceps]
        case "triceps": return [.tricepsLongHead, .tricepsLateralHead]
        case "trapezius": return [.trapsUpper, .trapsMiddle]
        case "deltoids": return side == .anterior ? [.deltoidAnterior] : [.deltoidLateral, .deltoidPosterior]
        case "adductors": return [.adductors]
        case "quadriceps": return [.quadriceps]
        case "forearm": return [.forearms]
        case "calves": return [.calves]
        case "upper-back": return [.lats, .rhomboids]
        case "lower-back": return [.lowerBack]
        case "gluteal": return [.glutes]
        case "hamstring": return [.hamstrings]
        default: return []
        }
    }

    // specs/01-system-spec.md §3.2: Score = 1.0 per set for each primary
    // muscle, 0.4 for each secondary muscle. Unchanged across every
    // revision of this view's rendering.
    static func muscleScores(from sets: [WorkoutSet]) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for set in sets {
            guard let exercise = set.exercise else { continue }
            for primary in exercise.primaryMuscles {
                scores[primary, default: 0] += 1.0
            }
            for secondary in exercise.secondaryMuscles {
                scores[secondary, default: 0] += 0.4
            }
        }
        return scores
    }
}
