import SwiftUI
import RoomCore

// MARK: - Dot (the signature motif: "you are here" or "look here", never decoration)

struct SindoorDot: View {
    var size: CGFloat = 6
    var color: Color = DS.sindoor
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Buttons: "Pill with icon"

enum PillVariant { case primary, secondary, ghost, danger }
enum PillSize {
    case small, regular, large
    var height: CGFloat { switch self { case .small: 32; case .regular: 40; case .large: 48 } }
    var font: CGFloat { switch self { case .small: 12; case .regular: 14; case .large: 16 } }
    var inset: CGFloat { switch self { case .small: 6; case .regular: 8; case .large: 10 } }
    var leading: CGFloat { switch self { case .small: 14; case .regular: 18; case .large: 22 } }
    var icon: CGFloat { height - inset * 2 }
}

struct PillButton: View {
    let title: String
    var variant: PillVariant = .primary
    var size: PillSize = .regular
    /// SF Symbol shown in the round chip. Primary buttons use an arrow unless told otherwise.
    var icon: String? = "arrow.right"
    var isLoading = false
    /// Played on tap. Primary buttons start flows with their own haptics, so they default to none.
    var haptic: Haptics.Pattern? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            if let p = haptic ?? (variant == .secondary || variant == .ghost ? .select : nil) { Haptics.play(p) }
            action()
        }) { EmptyView() }
            .buttonStyle(PillStyle(title: title, variant: variant, size: size, icon: variant == .primary ? icon : nil, isLoading: isLoading))
            .disabled(isLoading)
    }
}

private struct PillStyle: ButtonStyle {
    let title: String, variant: PillVariant, size: PillSize, icon: String?, isLoading: Bool
    func makeBody(configuration: Configuration) -> some View {
        PillBody(title: title, variant: variant, size: size, icon: icon, isLoading: isLoading, pressed: configuration.isPressed)
    }
}

private struct PillBody: View {
    let title: String, variant: PillVariant, size: PillSize, icon: String?, isLoading: Bool, pressed: Bool
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    private var fill: Color {
        switch variant {
        case .primary: pressed ? DS.sindoorPressed : (hover ? DS.sindoorHover : DS.sindoor)
        case .danger: DS.failed.opacity(pressed ? 0.85 : 1)
        default: .clear
        }
    }
    private var foreground: Color {
        switch variant {
        case .primary: DS.onSindoor
        case .danger: DS.paper
        case .secondary: hover ? DS.sindoorText : DS.text
        case .ghost: hover ? DS.text : DS.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.ds(.init(size.font, 500))).contentTransition(.numericText())
            if isLoading { InlineSpinner().transition(.opacity) }
            else if let icon {
                ZStack {
                    Circle().fill(DS.obsidian)
                    Image(systemName: icon).font(.system(size: size.icon * 0.42, weight: .semibold)).foregroundStyle(DS.sindoor)
                        .rotationEffect(.degrees(hover && icon == "arrow.right" ? -45 : 0))
                        .motion(.fast, value: hover)
                }.frame(width: size.icon, height: size.icon).transition(.opacity)
            }
        }
        .motion(.base, value: isLoading).motion(.base, value: title)
        .foregroundStyle(foreground)
        .padding(.leading, icon == nil && !isLoading ? size.leading : size.leading)
        .padding(.trailing, icon != nil || isLoading ? size.inset : size.leading)
        .frame(height: size.height)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(variant == .secondary ? (hover ? DS.sindoor : DS.lineStrong) : .clear, lineWidth: Token.hairline))
        .overlay(Capsule().strokeBorder(DS.sindoorRing, lineWidth: Token.focusRing).padding(-Token.focusRing / 2).opacity(focused ? 1 : 0))
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Capsule())
        .scaleEffect(pressed ? 0.975 : 1)
        .onHover { hover = $0 }
        .motion(.fast, value: hover).motion(.fast, value: pressed)
    }
}

// MARK: - Spinner (inline, for buttons and small spaces)

struct InlineSpinner: View {
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        ZStack {
            Circle().stroke(DS.lineStrong, lineWidth: 2)
            Circle().trim(from: 0, to: 0.25).stroke(DS.sindoor, style: StrokeStyle(lineWidth: 2, lineCap: .butt)).rotationEffect(.degrees(angle))
        }
        .frame(width: 16, height: 16)
        .onAppear { if !reduce { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { angle = 360 } } }
    }
}

// MARK: - Card: "Filled with sindoor hover border"

struct DSCard<Content: View>: View {
    var padding: CGFloat = 20
    var interactive = false
    var selected = false
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Token.radiusLG, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: Token.radiusLG, style: .continuous)
                .strokeBorder((interactive && hover) || selected ? DS.sindoor : DS.line, lineWidth: Token.hairline))
            .motion(.base, value: hover)
            .onHover { if interactive { hover = $0 } }
    }
}

// MARK: - Badge: "Outline with dot"

