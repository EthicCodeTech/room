import SwiftUI
import RoomCore

/// The "ec" outline from the Cinnabar spec, drawn with even-odd fill.
struct ECMark: Shape {
    static let cgPath: CGPath = SVGPath.cgPath((try? SVGPath.parse(SparkTraceData.logoPath)) ?? [])
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / SparkTraceData.viewBoxWidth, rect.height / SparkTraceData.viewBoxHeight)
        let dx = rect.minX + (rect.width - SparkTraceData.viewBoxWidth * s) / 2
        let dy = rect.minY + (rect.height - SparkTraceData.viewBoxHeight * s) / 2
        return Path(Self.cgPath).applying(CGAffineTransform(scaleX: s, y: s)).applying(CGAffineTransform(translationX: dx, y: dy))
    }
}

/// The static logo: the "ec" with the sindoor dot at rest on the tip of the c.
struct LogoMark: View {
    var height: CGFloat = 24
    var body: some View {
        SparkTraceLoader(isRunning: false, height: height)
    }
}

/// The official loader. The dot leaves its resting place, circles the outline at constant speed, and lands home.
/// Used for full-page and brand moments only; lists use skeletons and buttons use the inline spinner.
struct SparkTraceLoader: View {
    var isRunning = true
    var height: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let sampler = PathSampler(commands: (try? SVGPath.parse(SparkTraceData.motionPath)) ?? [])

    var body: some View {
        let scale = height / SparkTraceData.viewBoxHeight
        let width = SparkTraceData.viewBoxWidth * scale
        TimelineView(.animation(minimumInterval: nil, paused: !isRunning)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let orbit = isRunning && !reduce
            let fraction = orbit ? t.truncatingRemainder(dividingBy: Token.durLoader) / Token.durLoader : 0
            let offset = Self.sampler.point(at: fraction)
            // Reduced motion: the dot pulses in place instead of orbiting (1 to 0.4 to 1 over 1.6s).
            let pulse = (isRunning && reduce) ? 0.7 + 0.3 * cos(t.truncatingRemainder(dividingBy: 1.6) / 1.6 * 2 * .pi) : 1
            ZStack(alignment: .topLeading) {
                ECMark().fill(DS.text, style: FillStyle(eoFill: true))
                Circle().fill(DS.sindoor)
                    .frame(width: SparkTraceData.dotRadius * 2 * scale, height: SparkTraceData.dotRadius * 2 * scale)
                    .opacity(pulse)
                    .position(x: (SparkTraceData.restX + offset.x) * scale, y: (SparkTraceData.restY + offset.y) * scale)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement().accessibilityLabel(isRunning ? "Loading" : "Room")
    }
}
