import Foundation
import CryptoKit

/// Fixed set of commands a rule may trigger. The catalog only names them; it can't define new ones.
public enum CommandID: String, Codable, Sendable, CaseIterable {
    case brewCleanup, npmCacheClean, pnpmStorePrune, uvCacheClean, dockerBuilderPruneAndTrim

    public var steps: [(tool: String, args: [String])] {
        switch self {
        case .brewCleanup: [("brew", ["cleanup", "-s"])]
        case .npmCacheClean: [("npm", ["cache", "clean", "--force"])]
        case .pnpmStorePrune: [("pnpm", ["store", "prune"])]
        case .uvCacheClean: [("uv", ["cache", "clean"])]
        case .dockerBuilderPruneAndTrim: [("docker", ["builder", "prune", "-a", "-f"]),
                                          ("colima", ["ssh", "--", "sudo", "fstrim", "-av"])]
        }
    }
    public var requiredTool: String {
        switch self {
        case .brewCleanup: "brew"
        case .npmCacheClean: "npm"
        case .pnpmStorePrune: "pnpm"
        case .uvCacheClean: "uv"
        case .dockerBuilderPruneAndTrim: "docker"
        }
    }
}

public enum RuleAction: Codable, Sendable, Hashable {
    /// Delete everything inside the folder, keep the folder.
    case deleteContents
    /// Delete the matched item itself.
    case deleteItem
    /// Run a fixed, whitelisted command.
    case command(CommandID)
}

public struct CatalogRule: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let why: String
    public let tier: RiskTier
    public let regen: RegenCost
    public let paths: [String]
    public let action: RuleAction
    /// Only touch children not modified for this many minutes (protects in-flight updates).
    public var minAgeMinutes: Int?
    public var tags: [String] = []

    public init(id: String, title: String, why: String, tier: RiskTier, regen: RegenCost,
                paths: [String], action: RuleAction, minAgeMinutes: Int? = nil, tags: [String] = []) {
        self.id = id; self.title = title; self.why = why; self.tier = tier; self.regen = regen
        self.paths = paths; self.action = action; self.minAgeMinutes = minAgeMinutes; self.tags = tags
    }
}

public struct Catalog: Codable, Sendable {
    public var version: Int
    public var rules: [CatalogRule]
    public init(version: Int, rules: [CatalogRule]) { self.version = version; self.rules = rules }

    public func rule(_ id: String) -> CatalogRule? { rules.first { $0.id == id } }
}

public enum CatalogVerifier {
    public enum Failure: Error { case disabled, badKey, badSignature }

