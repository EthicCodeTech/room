import Foundation
import CoreGraphics

// MARK: - Sensor samples and calibration

/// One accelerometer reading in g. The axes are the sensor's own; calibration says which one is "sideways".
public struct MotionSample: Sendable, Equatable {
    public var x: Double, y: Double, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Which sensor axis points across the screen, and which way. Learned once from a "lower the left edge" gesture,
/// because Apple does not document the axes of this sensor and guessing would make the water flow uphill.
public struct TiltCalibration: Codable, Sendable, Equatable {
    public var axis: Int            // 0 = sensor x, 1 = sensor y
    public var sign: Double         // +1 or -1
    public var isCalibrated: Bool
    public static let none = TiltCalibration(axis: 0, sign: 1, isCalibrated: false)
    public init(axis: Int, sign: Double, isCalibrated: Bool) { self.axis = axis; self.sign = sign; self.isCalibrated = isCalibrated }

    /// Gravity (or acceleration) along the screen's +x. Positive = the right edge is lower.
    public func sideways(_ s: MotionSample) -> Double { sign * (axis == 0 ? s.x : s.y) }
}

/// Watches readings until the user lowers the left edge, then works out axis and sign.
public struct TiltCalibrator: Sendable {
    public var threshold = 0.18             // g of change that counts as a deliberate tilt
    public var holdSamples = 15             // about 150 ms at 100 Hz
    public var baselineSamples = 40
    private var baselineSum = (x: 0.0, y: 0.0)
    private var count = 0
    private var held = 0
    private var smoothed: (x: Double, y: Double)?

    public init() {}
    public var hasBaseline: Bool { count >= baselineSamples }

    /// Returns a calibration once a deliberate tilt has been held.
    public mutating func add(_ s: MotionSample) -> TiltCalibration? {
        if count < baselineSamples {
            baselineSum.x += s.x; baselineSum.y += s.y; count += 1
            return nil
        }
        let base = (x: baselineSum.x / Double(baselineSamples), y: baselineSum.y / Double(baselineSamples))
        let a = 0.25                                         // light smoothing so a jolt isn't mistaken for a tilt
        smoothed = (x: (smoothed?.x ?? s.x) * (1 - a) + s.x * a, y: (smoothed?.y ?? s.y) * (1 - a) + s.y * a)
        let dx = smoothed!.x - base.x, dy = smoothed!.y - base.y
        if max(abs(dx), abs(dy)) >= threshold { held += 1 } else { held = 0 }
        guard held >= holdSamples else { return nil }
        let axis = abs(dx) >= abs(dy) ? 0 : 1
        let delta = axis == 0 ? dx : dy
        // The left edge went down, so "sideways" must come out negative: sign * delta < 0.
        return TiltCalibration(axis: axis, sign: delta > 0 ? -1 : 1, isCalibrated: true)
    }
}

// MARK: - Water physics

public enum Tilt {
    /// Surface angle (radians, positive = water higher on the right) for the gravity felt in the screen plane.
    /// `sideways` is along +x; the "down" part is derived so the angle equals the true tilt for a still Mac.
    public static func targetAngle(sideways: Double, maxAngle: Double = LiquidPhysics.defaultMaxAngle) -> Double {
        let side = max(-1.6, min(1.6, sideways))
        let down = max(0.35, (1 - min(1, abs(side)) * min(1, abs(side))).squareRoot())
        return max(-maxAngle, min(maxAngle, atan2(side, down)))
    }
}

/// Damped slosh: the surface angle chases the target like water in a shallow tank, overshooting a little.
public struct LiquidPhysics: Sendable {
    public static let defaultMaxAngle = 70.0 * .pi / 180
    public var angle = 0.0
    public var velocity = 0.0
    public var stiffness = 38.0            // about 1 Hz natural frequency
    public var damping = 4.3               // damping ratio about 0.35: roughly 30% overshoot, settled in under two seconds
    public var maxAngle = LiquidPhysics.defaultMaxAngle
    public init() {}

