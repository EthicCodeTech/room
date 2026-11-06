import Foundation

/// Central, non-secret configuration. Nothing here talks to the network by itself.
public enum RoomConfig {
    public static let appName = "Room"
    public static let appVersion = "1.0.0"

    /// Product home. Also hosts the (future) signed rules-catalog feed.
    public static let homeURL = URL(string: "https://ethiccode.in/room")!
    public static var catalogFeedURL: URL { homeURL.appendingPathComponent("catalog.json") }
    public static var catalogSignatureURL: URL { homeURL.appendingPathComponent("catalog.sig") }

    /// Base64 Ed25519 public key used to verify catalog updates.
    /// `nil` = catalog updates are disabled (the built-in catalog is used).
    public static let catalogPublicKeyBase64: String? = nil

    /// Opt-in learning upload endpoint. `nil` = nothing is ever uploaded,
    /// even for users who opted in (they can still export a local, anonymized file).
    public static let learningEndpoint: URL? = nil
}

/// Where Room keeps its own state. Injectable so tests never touch real data.
public struct AppPaths: Sendable {
    public let root: URL
    public var vault: URL { root.appendingPathComponent("Vault", isDirectory: true) }
    public var growth: URL { root.appendingPathComponent("growth.json") }
    public var decisions: URL { root.appendingPathComponent("decisions.jsonl") }
    public var model: URL { root.appendingPathComponent("scorer-weights.json") }
    public var catalogCache: URL { root.appendingPathComponent("catalog-cache.json") }
    public var settings: URL { root.appendingPathComponent("settings.json") }
    public var mapCache: URL { root.appendingPathComponent("map-cache.json") }

    public init(root: URL) { self.root = root }

    public static var standard: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appendingPathComponent("Room", isDirectory: true))
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
