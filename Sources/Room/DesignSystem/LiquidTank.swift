import SwiftUI
import RoomCore

/// The water: the exact outline of the liquid inside the card at the current tilt (volume is conserved).
struct LiquidBody: Shape {
    var level: Double
    var angle: Double
    var ripple: Double
    var phase: Double
    var animatableData: Double { get { level } set { level = newValue } }
    func path(in rect: CGRect) -> Path {
        let pts = LiquidGeometry.outline(width: rect.width, height: rect.height, level: level, angle: angle, ripple: ripple, phase: phase)
        guard pts.count > 2 else { return Path() }
        var p = Path()
        p.addLines(pts.map { CGPoint(x: rect.minX + $0.x, y: rect.minY + $0.y) })
        p.closeSubpath()
        return p
    }
}

/// The meniscus: the thin line along the free surface.
struct LiquidMeniscus: Shape {
    var level: Double
    var angle: Double
    var ripple: Double
    var phase: Double
    var animatableData: Double { get { level } set { level = newValue } }
    func path(in rect: CGRect) -> Path {
        let pts = LiquidGeometry.surface(width: rect.width, height: rect.height, level: level, angle: angle, ripple: ripple, phase: phase)
        guard pts.count > 1 else { return Path() }
        var p = Path()
        p.addLines(pts.map { CGPoint(x: rect.minX + $0.x, y: rect.minY + $0.y) })
        return p
    }
}

/// Holds the water's motion between frames.
@MainActor final class LiquidDynamics {
    var physics = LiquidPhysics()
    private var last: Date?
    var calmFrames = 0

    func advance(to date: Date, target: Double) {
        defer { last = date }
        guard let last else { return }
        let before = physics.velocity
        physics.step(dt: date.timeIntervalSince(last), target: target)
        // A big slosh peaks and turns back: that is the water meeting the glass. Felt at the Full level only.
        if abs(physics.angle) > 0.25, abs(before) > 0.3, before * physics.velocity < 0 { Haptics.play(.thump) }
        calmFrames = physics.isSettled(target: target) ? calmFrames + 1 : 0
    }
    func resetClock() { last = nil }
}

/// Your disk as a tank. The sindoor liquid is used space, so the card fills as the disk fills.
/// Cleaning drains it; the marker shows where it will land before you commit.
/// With the Mac's motion sensor, the water behaves like real water: it stays level as you tilt the laptop and
/// sloshes when you move it. Motion answers actions only: the surface sloshes when the level or the Mac changes,
/// then rests, and a still tank costs no frames.
struct LiquidTank: View {
    var level: Double
    var preview: Double?
    var previewLabel: String?
    var motion: MotionSensor?
    var calibration: TiltCalibration = .none
    var tiltEnabled = true
    var onCalibrate: () -> Void = {}
    var devTiltDegrees: Double?                // screenshots only
    var cornerRadius: CGFloat = Token.radiusXL

    @State private var dynamics = LiquidDynamics()
    @State private var awake = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var scenePhase
    private let watcher = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// Where the surface wants to be: level, or tilted to match the Mac.
    private func targetAngle() -> Double {
        if reduce { return 0 }
        if let deg = devTiltDegrees { return deg * .pi / 180 }
        guard tiltEnabled, calibration.isCalibrated, let motion, motion.isRunning else { return 0 }
        return Tilt.targetAngle(sideways: calibration.sideways(motion.latest))
    }

    var body: some View {
        GeometryReader { g in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Glass gives the card its sheen and edge. The liquid sits ABOVE it, so a lens never bends the surface.
            shape.fill(DS.card)
                .overlay { Color.clear.cinnabarGlass(shape, clear: true) }
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 45, paused: !awake)) { ctx in
                        let _ = dynamics.advance(to: ctx.date, target: targetAngle())
                        let angle = dynamics.physics.angle
                        let ripple = dynamics.physics.rippleAmplitude
                        let phase = ctx.date.timeIntervalSinceReferenceDate * 3
                        ZStack {
                            // The water that cleaning will drain is drawn lighter. Its lower edge IS the "after" level,
                            // so the preview needs no line.
                            if let preview, preview < level - 0.004 {
                                LiquidBody(level: level, angle: angle, ripple: ripple, phase: phase)
                                    .fill(DS.sindoor.opacity(scheme == .dark ? 0.15 : 0.09))
                            }
                            LiquidBody(level: draining ? (preview ?? level) : level, angle: angle, ripple: ripple, phase: phase)
                                .fill(DS.sindoor.opacity(scheme == .dark ? 0.42 : 0.24))
                            LiquidMeniscus(level: level, angle: angle, ripple: ripple, phase: phase)
                                .stroke(DS.sindoor, lineWidth: 1.5)
                        }
                    }
                    .clipShape(shape)
                }
                .overlay(alignment: .topTrailing) { previewBadge }
                .overlay(alignment: .bottomTrailing) { calibrationControl }
                .animation(.timingCurve(0.2, 0, 0, 1, duration: reduce ? 0 : 0.9), value: level)
                .animation(.timingCurve(0.2, 0, 0, 1, duration: reduce ? 0 : 0.5), value: preview)
        }
        .onChange(of: level) { _, _ in
            guard !reduce else { return }
            dynamics.physics.velocity += 0.45            // a splash when the level changes
            wake()
        }
        .onReceive(watcher) { _ in watch() }
        .onAppear { if tiltEnabled { motion?.start() }; dynamics.resetClock(); wake() }
        .onDisappear { motion?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { if tiltEnabled { motion?.start() }; dynamics.resetClock(); wake() } else { motion?.stop() }
        }
        .onChange(of: tiltEnabled) { _, on in if on { motion?.start() } else { motion?.stop() }; wake() }
    }

    private func wake() { dynamics.calmFrames = 0; awake = true }

    /// Sleeps the render loop once the water is calm, and wakes it when the Mac moves.
    private func watch() {
        let target = targetAngle()
        if !dynamics.physics.isSettled(target: target, tolerance: 0.012) { if !awake { wake() }; return }
        if awake && dynamics.calmFrames > 20 { awake = false }
    }

    private var draining: Bool { if let preview { return preview < level - 0.004 } else { return false } }

    /// A quiet badge in the corner, above the glass so the lens never distorts it. No line crosses the card.
    @ViewBuilder private var previewBadge: some View {
        if draining, let previewLabel {
            HStack(spacing: 6) { SindoorDot(size: 6); Text(previewLabel).dsText(Token.monoTiny, mono: true, color: DS.text) }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(DS.card.opacity(0.85)))
                .overlay(Capsule().strokeBorder(DS.line, lineWidth: Token.hairline))
                .padding(16).transition(.opacity)
        }
    }

    /// One-time setup: the sensor's axes aren't documented, so the app learns them from "lower the left edge".
    @ViewBuilder private var calibrationControl: some View {
        if tiltEnabled, devTiltDegrees == nil, let motion, motion.isAvailable, !calibration.isCalibrated {
            Button(action: onCalibrate) {
                HStack(spacing: 8) {
                    if motion.isCalibrating { InlineSpinner() }
                    Text(motion.isCalibrating ? "Lower your Mac's left edge" : "Make the water move").font(.ds(.init(13, 500))).foregroundStyle(DS.text)
                }
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(DS.card.opacity(0.5)))
                .cinnabarGlass(Capsule(), interactive: true)
            }
            .buttonStyle(.plain).padding(16)
            .help("Tilt your Mac and the water follows. This takes about five seconds, once.")
        }
    }
}