    /// Verifies a downloaded catalog against the pinned Ed25519 key. Unsigned catalogs are rejected.
    public static func verify(data: Data, signature: Data, publicKeyBase64: String?) throws {
        guard let b64 = publicKeyBase64 else { throw Failure.disabled }
        guard let raw = Data(base64Encoded: b64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { throw Failure.badKey }
        guard key.isValidSignature(signature, for: data) else { throw Failure.badSignature }
    }

    public static func decodeVerified(data: Data, signature: Data, publicKeyBase64: String?) throws -> Catalog {
        try verify(data: data, signature: signature, publicKeyBase64: publicKeyBase64)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }
}

// MARK: - Built-in knowledge (seeded from real cleanups)

public extension Catalog {
    static let builtIn = Catalog(version: 1, rules: [
        // — Safe: caches apps rebuild on their own —
        .init(id: "cache.spotify", title: "Spotify cache",
              why: "Offline song cache. Spotify refills it on its own, so it tends to grow back to ~10 GB; lower its limit in Spotify settings to keep it small.",
              tier: .safe, regen: .instant, paths: ["~/Library/Caches/com.spotify.client"], action: .deleteContents, tags: ["regrows"]),
        .init(id: "cache.browsers", title: "Browser caches",
              why: "Page and asset caches for Chrome, Arc, Firefox and Brave. Sites reload a little slower once; no logins or bookmarks are touched.",
              tier: .safe, regen: .instant,
              paths: ["~/Library/Caches/Google", "~/Library/Caches/company.thebrowser.Browser", "~/Library/Caches/Arc",
                      "~/Library/Caches/Mozilla", "~/Library/Caches/com.brave.Browser"], action: .deleteContents),
        .init(id: "cache.updaters", title: "App updater leftovers",
              why: "Downloaded installers that updaters (ShipIt) forgot to delete.",
              tier: .safe, regen: .instant, paths: ["~/Library/Caches/*.ShipIt"], action: .deleteContents, minAgeMinutes: 60),
        .init(id: "cache.chrome-updater", title: "Chrome updater download cache",
              why: "Chrome's updater keeps old update packages here.",
              tier: .safe, regen: .instant, paths: ["~/Library/Application Support/Google/GoogleUpdater/crx_cache"],
              action: .deleteContents, minAgeMinutes: 60),
        .init(id: "cache.chrome-ai-model", title: "Chrome on-device model",
              why: "Chrome re-downloads this model when it needs it (about 4 GB).",
              tier: .safe, regen: .minutes, paths: ["~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"],
              action: .deleteItem, tags: ["regrows"]),
        .init(id: "cache.chrome-clones", title: "Chrome code-sign clones",
              why: "Leftover copies Chrome makes while updating. They're APFS clones, so they look huge but free much less than their size.",
              tier: .safe, regen: .instant, paths: ["/private/var/folders/*/*/X/com.google.Chrome.code_sign_clone"],
              action: .deleteContents, minAgeMinutes: 60, tags: ["clone"]),
        .init(id: "cache.dev-tools", title: "Dev tool caches",
              why: "Playwright browsers, JetBrains and Codex caches. They're downloaded again on next use.",
              tier: .safe, regen: .minutes,
              paths: ["~/Library/Caches/ms-playwright", "~/Library/Caches/JetBrains", "~/Library/Caches/com.openai.codex"],
              action: .deleteContents),
        .init(id: "cache.xcode-derived", title: "Xcode DerivedData",
              why: "Build products and indexes. Xcode regenerates them on the next build.",
              tier: .safe, regen: .minutes, paths: ["~/Library/Developer/Xcode/DerivedData"], action: .deleteContents),
        .init(id: "cache.simulator", title: "Simulator caches",
              why: "Caches for iOS Simulator. Rebuilt when you run a simulator.",
              tier: .safe, regen: .minutes, paths: ["~/Library/Developer/CoreSimulator/Caches"], action: .deleteContents),
        .init(id: "cmd.brew", title: "Homebrew old downloads",
              why: "Removes old formula versions and downloaded bottles.", tier: .safe, regen: .instant,
              paths: [], action: .command(.brewCleanup)),
        .init(id: "cmd.npm", title: "npm cache", why: "Package tarballs npm re-downloads when needed.",
              tier: .safe, regen: .minutes, paths: [], action: .command(.npmCacheClean)),
        .init(id: "cmd.pnpm", title: "pnpm store (unreferenced)",
              why: "Removes packages no project uses any more.", tier: .safe, regen: .minutes, paths: [], action: .command(.pnpmStorePrune)),
        .init(id: "cmd.uv", title: "uv cache", why: "Python packages uv downloads again when needed.",
              tier: .safe, regen: .minutes, paths: [], action: .command(.uvCacheClean)),
        .init(id: "cmd.docker-build", title: "Docker build cache + shrink VM disk",
              why: "Build cache is rebuilt on the next build. Room also runs fstrim so macOS actually gets the space back. Deleting Docker data alone never shrinks Colima's disk file.",
              tier: .safe, regen: .minutes, paths: [], action: .command(.dockerBuilderPruneAndTrim), tags: ["docker"]),

        // — Rebuildable: not your data, but costs time or bandwidth —
        .init(id: "cache.huggingface", title: "Hugging Face model cache",
              why: "Downloaded ML models. They download again when a tool needs them, which can be many GB.",
              tier: .rebuildable, regen: .hours, paths: ["~/.cache/huggingface"], action: .deleteContents),
        .init(id: "cache.gradle", title: "Gradle caches",
              why: "Dependencies re-downloaded on your next Android/Gradle build (slower once).",
              tier: .rebuildable, regen: .hours, paths: ["~/.gradle/caches"], action: .deleteContents),
        .init(id: "cache.ios-devicesupport", title: "iOS DeviceSupport symbols",
              why: "Debug symbols Xcode re-downloads the next time a device is attached.",
              tier: .rebuildable, regen: .hours, paths: ["~/Library/Developer/Xcode/iOS DeviceSupport/*"], action: .deleteItem),
        .init(id: "cache.android-ndk", title: "Android NDK versions",
              why: "Re-installable from Android Studio's SDK Manager.",
              tier: .rebuildable, regen: .hours, paths: ["~/Library/Android/sdk/ndk/*"], action: .deleteItem),
    ])
}