struct DSBadge: View {
    let text: String
    var dot: Color = DS.neutralDot
    var body: some View {
        HStack(spacing: 6) {
            SindoorDot(size: 6, color: dot)
            Text(text).font(.ds(.init(12, 500))).foregroundStyle(DS.textSoft)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: Token.hairline))
    }
}

// MARK: - Toggle and checkbox: "Outline glow"

struct DSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle(); Haptics.play(.select) } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? DS.card : DS.lineStrong)
                        .overlay(Capsule().strokeBorder(configuration.isOn ? DS.sindoor : .clear, lineWidth: 1))
                    Circle().fill(configuration.isOn ? DS.sindoor : DS.neutralDot).frame(width: 18, height: 18).padding(3)
                }
                .frame(width: 44, height: 24)
                .motion(.base, value: configuration.isOn)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct DSCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle(); Haptics.play(.select) } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(configuration.isOn ? DS.sindoor : DS.lineStronger, lineWidth: 1.5)
                    if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.sindoor).transition(.pop) }
                }.frame(width: 20, height: 20)
                configuration.label
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
        .motion(.base, value: configuration.isOn)
    }
}

// MARK: - Progress

struct DSProgressBar: View {
    var value: Double?          // nil = indeterminate
    var label: String?
    /// Sindoor for progress and goals; a neutral for lists of many bars, where sindoor would be everywhere.
    var fill: Color = DS.sindoor
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label, let value {
                HStack { Text(label).dsText(Token.micro, color: DS.textMuted); Spacer()
                    Text("\(Int((value * 100).rounded()))%").dsText(Token.monoSmall, mono: true, color: DS.textSoft) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.input)
                    if let value { Capsule().fill(fill).frame(width: max(6, g.size.width * min(1, max(0, value)))) }
                    else {
                        Capsule().fill(DS.sindoor).frame(width: g.size.width * 0.3)
                            .offset(x: reduce ? g.size.width * 0.35 : (phase ? g.size.width * 0.7 : 0))
                    }
                }
            }.frame(height: 6)
        }
        .onAppear { if value == nil && !reduce { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: true)) { phase = true } } }
        .motion(.panel, value: value)
    }
}

// MARK: - Segmented control and tabs

struct DSSegmented<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    @Namespace private var pill
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]; let on = o.value == selection
                Button { if !on { selection = o.value; Haptics.play(.select) } } label: {
                    Text(o.title).font(.ds(.init(13, 500)))
                        .foregroundStyle(on ? DS.onSelected : DS.textMuted)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background { if on { Capsule().fill(DS.selectedFill).matchedGeometryEffect(id: "pill", in: pill) } }     // slides, not fades
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .cinnabarGlass(Capsule())
        .motion(.base, value: selection)
    }
}

// MARK: - Input: "Filled with glow ring"

struct DSFieldStyle: TextFieldStyle {
    var mono = false
    var error = false
    @FocusState private var focused: Bool
    @State private var hover = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(mono ? .ds(Token.mono, mono: true) : .ds(Token.small))
            .foregroundStyle(DS.text)
            .padding(.horizontal, 14).frame(height: Token.touch)
            .background(RoundedRectangle(cornerRadius: Token.radiusSM, style: .continuous).fill(focused || error ? DS.bg : (hover ? DS.inputHover : DS.input)))
            .overlay(RoundedRectangle(cornerRadius: Token.radiusSM, style: .continuous)
                .strokeBorder(error ? DS.failed : (focused ? DS.sindoor : .clear), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: Token.radiusSM, style: .continuous)
                .strokeBorder(error ? DS.failedRing : DS.sindoorRing, lineWidth: Token.focusRing).padding(-Token.focusRing / 2)
                .opacity(focused || error ? 1 : 0))
            .focused($focused)
            .onHover { hover = $0 }
            .motion(.fast, value: focused)
    }
}

struct DSField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var mono = false
    var helper: String?
    var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).dsText(Token.micro, color: DS.textMuted)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DS.placeholder))
                .textFieldStyle(DSFieldStyle(mono: mono, error: error != nil))
                .accessibilityLabel(label)
            if let msg = error ?? helper { Text(msg).dsText(Token.micro, color: error != nil ? DS.failedText : DS.textMuted) }
        }
    }
}

// MARK: - Empty state: ring and dot

struct DSEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(DS.lineStrong, lineWidth: 2).frame(width: 56, height: 56)
                SindoorDot(size: 8).offset(x: 20, y: -20)
            }
            Text(title).dsText(Token.h4)
            Text(message).dsText(Token.small, color: DS.textMuted).multilineTextAlignment(.center).frame(maxWidth: 360)
            if let actionTitle, let action { PillButton(title: actionTitle, action: action).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

struct DSSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(DS.input).frame(width: width, height: height)
            .overlay(GeometryReader { g in
                if !reduce {
                    Rectangle().fill(DS.text.opacity(0.06)).frame(width: g.size.width * 0.4)
                        .offset(x: sweep ? g.size.width : -g.size.width * 0.4)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 6)))
            .onAppear { if !reduce { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true } } }
            .accessibilityHidden(true)
    }
}
