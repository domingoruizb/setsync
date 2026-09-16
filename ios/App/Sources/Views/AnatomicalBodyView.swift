import SwiftUI

/// specs/modules/03-ai-and-muscle-map.md §2 (superseding Task 5.2's
/// decision): a vectorial anatomical body silhouette — anterior and
/// posterior — replacing the modular tile grid `MuscleHeatMapView`. Task
/// 5.2 chose the tile grid specifically because there was no reference
/// image and no local Xcode/SwiftUI preview to visually verify a
/// hand-drawn `Path`-based body outline; that constraint hasn't changed,
/// so this view is deliberately built from simple, predictable composed
/// primitives (`Ellipse`/`Capsule`/`RoundedRectangle`, plus a straight-line
/// polygon for the torso) at proportions derived from standard body
/// proportion ratios, rather than freehand bezier anatomical tracing —
/// a schematic diagram, not fine-art anatomy. It should be expected to
/// need visual polish once actually seen on a device, the same way the
/// Garmin watch UI needed several iteration rounds after real hardware
/// feedback.
///
/// A pure/stateless-over-its-input component, like the view it replaces:
/// the caller computes `scores` via `AnatomicalBodyView.muscleScores(from:)`
/// and passes them in.
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
                ZStack {
                    BodyOutlineShape()
                        .stroke(Color(white: 0.85), lineWidth: 1.5)

                    ForEach(Self.regionSpecs.filter { $0.region.side == selectedSide }, id: \.region) { spec in
                        regionView(spec, size: proxy.size)
                    }
                }
            }
            .aspectRatio(0.46, contentMode: .fit)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func regionView(_ spec: RegionSpec, size: CGSize) -> some View {
        let color = MuscleGroup.heatColor(forScore: spec.region.score(from: scores))
        let regionSize = CGSize(width: spec.widthFraction * size.width, height: spec.heightFraction * size.height)
        let y = spec.yFraction * size.height

        if spec.mirrored {
            let dx = spec.xOffsetFraction * size.width
            regionShape(spec.kind)
                .fill(color)
                .frame(width: regionSize.width, height: regionSize.height)
                .position(x: size.width / 2 - dx, y: y)
            regionShape(spec.kind)
                .fill(color)
                .frame(width: regionSize.width, height: regionSize.height)
                .position(x: size.width / 2 + dx, y: y)
        } else {
            regionShape(spec.kind)
                .fill(color)
                .frame(width: regionSize.width, height: regionSize.height)
                .position(x: size.width / 2, y: y)
        }
    }

    @ViewBuilder
    private func regionShape(_ kind: RegionSpec.Kind) -> some View {
        switch kind {
        case .capsule: Capsule()
        case .ellipse: Ellipse()
        case .roundedRect: RoundedRectangle(cornerRadius: 10)
        }
    }

    // specs/01-system-spec.md §3.2: Score = 1.0 per set for each primary
    // muscle, 0.4 for each secondary muscle. Unchanged from the tile grid
    // this view replaces — only the rendering changed, not the scoring.
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
// one region's `muscles` list, the same invariant the tile grid enforced
// over its own anterior/posterior lists.
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

// Proportional layout (fractions of the container's width/height, origin
// top-leading) for each region's overlay shape. `xOffsetFraction` is the
// horizontal distance from the body's vertical centerline; `mirrored`
// regions are drawn twice, once on each side.
private struct RegionSpec {
    let region: MuscleGroup.BodyRegion
    let xOffsetFraction: CGFloat
    let yFraction: CGFloat
    let widthFraction: CGFloat
    let heightFraction: CGFloat
    let mirrored: Bool
    let kind: Kind

    enum Kind {
        case capsule, ellipse, roundedRect
    }
}

