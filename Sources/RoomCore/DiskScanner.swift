import Foundation
import Darwin

/// Fast allocated-size measuring with the C `fts` walker (several times quicker than Foundation's file enumerator).
/// Symlinks are never followed and other volumes are not crossed. Honours Task cancellation.
public enum FastSize {
    public struct Result: Sendable, Equatable {
        public var bytes: Int64
        /// True if the starting point itself could not be read.
        public var rootUnreadable: Bool
    }

    /// The fast path (`getattrlistbulk`), with `fts` as the automatic fallback.
    public static func measure(path: String) -> Result { BulkWalk.measure(path: path) ?? ftsMeasure(path: path) }

    /// The portable reference implementation, kept for fallback and for cross-checking the fast one.
    static func ftsMeasure(path: String) -> Result {
        var total: Int64 = 0
        var rootUnreadable = false
        guard let cPath = strdup(path) else { return Result(bytes: 0, rootUnreadable: true) }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        let handle: UnsafeMutablePointer<FTS>? = argv.withUnsafeMutableBufferPointer { buf in
            fts_open(buf.baseAddress, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)
        }
        guard let fts = handle else { return Result(bytes: 0, rootUnreadable: true) }
        defer { fts_close(fts) }
        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited & 0x3FF == 0 && Task.isCancelled { break }
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_DEFAULT:
                if let st = entry.pointee.fts_statp { total += Int64(st.pointee.st_blocks) * 512 }
            case FTS_DNR, FTS_ERR, FTS_NS:
                if entry.pointee.fts_level == 0 { rootUnreadable = true }
            default: break          // directories, symlinks and post-order visits add nothing
            }
        }
        return Result(bytes: total, rootUnreadable: rootUnreadable)
    }

    public static func allocatedBytes(atPath path: String) -> Int64 { measure(path: path).bytes }
}

public enum DiskScanner {
    /// `done` and `total` count the folders being measured, so a progress bar moves smoothly instead of in a few big jumps.
    public typealias Progress = @Sendable (_ partial: DiskNode, _ done: Int, _ total: Int) -> Void

    /// A node while the scan is still running. Only ever touched by the scan itself.
    private final class Draft {
        let path: String, name: String
        var isDirectory: Bool
        var bytes: Int64 = 0
        var children: [Draft] = []
        var expanded = false
        var unreadable = false
        init(path: String, name: String, isDirectory: Bool) { self.path = path; self.name = name; self.isDirectory = isDirectory }
    }

