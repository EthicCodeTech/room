import Foundation
import CoreGraphics

/// Minimal SVG path support: absolute M, L, C, Z, which is all the Cinnabar logo and loader use.
public enum SVGPathCommand: Equatable, Sendable {
    case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
}

public enum SVGPath {
    public enum ParseError: Error { case unsupported(Character), malformed }

    public static func parse(_ d: String) throws -> [SVGPathCommand] {
        var out: [SVGPathCommand] = []
        var tokens: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter { flush(); tokens.append(String(ch)) }
            else if ch == " " || ch == "," || ch == "\n" || ch == "\t" { flush() }
            else if ch == "-" && !cur.isEmpty && !cur.hasSuffix("e") { flush(); cur.append(ch) }
            else { cur.append(ch) }
        }
        flush()

        var i = 0; var op: Character = "M"
        func num() throws -> CGFloat { guard i < tokens.count, let v = Double(tokens[i]) else { throw ParseError.malformed }; i += 1; return CGFloat(v) }
        func pt() throws -> CGPoint { CGPoint(x: try num(), y: try num()) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter, tokens[i].count == 1 { op = c; i += 1 }
            switch op {
            case "M": out.append(.move(try pt())); op = "L"      // extra pairs after M are implicit lineto
            case "L": out.append(.line(try pt()))
            case "C": out.append(.curve(try pt(), try pt(), try pt()))
            case "Z", "z": out.append(.close)
            default: throw ParseError.unsupported(op)
            }
        }
        return out
    }

    public static func cgPath(_ commands: [SVGPathCommand]) -> CGPath {
        let p = CGMutablePath()
        for c in commands {
            switch c {
            case .move(let a): p.move(to: a)
            case .line(let a): p.addLine(to: a)
            case .curve(let c1, let c2, let e): p.addCurve(to: e, control1: c1, control2: c2)
            case .close: p.closeSubpath()
            }
        }
        return p
    }
}

/// Walks a path at constant speed (SVG `calcMode="paced"`), so a dot glides without speeding up on curves.
public struct PathSampler: Sendable {
    public let points: [CGPoint]
    public let cumulative: [CGFloat]
    public var length: CGFloat { cumulative.last ?? 0 }

    public init(commands: [SVGPathCommand], curveSteps: Int = 24) {
        var pts: [CGPoint] = []
        var current = CGPoint.zero
        for c in commands {
            switch c {
            case .move(let a): current = a; pts.append(a)
            case .line(let a): pts.append(a); current = a
            case .curve(let c1, let c2, let e):
                for s in 1...curveSteps {
                    let t = CGFloat(s) / CGFloat(curveSteps), u = 1 - t
                    pts.append(CGPoint(
                        x: u * u * u * current.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * e.x,
                        y: u * u * u * current.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * e.y))
                }
                current = e
            case .close: break
            }
        }
        points = pts
        var cum: [CGFloat] = [0]
        for k in 1..<max(1, pts.count) { cum.append(cum[k - 1] + hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)) }
        cumulative = cum
    }

    /// Position after travelling `fraction` (0...1) of the path's length.
    public func point(at fraction: Double) -> CGPoint {
        guard points.count > 1, length > 0 else { return points.first ?? .zero }
        let target = CGFloat(min(max(fraction, 0), 1)) * length
        var lo = 0, hi = cumulative.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if cumulative[mid] < target { lo = mid + 1 } else { hi = mid } }
        let k = max(1, lo)
        let seg = cumulative[k] - cumulative[k - 1]
        let f = seg > 0 ? (target - cumulative[k - 1]) / seg : 0
        return CGPoint(x: points[k - 1].x + (points[k].x - points[k - 1].x) * f, y: points[k - 1].y + (points[k].y - points[k - 1].y) * f)
    }
}