private extension AnatomicalBodyView {
    static let regionSpecs: [RegionSpec] = [
        // Anterior
        RegionSpec(region: .chest, xOffsetFraction: 0.13, yFraction: 0.225, widthFraction: 0.16, heightFraction: 0.09, mirrored: true, kind: .ellipse),
        RegionSpec(region: .frontDeltoids, xOffsetFraction: 0.28, yFraction: 0.175, widthFraction: 0.09, heightFraction: 0.09, mirrored: true, kind: .ellipse),
        RegionSpec(region: .biceps, xOffsetFraction: 0.30, yFraction: 0.26, widthFraction: 0.075, heightFraction: 0.13, mirrored: true, kind: .capsule),
        RegionSpec(region: .forearms, xOffsetFraction: 0.315, yFraction: 0.40, widthFraction: 0.065, heightFraction: 0.14, mirrored: true, kind: .capsule),
        RegionSpec(region: .abs, xOffsetFraction: 0, yFraction: 0.33, widthFraction: 0.16, heightFraction: 0.17, mirrored: false, kind: .roundedRect),
        RegionSpec(region: .quads, xOffsetFraction: 0.115, yFraction: 0.58, widthFraction: 0.11, heightFraction: 0.20, mirrored: true, kind: .capsule),

        // Posterior
        RegionSpec(region: .traps, xOffsetFraction: 0, yFraction: 0.185, widthFraction: 0.34, heightFraction: 0.11, mirrored: false, kind: .ellipse),
        RegionSpec(region: .rearDeltoids, xOffsetFraction: 0.28, yFraction: 0.175, widthFraction: 0.09, heightFraction: 0.09, mirrored: true, kind: .ellipse),
        RegionSpec(region: .lats, xOffsetFraction: 0.17, yFraction: 0.27, widthFraction: 0.15, heightFraction: 0.17, mirrored: true, kind: .ellipse),
        RegionSpec(region: .triceps, xOffsetFraction: 0.30, yFraction: 0.26, widthFraction: 0.075, heightFraction: 0.13, mirrored: true, kind: .capsule),
        RegionSpec(region: .lowerBack, xOffsetFraction: 0, yFraction: 0.40, widthFraction: 0.13, heightFraction: 0.08, mirrored: false, kind: .roundedRect),
        RegionSpec(region: .glutes, xOffsetFraction: 0.095, yFraction: 0.465, widthFraction: 0.13, heightFraction: 0.10, mirrored: true, kind: .roundedRect),
        RegionSpec(region: .hamstrings, xOffsetFraction: 0.115, yFraction: 0.58, widthFraction: 0.11, heightFraction: 0.20, mirrored: true, kind: .capsule),
        RegionSpec(region: .calves, xOffsetFraction: 0.105, yFraction: 0.80, widthFraction: 0.08, heightFraction: 0.14, mirrored: true, kind: .capsule)
    ]
}

// Neutral light-gray base body contour: head, neck, torso (a straight-line
// polygon, not bezier curves — easier to keep geometrically correct
// without a visual preview), arms and legs (rounded-rect "capsule"
// outlines). Anterior and posterior share the same outline; only the
// overlaid muscle regions differ between the two sides.
private struct BodyOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        let headRadius = 0.065 * w
        let headCenterY = 0.06 * h + headRadius
        path.addEllipse(in: CGRect(x: 0.5 * w - headRadius, y: headCenterY - headRadius, width: headRadius * 2, height: headRadius * 2))

        let neckHalfWidth = 0.045 * w
        let neckTopY = headCenterY + headRadius
        let neckBottomY = 0.16 * h

        let shoulderHalfWidth = 0.27 * w
        let shoulderY = 0.16 * h
        let waistHalfWidth = 0.155 * w
        let waistY = 0.38 * h
        let hipHalfWidth = 0.19 * w
        let hipY = 0.44 * h

        path.move(to: CGPoint(x: 0.5 * w - neckHalfWidth, y: neckTopY))
        path.addLine(to: CGPoint(x: 0.5 * w - neckHalfWidth, y: neckBottomY))
        path.addLine(to: CGPoint(x: 0.5 * w - shoulderHalfWidth, y: shoulderY))
        path.addLine(to: CGPoint(x: 0.5 * w - waistHalfWidth, y: waistY))
        path.addLine(to: CGPoint(x: 0.5 * w - hipHalfWidth, y: hipY))
        path.addLine(to: CGPoint(x: 0.5 * w + hipHalfWidth, y: hipY))
        path.addLine(to: CGPoint(x: 0.5 * w + waistHalfWidth, y: waistY))
        path.addLine(to: CGPoint(x: 0.5 * w + shoulderHalfWidth, y: shoulderY))
        path.addLine(to: CGPoint(x: 0.5 * w + neckHalfWidth, y: neckBottomY))
        path.addLine(to: CGPoint(x: 0.5 * w + neckHalfWidth, y: neckTopY))

        let armWidth = 0.075 * w
        let armTopY = shoulderY
        let armBottomY = 0.50 * h
        for sign: CGFloat in [-1, 1] {
            let armCenterX = 0.5 * w + sign * (shoulderHalfWidth + armWidth * 0.5)
            let armRect = CGRect(x: armCenterX - armWidth / 2, y: armTopY, width: armWidth, height: armBottomY - armTopY)
            path.addRoundedRect(in: armRect, cornerSize: CGSize(width: armWidth / 2, height: armWidth / 2))
        }

        let legWidth = 0.115 * w
        let legTopY = hipY
        let legBottomY = 0.92 * h
        for sign: CGFloat in [-1, 1] {
            let legCenterX = 0.5 * w + sign * (hipHalfWidth * 0.55)
            let legRect = CGRect(x: legCenterX - legWidth / 2, y: legTopY, width: legWidth, height: legBottomY - legTopY)
            path.addRoundedRect(in: legRect, cornerSize: CGSize(width: legWidth / 2, height: legWidth / 2))
        }

        return path
    }
}
