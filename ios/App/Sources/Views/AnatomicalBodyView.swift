import SwiftUI

/// specs/modules/03-ai-and-muscle-map.md §2: a vectorial anatomical body
/// silhouette — anterior and posterior — reactive to per-muscle scores.
///
/// **Revision history on this exact component:** Task 5.2 first built a
/// tile grid (no reference image, no local SwiftUI preview to verify a
/// hand-drawn `Path`). A first `Path`-based attempt then replaced the
/// tiles with straight-line polygons and `Capsule`/`Ellipse`/
/// `RoundedRectangle` primitives floating at fractional positions — you
/// reported that result as unacceptable ("parece un esquema geométrico
/// rígido con cajas y palos"). This version fixes the actual cause: every
/// shape, including the base outline, is now built from a small set of
/// hand-placed anatomical landmark points on a normalized 100×200 design
/// canvas (`designWidth`/`designHeight` below — the "viewBox normalizado"
/// you asked for), run through `smoothClosedPath(points:)`, a Catmull-Rom-
/// style smoother that turns any polygon into a soft, organic closed
/// curve by treating each vertex as a bulge control point between the
/// midpoints of its neighbors. The same smoothing function draws the
/// outline AND every muscle region, so nothing here is a rigid primitive
/// any more — but it is still a hand-placed approximation, not a traced
/// medical/athletic reference image (none was ever provided, and there is
/// still no local Xcode/SwiftUI preview in this environment), so it
/// should be expected to need further point-tuning once actually seen on
/// a device.
struct AnatomicalBodyView: View {
    let scores: [MuscleGroup: Double]

    @State private var selectedSide: Side = .anterior

    enum Side: String, CaseIterable, Identifiable {
        case anterior = "Anterior"
        case posterior = "Posterior"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Vista corporal", selection: $selectedSide) {
                ForEach(Side.allCases) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)