    /// Builds a size tree `depth` levels deep in two phases, so every core stays busy:
    /// 1. list the folder structure down to `depth` (cheap), then
    /// 2. measure every leaf folder in parallel, biggest first when `hints` (the previous scan) says which are big.
    /// A big folder therefore no longer holds up the whole scan, which was the bottleneck when each top-level folder
    /// ran on one core. `progress` reports a partial tree as leaves finish, at most about five times a second.
    public static func scan(_ root: URL, depth: Int = 3, maxChildren: Int = 40, hints: DiskNode? = nil,
                            concurrency: Int = max(4, ProcessInfo.processInfo.activeProcessorCount),
                            progress: Progress? = nil) async -> DiskNode {
        let top = Draft(path: root.path, name: root.lastPathComponent, isDirectory: true)
        var leaves: [Draft] = []

        // Phase 1: structure. Child paths are built from the parent's own path (the system may hand back /private/var
        // for /var, and every prefix comparison downstream needs one consistent spelling).
        func list(_ d: Draft, level: Int) {
            if Task.isCancelled { return }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { d.unreadable = true; d.expanded = true; return }
            d.expanded = true
            for name in names {
                var st = stat()
                let path = d.path == "/" ? "/" + name : d.path + "/" + name
                guard lstat(path, &st) == 0 else { continue }
                let mode = st.st_mode & S_IFMT
                if mode == S_IFLNK { continue }                                   // never follow symlinks
                let child = Draft(path: path, name: name, isDirectory: mode == S_IFDIR)
                if !child.isDirectory { child.bytes = Int64(st.st_blocks) * 512; child.expanded = true }
                else if level < depth { list(child, level: level + 1) }
                if child.isDirectory && !child.expanded { leaves.append(child) }
                d.children.append(child)
            }
        }
        list(top, level: 1)

        // Phase 2: measure the leaves, biggest first so the slowest work starts earliest.
        let known = hints.map { Self.sizes(in: $0) } ?? [:]
        let order = leaves.indices.sorted { (known[leaves[$0].path] ?? 0) > (known[leaves[$1].path] ?? 0) }
        let total = order.count
        var done = 0
        var lastEmit = Date.distantPast
        func emit(force: Bool) {
            guard let progress, force || Date().timeIntervalSince(lastEmit) > 0.2 else { return }
            lastEmit = Date()
            progress(assemble(top, maxChildren: maxChildren), done, total)
        }
        await withTaskGroup(of: (Int, FastSize.Result).self) { group in
            var next = 0
            while next < min(concurrency, order.count) {
                let i = order[next]; next += 1
                let path = leaves[i].path
                group.addTask { (i, FastSize.measure(path: path)) }
            }
            for await (i, result) in group {
                leaves[i].bytes = result.bytes; leaves[i].unreadable = result.rootUnreadable
                done += 1
                emit(force: false)
                if Task.isCancelled { group.cancelAll(); continue }
                if next < order.count {
                    let j = order[next]; next += 1
                    let path = leaves[j].path
                    group.addTask { (j, FastSize.measure(path: path)) }
                }
            }
        }
        let result = assemble(top, maxChildren: maxChildren)
        if !Task.isCancelled { progress?(result, total, total) }
        return result
    }

    private static func assemble(_ d: Draft, maxChildren: Int) -> DiskNode {
        guard d.isDirectory, d.expanded else {
            return DiskNode(path: d.path, name: d.name, bytes: d.bytes, children: [], isDirectory: d.isDirectory,
                            isExpanded: !d.isDirectory, isUnreadable: d.unreadable)
        }
        let kids = d.children.map { assemble($0, maxChildren: maxChildren) }.sorted { $0.bytes > $1.bytes }
        return DiskNode(path: d.path, name: d.name, bytes: kids.reduce(0) { $0 + $1.bytes }, children: kids,
                        isDirectory: true, isExpanded: true, isUnreadable: d.unreadable).trimmed(maxChildren: maxChildren)
    }

    private static func sizes(in node: DiskNode) -> [String: Int64] {
        var out: [String: Int64] = [:]
        func walk(_ n: DiskNode) { out[n.path] = n.bytes; n.children.forEach(walk) }
        walk(node)
        return out
    }
}

/// The last map, kept between launches so reopening the Map is instant while a fresh scan runs behind it.
public struct MapCache: Codable, Sendable {
    public var root: DiskNode
    public var scannedAt: Date
    public init(root: DiskNode, scannedAt: Date) { self.root = root; self.scannedAt = scannedAt }

    public static func load(from url: URL) -> MapCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MapCache.self, from: data)
    }
    public func save(to url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? enc.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}

/// Which folders contain things Room can free, so the map can say "look here" on the right tiles.
public struct FreeableIndex: Sendable {
    private let items: [(path: String, bytes: Int64)]
    public init(candidates: [Candidate]) {
        // Only things Room would offer without a second thought: never the user's own files, never commands.
        items = candidates.filter { $0.kind != .command && $0.tier != .yours }
            .flatMap { c in c.targets.map { (path: $0.standardizedFileURL.path, bytes: c.estimate.planning / Int64(max(1, c.targets.count))) } }
    }
    public func bytes(under folder: String) -> Int64 {
        let prefix = folder == "/" ? "/" : folder + "/"
        return items.filter { $0.path == folder || $0.path.hasPrefix(prefix) }.reduce(0) { $0 + $1.bytes }
    }
    public func count(under folder: String) -> Int {
        let prefix = folder == "/" ? "/" : folder + "/"
        return items.filter { $0.path == folder || $0.path.hasPrefix(prefix) }.count
    }
}
