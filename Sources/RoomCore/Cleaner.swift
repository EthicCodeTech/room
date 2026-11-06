import Foundation

/// What the user explicitly agreed to, beyond ticking the box.
public struct Confirmations: Sendable {
    /// `yours`-tier candidates the user confirmed by name.
    public var yours: Set<String> = []
    /// Candidates inside a git repo whose work isn't backed up that the user confirmed anyway.
    public var unbackedRepo: Set<String> = []
    /// Candidates the user left unticked that were preselected (a learning signal).
    public var declined: [Candidate] = []
    public init(yours: Set<String> = [], unbackedRepo: Set<String> = [], declined: [Candidate] = []) {
        self.yours = yours; self.unbackedRepo = unbackedRepo; self.declined = declined
    }
}

public struct CleanItemResult: Sendable, Identifiable {
    public enum Status: Sendable, Equatable { case deleted, vaulted(days: Int), skipped(String), failed(String) }
    public var id: String { candidate.id }
    public let candidate: Candidate
    public let status: Status
}

public struct CleanReport: Sendable {
    public var results: [CleanItemResult]
    public var freeBefore: Int64
    public var freeAfter: Int64
    public var measuredFreed: Int64 { max(0, freeAfter - freeBefore) }
    public var vaultedBytes: Int64 {
        results.reduce(0) { if case .vaulted = $1.status { return $0 + $1.candidate.estimate.allocated } else { return $0 } }
    }
}

public final class Cleaner: @unchecked Sendable {
    private let vault: Vault
    private let log: DecisionLog?
    private let home: URL
    private let fm = FileManager.default

    public init(vault: Vault, log: DecisionLog? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.vault = vault; self.log = log; self.home = home
    }

    /// Refuses unsafe work up front. Returns a reason or nil if it can proceed.
    public func blockReason(for c: Candidate, confirmations: Confirmations) -> String? {
        if c.tier == .yours && !confirmations.yours.contains(c.id) { return "Needs your explicit confirmation" }
        if c.kind != .command, c.targets.isEmpty { return "Nothing to delete" }
        for t in c.targets where !PathSafety.isDeletable(t, home: home) { return "Protected location" }
        if c.tier == .yours, c.git != .notRepo, !c.git.isSafeCopyElsewhere, !confirmations.unbackedRepo.contains(c.id) {
            return "Not backed up: \(c.git.label)"
        }
        return nil
    }

    public func execute(_ items: [Candidate], confirmations: Confirmations = .init(),
                        policy: (Candidate) -> DeletionPolicy = { DeletionPolicy.default(for: $0.tier) },
                        progress: (@Sendable (String) -> Void)? = nil) -> CleanReport {
        let before = FreeSpace.available(at: home)
        var results: [CleanItemResult] = []
        for c in items {
            progress?(c.title)
            if let reason = blockReason(for: c, confirmations: confirmations) {
                results.append(.init(candidate: c, status: .skipped(reason))); continue
            }
            switch c.action {
            case .command(let id):
                let r = run(id)
                if r.ok { results.append(.init(candidate: c, status: .deleted)); log?.record(c, outcome: .deleted) }
                else { results.append(.init(candidate: c, status: .failed(String(r.output.suffix(200))))) }
            case .deleteContents, .deleteItem:
                switch policy(c) {
                case .immediate:
                    var firstError: String?
                    for t in c.targets { do { try fm.removeItem(at: t) } catch { firstError = firstError ?? error.localizedDescription } }
                    if let e = firstError, c.targets.allSatisfy({ fm.fileExists(atPath: $0.path) }) {
                        results.append(.init(candidate: c, status: .failed(e)))
                    } else { results.append(.init(candidate: c, status: .deleted)); log?.record(c, outcome: .deleted) }
                case .vault(let days):
                    let payload = c.targets.map { (url: $0, bytes: c.estimate.allocated / Int64(max(1, c.targets.count)), title: c.title, ruleID: c.ruleID) }
                    do {
                        let (_, failures) = try vault.stash(payload, label: c.title, days: days)
                        if failures.count == c.targets.count { results.append(.init(candidate: c, status: .failed(failures[0].1.localizedDescription))) }
                        else { results.append(.init(candidate: c, status: .vaulted(days: days))); log?.record(c, outcome: .deleted) }
                    } catch { results.append(.init(candidate: c, status: .failed(error.localizedDescription))) }
                }
            }
        }
        for d in confirmations.declined { log?.record(d, outcome: .declined) }
        return CleanReport(results: results, freeBefore: before, freeAfter: FreeSpace.available(at: home))
    }

    /// Releases the space held by the undo vault right now.
    public func freeVaultNow() -> CleanReport {
        let before = FreeSpace.available(at: home)
        vault.list().forEach { vault.purge($0.id) }
        return CleanReport(results: [], freeBefore: before, freeAfter: FreeSpace.available(at: home))
    }

    public func restore(_ manifest: VaultManifest, candidates: [Candidate] = []) throws -> [URL] {
        let urls = try vault.restore(manifest.id)
        for e in manifest.entries {
            if let c = candidates.first(where: { $0.ruleID == e.ruleID }) { log?.record(c, outcome: .restored) }
            else {
                log?.append(DecisionRecord(day: Anonymizer.record(for: Self.stub(e), outcome: .restored).day, ruleID: e.ruleID,
                                           tier: .yours, sizeBucket: Int(log2(Double(max(1, e.bytes / 1_000_000)))), ageBucket: 0,
                                           git: "notRepo", outcome: .restored, appVersion: RoomConfig.appVersion))
            }
        }
        return urls
    }

    private static func stub(_ e: VaultManifest.Entry) -> Candidate {
        Candidate(id: e.ruleID, ruleID: e.ruleID, kind: .rule, title: e.title, why: "", tier: .yours, regen: .hours, action: .deleteItem,
                  targets: [], displayPath: "", estimate: SizeEstimate(allocated: e.bytes, guaranteed: e.bytes), lastModified: nil, preselected: false)
    }

    private func run(_ id: CommandID) -> CommandResult {
        var last = CommandResult(status: 0, output: "")
        for step in id.steps {
            last = CommandRunner.run(step.tool, step.args, timeout: 900)
            if !last.ok && !(id == .dockerBuilderPruneAndTrim && step.tool == "colima") { return last }
        }
        return last
    }
}
