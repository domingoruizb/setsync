import SwiftUI

/// Parses a minimal-but-complete subset of the SVG path `d` grammar
/// (M/m, L/l, C/c, Q/q, A/a, Z/z — every command actually used by the
/// anatomical body-part path data in `BodyAtlasData.swift`) into a
/// SwiftUI `Path`. This exists so the app can render **real anatomical
/// vector paths** (see `BodyAtlasData.swift` for provenance/license)
/// instead of hand-approximated shapes.
///
/// Numbers in SVG path data may be packed with no separating whitespace
/// whenever a sign or a second decimal point makes the boundary
/// unambiguous (e.g. `"37.02.75"` is two numbers, `37.02` and `.75`, and
/// `"1.71 1.7-89.2"` is three, `1.71`, `1.7`, `-89.2`) — real-world minified
/// path data (including this project's vendored data) relies on this, so
/// the tokenizer implements it directly rather than splitting on
/// whitespace/commas.
enum SVGPathParser {
    static func path(from d: String) -> Path {
        var path = Path()
        var index = d.startIndex
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = "M"

        func skipSeparators() {
            while index < d.endIndex, d[index] == " " || d[index] == "," || d[index] == "\n" || d[index] == "\t" || d[index] == "\r" {
                index = d.index(after: index)
            }
        }

        func nextNumber() -> CGFloat? {
            skipSeparators()
            guard index < d.endIndex else { return nil }
            var text = ""
            var sawDot = false
            var sawDigit = false

            if d[index] == "+" || d[index] == "-" {
                text.append(d[index])
                index = d.index(after: index)
            }
            while index < d.endIndex {
                let c = d[index]
                if c.isNumber {
                    sawDigit = true
                    text.append(c)
                    index = d.index(after: index)
                } else if c == "." && !sawDot {
                    sawDot = true
                    text.append(c)
                    index = d.index(after: index)
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(text) else { return nil }
            return CGFloat(value)
        }

        func nextPoint() -> CGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else { return nil }
            return CGPoint(x: x, y: y)
        }

        // The arc command's large-arc-flag/sweep-flag are always exactly
        // one character (0 or 1) and real-world path data (including this
        // project's vendored data) routinely packs them with no separator
        // before the next number — e.g. "011.7" means flag 0, flag 1,
        // then the number 1.7. Reading a flag with the general
        // number-tokenizer above would greedily consume "011.7" as a
        // single malformed number, so flags get their own single-char read.
        func nextFlag() -> Bool? {
            skipSeparators()
            guard index < d.endIndex, d[index] == "0" || d[index] == "1" else { return nil }
            let value = d[index] == "1"
            index = d.index(after: index)
            return value
        }

        func resolved(_ p: CGPoint, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + p.x, y: current.y + p.y) : p
        }

        while true {
            skipSeparators()
            guard index < d.endIndex else { break }
            let c = d[index]
            if c.isLetter {
                command = c
                index = d.index(after: index)
            }
            let relative = command.isLowercase

            switch Character(command.lowercased()) {
            case "m":
                guard let p = nextPoint() else { return path }
                current = resolved(p, relative: relative)
                subpathStart = current
                path.move(to: current)
                // Extra coordinate pairs right after an initial M are
                // implicit lineto commands, per the SVG spec.
                command = relative ? "l" : "L"
            case "l":
                guard let p = nextPoint() else { return path }
                current = resolved(p, relative: relative)
                path.addLine(to: current)
            case "c":
                guard let c1 = nextPoint(), let c2 = nextPoint(), let end = nextPoint() else { return path }
                let control1 = resolved(c1, relative: relative)
                let control2 = resolved(c2, relative: relative)
                let endPoint = resolved(end, relative: relative)
                path.addCurve(to: endPoint, control1: control1, control2: control2)
                current = endPoint
            case "q":
                guard let c1 = nextPoint(), let end = nextPoint() else { return path }
                let control = resolved(c1, relative: relative)
                let endPoint = resolved(end, relative: relative)
                path.addQuadCurve(to: endPoint, control: control)
                current = endPoint
            case "a":
                guard
                    let rx = nextNumber(), let ry = nextNumber(),
                    let rotation = nextNumber(),
                    let largeArc = nextFlag(), let sweep = nextFlag(),
                    let end = nextPoint()
                else { return path }
                let endPoint = resolved(end, relative: relative)
                appendArc(
                    to: &path, from: current, to: endPoint,
                    rx: rx, ry: ry, rotationDegrees: rotation,
                    largeArc: largeArc, sweep: sweep
                )
                current = endPoint
            case "z":
                path.closeSubpath()
                current = subpathStart
            default:
                return path
            }
        }
        return path
    }

    // SVG 1.1 spec, Appendix F.6 ("Elliptical arc implementation notes"):
    // converts an arc's endpoint parameterization (rx, ry, x-axis
    // rotation, large-arc-flag, sweep-flag, endpoint) into its center
    // parameterization, then emits it as one cubic Bézier per <=90° of
    // arc (the standard, well-defined approximation) — a documented
    // formula, not a visual approximation.
    private static func appendArc(
        to path: inout Path, from start: CGPoint, to end: CGPoint,
        rx: CGFloat, ry: CGFloat, rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        if rx == 0 || ry == 0 || (start.x == end.x && start.y == end.y) {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = den == 0 ? 0 : sign * (num / den).squareRoot()
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaTheta = angleBetween((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep, deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let delta = deltaTheta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)

        func point(at theta: CGFloat) -> CGPoint {
            let x = rx * cos(theta)
            let y = ry * sin(theta)
            return CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y)
        }

        func derivative(at theta: CGFloat) -> CGPoint {
            let x = -rx * sin(theta)
            let y = ry * cos(theta)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var theta = theta1
        for _ in 0..<segments {
            let thetaEnd = theta + delta
            let p1 = point(at: theta)
            let p2 = point(at: thetaEnd)
            let d1 = derivative(at: theta)
            let d2 = derivative(at: thetaEnd)
            let control1 = CGPoint(x: p1.x + t * d1.x, y: p1.y + t * d1.y)
            let control2 = CGPoint(x: p2.x - t * d2.x, y: p2.y - t * d2.y)
            path.addCurve(to: p2, control1: control1, control2: control2)
            theta = thetaEnd
        }
    }
}
