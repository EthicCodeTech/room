import Foundation

/// Fetches the signed rules catalog from ethiccode.in/room. Disabled until a public key is pinned
/// in `RoomConfig`, and any download that doesn't verify is discarded.
public enum CatalogUpdater {
    public enum UpdateError: Error, LocalizedError {
        case disabled, notNewer
        public var errorDescription: String? {
            switch self { case .disabled: "Catalog updates aren't enabled in this build."; case .notNewer: "Already up to date." }
        }
    }

    /// Cached verified catalog if it is newer than the built-in one; otherwise built-in.
    public static func current(paths: AppPaths) -> Catalog {
        guard let data = try? Data(contentsOf: paths.catalogCache), let cached = try? JSONDecoder().decode(Catalog.self, from: data),
              cached.version > Catalog.builtIn.version else { return .builtIn }
        return cached
    }

    @discardableResult
    public static func update(paths: AppPaths, key: String? = RoomConfig.catalogPublicKeyBase64,
                              feed: URL = RoomConfig.catalogFeedURL, signature: URL = RoomConfig.catalogSignatureURL) async throws -> Catalog {
        guard key != nil else { throw UpdateError.disabled }
        async let body = URLSession.shared.data(from: feed)
        async let sig = URLSession.shared.data(from: signature)
        let (data, _) = try await body
        let (sigData, _) = try await sig
        let catalog = try CatalogVerifier.decodeVerified(data: data, signature: sigData, publicKeyBase64: key)
        guard catalog.version > current(paths: paths).version else { throw UpdateError.notNewer }
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try data.write(to: paths.catalogCache, options: .atomic)
        return catalog
    }
}
