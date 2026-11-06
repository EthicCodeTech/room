import Foundation

/// The undo vault. "Delete" for anything that might be someone's work moves it here first.
/// A same-volume move is an instant rename, so nothing is copied; space is returned on purge.
/// Items on an external drive stay on that drive, in a hidden `.Room-Vault` folder at its root, so they get the same
/// 7-day undo without a slow cross-disk copy. Only a drive that can't hold one (read-only, say) falls back to the Trash.
public struct VaultManifest: Codable, Identifiable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var originalPath: String
        public var storedPath: String      // inside a vault, or the Trash path when the drive couldn't hold one
        public var bytes: Int64
        public var title: String
        public var ruleID: String
        /// Mount point of the external drive holding this item. nil for the main vault and for Trash fallbacks.
        public var volume: String?
        /// True when the drive couldn't hold a vault and the item went to the macOS Trash instead.
        public var viaTrash: Bool?
    }
    public var id: UUID
    public var label: String
    public var created: Date
    public var expires: Date
    public var entries: [Entry]
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
    /// Names of the external drives holding part of this batch.
    public var driveNames: [String] {
        var seen = Set<String>()
        return entries.compactMap(\.volume).filter { seen.insert($0).inserted }.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
    /// True when any item was sent to the macOS Trash because its drive couldn't hold a vault.
    public var usesTrash: Bool { entries.contains { $0.viaTrash == true } }
}

public final class Vault: @unchecked Sendable {
    public enum VaultError: Error, LocalizedError {
        case notFound
        case gone
        case partial(restored: Int, drives: [String])
        public var errorDescription: String? {
            switch self {
            case .notFound: return "That vault batch no longer exists."
            case .gone: return "These files were already removed from the vault."
            case .partial(let restored, let drives):
                let list = drives.map { "“\($0)”" }.joined(separator: ", ")
                return restored == 0 ? "Connect \(list) to restore this." : "Restored \(restored). Connect \(list) to put back the rest."
            }
        }
    }

    /// Name of the hidden folder at the root of each external drive that holds a vault.
    public static let driveFolder = ".Room-Vault"

    private let paths: AppPaths
    private let fm = FileManager.default
    private let volumeRoot: @Sendable (URL) -> URL?
    private let isSameVolume: @Sendable (URL, URL) -> Bool

