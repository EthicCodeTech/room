import Foundation

/// Cinnabar design tokens as plain values (no UI framework), so they can be checked against
/// `tandem/packages/cinnabar-tokens/tokens.json` in tests. The SwiftUI layer maps these to colors and fonts.
/// Sources: tokens.json (core set) and cinnabar-design-system.md sections 3 to 5 and 8 (extended neutrals, states).
public enum Token {
    // MARK: Colour, dark theme ("Sindoor on Obsidian")
    public static let sindoor: UInt32 = 0xF2542D
    public static let sindoorHover: UInt32 = 0xFF6A44
    public static let sindoorPressed: UInt32 = 0xD9461F
    public static let sindoorText: UInt32 = 0xFF7A57          // sindoor as text on dark
    public static let sindoorTextOnLight: UInt32 = 0xC93D1A   // AA on light surfaces
    public static let obsidian: UInt32 = 0x0B0B0D
    public static let graphite: UInt32 = 0x16161A
    public static let graphiteRaised: UInt32 = 0x1A1A1F
    public static let graphiteInput: UInt32 = 0x222228
    public static let graphiteInputHover: UInt32 = 0x26262C
    public static let paper: UInt32 = 0xF7F7F5
    public static let line: UInt32 = 0x232328
    public static let lineStrong: UInt32 = 0x2A2A30
    public static let lineStronger: UInt32 = 0x3A3A42
    public static let text: UInt32 = 0xF7F7F5
    public static let textSoft: UInt32 = 0xD4D4D8
    public static let textMuted: UInt32 = 0xA1A1AA
    public static let textFaint: UInt32 = 0x8A8A93
    public static let placeholder: UInt32 = 0x8E8E97
    public static let neutralDot: UInt32 = 0x71717A

    // Alpha tints (0...1) over the sindoor / semantic colours
    public static let sindoorTintAlpha = 0.14
    public static let sindoorRingAlpha = 0.20

    // MARK: Semantic (state only, never decorative). Errors are rose, never sindoor.
    public static let success: UInt32 = 0x22C55E
    public static let successText: UInt32 = 0x4ADE80
    public static let pending: UInt32 = 0xEAB308
    public static let pendingText: UInt32 = 0xFACC15
    public static let failed: UInt32 = 0xE11D48
    public static let failedText: UInt32 = 0xFB7185
    public static let info: UInt32 = 0x2F4A6B
    public static let infoText: UInt32 = 0x93B4D9

    // MARK: Light theme (swap obsidian and paper; sindoor stays)
    public static let lightBackground: UInt32 = 0xF7F7F5
    public static let lightCard: UInt32 = 0xFFFFFF
    public static let lightLine: UInt32 = 0xE4E4E7
    /// Not in the spec: derived neutrals for secondary text on light surfaces (AA on white).
    public static let lightTextMuted: UInt32 = 0x52525B
    public static let lightTextFaint: UInt32 = 0x71717A

    // MARK: Data visualisation
    public static let series: [UInt32] = [0xF2542D, 0xD4D4D8, 0x7C93C3, 0xC9962E, 0x8A8A93]

    // MARK: Type (px = pt on macOS)
    public static let fontSans = "Parkinsans"
    public static let fontMono = "JetBrains Mono"
    public struct TypeStyle: Sendable { public let size: Double; public let weight: Int; public let tracking: Double
        public init(_ size: Double, _ weight: Int, _ tracking: Double = 0) { self.size = size; self.weight = weight; self.tracking = tracking } }
    public static let display = TypeStyle(64, 700, -0.03)
    public static let h1 = TypeStyle(48, 700, -0.02)
    public static let h2 = TypeStyle(36, 600, -0.02)
    public static let h3 = TypeStyle(24, 600, -0.01)
    public static let h4 = TypeStyle(18, 600, -0.01)
    public static let bodyLg = TypeStyle(18, 400)
    public static let body = TypeStyle(16, 400)
    public static let small = TypeStyle(14, 400)
    public static let label = TypeStyle(13, 500)
    public static let micro = TypeStyle(12, 400)
    public static let mono = TypeStyle(13, 400, 0.02)

    // MARK: Space, radius, size
    public static let space: [Int: Double] = [1: 4, 2: 8, 3: 12, 4: 16, 5: 20, 6: 24, 8: 32, 12: 48, 16: 64, 24: 96]
    public static let radiusXS = 6.0, radiusSM = 12.0, radiusMD = 16.0, radiusLG = 20.0, radiusXL = 24.0, radiusPill = 999.0
    public static let hairline = 1.0, focusRing = 3.0, touch = 44.0

    // MARK: Motion (seconds)
    public static let durFast = 0.15, durBase = 0.20, durPanel = 0.30, durToast = 5.0, durLoader = 2.4
    public static let easeStandard: [Double] = [0.2, 0, 0, 1]   // cubic-bezier(.2,0,0,1)
}

public extension Token {
    /// Not in the spec: neutrals derived for light mode so the same component set works there.
    /// Dark theme is the primary design; replace these if the spec later defines a light palette.
    static let lightRaised: UInt32 = 0xF0F0EE
    static let lightInput: UInt32 = 0xEBEBE8
    static let lightLineStrong: UInt32 = 0xD4D4D8
    static let lightLineStronger: UInt32 = 0xA1A1AA
}
