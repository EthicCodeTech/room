import Testing
import Foundation
import CoreGraphics
@testable import RoomCore

@Suite("Water in a container") struct MotionTests {
    // MARK: geometry

    @Test func waterVolumeIsExactAtAnyTilt() {
        let w = 560.0, h = 300.0
        for level in [0.05, 0.2, 0.5, 0.8, 0.93] {
            for deg in stride(from: -65.0, through: 65.0, by: 13.0) {
                let a = LiquidGeometry.area(LiquidGeometry.outline(width: w, height: h, level: level, angle: deg * .pi / 180, step: 1))
                let expected = level * w * h
                #expect(abs(a - expected) / expected < 0.02, "level \(level) at \(deg) degrees: \(Int(a)) vs \(Int(expected))")
            }
        }
    }

    @Test func levelWaterIsFlatAndTiltIsSymmetric() {
        let flat = LiquidGeometry.surface(width: 400, height: 200, level: 0.5, angle: 0)
        #expect(flat.allSatisfy { abs($0.y - 100) < 0.01 })
        let up = LiquidGeometry.surface(width: 400, height: 200, level: 0.5, angle: 0.3)
        #expect(up.first!.y > up.last!.y, "positive angle: water is higher on the right, so smaller y there")
        let down = LiquidGeometry.surface(width: 400, height: 200, level: 0.5, angle: -0.3)
        #expect(down.first!.y < down.last!.y)
        #expect(abs((up.first!.y - 100) + (down.first!.y - 100)) < 0.5, "mirror image")
    }

    @Test func emptyAndFullTanksAreHandled() {
        #expect(LiquidGeometry.outline(width: 100, height: 100, level: 0, angle: 0.4).isEmpty)
        let full = LiquidGeometry.outline(width: 100, height: 100, level: 1, angle: 0.4)
        #expect(abs(LiquidGeometry.area(full) - 10_000) < 1)
        #expect(LiquidGeometry.surface(width: 100, height: 100, level: 1, angle: 0.4).isEmpty)
        #expect(LiquidGeometry.outline(width: 0, height: 100, level: 0.5, angle: 0).isEmpty)
    }

    @Test func aNearlyFullTankDoesNotSpillOutOfItsWalls() {
        let pts = LiquidGeometry.outline(width: 500, height: 300, level: 0.93, angle: 1.0, ripple: 6, step: 2)
        #expect(pts.allSatisfy { $0.x >= 0 && $0.x <= 500 && $0.y >= 0 && $0.y <= 300 })
    }

    @Test func rippleMovesOnlyTheFreeSurface() {
        let calm = LiquidGeometry.outline(width: 300, height: 200, level: 0.5, angle: 0, ripple: 0)
        let rough = LiquidGeometry.outline(width: 300, height: 200, level: 0.5, angle: 0, ripple: 6)
        #expect(calm.last == rough.last && calm[calm.count - 2] == rough[rough.count - 2], "the bottom corners never move")
        #expect(zip(calm, rough).contains { abs($0.y - $1.y) > 1 })
    }

    // MARK: physics

    @Test func theSurfaceFollowsATiltAndOvershootsALittle() {
        var p = LiquidPhysics(); var peak = 0.0
        for _ in 0..<600 { p.step(dt: 1.0 / 60, target: 0.5); peak = max(peak, p.angle) }
        #expect(abs(p.angle - 0.5) < 0.01, "settles on the target")
        #expect(peak > 0.5 && peak < 0.72, "a visible slosh, not a snap and not a wild swing: peak \(peak)")
        #expect(p.isSettled(target: 0.5))
    }

    @Test func aStalledFrameOrAHugeStepCannotBreakTheSimulation() {
        var p = LiquidPhysics()
        p.step(dt: 5, target: 1.2); #expect(p.angle.isFinite && abs(p.angle) <= p.maxAngle)
        p.step(dt: .nan, target: 0.2); p.step(dt: -1, target: 0.2); p.step(dt: 0, target: 0.2)
        #expect(p.angle.isFinite && p.velocity.isFinite)
    }

    @Test func theAngleIsClampedAndWallsStopTheMotion() {
        var p = LiquidPhysics()
        for _ in 0..<300 { p.step(dt: 1.0 / 60, target: 3) }
        #expect(p.angle <= p.maxAngle + 1e-9)
    }

    @Test func aStillMacHasLevelWaterAndRippleOnlyWhileMoving() {
        var p = LiquidPhysics()
        for _ in 0..<300 { p.step(dt: 1.0 / 60, target: 0) }
        #expect(p.rippleAmplitude < 0.01)
        p.velocity = 1.5; #expect(p.rippleAmplitude > 3)
    }

    @Test func targetAngleMatchesTheTrueTiltOfAStillMac() {
        // A Mac tilted by 20 degrees feels sin(20) g sideways; the water must sit at 20 degrees.
        for deg in [5.0, 20.0, 40.0, 60.0] {
            let angle = Tilt.targetAngle(sideways: sin(deg * .pi / 180))
            #expect(abs(angle - deg * .pi / 180) < 0.02, "\(deg) degrees")
        }
        #expect(Tilt.targetAngle(sideways: 0) == 0)
        #expect(Tilt.targetAngle(sideways: -0.5) < 0, "left edge down: water goes left")
        #expect(abs(Tilt.targetAngle(sideways: 5)) <= LiquidPhysics.defaultMaxAngle, "a hard shake cannot exceed the limit")
    }

