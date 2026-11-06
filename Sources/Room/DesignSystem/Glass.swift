import SwiftUI
import RoomCore

/// Cinnabar Glass: a deliberate extension of the design system that mixes macOS Liquid Glass with Cinnabar.
///
/// Rules (these keep every other Cinnabar rule intact):
/// 1. Content stays flat: cards, tables and text use Graphite, hairlines and the sindoor accent exactly as specified.
/// 2. Glass is only for the control layer that floats above content: navigation, the action bar, the inspector,
///    dialogs, toasts and segmented controls. There must be real content underneath for it to refract.
/// 3. Sindoor tints glass only for the one primary action in a view (the 90/10 rule still holds).
/// 4. A 1px Cinnabar hairline stays on glass edges, so depth still comes from borders more than shadows.
/// 5. Motion answers actions: glass morphs when state changes (selection moves, items appear) and never loops.
extension View {
    func cinnabarGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false,
                                           clear: Bool = false, hairline: Bool = true) -> some View {
        var glass: Glass = clear ? .clear : .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self
            .glassEffect(glass, in: shape)
            .overlay { if hairline { shape.strokeBorder(DS.line.opacity(0.7), lineWidth: Token.hairline) } }
    }
}

/// Fades the page's content out under floating glass instead of cutting it off.
struct PageTopInset: ViewModifier {
    func body(content: Content) -> some View { content.padding(.top, 76) }
}
extension View { func belowFloatingNav() -> some View { modifier(PageTopInset()) } }
