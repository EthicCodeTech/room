import Foundation

public struct DiscoveryOptions: Sendable {
    public var home: URL = FileManager.default.homeDirectoryForCurrentUser
    public var projectRoots: [String] = ["~/Projects", "~/Developer", "~/Code", "~/dev", "~/src"]
    public var staleProjectDays = 60
    public var installerMinAgeDays = 14
    public var largeFileBytes: Int64 = 500_000_000
    public var largeFileMinAgeDays = 60
    public var minimumBytes: Int64 = 20_000_000
    public var catalog: Catalog = .builtIn
    public init() {}
}

/// Turns the catalog and a few detectors into concrete, sized, deletable candidates.
public struct Discovery: Sendable {
    public var options: DiscoveryOptions
    public init(options: DiscoveryOptions = .init()) { self.options = options }

    /// Measures everything concurrently, so the whole scan takes as long as its slowest part, not the sum of them.
    public func run(progress: (@Sendable (String) -> Void)? = nil) async -> [Candidate] {
        progress?("Measuring caches, projects and downloads")
        async let rules = ruleCandidatesParallel()
        async let projects = nodeModulesParallel()
        async let small = Task.detached(priority: .userInitiated) { (self.downloadsAndDesktop(), self.virtualMachines()) }.value
        let (downloads, vms) = await small
        let all = await rules + projects + downloads + vms
        return all.filter { $0.kind == .command || $0.estimate.planning >= options.minimumBytes }
            .sorted { $0.estimate.planning > $1.estimate.planning }
    }

    // MARK: Catalog rules

    func ruleCandidatesParallel() async -> [Candidate] {
        let rules = options.catalog.rules, now = Date()
        let lists = await withTaskGroup(of: (Int, [Candidate]).self) { group -> [[Candidate]] in
            for (i, rule) in rules.enumerated() { group.addTask { (i, self.candidates(for: rule, now: now)) } }
            var out = [[Candidate]](repeating: [], count: rules.count)
            for await (i, list) in group { out[i] = list }
            return out
        }
        return merge(lists.flatMap { $0 })
    }

    /// Kept for tests and callers that want a plain synchronous result.
    func ruleCandidates() -> [Candidate] { merge(options.catalog.rules.flatMap { candidates(for: $0, now: Date()) }) }

