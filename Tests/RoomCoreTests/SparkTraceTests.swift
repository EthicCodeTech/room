import Testing
import Foundation
import CoreGraphics
@testable import RoomCore

@Suite("Logo and Spark Trace") struct SparkTraceTests {
    @Test func parsesBasicCommands() throws {
        let c = try SVGPath.parse("M0 0 L10 0 C10 5 5 10 0 10 Z")
        #expect(c == [.move(.zero), .line(CGPoint(x: 10, y: 0)), .curve(CGPoint(x: 10, y: 5), CGPoint(x: 5, y: 10), CGPoint(x: 0, y: 10)), .close])
    }

    @Test func handlesNegativesWithoutSeparators() throws {
        let c = try SVGPath.parse("M0 0 L-5-6")
        #expect(c == [.move(.zero), .line(CGPoint(x: -5, y: -6))])
    }

    @Test func rejectsUnsupportedCommandsInsteadOfDrawingGarbage() {
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 A5 5 0 0 1 10 10") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 x") }
    }

    @Test func realLogoAndLoaderPathsParse() throws {
        let logo = try SVGPath.parse(SparkTraceData.logoPath)
        let motion = try SVGPath.parse(SparkTraceData.motionPath)
        #expect(logo.count > 300); #expect(motion.count > 200)
        #expect(logo.filter { $0 == .close }.count == 3, "e outer, e counter and c each close once")
        let bounds = SVGPath.cgPath(logo).boundingBox
        #expect(bounds.minX >= 0 && bounds.maxX <= SparkTraceData.viewBoxWidth)
        #expect(bounds.minY >= 0 && bounds.maxY <= SparkTraceData.viewBoxHeight)
    }

    @Test func loaderOrbitStartsAndEndsAtTheRestingPlace() throws {
        let s = PathSampler(commands: try SVGPath.parse(SparkTraceData.motionPath))
        let start = s.point(at: 0), end = s.point(at: 1)
        #expect(hypot(start.x, start.y) < 0.5, "the dot starts at its resting place")
        #expect(hypot(end.x, end.y) < 0.5, "and lands home, so stopping always reveals the full logo")
        #expect(s.length > 3000, "it travels all the way around the ec")
    }

    @Test func samplerMovesAtConstantSpeed() throws {
        let s = PathSampler(commands: try SVGPath.parse(SparkTraceData.motionPath))
        let step = 1.0 / 400
        var distances: [CGFloat] = []
        var prev = s.point(at: 0)
        for k in 1...400 { let p = s.point(at: Double(k) * step); distances.append(hypot(p.x - prev.x, p.y - prev.y)); prev = p }
        let mean = distances.reduce(0, +) / CGFloat(distances.count)
        // Straight-line chords shorten slightly on tight curves, but speed must stay within 25% of constant.
        #expect(distances.allSatisfy { abs($0 - mean) / mean < 0.25 }, "paced motion means constant speed")
    }

    @Test func samplerClampsOutOfRangeInput() throws {
        let s = PathSampler(commands: try SVGPath.parse("M0 0 L10 0"))
        #expect(s.point(at: -1) == CGPoint(x: 0, y: 0)); #expect(s.point(at: 5) == CGPoint(x: 10, y: 0))
        #expect(s.point(at: 0.5) == CGPoint(x: 5, y: 0))
    }
}
