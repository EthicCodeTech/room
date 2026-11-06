import SwiftUI
import RoomCore

// MARK: - Navigation: floating glass capsules over the content

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview", review = "Review", map = "Map", vault = "Vault", growth = "Growth", ask = "Ask"
    var id: String { rawValue }
}

/// Three glass capsules float over the page: the mark, the sections, and the one primary action.
/// The selection thumb is a glass bead that morphs between sections, with the sindoor dot ("you are here") inside it.
struct NavBar: View {
    @Binding var section: Section
    var vaultCount = 0
    var reviewCount = 0
    var primaryTitle: String
    var primaryLoading = false
    var primaryAction: () -> Void
    var settingsAction: () -> Void = {}
    @Namespace private var glassSpace

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    LogoMark(height: 18)
                    Text("Room").dsText(.init(15, 600), color: DS.text)
                }
                .padding(.horizontal, 16).frame(height: 44)
                .cinnabarGlass(Capsule())
                .padding(.leading, 76)          // clears the window's traffic lights

                Spacer(minLength: 16)

                HStack(spacing: 2) { ForEach(Section.allCases) { item($0) } }
                    .padding(4).frame(height: 44)
                    .cinnabarGlass(Capsule())

                Spacer(minLength: 16)

                Button(action: { Haptics.play(.select); settingsAction() }) {
                    Image(systemName: "gearshape").font(.system(size: 15, weight: .regular)).foregroundStyle(DS.textMuted)
                        .frame(width: 44, height: 44).contentShape(Circle())
                        .cinnabarGlass(Circle(), interactive: true)
                }.buttonStyle(.plain).help("Settings").keyboardShortcut(",", modifiers: .command)

                primary
            }
        }
        .padding(.horizontal, 20).padding(.top, 14)
        .motion(.panel, value: section).motion(.panel, value: reviewCount).motion(.panel, value: vaultCount).motion(.panel, value: primaryTitle)
    }

    private func item(_ s: Section) -> some View {
        let selected = section == s
        return Button { if !selected { section = s; Haptics.play(.select) } } label: {
            HStack(spacing: 7) {
                if selected { SindoorDot(size: 5) }
                Text(s.rawValue).font(.ds(.init(14, selected ? 500 : 400)))
                if let n = count(for: s), n > 0 { Text("\(n)").font(.ds(Token.monoTiny, mono: true)).foregroundStyle(DS.textFaint).contentTransition(.numericText()).transition(.opacity) }
            }
            .foregroundStyle(selected ? DS.text : DS.textMuted)
            .padding(.horizontal, 14).frame(height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(SelectionThumb(selected: selected, space: glassSpace))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var primary: some View {
        Button(action: primaryAction) {
            HStack(spacing: 10) {
                Text(primaryTitle).font(.ds(.init(14, 500))).foregroundStyle(DS.onSindoor).contentTransition(.numericText())
                ZStack {
                    Circle().fill(DS.obsidian)
                    if primaryLoading { InlineSpinner().scaleEffect(0.6).transition(.opacity) }
                    else { Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.sindoor).transition(.opacity) }
                }.frame(width: 28, height: 28)
            }
            .padding(.leading, 18).padding(.trailing, 8).frame(height: 44)
            .cinnabarGlass(Capsule(), tint: DS.sindoor, interactive: true, hairline: false)
            .contentShape(Capsule())
        }.buttonStyle(.plain).allowsHitTesting(!primaryLoading)
    }

    private func count(for s: Section) -> Int? { s == .vault ? vaultCount : (s == .review ? reviewCount : nil) }
}

private struct SelectionThumb: ViewModifier {
    let selected: Bool
    let space: Namespace.ID
    func body(content: Content) -> some View {
        if selected {
            content.glassEffect(.regular.tint(DS.sindoor.opacity(0.16)).interactive(), in: Capsule()).glassEffectID("thumb", in: space)
        } else { content }
    }
}

// MARK: - Toasts: "Card with tinted icon"

struct Toast: Identifiable, Equatable {
    enum Kind { case success, failed, pending, info
        var tint: Color { switch self { case .success: DS.successTint; case .failed: DS.failedTint; case .pending: DS.pendingTint; case .info: Color(hex: Token.info, alpha: 0.25) } }
        var ink: Color { switch self { case .success: DS.successText; case .failed: DS.failedText; case .pending: DS.pendingText; case .info: Color(hex: Token.infoText) } }
        var symbol: String { switch self { case .success: "checkmark"; case .failed: "xmark"; case .pending: "clock"; case .info: "info" } }
    }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
}

@MainActor @Observable
final class ToastCenter {
    var items: [Toast] = []
    func show(_ kind: Toast.Kind, _ title: String, detail: String? = nil, haptic: Haptics.Pattern? = nil) {
        let t = Toast(kind: kind, title: title, detail: detail)
        items.append(t)
        if let haptic { Haptics.play(haptic) }
        else {
            switch kind {          // one message, one haptic
            case .success: Haptics.play(.confirm)
            case .failed: Haptics.play(.decline)
            case .pending: Haptics.play(.attention)
            case .info: Haptics.play(.select)
            }
        }
        if kind != .failed {      // errors stay until dismissed
            Task { try? await Task.sleep(for: .seconds(Token.durToast)); dismiss(t.id) }
        }
    }
    func dismiss(_ id: UUID) { items.removeAll { $0.id == id } }
}

struct ToastHost: View {
    let center: ToastCenter
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.items) { t in
                HStack(alignment: .top, spacing: 12) {
                    ZStack { Circle().fill(t.kind.tint); Image(systemName: t.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.kind.ink) }
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).dsText(.init(13, 500))
                        if let d = t.detail { Text(d).dsText(Token.monoSmall, mono: true, color: DS.textMuted).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 8)
                    Button { center.dismiss(t.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundStyle(DS.textFaint) }
                        .buttonStyle(.plain).help("Dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 12).frame(width: 340, alignment: .leading)
                .cinnabarGlass(RoundedRectangle(cornerRadius: Token.radiusMD, style: .continuous))     // floats above content
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .motion(.base, value: center.items)
        .padding(20)
    }
}

// MARK: - Modal

struct DSModal<Content: View>: View {
    var width: CGFloat = 480
    var dismissOnBackdrop = true
    var onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            DS.obsidian.opacity(scheme == .dark ? 0.72 : 0.45).ignoresSafeArea().onTapGesture { if dismissOnBackdrop { onClose() } }   // scrim: no blur
            content
                .padding(24).frame(width: width)
                .background(RoundedRectangle(cornerRadius: Token.radiusXL, style: .continuous).fill(DS.card.opacity(0.55)))   // keeps text legible on glass
                .cinnabarGlass(RoundedRectangle(cornerRadius: Token.radiusXL, style: .continuous))
                .scaleEffect(shown ? 1 : 0.98).offset(y: shown ? 0 : 8).opacity(shown ? 1 : 0)
                .accessibilityAddTraits(.isModal)
        }
        .onAppear { Motion.run(.panel) { shown = true } }
        .onExitCommand(perform: onClose)
    }
}
