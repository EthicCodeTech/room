import Foundation
import CryptoKit

public struct Candidate: Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case rule, command, nodeModules, installer, duplicate, largeFile, vm }

    /// Stable, path-free identifier safe to give an AI advisor.
    public let id: String
    public let ruleID: String
    public let kind: Kind
    public let title: String
    public let why: String
    public var tier: RiskTier
    public let regen: RegenCost
    public let action: RuleAction
    /// Concrete things to delete (empty for command rules).
    public let targets: [URL]
    public let displayPath: String
    public var estimate: SizeEstimate
    public let lastModified: Date?
    public var git: GitStatus = .notRepo
    public var tags: [String] = []
    /// Whether the app should tick this by default.
    public var preselected: Bool

    public init(id: String, ruleID: String, kind: Kind, title: String, why: String, tier: RiskTier, regen: RegenCost, action: RuleAction,
                targets: [URL], displayPath: String, estimate: SizeEstimate, lastModified: Date?, git: GitStatus = .notRepo,
                tags: [String] = [], preselected: Bool) {
        self.id = id; self.ruleID = ruleID; self.kind = kind; self.title = title; self.why = why; self.tier = tier; self.regen = regen
        self.action = action; self.targets = targets; self.displayPath = displayPath; self.estimate = estimate
        self.lastModified = lastModified; self.git = git; self.tags = tags; self.preselected = preselected
    }

    public var ageDays: Int {
        guard let d = lastModified else { return 0 }
        return max(0, Int(Date().timeIntervalSince(d) / 86_400))
    }

    public static func makeID(ruleID: String, key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let short = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(ruleID)#\(short)"
    }
}
