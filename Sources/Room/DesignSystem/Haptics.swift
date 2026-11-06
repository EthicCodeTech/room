import AppKit
import RoomCore

/// Cinnabar's haptic vocabulary on the Mac trackpad, which has three feedback strengths and no amplitude control.
///
/// Rules from the spec: haptics answer actions, are never the only signal, and respect the user's setting and
/// Reduce Motion. Hover detents break the "nothing on hover" rule, so they only play at the opt-in Full level.
/// A trackpad only answers while a finger is on it, so clicks from a mouse or the keyboard stay silent.
@MainActor
enum Haptics {
    enum Pattern: CaseIterable {
        case select, confirm, attention, spark, decline, pending
        case detent        // a hairline tick when the pointer crosses an edge (Full only)
        case thump         // the water meeting the glass (Full only)

        var requires: HapticLevel { self == .detent || self == .thump ? .full : .standard }
        /// Shortest gap between two plays of the same pattern, so bursts stay crisp instead of turning to buzz.
        fileprivate var minGap: TimeInterval {
            switch self { case .detent: 0.05; case .thump: 0.22; case .pending: 0.8; case .decline: 0.5; default: 0.04 }
        }
        var title: String {
            switch self {
            case .select: "Tick"; case .confirm: "Confirm"; case .attention: "Nudge"; case .spark: "Spark"
            case .decline: "No"; case .pending: "Heartbeat"; case .detent: "Detent"; case .thump: "Thump"
            }
        }
    }

    static var level: HapticLevel = .standard
    private static var lastPlayed: [Pattern: Date] = [:]
    private static var lastFailure = Date.distantPast

    static func play(_ pattern: Pattern, force: Bool = false) {
        guard force || (level.permits(pattern.requires) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        let now = Date()
        if let last = lastPlayed[pattern], now.timeIntervalSince(last) < pattern.minGap { return }
        // A failure outranks a success that lands in the same moment.
        if pattern == .decline { lastFailure = now }
        else if pattern == .confirm || pattern == .spark, now.timeIntervalSince(lastFailure) < 0.6 { return }
        lastPlayed[pattern] = now

        let steps: [(delay: Double, kind: NSHapticFeedbackManager.FeedbackPattern)]
        switch pattern {
        case .select: steps = [(0, .alignment)]                                                    // a tiny tick
        case .confirm: steps = [(0, .levelChange)]                                                 // one clean, strong tap
        case .attention: steps = [(0, .alignment), (0.082, .alignment)]                            // a gentle double nudge
        case .spark: steps = [(0, .alignment), (0.084, .levelChange)]                              // low tap, then a crisp lift
        case .decline: steps = [(0, .generic), (0.15, .generic), (0.30, .generic)]                 // three firm buzzes
        case .pending: steps = [(0, .alignment), (0.2, .alignment), (0.66, .alignment), (0.86, .alignment)]   // a slow heartbeat
        case .detent: steps = [(0, .alignment)]
        case .thump: steps = [(0, .levelChange)]
        }
        for s in steps {
            if s.delay == 0 { NSHapticFeedbackManager.defaultPerformer.perform(s.kind, performanceTime: .now) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + s.delay) {
                NSHapticFeedbackManager.defaultPerformer.perform(s.kind, performanceTime: .now) } }
        }
    }
}
