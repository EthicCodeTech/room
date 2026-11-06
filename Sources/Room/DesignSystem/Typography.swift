import SwiftUI
import CoreText
import RoomCore

/// Registers Parkinsans and JetBrains Mono (both OFL) from the app bundle.
/// Falls back to the source tree when run with `swift run`, so there is one code path in dev and release.
enum DSFonts {
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts"))
        guard let dir = dirs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
    }

    static func sans(_ weight: Int) -> String {
        switch weight { case ..<450: "Parkinsans-Regular"; case ..<550: "Parkinsans-Medium"; case ..<650: "Parkinsans-SemiBold"; default: "Parkinsans-Bold" }
    }
    static func mono(_ weight: Int) -> String { weight >= 450 ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular" }
}

extension Font {
    /// Parkinsans by default. Mono is for data only: sizes, IDs, amounts, timestamps.
    static func ds(_ style: Token.TypeStyle, mono: Bool = false) -> Font {
        .custom(mono ? DSFonts.mono(style.weight) : DSFonts.sans(style.weight), size: style.size)
    }
}

extension View {
    func dsText(_ style: Token.TypeStyle, mono: Bool = false, color: Color = DS.text) -> some View {
        self.font(.ds(style, mono: mono)).tracking(style.size * style.tracking).foregroundStyle(color)
    }
}

/// The type styles the spec defines that aren't in tokens.json's reduced set.
extension Token {
    static let dataLarge = TypeStyle(56, 500, -0.02)    // the big free-space figure, set in mono
    static let monoSmall = TypeStyle(12, 400, 0.02)
    static let monoTiny = TypeStyle(11, 400, 0.02)
}