            GeometryReader { proxy in
                let transform = designTransform(for: proxy.size)
                ZStack {
                    BodyOutlineShape()
                        .stroke(Color(white: 0.82), lineWidth: 1.5)

                    ForEach(MuscleGroup.BodyRegion.allCases.filter { $0.side == selectedSide }, id: \.self) { region in
                        regionView(region, transform: transform)
                    }
                }
            }
            .aspectRatio(designWidth / designHeight, contentMode: .fit)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func regionView(_ region: MuscleGroup.BodyRegion, transform: CGAffineTransform) -> some View {
        let color = MuscleGroup.heatColor(forScore: region.score(from: scores))
        let shape = regionShape(for: region)
        if shape.mirrored {
            smoothClosedPath(points: shape.points).applying(transform).fill(color)
            smoothClosedPath(points: mirroredX(shape.points)).applying(transform).fill(color)
        } else {
            smoothClosedPath(points: shape.points).applying(transform).fill(color)
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

// A coarser ~14-region visual grouping over the full 23-case MuscleGroup
// taxonomy, used only for rendering this silhouette (the fine-grained
// taxonomy itself, used everywhere else — scoring, AI classification,
// chip pickers — is untouched). Every MuscleGroup case appears in exactly
// one region's `muscles` list.
extension MuscleGroup {
    enum BodyRegion: String, CaseIterable {
        case chest, frontDeltoids, biceps, forearms, abs, quads
        case rearDeltoids, triceps, lats, traps, lowerBack, glutes, hamstrings, calves

        var side: AnatomicalBodyView.Side {
            switch self {
            case .chest, .frontDeltoids, .biceps, .forearms, .abs, .quads:
                return .anterior
            case .rearDeltoids, .triceps, .lats, .traps, .lowerBack, .glutes, .hamstrings, .calves:
                return .posterior
            }
        }

        var muscles: [MuscleGroup] {
            switch self {
            case .chest: return [.chestUpper, .chestMiddle, .chestLower]
            case .frontDeltoids: return [.deltoidAnterior]
            case .biceps: return [.biceps]
            case .forearms: return [.forearms]
            case .abs: return [.absUpper, .absLower, .obliques]
            case .quads: return [.quadriceps, .adductors]
            case .rearDeltoids: return [.deltoidLateral, .deltoidPosterior]
            case .triceps: return [.tricepsLongHead, .tricepsLateralHead]
            case .lats: return [.lats, .rhomboids]
            case .traps: return [.trapsUpper, .trapsMiddle]
            case .lowerBack: return [.lowerBack]
            case .glutes: return [.glutes]
            case .hamstrings: return [.hamstrings]
            case .calves: return [.calves]
            }
        }

        // Aggregation across a region's constituent muscles uses the max,
        // not the sum: a single heavily-trained sub-muscle should read as
        // "hot" on the silhouette, not be visually diluted by averaging
        // against an untouched neighbor sharing the same drawn shape.
        func score(from scores: [MuscleGroup: Double]) -> Double {
            muscles.map { scores[$0] ?? 0 }.max() ?? 0
        }
    }
}

// MARK: - Normalized anatomical coordinate system

// A fixed "viewBox" (100 units wide, 200 tall — a 1:2 aspect, close to a
// standing figure cropped at the wrists/ankles) that every point below is
// authored in. `designTransform(for:)` maps it onto the view's actual
// pixel size once, so both the outline and every muscle region share
// identical scale/alignment — nothing is positioned independently, unlike
// the previous fraction-of-container-size approach.
private let designWidth: CGFloat = 100
private let designHeight: CGFloat = 200

private func designTransform(for size: CGSize) -> CGAffineTransform {
    let scale = min(size.width / designWidth, size.height / designHeight)
    let dx = (size.width - designWidth * scale) / 2
    let dy = (size.height - designHeight * scale) / 2
    return CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: dx, y: dy))
}

private func mirroredX(_ points: [CGPoint]) -> [CGPoint] {
    points.map { CGPoint(x: designWidth - $0.x, y: $0.y) }
}

// Turns a polygon's vertices into a soft, organic closed curve: each
// original vertex becomes a bulge control point for a quadratic curve
// between the midpoints of its two neighbors (a standard "smooth a
// polyline" trick). This is what replaces every straight-line polygon,
// Capsule, Ellipse and RoundedRectangle from the previous revision — one
// single technique used for the outline and every muscle region, so the
// whole figure reads as one consistent family of soft shapes.
private func smoothClosedPath(points: [CGPoint]) -> Path {
    var path = Path()
    guard points.count > 2 else { return path }
    func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    let count = points.count
    path.move(to: midpoint(points[count - 1], points[0]))
    for index in 0..<count {
        let end = midpoint(points[index], points[(index + 1) % count])
        path.addQuadCurve(to: end, control: points[index])
    }
    path.closeSubpath()
    return path
}

// MARK: - Body outline

// The right half of the silhouette, traced from the top of the head down
// to the crotch: head → jaw → neck/shoulder → down the outer arm → around
// the hand → back up the inner arm to the armpit (the gap between arm and
// torso) → down the torso's side (chest/waist/hip curve) → down the outer
// leg → around the foot → back up the inner leg to the crotch. The left
// half is this same traversal mirrored and reversed (see `outlinePoints`),
// so editing a landmark here only ever needs to happen once.
private let outlineRightSide: [CGPoint] = [
    CGPoint(x: 50, y: 2),    // top of head
    CGPoint(x: 64, y: 12),   // head, right side
    CGPoint(x: 58, y: 24),   // jaw
    CGPoint(x: 61, y: 31),   // neck base
    CGPoint(x: 79, y: 35),   // shoulder tip
    CGPoint(x: 85, y: 46),   // deltoid bulge
    CGPoint(x: 84, y: 70),   // elbow, outer edge
    CGPoint(x: 79, y: 98),   // wrist, outer edge
    CGPoint(x: 74, y: 107),  // hand tip
    CGPoint(x: 73, y: 97),   // wrist, inner edge
    CGPoint(x: 77, y: 69),   // elbow, inner edge
    CGPoint(x: 72, y: 40),   // armpit (arm/torso gap)
    CGPoint(x: 76, y: 52),   // chest bulge
    CGPoint(x: 63, y: 75),   // waist
    CGPoint(x: 69, y: 88),   // hip
    CGPoint(x: 66, y: 110),  // thigh bulge, outer
    CGPoint(x: 59, y: 138),  // knee, outer edge
    CGPoint(x: 63, y: 156),  // calf bulge
    CGPoint(x: 56, y: 184),  // ankle, outer edge
    CGPoint(x: 58, y: 194),  // foot tip
    CGPoint(x: 53, y: 184),  // ankle, inner edge
    CGPoint(x: 54, y: 156),  // calf bulge, inner
    CGPoint(x: 53, y: 138),  // knee, inner edge
    CGPoint(x: 52, y: 100),  // thigh, inner edge
    CGPoint(x: 50, y: 92)    // crotch (shared with the left leg)
]

private var outlinePoints: [CGPoint] {
    let returnLeg = Array(outlineRightSide.dropFirst().dropLast().reversed())
    return outlineRightSide + mirroredX(returnLeg)
}

private struct BodyOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        smoothClosedPath(points: outlinePoints).applying(designTransform(for: rect.size))
    }
}

