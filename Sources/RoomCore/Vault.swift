import Foundation

/// The undo vault. "Delete" for anything that might be someone's work moves it here first.
/// On APFS a same-volume move is an instant rename, so nothing is copied; space is returned on purge.
public struct VaultManifest: Codable, Identifiable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var originalPath: String
        public var storedPath: String      // inside the vault, or the Trash path for cross-volume items
        public var bytes: Int64
        public var title: String
        public var ruleID: String
    }
    public var id: UUID
    public var label: String
    public var created: Date
    public var expires: Date
    public var entries: [Entry]
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
}

public final class Vault: @unchecked Sendable {
    public enum VaultError: Error, LocalizedError {
        case notFound
        public var errorDescription: String? { "That vault batch no longer exists." }
    }

    private let paths: AppPaths
    private let fm = FileManager.default
    public init(paths: AppPaths) { self.paths = paths }

    private func batchDir(_ id: UUID) -> URL { paths.vault.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func manifestURL(_ id: UUID) -> URL { batchDir(id).appendingPathComponent("manifest.json") }

    /// Moves items into the vault. Returns the manifest plus any items that couldn't be moved.
    public func stash(_ items: [(url: URL, bytes: Int64, title: String, ruleID: String)],
                      label: String, days: Int, now: Date = Date()) throws -> (VaultManifest, failures: [(URL, Error)]) {
        let id = UUID()
        try fm.createDirectory(at: batchDir(id), withIntermediateDirectories: true)
        var entries: [VaultManifest.Entry] = []
        var failures: [(URL, Error)] = []
        for (index, item) in items.enumerated() {
            let dest = batchDir(id).appendingPathComponent("\(index)-\(item.url.lastPathComponent)")
            do {
                if sameVolume(item.url, paths.vault) {
                    try fm.moveItem(at: item.url, to: dest)
                    entries.append(.init(originalPath: item.url.path, storedPath: dest.path, bytes: item.bytes, title: item.title, ruleID: item.ruleID))
                } else {
                    var trashed: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &trashed)
                    entries.append(.init(originalPath: item.url.path, storedPath: (trashed as URL?)?.path ?? "", bytes: item.bytes, title: item.title, ruleID: item.ruleID))
                }
            } catch { failures.append((item.url, error)) }
        }
        let manifest = VaultManifest(id: id, label: label, created: now,
                                     expires: now.addingTimeInterval(Double(days) * 86_400), entries: entries)
        try write(manifest)
        return (manifest, failures)
    }

    public func list() -> [VaultManifest] {
        guard let dirs = try? fm.contentsOfDirectory(at: paths.vault, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return dirs.compactMap { try? dec.decode(VaultManifest.self, from: Data(contentsOf: $0.appendingPathComponent("manifest.json"))) }
            .sorted { $0.created > $1.created }
    }

    /// Puts everything back where it came from. If the spot is taken, restores beside it as "name (restored)".
    @discardableResult
    public func restore(_ id: UUID) throws -> [URL] {
        guard fm.fileExists(atPath: manifestURL(id).path) else { throw VaultError.notFound }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let manifest = try dec.decode(VaultManifest.self, from: Data(contentsOf: manifestURL(id)))
        var restored: [URL] = []
        for e in manifest.entries {
            var target = URL(fileURLWithPath: e.originalPath)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                let ext = target.pathExtension
                let base = target.deletingPathExtension().lastPathComponent + " (restored)"
                target = target.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
            }
            try fm.moveItem(at: URL(fileURLWithPath: e.storedPath), to: target)
            restored.append(target)
        }
        try? fm.removeItem(at: batchDir(id))
        return restored
    }

    /// Permanently deletes a batch. This is the point of no return.
    public func purge(_ id: UUID) {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: manifestURL(id)), let m = try? dec.decode(VaultManifest.self, from: data) {
            for e in m.entries where !e.storedPath.hasPrefix(batchDir(id).path) { try? fm.removeItem(atPath: e.storedPath) }
        }
        try? fm.removeItem(at: batchDir(id))
    }

    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        let expired = list().filter { $0.expires <= now }
        expired.forEach { purge($0.id) }
        return expired.count
    }

    public func totalBytes() -> Int64 { list().reduce(0) { $0 + $1.totalBytes } }

    private func write(_ m: VaultManifest) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(m).write(to: manifestURL(m.id), options: .atomic)
    }

    private func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: URLResourceKey = .volumeIdentifierKey
        guard let av = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let bv = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return av.isEqual(bv)
    }
}
