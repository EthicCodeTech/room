import Foundation

public struct GrowthSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var freeBytes: Int64
    public var totalBytes: Int64
    /// Sizes of named areas (top-level home folders, candidates), keyed by a display name.
    public var areas: [String: Int64]
    public init(date: Date, freeBytes: Int64, totalBytes: Int64, areas: [String: Int64]) {
        self.date = date; self.freeBytes = freeBytes; self.totalBytes = totalBytes; self.areas = areas
    }
}

public struct GrowthDelta: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let delta: Int64
}

public final class GrowthStore: @unchecked Sendable {
    private let paths: AppPaths
    private let lock = NSLock()
    public init(paths: AppPaths) { self.paths = paths }

    public func load() -> [GrowthSnapshot] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: paths.growth) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([GrowthSnapshot].self, from: data)) ?? []
    }

    /// Keeps at most one snapshot per hour and 200 total.
    public func add(_ snap: GrowthSnapshot) {
        var all = load()
        if let last = all.last, snap.date.timeIntervalSince(last.date) < 3600 { all.removeLast() }
        all.append(snap)
        if all.count > 200 { all.removeFirst(all.count - 200) }
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(all).write(to: paths.growth, options: .atomic)
    }

    /// What grew (or shrank) between two snapshots, biggest change first.
    public static func deltas(from old: GrowthSnapshot, to new: GrowthSnapshot, minimum: Int64 = 100_000_000) -> [GrowthDelta] {
        let keys = Set(old.areas.keys).union(new.areas.keys)
        return keys.map { GrowthDelta(name: $0, delta: (new.areas[$0] ?? 0) - (old.areas[$0] ?? 0)) }
            .filter { abs($0.delta) >= minimum }.sorted { abs($0.delta) > abs($1.delta) }
    }

    /// Compares the newest snapshot with the closest one at least `days` old.
    public func recentDeltas(days: Int = 7, now: Date = Date()) -> (from: GrowthSnapshot, to: GrowthSnapshot, deltas: [GrowthDelta])? {
        let all = load()
        guard let latest = all.last else { return nil }
        let target = now.addingTimeInterval(-Double(days) * 86_400)
        guard let base = all.last(where: { $0.date <= target }) ?? all.first, base != latest else { return nil }
        return (base, latest, Self.deltas(from: base, to: latest))
    }
}

/// Measures a fixed set of well-known areas so growth can be tracked week to week.
public enum AreaMeter {
    public static func defaultAreas(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [(name: String, url: URL)] {
        func h(_ p: String) -> URL { home.appendingPathComponent(p) }
        return [("Caches", h("Library/Caches")), ("App data", h("Library/Application Support")),
                ("App containers", h("Library/Containers")), ("Group containers", h("Library/Group Containers")),
                ("Downloads", h("Downloads")), ("Desktop", h("Desktop")), ("Documents", h("Documents")),
                ("Projects", h("Projects")), ("Docker (Colima)", h(".colima")), ("Local models", h(".ollama")),
                ("Gradle", h(".gradle")), ("Package caches", h(".npm")), ("Temp folders", URL(fileURLWithPath: "/private/var/folders")),
                ("Simulators and Xcode", h("Library/Developer"))]
    }

    /// Allocated sizes, measured in parallel. Slow on big disks, so call it off the main thread and sparingly.
    public static func measure(_ areas: [(name: String, url: URL)]) async -> [String: Int64] {
        await withTaskGroup(of: (String, Int64).self) { group in
            for a in areas where FileManager.default.fileExists(atPath: a.url.path) {
                group.addTask { (a.name, SizeEstimator.allocatedBytes(at: a.url)) }
            }
            var out: [String: Int64] = [:]
            for await (n, b) in group { out[n] = b }
            return out
        }
    }
}