// MARK: - Muscle region shapes

// Each region's points describe its right-side (or, for a centerline
// region, its single) shape in the same 100×200 design space as the
// outline above, so every region is positioned relative to real
// anatomical landmarks (e.g. the biceps box sits between the same
// shoulder/elbow points used for the arm's own outline) instead of an
// independent fractional offset. `mirrored` regions are drawn twice, once
// reflected across the centerline.
private struct RegionShape {
    let points: [CGPoint]
    let mirrored: Bool
}

private func regionShape(for region: MuscleGroup.BodyRegion) -> RegionShape {
    switch region {
    case .chest:
        return RegionShape(points: [
            CGPoint(x: 50, y: 40), CGPoint(x: 61, y: 39), CGPoint(x: 75, y: 48),
            CGPoint(x: 70, y: 61), CGPoint(x: 56, y: 61)
        ], mirrored: true)
    case .frontDeltoids, .rearDeltoids:
        return RegionShape(points: [
            CGPoint(x: 73, y: 37), CGPoint(x: 85, y: 42), CGPoint(x: 84, y: 51), CGPoint(x: 75, y: 50)
        ], mirrored: true)
    case .biceps, .triceps:
        return RegionShape(points: [
            CGPoint(x: 79, y: 49), CGPoint(x: 85, y: 52), CGPoint(x: 82, y: 68), CGPoint(x: 76, y: 66)
        ], mirrored: true)
    case .forearms:
        return RegionShape(points: [
            CGPoint(x: 76, y: 70), CGPoint(x: 82, y: 73), CGPoint(x: 78, y: 96), CGPoint(x: 73, y: 94)
        ], mirrored: true)
    case .abs:
        return RegionShape(points: [
            CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 60), CGPoint(x: 62, y: 87), CGPoint(x: 38, y: 87)
        ], mirrored: false)
    case .quads, .hamstrings:
        return RegionShape(points: [
            CGPoint(x: 52, y: 92), CGPoint(x: 67, y: 90), CGPoint(x: 65, y: 136), CGPoint(x: 54, y: 136)
        ], mirrored: true)
    case .traps:
        return RegionShape(points: [
            CGPoint(x: 50, y: 27), CGPoint(x: 75, y: 39), CGPoint(x: 50, y: 60), CGPoint(x: 25, y: 39)
        ], mirrored: false)
    case .lats:
        return RegionShape(points: [
            CGPoint(x: 72, y: 42), CGPoint(x: 78, y: 56), CGPoint(x: 68, y: 76), CGPoint(x: 60, y: 60)
        ], mirrored: true)
    case .lowerBack:
        return RegionShape(points: [
            CGPoint(x: 42, y: 79), CGPoint(x: 58, y: 79), CGPoint(x: 60, y: 91), CGPoint(x: 40, y: 91)
        ], mirrored: false)
    case .glutes:
        return RegionShape(points: [
            CGPoint(x: 50, y: 89), CGPoint(x: 67, y: 88), CGPoint(x: 65, y: 107), CGPoint(x: 50, y: 105)
        ], mirrored: true)
    case .calves:
        return RegionShape(points: [
            CGPoint(x: 55, y: 140), CGPoint(x: 64, y: 143), CGPoint(x: 61, y: 181), CGPoint(x: 55, y: 179)
        ], mirrored: true)
    }
}
