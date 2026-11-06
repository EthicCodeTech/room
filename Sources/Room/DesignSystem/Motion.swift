import SwiftUI
import AppKit
import RoomCore

/// One motion system, built from Cinnabar's timing tokens, so everything in Room moves the same way.
/// Short and soft (150 to 300 ms) on the standard curve, and it all collapses to instant under Reduce Motion.
enum Motion {
    case fast       // hovers, colour changes (150 ms)
    case base       // toggles, small state changes (200 ms)
    case panel      // cards, lists and panels (300 ms)
    case slow       // layout that rearranges as data arrives (450 ms)
    case instant    // no animation: for changes that arrive too fast to look good in motion

    var animation: Animation? {
        switch self {
        case .fast: .easeOut(duration: Token.durFast)
        case .base: .timingCurve(0.2, 0, 0, 1, duration: Token.durBase)
        case .panel: .timingCurve(0.2, 0, 0, 1, duration: Token.durPanel)
        case .slow: .timingCurve(0.2, 0, 0, 1, duration: 0.45)
        case .instant: nil
        }
    }

    /// `withAnimation` that honours Reduce Motion.
    @MainActor static func run(_ motion: Motion = .panel, _ body: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { body() } else { withAnimation(motion.animation, body) }
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let motion: Motion
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View { content.animation(reduce ? nil : motion.animation, value: value) }
}

extension View {
    /// Animates changes to `value` with a Cinnabar motion, or not at all when Reduce Motion is on.
    func motion<V: Equatable>(_ motion: Motion = .panel, value: V) -> some View { modifier(MotionModifier(motion: motion, value: value)) }
}

extension AnyTransition {
    /// Content arriving: fades in while rising a few points. Leaves by fading, so a stale direction never shows.
    static var rise: AnyTransition { .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity) }
    /// A list row appearing or leaving.
    static var row: AnyTransition { .asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity) }
    /// A page arriving from the side it is next to in the navigation.
    static func page(forward: Bool) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 22 : -22)), removal: .opacity)
    }
    static var pop: AnyTransition { .opacity.combined(with: .scale(scale: 0.92)) }
}