    // MARK: calibration

    func feed(_ cal: inout TiltCalibrator, still: MotionSample, then moved: MotionSample, still n: Int = 60, moved m: Int = 60) -> TiltCalibration? {
        var out: TiltCalibration?
        for i in 0..<n { var s = still; s.x += i % 2 == 0 ? 0.004 : -0.004; out = out ?? cal.add(s) }
        for _ in 0..<m { out = out ?? cal.add(moved) }
        return out
    }

    @Test func lowersTheLeftEdgeAndLearnsTheAxisAndSign() {
        // If the sensor's x goes UP when the left edge goes down, sideways = -x so the water goes left.
        var a = TiltCalibrator()
        let up = feed(&a, still: .init(x: 0, y: 0, z: -1), then: .init(x: 0.45, y: 0.02, z: -0.9))
        #expect(up == TiltCalibration(axis: 0, sign: -1, isCalibrated: true))
        var b = TiltCalibrator()
        let down = feed(&b, still: .init(x: 0, y: 0, z: -1), then: .init(x: -0.45, y: 0.02, z: -0.9))
        #expect(down == TiltCalibration(axis: 0, sign: 1, isCalibrated: true))
        // A sensor whose y axis runs across the screen is detected too.
        var c = TiltCalibrator()
        let alt = feed(&c, still: .init(x: 0, y: 0, z: -1), then: .init(x: 0.01, y: -0.5, z: -0.9))
        #expect(alt == TiltCalibration(axis: 1, sign: 1, isCalibrated: true))
    }

    @Test func calibratedSidewaysIsNegativeWhenTheLeftEdgeIsLowered() {
        var a = TiltCalibrator()
        let moved = MotionSample(x: 0.45, y: 0, z: -0.9)
        let cal = feed(&a, still: .init(x: 0, y: 0, z: -1), then: moved)!
        #expect(cal.sideways(moved) < 0)
        #expect(cal.sideways(.init(x: -0.45, y: 0, z: -0.9)) > 0, "and positive for the opposite tilt")
    }

    @Test func jitterAndShortBumpsDoNotCalibrate() {
        var cal = TiltCalibrator()
        var out: TiltCalibration?
        for i in 0..<400 { out = out ?? cal.add(.init(x: i % 2 == 0 ? 0.03 : -0.03, y: 0.02, z: -1)) }
        #expect(out == nil, "ordinary noise is ignored")
        var bump = TiltCalibrator()
        for _ in 0..<50 { _ = bump.add(.init(x: 0, y: 0, z: -1)) }
        for _ in 0..<5 { out = out ?? bump.add(.init(x: 0.6, y: 0, z: -1)) }       // a 50 ms knock
        for _ in 0..<50 { out = out ?? bump.add(.init(x: 0, y: 0, z: -1)) }
        #expect(out == nil, "a brief knock is not a deliberate tilt")
    }

    @Test func uncalibratedSettingsKeepTheTankStill() {
        #expect(AppSettings().tilt.isCalibrated == false)
        #expect(AppSettings().tiltEnabled)
    }
}

@Suite("Map hover and click") struct MapHitTests {
    func tiles() -> (rect: CGRect, tiles: [Treemap.Tile]) {
        let rect = CGRect(x: 8, y: 8, width: 700, height: 400)
        let items = (1...14).map { (id: "n\($0)", name: "n\($0)", bytes: Int64($0 * $0 * 1_000_000)) }
        return (rect, Treemap.layout(items, in: rect))
    }

    @Test func everyPointInTheMapBelongsToExactlyOneTile() {
        let (rect, tiles) = tiles()
        var x = rect.minX
        while x < rect.maxX {
            var y = rect.minY
            while y < rect.maxY {
                let p = CGPoint(x: x, y: y)
                let hits = tiles.filter { $0.rect.contains(p) }
                #expect(hits.count == 1, "\(p) is in \(hits.count) tiles: a hover could highlight two, or none")
                #expect(Treemap.tile(at: p, in: tiles)?.id == hits.first?.id)
                y += 7.3
            }
            x += 7.3
        }
    }

    @Test func pointsOutsideTheMapHitNothingSoHoverClears() {
        let (rect, tiles) = tiles()
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: rect.maxX + 5, y: 100), CGPoint(x: 100, y: rect.maxY + 5), CGPoint(x: -10, y: -10)] {
            #expect(Treemap.tile(at: p, in: tiles) == nil)
        }
    }

    @Test func aTilesCentreMapsBackToThatTile() {
        let (_, tiles) = tiles()
        for t in tiles { #expect(Treemap.tile(at: CGPoint(x: t.rect.midX, y: t.rect.midY), in: tiles)?.id == t.id) }
    }
}