    /// The two closures exist so tests can stand in for a second drive.
    public init(paths: AppPaths,
                volumeRoot: @escaping @Sendable (URL) -> URL? = Vault.mountPoint(of:),
                isSameVolume: @escaping @Sendable (URL, URL) -> Bool = Vault.onSameVolume(_:_:)) {
        self.paths = paths; self.volumeRoot = volumeRoot; self.isSameVolume = isSameVolume
    }

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
            let name = "\(index)-\(item.url.lastPathComponent)"
            func entry(_ stored: String, volume: String? = nil, viaTrash: Bool? = nil) -> VaultManifest.Entry {
                .init(originalPath: item.url.path, storedPath: stored, bytes: item.bytes, title: item.title, ruleID: item.ruleID, volume: volume, viaTrash: viaTrash)
            }
            do {
                if isSameVolume(item.url, paths.vault) {
                    let dest = batchDir(id).appendingPathComponent(name)
                    try fm.moveItem(at: item.url, to: dest)
                    entries.append(entry(dest.path))
                } else if let root = volumeRoot(item.url), let dest = try? moveIntoDriveVault(item.url, root: root, id: id, name: name) {
                    entries.append(entry(dest.path, volume: root.path))
                } else {
                    var trashed: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &trashed)
                    entries.append(entry((trashed as URL?)?.path ?? "", viaTrash: true))
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
    /// Items on a drive that isn't plugged in stay in the vault until it is; the rest are restored now.
    @discardableResult
    public func restore(_ id: UUID) throws -> [URL] {
        guard let manifest = manifest(id) else { throw VaultError.notFound }
        var restored: [URL] = [], remaining: [VaultManifest.Entry] = [], waitingFor = Set<String>()
        var firstError: Error?
        for e in manifest.entries {
            if let v = e.volume, !isOnline(v) { remaining.append(e); waitingFor.insert(URL(fileURLWithPath: v).lastPathComponent); continue }
            guard fm.fileExists(atPath: e.storedPath) else { continue }          // already gone, nothing to put back
            var target = URL(fileURLWithPath: e.originalPath)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) {
                    let ext = target.pathExtension
                    let base = target.deletingPathExtension().lastPathComponent + " (restored)"
                    target = target.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
                }
                try fm.moveItem(at: URL(fileURLWithPath: e.storedPath), to: target)
                restored.append(target)
            } catch { remaining.append(e); firstError = firstError ?? error }
        }
        if remaining.isEmpty {
            try? fm.removeItem(at: batchDir(id))
            removeDriveBatches(id, volumes: Set(manifest.entries.compactMap(\.volume)))
            if restored.isEmpty && !manifest.entries.isEmpty { throw VaultError.gone }
        } else {
            var rest = manifest; rest.entries = remaining
            try write(rest)
            if waitingFor.isEmpty, let firstError { throw firstError }
            throw VaultError.partial(restored: restored.count, drives: waitingFor.sorted())
        }
        return restored
    }

    /// Permanently deletes a batch. This is the point of no return. Returns false when part of it sits on a drive
    /// that isn't connected: that part is kept until the drive is back.
    @discardableResult
    public func purge(_ id: UUID) -> Bool {
        guard let m = manifest(id) else { try? fm.removeItem(at: batchDir(id)); return true }
        var waiting: [VaultManifest.Entry] = []
        for e in m.entries {
            if let v = e.volume, !isOnline(v) { waiting.append(e); continue }
            try? fm.removeItem(atPath: e.storedPath)
        }
        removeDriveBatches(id, volumes: Set(m.entries.compactMap(\.volume)).filter(isOnline))
        if waiting.isEmpty { try? fm.removeItem(at: batchDir(id)); return true }
        var rest = m; rest.entries = waiting
        try? write(rest)
        return false
    }

    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        list().filter { $0.expires <= now }.reduce(0) { $0 + (purge($1.id) ? 1 : 0) }
    }

    /// True when every drive holding part of this batch is connected.
    public func isAvailable(_ m: VaultManifest) -> Bool { m.entries.allSatisfy { $0.volume.map(isOnline) ?? true } }

    public func totalBytes() -> Int64 { list().reduce(0) { $0 + $1.totalBytes } }

    private func write(_ m: VaultManifest) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(m).write(to: manifestURL(m.id), options: .atomic)
    }

    private func manifest(_ id: UUID) -> VaultManifest? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: manifestURL(id))).flatMap { try? dec.decode(VaultManifest.self, from: $0) }
    }

    /// A drive counts as connected when its vault folder is readable at the mount point we recorded.
    private func isOnline(_ volume: String) -> Bool {
        fm.fileExists(atPath: URL(fileURLWithPath: volume).appendingPathComponent(Self.driveFolder).path)
    }

    private func moveIntoDriveVault(_ url: URL, root: URL, id: UUID, name: String) throws -> URL {
        let dir = root.appendingPathComponent(Self.driveFolder, isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        do { try fm.moveItem(at: url, to: dest) } catch {
            if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { removeDriveBatches(id, volumes: [root.path]) }
            throw error
        }
        return dest
    }

    /// Removes this batch's folder on each drive, and the drive's `.Room-Vault` once nothing is left in it.
    private func removeDriveBatches(_ id: UUID, volumes: Set<String>) {
        for v in volumes {
            let folder = URL(fileURLWithPath: v).appendingPathComponent(Self.driveFolder, isDirectory: true)
            try? fm.removeItem(at: folder.appendingPathComponent(id.uuidString, isDirectory: true))
            let left = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != ".DS_Store" }
            if left.isEmpty { try? fm.removeItem(at: folder) }
        }
    }

    /// The mount point of an external drive holding `url`, or nil for the startup volume and anything outside /Volumes.
    public static func mountPoint(of url: URL) -> URL? {
        guard let v = try? url.resourceValues(forKeys: [.volumeURLKey]).volume, v.path.hasPrefix("/Volumes/") else { return nil }
        return v
    }

    public static func onSameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: URLResourceKey = .volumeIdentifierKey
        guard let av = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let bv = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return false }
        return av.isEqual(bv)
    }
}
