import Foundation

/// Answers "is this work safe somewhere else?" before anything inside a repo is removed.
public enum GitStatus: Codable, Sendable, Equatable {
    case notRepo
    case pushed                    // clean tree, nothing ahead of upstream
    case dirty(changedFiles: Int)  // uncommitted work
    case unpushed(commits: Int)    // commits that exist only here
    case noRemote                  // repo with no remote at all

    public var isSafeCopyElsewhere: Bool { if case .pushed = self { true } else { false } }

    public var label: String {
        switch self {
        case .notRepo: "Not a git repo"
        case .pushed: "Backed up on remote"
        case .dirty(let n): "\(n) uncommitted change\(n == 1 ? "" : "s")"
        case .unpushed(let n): "\(n) unpushed commit\(n == 1 ? "" : "s")"
        case .noRemote: "No remote, only copy"
        }
    }

    /// Short key for anonymized learning records.
    public var key: String {
        switch self {
        case .notRepo: "notRepo"; case .pushed: "pushed"; case .dirty: "dirty"
        case .unpushed: "unpushed"; case .noRemote: "noRemote"
        }
    }
}

public enum GitGuard {
    /// Nearest enclosing git repo root, if any.
    public static func repoRoot(for url: URL) -> URL? {
        // Ask the filesystem: a URL built without a trailing slash can still be a directory.
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        var dir = isDir ? url : url.deletingLastPathComponent()
        let fm = FileManager.default
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    public static func status(for url: URL) -> GitStatus {
        guard let root = repoRoot(for: url) else { return .notRepo }
        func git(_ args: [String]) -> CommandResult { CommandRunner.run("git", ["-C", root.path] + args, timeout: 20) }

        let remotes = git(["remote"])
        guard remotes.ok else { return .notRepo }
        if remotes.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .noRemote }

        let dirty = git(["status", "--porcelain"])
        let changed = dirty.output.split(separator: "\n").count
        if dirty.ok && changed > 0 { return .dirty(changedFiles: changed) }

        let ahead = git(["rev-list", "--count", "@{u}..HEAD"])
        if ahead.ok, let n = Int(ahead.output.trimmingCharacters(in: .whitespacesAndNewlines)), n > 0 { return .unpushed(commits: n) }
        // No upstream configured for this branch: compare against any remote branch instead.
        if !ahead.ok {
            let unique = git(["log", "--branches", "--not", "--remotes", "--oneline"])
            let n = unique.output.split(separator: "\n").count
            if unique.ok && n > 0 { return .unpushed(commits: n) }
        }
        return .pushed
    }
}
