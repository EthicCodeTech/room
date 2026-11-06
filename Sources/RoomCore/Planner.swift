import Foundation

public struct Plan: Sendable {
    public var items: [Candidate]
    public var goalBytes: Int64
    public var guaranteedBytes: Int64
    public var reachesGoal: Bool { guaranteedBytes >= goalBytes }
    public var shortfall: Int64 { max(0, goalBytes - guaranteedBytes) }
    public var totalRegret: Double
    public var includesYours: Bool { items.contains { $0.tier == .yours } }
}

/// Picks the cheapest, lowest-regret set of actions that reaches a goal.
/// Hard rules: `yours` items are only ever included when explicitly allowed.
public struct Planner: Sendable {
    public var scorer: RegretScorer
    public var restoreRates: [String: Double]
    public init(scorer: RegretScorer, restoreRates: [String: Double] = [:]) { self.scorer = scorer; self.restoreRates = restoreRates }

    /// Plans in stages: safe items alone first; only if they can't reach the goal does it widen to the next tier.
    /// This guarantees a lower-risk tier is never skipped in favour of a higher-risk one that happens to be bigger.
    public func plan(goalBytes: Int64, from candidates: [Candidate], allowedTiers: Set<RiskTier> = [.safe, .rebuildable]) -> Plan {
        let stages = RiskTier.allCases.sorted().filter { allowedTiers.contains($0) }
        var best = Plan(items: [], goalBytes: goalBytes, guaranteedBytes: 0, totalRegret: 0)
        for stage in stages {
            let pool = candidates.filter { $0.tier <= stage && allowedTiers.contains($0.tier) && $0.estimate.planning > 0 }
            best = select(goalBytes: goalBytes, from: pool)
            if best.reachesGoal { return best }
        }
        return best
    }

    private func select(goalBytes: Int64, from pool: [Candidate]) -> Plan {
        let scored = pool.map { c -> (Candidate, Double) in (c, scorer.regret(for: c, restoreRates: restoreRates)) }
        // Best value first: most guaranteed space per unit of regret.
        let ranked = scored.sorted {
            Double($0.0.estimate.planning) / (0.05 + $0.1) > Double($1.0.estimate.planning) / (0.05 + $1.1)
        }
        var chosen: [(Candidate, Double)] = []
        var total: Int64 = 0
        for entry in ranked {
            if total >= goalBytes { break }
            chosen.append(entry); total += entry.0.estimate.planning
        }
        // Drop anything that turned out redundant, highest regret first.
        for entry in chosen.sorted(by: { $0.1 > $1.1 }) where total - entry.0.estimate.planning >= goalBytes {
            if let idx = chosen.firstIndex(where: { $0.0.id == entry.0.id }) {
                chosen.remove(at: idx); total -= entry.0.estimate.planning
            }
        }
        return Plan(items: chosen.map(\.0).sorted { $0.estimate.planning > $1.estimate.planning }, goalBytes: goalBytes,
                    guaranteedBytes: total, totalRegret: chosen.reduce(0) { $0 + $1.1 })
    }
}

/// Validates plans proposed by an AI. The AI may only name candidates that exist and are allowed.
public enum PlanValidator {
    public static func validate(ids: [String], candidates: [Candidate], allowYours: Bool) -> [Candidate] {
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let c = byID[id] else { return nil }
            return (c.tier == .yours && !allowYours) ? nil : c
        }
    }
}