    public mutating func step(dt: Double, target: Double) {
        guard dt > 0, dt.isFinite else { return }
        let dt = min(dt, 0.25)                                   // a stalled frame must not blow the simulation up
        let n = max(1, Int((dt / 0.008).rounded(.up)))
        let h = dt / Double(n)
        for _ in 0..<n {
            let accel = -stiffness * (angle - target) - damping * velocity
            velocity += accel * h
            angle += velocity * h
        }
        if angle > maxAngle { angle = maxAngle; velocity = min(0, velocity) }
        if angle < -maxAngle { angle = -maxAngle; velocity = max(0, velocity) }
    }

    public func isSettled(target: Double, tolerance: Double = 0.004) -> Bool {
        abs(angle - target) < tolerance && abs(velocity) < tolerance
    }

    /// Wave height in points: the surface ripples while it moves and goes flat at rest.
    public var rippleAmplitude: Double { min(7, abs(velocity) * 6) }
}

// MARK: - Geometry

public enum LiquidGeometry {
    /// Height of the surface at x for a line through (width/2, ys) tilted by `angle`. y grows downward.
    @inline(__always) static func lineY(x: Double, ys: Double, tan: Double, width: Double) -> Double { ys - tan * (x - width / 2) }

    /// Finds the surface height that keeps the water volume exact at any tilt (volume is conserved, not the level).
    static func surfaceHeight(width: Double, height: Double, level: Double, angle: Double) -> Double {
        let t = Foundation.tan(angle), target = max(0, min(1, level)) * width * height
        func area(_ ys: Double) -> Double {
            let steps = 64
            var sum = 0.0
            for i in 0..<steps {
                let x = (Double(i) + 0.5) / Double(steps) * width
                let y = max(0, min(height, lineY(x: x, ys: ys, tan: t, width: width)))
                sum += (height - y) * width / Double(steps)
            }
            return sum
        }
        var lo = -abs(t) * width - 1, hi = height + abs(t) * width + 1      // area(lo) is full, area(hi) is empty
        for _ in 0..<42 { let mid = (lo + hi) / 2; if area(mid) > target { lo = mid } else { hi = mid } }
        return (lo + hi) / 2
    }

    /// The liquid's outline inside a rect of the given size, y down. `ripple` adds waves to the surface only.
    public static func outline(width: Double, height: Double, level: Double, angle: Double,
                               ripple: Double = 0, phase: Double = 0, step: Double = 4) -> [CGPoint] {
        guard width > 0, height > 0, level > 0 else { return [] }
        if level >= 1 { return [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 0, y: height)] }
        let ys = surfaceHeight(width: width, height: height, level: level, angle: angle)
        let t = Foundation.tan(angle)
        var pts: [CGPoint] = []
        var x = 0.0
        while x < width + step {
            let cx = min(x, width)
            var y = lineY(x: cx, ys: ys, tan: t, width: width)
            if y > 0 && y < height { y += sin(cx / width * .pi * 3 + phase) * ripple }     // only the free surface ripples
            pts.append(CGPoint(x: cx, y: max(0, min(height, y))))
            if cx >= width { break }
            x += step
        }
        pts.append(CGPoint(x: width, y: height)); pts.append(CGPoint(x: 0, y: height))
        return pts
    }

    /// Just the free surface (where it is inside the tank), for the thin meniscus line.
    public static func surface(width: Double, height: Double, level: Double, angle: Double,
                               ripple: Double = 0, phase: Double = 0, step: Double = 4) -> [CGPoint] {
        guard level > 0, level < 1 else { return [] }
        let ys = surfaceHeight(width: width, height: height, level: level, angle: angle)
        let t = Foundation.tan(angle)
        var pts: [CGPoint] = []
        var x = 0.0
        while x <= width + step {
            let cx = min(x, width)
            let y = lineY(x: cx, ys: ys, tan: t, width: width)
            if y > 0 && y < height { pts.append(CGPoint(x: cx, y: y + sin(cx / width * .pi * 3 + phase) * ripple)) }
            if cx >= width { break }
            x += step
        }
        return pts
    }

    /// Shoelace area, for tests.
    public static func area(_ p: [CGPoint]) -> Double {
        guard p.count > 2 else { return 0 }
        var s = 0.0
        for i in 0..<p.count { let a = p[i], b = p[(i + 1) % p.count]; s += Double(a.x * b.y - b.x * a.y) }
        return abs(s) / 2
    }
}