    func candidates(for rule: CatalogRule, now: Date) -> [Candidate] {
        var out: [Candidate] = []
        switch rule.action {
        case .command(let cmd):
            guard CommandRunner.locate(cmd.requiredTool) != nil else { return [] }
            let reclaim = cmd == .dockerBuilderPruneAndTrim ? DockerInspector.reclaimableBuildCache() : nil
            guard cmd != .dockerBuilderPruneAndTrim || (reclaim ?? 0) > 0 else { return [] }
            out.append(Candidate(
                id: Candidate.makeID(ruleID: rule.id, key: rule.id), ruleID: rule.id, kind: .command,
                title: rule.title, why: rule.why, tier: rule.tier, regen: rule.regen, action: rule.action,
                targets: [], displayPath: "runs `\(cmd.steps.map { ([$0.tool] + $0.args).joined(separator: " ") }.joined(separator: " && "))`",
                estimate: SizeEstimate(allocated: reclaim ?? 0, guaranteed: reclaim ?? 0), lastModified: nil,
                tags: rule.tags, preselected: rule.tier == .safe && (reclaim ?? 0) > 0))
        case .deleteContents, .deleteItem:
            // The per-file clone check is expensive, and only some tools create clones (Chrome's updater, for one).
            // Rules say so with a "clone" tag; everything else is measured with the fast bulk walker.
            let checkClones = rule.tags.contains("clone")
            for pattern in rule.paths {
                for url in PathExpander.expand(pattern, home: options.home) {
                    var targets = [url]
                    if rule.action == .deleteContents {
                        let kids = (try? FileManager.default.contentsOfDirectory(
                            at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                        targets = kids.filter { kid in
                            guard let mins = rule.minAgeMinutes else { return true }
                            let m = (try? kid.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                            return m.map { now.timeIntervalSince($0) > Double(mins) * 60 } ?? true
                        }
                    }
                    guard !targets.isEmpty else { continue }
                    let est = targets.reduce(SizeEstimate.zero) { $0 + SizeEstimator.estimate(at: $1, precise: checkClones) }
                    let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let perItem = rule.action == .deleteItem && rule.paths.contains { $0.contains("*") }
                    out.append(Candidate(
                        id: Candidate.makeID(ruleID: rule.id, key: url.path), ruleID: rule.id, kind: .rule,
                        title: perItem ? "\(rule.title): \(url.lastPathComponent)" : rule.title, why: rule.why, tier: rule.tier, regen: rule.regen, action: rule.action,
                        targets: targets, displayPath: Self.pretty(url), estimate: est, lastModified: mod,
                        tags: rule.tags, preselected: rule.tier == .safe))
                }
            }
        }
        return out
    }

    /// Rules with several paths (e.g. all browser caches) become one row; per-item rules stay separate.
    private func merge(_ list: [Candidate]) -> [Candidate] {
        var order: [String] = []
        var groups: [String: [Candidate]] = [:]
        for c in list {
            if groups[c.ruleID] == nil { order.append(c.ruleID) }
            groups[c.ruleID, default: []].append(c)
        }
        return order.flatMap { rid -> [Candidate] in
            let g = groups[rid]!
            guard g.count > 1, g[0].action == .deleteContents else { return g }
            let f = g[0]
            return [Candidate(id: Candidate.makeID(ruleID: rid, key: rid), ruleID: rid, kind: .rule, title: f.title, why: f.why,
                              tier: f.tier, regen: f.regen, action: f.action, targets: g.flatMap(\.targets),
                              displayPath: "\(g.count) locations", estimate: g.reduce(.zero) { $0 + $1.estimate },
                              lastModified: g.compactMap(\.lastModified).max(), tags: f.tags, preselected: f.preselected)]
        }
    }

    // MARK: Detectors

    private struct NodeModulesSite { let dir: URL; let nm: URL; let activity: Date }

    /// Finds stale projects first (cheap), so the expensive sizing can then run for all of them at once.
    private func nodeModuleSites() -> [NodeModulesSite] {
        let fm = FileManager.default
        var sites: [NodeModulesSite] = []
        let cutoff = Date().addingTimeInterval(-Double(options.staleProjectDays) * 86_400)
        for pattern in options.projectRoots {
            for root in PathExpander.expand(pattern, home: options.home) {
                walk(root, depth: 0, maxDepth: 5) { dir in
                    let nm = dir.appendingPathComponent("node_modules")
                    guard fm.fileExists(atPath: nm.path) else { return false }
                    let activity = Self.projectActivity(dir)
                    if activity < cutoff { sites.append(NodeModulesSite(dir: dir, nm: nm, activity: activity)) }
                    return true // don't descend into this project's own tree further
                }
            }
        }
        return sites
    }

    private func nodeModulesCandidate(_ site: NodeModulesSite) -> Candidate {
        Candidate(
            id: Candidate.makeID(ruleID: "detect.node_modules", key: site.nm.path), ruleID: "detect.node_modules",
            kind: .nodeModules, title: "node_modules: \(site.dir.lastPathComponent)",
            why: "Dependencies for a project untouched for \(Int(Date().timeIntervalSince(site.activity) / 86_400)) days. `npm install` / `pnpm install` brings them back.",
            tier: .rebuildable, regen: .minutes, action: .deleteItem, targets: [site.nm],
            displayPath: Self.pretty(site.nm), estimate: SizeEstimator.estimate(at: site.nm, precise: false), lastModified: site.activity,
            preselected: true)
    }

    func nodeModulesParallel() async -> [Candidate] {
        let sites = await Task.detached(priority: .userInitiated) { self.nodeModuleSites() }.value
        return await withTaskGroup(of: Candidate.self) { group in
            for site in sites { group.addTask { self.nodeModulesCandidate(site) } }
            var out: [Candidate] = []
            for await c in group { out.append(c) }
            return out
        }
    }

    func nodeModules() -> [Candidate] { nodeModuleSites().map(nodeModulesCandidate) }

    /// Newest of: package.json, lockfiles, git index — a decent "last worked on" signal.
    static func projectActivity(_ dir: URL) -> Date {
        let fm = FileManager.default
        let names = ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", ".git/index", ".git/HEAD"]
        let dates = names.compactMap { n -> Date? in
            let u = dir.appendingPathComponent(n)
            return (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
        }
        // Source edits bump the directory mtime on most editors' atomic saves.
        let dirDate = (try? fm.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date
        return (dates + [dirDate].compactMap { $0 }).max() ?? .distantPast
    }

    private func walk(_ url: URL, depth: Int, maxDepth: Int, visit: (URL) -> Bool) {
        let fm = FileManager.default
        if visit(url) { return }
        guard depth < maxDepth,
              let kids = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for k in kids {
            let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
            let n = k.lastPathComponent
            if n.hasPrefix(".") || n == "node_modules" || n == "Library" { continue }
            walk(k, depth: depth + 1, maxDepth: maxDepth, visit: visit)
        }
    }

    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "exe", "msi", "crdownload", "part"]

    func downloadsAndDesktop() -> [Candidate] {
        let fm = FileManager.default
        var out: [Candidate] = []
        let installerCutoff = Date().addingTimeInterval(-Double(options.installerMinAgeDays) * 86_400)
        let largeCutoff = Date().addingTimeInterval(-Double(options.largeFileMinAgeDays) * 86_400)
        for folder in ["Downloads", "Desktop"] {
            let dir = options.home.appendingPathComponent(folder)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
            let names = Set(items.map(\.lastPathComponent))
            for item in items {
                let name = item.lastPathComponent
                let ext = item.pathExtension.lowercased()
                let mod = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
                let isApp = ext == "app"
                if Self.installerExtensions.contains(ext) || (isApp && name.lowercased().contains("install")) {
                    guard mod < installerCutoff || ext == "crdownload" || ext == "part" else { continue }
                    let est = SizeEstimator.estimate(at: item, precise: false)
                    out.append(make(.installer, "detect.installer", "Installer: \(name)",
                                    ext == "crdownload" || ext == "part" ? "An unfinished download." : "An installer you've probably already used. You can download it again.",
                                    .rebuildable, .minutes, item, est, mod, preselected: true))
                } else if ext == "zip", names.contains((name as NSString).deletingPathExtension) {
                    let est = SizeEstimator.estimate(at: item, precise: false)
                    out.append(make(.duplicate, "detect.zip-duplicate", "Zip with extracted copy: \(name)",
                                    "A folder with the same name already sits next to this zip, so the archive is redundant.",
                                    .rebuildable, .instant, item, est, mod, preselected: false))
                } else {
                    let est = SizeEstimator.estimate(at: item, precise: false)
                    if est.allocated >= options.largeFileBytes && mod < largeCutoff {
                        out.append(make(.largeFile, "detect.large-old", "Large and untouched: \(name)",
                                        "Over \(ByteFormat.string(options.largeFileBytes)) and unopened for \(Int(Date().timeIntervalSince(mod) / 86_400)) days. Only you know if it matters.",
                                        .yours, .never, item, est, mod, preselected: false))
                    }
                }
            }
        }
        return out
    }

    func virtualMachines() -> [Candidate] {
        var out: [Candidate] = []
        let patterns = ["~/Virtual Machines.localized/*.vmwarevm", "~/Parallels/*.pvm", "~/Library/Containers/com.utmapp.UTM/Data/Documents/*.utm"]
        for p in patterns {
            for url in PathExpander.expand(p, home: options.home) {
                let est = SizeEstimator.estimate(at: url, precise: false)
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                out.append(make(.vm, "detect.vm", "Virtual machine: \(url.deletingPathExtension().lastPathComponent)",
                                "A full VM disk. Deleting it removes everything installed inside it.",
                                .yours, .never, url, est, mod, preselected: false))
            }
        }
        return out
    }

    private func make(_ kind: Candidate.Kind, _ ruleID: String, _ title: String, _ why: String, _ tier: RiskTier,
                      _ regen: RegenCost, _ url: URL, _ est: SizeEstimate, _ mod: Date?, preselected: Bool) -> Candidate {
        Candidate(id: Candidate.makeID(ruleID: ruleID, key: url.path), ruleID: ruleID, kind: kind, title: title, why: why,
                  tier: tier, regen: regen, action: .deleteItem, targets: [url], displayPath: Self.pretty(url),
                  estimate: est, lastModified: mod, preselected: preselected)
    }

    static func pretty(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Reads Docker's own accounting so the build-cache row shows a real number.
public enum DockerInspector {
    public static func reclaimableBuildCache() -> Int64? {
        let r = CommandRunner.run("docker", ["system", "df", "--format", "{{json .}}"], timeout: 15)
        guard r.ok else { return nil }
        for line in r.output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["Type"] as? String) == "Build Cache",
                  let rec = obj["Reclaimable"] as? String else { continue }
            return parseDockerSize(rec)
        }
        return nil
    }

    /// "28.66GB (91%)" → bytes. Docker uses decimal units.
    static func parseDockerSize(_ s: String) -> Int64? {
        let token = s.split(separator: " ").first.map(String.init) ?? s
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, mult) in units where token.hasSuffix(suffix) {
            if let v = Double(token.dropLast(suffix.count)) { return Int64(v * mult) }
        }
        return nil
    }
}

/// "/Users/me/Projects/x" → "~/Projects/x", the way candidates display their paths.
public enum PathDisplay {
    public static func pretty(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
    }
}
