import Foundation

public enum Outcome: String, Codable, Sendable { case deleted, declined, restored }

/// One anonymized learning example. By construction it holds no paths, names or contents:
/// only a closed-set rule id, coarse buckets and the outcome.
public struct DecisionRecord: Codable, Sendable, Equatable {
    public var v = 1
    public var day: String            // UTC date, no time of day
    public var ruleID: String         // from the catalog / detector set, else "custom"
    public var tier: RiskTier
    public var sizeBucket: Int        // floor(log2(MB))
    public var ageBucket: Int         // months since last modified
    public var git: String            // GitStatus.key
    public var outcome: Outcome
    public var appVersion: String

    public init(day: String, ruleID: String, tier: RiskTier, sizeBucket: Int, ageBucket: Int, git: String, outcome: Outcome, appVersion: String) {
        self.day = day; self.ruleID = ruleID; self.tier = tier; self.sizeBucket = sizeBucket
        self.ageBucket = ageBucket; self.git = git; self.outcome = outcome; self.appVersion = appVersion
    }
}

public enum Anonymizer {
    public static let detectorIDs: Set<String> = ["detect.node_modules", "detect.installer", "detect.zip-duplicate", "detect.large-old", "detect.vm"]

    public static func record(for c: Candidate, outcome: Outcome, catalog: Catalog = .builtIn, now: Date = Date()) -> DecisionRecord {
        let known = catalog.rule(c.ruleID) != nil || detectorIDs.contains(c.ruleID)
        let mb = max(1, c.estimate.planning / 1_000_000)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return DecisionRecord(day: f.string(from: now), ruleID: known ? c.ruleID : "custom", tier: c.tier,
                              sizeBucket: Int(log2(Double(mb))), ageBucket: min(60, c.ageDays / 30),
                              git: c.git.key, outcome: outcome, appVersion: RoomConfig.appVersion)
    }

    /// Defence in depth: refuse to export anything that looks like a path or a user name.
    public static func isClean(_ r: DecisionRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(r), let raw = String(data: data, encoding: .utf8) else { return false }
        let s = raw.replacingOccurrences(of: "\\/", with: "/")
        return !s.contains("/") && !s.contains("~") && !s.contains(NSUserName())
    }
}

public final class DecisionLog: @unchecked Sendable {
    public enum LogError: Error, LocalizedError {
        case notOptedIn, notConfigured
        public var errorDescription: String? {
            switch self {
            case .notOptedIn: "Sharing is off. Turn on “Help improve Room” first."
            case .notConfigured: "No upload server is configured, so nothing was sent."
            }
        }
    }

    private let paths: AppPaths
    private let lock = NSLock()
    private let catalog: Catalog
    public init(paths: AppPaths, catalog: Catalog = .builtIn) { self.paths = paths; self.catalog = catalog }

    /// Local history always stays on this Mac and personalizes the scorer. Sharing is a separate, opt-in step.
    public func record(_ c: Candidate, outcome: Outcome) {
        append(Anonymizer.record(for: c, outcome: outcome, catalog: catalog))
    }

    public func append(_ r: DecisionRecord) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        guard var line = try? JSONEncoder().encode(r) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: paths.decisions) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: line)
        } else { try? line.write(to: paths.decisions, options: .atomic) }
    }

    public func load() -> [DecisionRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: paths.decisions, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? dec.decode(DecisionRecord.self, from: Data($0.utf8)) }
    }

    public func count() -> Int { load().count }

    public func deleteAll() { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: paths.decisions) }

    /// Writes an anonymized JSONL file the user can inspect before sharing. Requires opt-in.
    public func export(to url: URL, optedIn: Bool) throws -> Int {
        guard optedIn else { throw LogError.notOptedIn }
        let clean = load().filter(Anonymizer.isClean)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let body = try clean.map { String(decoding: try enc.encode($0), as: UTF8.self) }.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return clean.count
    }

    /// Uploads only when the user opted in AND an endpoint is configured. Nothing is sent by default.
    public func upload(optedIn: Bool, endpoint: URL? = RoomConfig.learningEndpoint) async throws -> Int {
        guard optedIn else { throw LogError.notOptedIn }
        guard let endpoint else { throw LogError.notConfigured }
        let clean = load().filter(Anonymizer.isClean)
        var req = URLRequest(url: endpoint); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(clean)
        _ = try await URLSession.shared.data(for: req)
        return clean.count
    }
}
