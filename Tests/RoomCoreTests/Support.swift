import Foundation
@testable import RoomCore

/// A throwaway fake home so tests never touch real files.
final class Sandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var appRoot: URL { root.appendingPathComponent("app", isDirectory: true) }
    var paths: AppPaths { AppPaths(root: appRoot) }
    let fm = FileManager.default

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("room-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
    }
    deinit { try? fm.removeItem(at: root) }

    @discardableResult
    func file(_ rel: String, bytes: Int = 1024, age days: Int = 0) throws -> URL {
        let url = home.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = UInt8(truncatingIfNeeded: i / 4096 &+ 1) }   // non-zero so APFS really allocates
        try data.write(to: url)
        if days > 0 { try age(url, days: days) }
        return url
    }

    func age(_ url: URL, days: Int) throws {
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(days) * 86_400)], ofItemAtPath: url.path)
    }

    func exists(_ rel: String) -> Bool { fm.fileExists(atPath: home.appendingPathComponent(rel).path) }

    func options() -> DiscoveryOptions {
        var o = DiscoveryOptions()
        o.home = home
        o.projectRoots = ["~/Projects"]
        o.minimumBytes = 1
        return o
    }

    func candidate(_ id: String = "t", tier: RiskTier = .safe, targets: [URL], bytes: Int64 = 1000,
                   action: RuleAction = .deleteItem, git: GitStatus = .notRepo, ruleID: String = "cache.spotify") -> Candidate {
        var c = Candidate(id: id, ruleID: ruleID, kind: .rule, title: "Test \(id)", why: "why", tier: tier, regen: .instant, action: action,
                          targets: targets, displayPath: "x", estimate: SizeEstimate(allocated: bytes, guaranteed: bytes),
                          lastModified: Date(), preselected: tier == .safe)
        c.git = git
        return c
    }
}
