import Testing
import Foundation
@testable import RoomCore

/// WCAG contrast for the colour pairs the UI actually uses, in both themes.
/// The light neutrals are derived (not in the spec), so this is what keeps them honest.
@Suite("Contrast, dark and light") struct ContrastTests {
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }
    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b)); return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test func darkThemeBodyAndMutedTextPassAA() {
        for (name, fg, bg) in [("text on obsidian", Token.text, Token.obsidian), ("text on graphite", Token.text, Token.graphite),
                               ("muted on graphite", Token.textMuted, Token.graphite), ("faint on graphite", Token.textFaint, Token.graphite),
                               ("faint on input", Token.textFaint, Token.graphiteInput), ("sindoor text on graphite", Token.sindoorText, Token.graphite),
                               ("obsidian on sindoor (buttons)", Token.obsidian, Token.sindoor)] {
            #expect(Self.ratio(fg, bg) >= 4.5, "\(name): \(String(format: "%.2f", Self.ratio(fg, bg)))")
        }
    }

    @Test func lightThemeTextPassesAA() {
        for (name, fg, bg) in [("text on paper", Token.obsidian, Token.lightBackground), ("text on card", Token.obsidian, Token.lightCard),
                               ("muted on card", Token.lightTextMuted, Token.lightCard), ("muted on paper", Token.lightTextMuted, Token.lightBackground),
                               ("muted on raised", Token.lightTextMuted, Token.lightRaised),
                               ("faint on card", Token.lightTextFaint, Token.lightCard), ("faint on paper", Token.lightTextFaint, Token.lightBackground),
                               ("sindoor text on card", Token.sindoorTextOnLight, Token.lightCard), ("sindoor text on paper", Token.sindoorTextOnLight, Token.lightBackground),
                               ("obsidian on sindoor (buttons)", Token.obsidian, Token.sindoor),
                               ("paper on obsidian (selected pill)", Token.paper, Token.obsidian)] {
            #expect(Self.ratio(fg, bg) >= 4.5, "\(name): \(String(format: "%.2f", Self.ratio(fg, bg)))")
        }
    }

    @Test func statusTextIsReadableInBothThemes() {
        // Dark uses the spec's "text on dark" tones; light needs darker ones (kept in Palette.swift).
        for (name, fg) in [("success", Token.successText), ("pending", Token.pendingText), ("failed", Token.failedText)] {
            #expect(Self.ratio(fg, Token.graphite) >= 4.5, "dark \(name)")
        }
        for (name, fg) in [("success", UInt32(0x15803D)), ("pending", 0xA16207), ("failed", 0xBE123C)] {
            #expect(Self.ratio(fg, Token.lightCard) >= 4.5, "light \(name): \(String(format: "%.2f", Self.ratio(fg, Token.lightCard)))")
        }
    }

    @Test func appearanceDefaultsToSystemAndPersists() throws {
        #expect(AppSettings().appearance == .system)
        let sb = try Sandbox(); let store = SettingsStore(paths: sb.paths)
        var s = AppSettings(); s.appearance = .light; store.save(s)
        #expect(store.load().appearance == .light)
    }
}
