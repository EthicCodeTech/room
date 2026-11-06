import SwiftUI
import AppKit
import RoomCore

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// Resolves per appearance, so every surface follows the system's light or dark setting.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Cinnabar colours. Flat only: no gradients, no glows except the functional focus ring.
enum DS {
    // Surfaces
    static let bg = Color.adaptive(dark: Token.obsidian, light: Token.lightBackground)
    static let card = Color.adaptive(dark: Token.graphite, light: Token.lightCard)
    static let raised = Color.adaptive(dark: Token.graphiteRaised, light: Token.lightRaised)
    static let input = Color.adaptive(dark: Token.graphiteInput, light: Token.lightInput)
    static let inputHover = Color.adaptive(dark: Token.graphiteInputHover, light: Token.lightInput)
    static let line = Color.adaptive(dark: Token.line, light: Token.lightLine)
    static let lineStrong = Color.adaptive(dark: Token.lineStrong, light: Token.lightLineStrong)
    static let lineStronger = Color.adaptive(dark: Token.lineStronger, light: Token.lightLineStronger)

    // Text
    static let text = Color.adaptive(dark: Token.text, light: Token.obsidian)
    static let textSoft = Color.adaptive(dark: Token.textSoft, light: Token.lightTextMuted)
    static let textMuted = Color.adaptive(dark: Token.textMuted, light: Token.lightTextMuted)
    static let textFaint = Color.adaptive(dark: Token.textFaint, light: Token.lightTextFaint)
    static let placeholder = Color.adaptive(dark: Token.placeholder, light: Token.lightTextFaint)

    // Sindoor: brand and action. Never an error colour.
    static let sindoor = Color(hex: Token.sindoor)
    static let sindoorHover = Color(hex: Token.sindoorHover)
    static let sindoorPressed = Color(hex: Token.sindoorPressed)
    static let sindoorText = Color.adaptive(dark: Token.sindoorText, light: Token.sindoorTextOnLight)
    static let sindoorTint = Color(hex: Token.sindoor, alpha: Token.sindoorTintAlpha)
    static let sindoorRing = Color(hex: Token.sindoor, alpha: Token.sindoorRingAlpha)
    /// Text and icons that sit on a sindoor fill are always obsidian.
    static let onSindoor = Color(hex: Token.obsidian)
    static let obsidian = Color(hex: Token.obsidian)
    /// The selected segmented pill: paper on dark, obsidian on light (the spec's "swap obsidian and paper").
    static let selectedFill = Color.adaptive(dark: Token.paper, light: Token.obsidian)
    static let onSelected = Color.adaptive(dark: Token.obsidian, light: Token.paper)
    static let paper = Color(hex: Token.paper)

    // State only, never decorative
    static let success = Color(hex: Token.success), successText = Color.adaptive(dark: Token.successText, light: 0x15803D)
    static let pending = Color(hex: Token.pending), pendingText = Color.adaptive(dark: Token.pendingText, light: 0xA16207)
    static let failed = Color(hex: Token.failed), failedText = Color.adaptive(dark: Token.failedText, light: 0xBE123C)
    static let neutralDot = Color(hex: Token.neutralDot)
    static let successTint = Color(hex: Token.success, alpha: 0.14)
    static let pendingTint = Color(hex: Token.pending, alpha: 0.14)
    static let failedTint = Color(hex: Token.failed, alpha: 0.16)
    static let failedRing = Color(hex: Token.failed, alpha: 0.20)

    static let series: [Color] = Token.series.map { Color(hex: $0) }
}

extension RiskTier {
    /// "Outline with dot": colour lives only in the dot. Yours is the "look here" dot, so it uses sindoor.
    var dot: Color {
        switch self {
        case .safe: Color(hex: Token.successText)
        case .rebuildable: Color(hex: Token.pendingText)
        case .yours: DS.sindoor
        }
    }
}
