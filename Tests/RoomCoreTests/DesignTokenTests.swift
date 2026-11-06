import Testing
import Foundation
@testable import RoomCore

/// Guards against drift from the real design system. Skipped (not failed) if the tokens file isn't on this machine.
@Suite("Design tokens match Cinnabar") struct DesignTokenTests {
    static let tokensPath = NSHomeDirectory() + "/Projects/tandem/packages/cinnabar-tokens/tokens.json"

    static func load() throws -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: tokensPath) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    static func value(_ root: [String: Any], _ path: [String]) -> Any? {
        var cur: Any? = root
        for p in path { cur = (cur as? [String: Any])?[p] }
        return (cur as? [String: Any])?["$value"]
    }
    static func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }

    @Test func colours() throws {
        guard let t = try Self.load() else { return }
        let map: [(String, [String], UInt32)] = [
            ("accent", ["color", "accent"], Token.sindoor), ("accent-hover", ["color", "accent-hover"], Token.sindoorHover),
            ("accent-text-light", ["color", "accent-text-light"], Token.sindoorTextOnLight),
            ("bg", ["color", "bg"], Token.obsidian), ("surface", ["color", "surface"], Token.graphite),
            ("paper", ["color", "paper"], Token.paper), ("line", ["color", "line"], Token.line),
            ("text", ["color", "text"], Token.text), ("text-muted", ["color", "text-muted"], Token.textMuted),
            ("text-faint", ["color", "text-faint"], Token.textFaint), ("placeholder", ["color", "placeholder"], Token.placeholder),
            ("success", ["status", "success"], Token.success), ("pending", ["status", "pending"], Token.pending),
            ("failed", ["status", "failed"], Token.failed),
        ]
        for (name, path, ours) in map {
            let theirs = try #require(Self.value(t, path) as? String, "missing \(name)")
            #expect(theirs.uppercased() == Self.hex(ours), "\(name): tokens.json \(theirs) vs Swift \(Self.hex(ours))")
        }
        for (i, hexValue) in Token.series.enumerated() {
            let theirs = try #require(Self.value(t, ["dataviz", "series-\(i + 1)"]) as? String)
            #expect(theirs.uppercased() == Self.hex(hexValue), "series-\(i + 1)")
        }
    }

    @Test func radiusSpaceAndMotion() throws {
        guard let t = try Self.load() else { return }
        func px(_ path: [String]) -> Double? { (Self.value(t, path) as? String).flatMap { Double($0.replacingOccurrences(of: "px", with: "")) } }
        #expect(px(["radius", "xs"]) == Token.radiusXS); #expect(px(["radius", "sm"]) == Token.radiusSM)
        #expect(px(["radius", "md"]) == Token.radiusMD); #expect(px(["radius", "lg"]) == Token.radiusLG)
        #expect(px(["radius", "xl"]) == Token.radiusXL)
        for (k, v) in [1: 4.0, 2: 8, 3: 12, 4: 16, 6: 24, 8: 32, 12: 48, 16: 64] { #expect(px(["space", "\(k)"]) == v); #expect(Token.space[k] == v) }
        #expect(px(["size", "touch"]) == Token.touch); #expect(px(["size", "focus-ring"]) == Token.focusRing)
        #expect(Self.value(t, ["dur", "fast"]) as? String == "150ms"); #expect(Self.value(t, ["dur", "base"]) as? String == "200ms")
        #expect(Self.value(t, ["dur", "panel"]) as? String == "300ms"); #expect(Self.value(t, ["dur", "loader"]) as? String == "2400ms")
        #expect((Self.value(t, ["ease", "standard"]) as? [Double]) == Token.easeStandard)
    }

    @Test func typeScale() throws {
        guard let t = try Self.load() else { return }
        for (name, style) in [("display", Token.display), ("h1", Token.h1), ("h2", Token.h2), ("h3", Token.h3),
                              ("body-lg", Token.bodyLg), ("body", Token.body), ("small", Token.small), ("mono", Token.mono)] {
            let v = try #require(Self.value(t, ["text", name]) as? [String: Any], "missing text.\(name)")
            #expect(v["fontSize"] as? String == "\(Int(style.size))px", "\(name) size")
            #expect(v["fontWeight"] as? Int == style.weight, "\(name) weight")
        }
    }
}
