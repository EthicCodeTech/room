import Foundation

/// How much a human should worry about deleting something.
public enum RiskTier: String, Codable, CaseIterable, Sendable, Comparable {
    /// Regenerable cache. Apps rebuild it on their own.
    case safe
    /// Not user data, but rebuilding costs time or bandwidth (node_modules, Gradle, installers).
    case rebuildable
    /// Might be someone's work or memories. Never touched automatically.
    case yours

    public var title: String {
        switch self {
        case .safe: "Safe"
        case .rebuildable: "Rebuildable"
        case .yours: "Yours"
        }
    }

    public var blurb: String {
        switch self {
        case .safe: "Caches the app rebuilds by itself."
        case .rebuildable: "Not your data, but it takes time or bandwidth to get back."
        case .yours: "Could be your work or memories. Always your call."
        }
    }

    private var order: Int { switch self { case .safe: 0; case .rebuildable: 1; case .yours: 2 } }
    public static func < (l: RiskTier, r: RiskTier) -> Bool { l.order < r.order }
}

/// Rough cost of getting something back after deleting it.
public enum RegenCost: String, Codable, Sendable {
    case instant, minutes, hours
    /// Personal data: once it is gone for good, nothing brings it back.
    case never

    public var weight: Double {
        switch self { case .instant: 0.05; case .minutes: 0.25; case .hours: 0.6; case .never: 1.0 }
    }
    public var title: String {
        switch self { case .instant: "Rebuilds instantly"; case .minutes: "Minutes to rebuild"; case .hours: "Hours to rebuild"; case .never: "Cannot be rebuilt" }
    }
}

public enum DeletionPolicy: Equatable, Sendable {
    /// Gone now. Space is freed immediately.
    case immediate
    /// Moved into the undo vault for N days. Space is freed when the vault is purged.
    case vault(days: Int)

    public static func `default`(for tier: RiskTier) -> DeletionPolicy {
        switch tier {
        case .safe, .rebuildable: .immediate
        case .yours: .vault(days: 7)
        }
    }
}
