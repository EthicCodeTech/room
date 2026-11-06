import Foundation

/// Features describing one deletion candidate. Deliberately small and path-free.
public struct ScoreFeatures: Sendable {
    public var values: [String: Double]
    public init(_ values: [String: Double]) { self.values = values }

    public init(candidate c: Candidate, ruleRestoreRate: Double = 0) {
        var v: [String: Double] = [:]
        v["tier.rebuildable"] = c.tier == .rebuildable ? 1 : 0
        v["tier.yours"] = c.tier == .yours ? 1 : 0
        v["regen.minutes"] = c.regen == .minutes ? 1 : 0
        v["regen.hours"] = (c.regen == .hours || c.regen == .never) ? 1 : 0
        v["size.log"] = max(0, log10(Double(max(1, c.estimate.planning)) / 1_000_000)) / 4   // 1 MB → 0, 10 GB → 1
        v["age.years"] = min(3, Double(c.ageDays) / 365)
        switch c.git {
        case .dirty: v["git.dirty"] = 1
        case .unpushed: v["git.unpushed"] = 1
        case .noRemote: v["git.noRemote"] = 1
        case .pushed: v["git.pushed"] = 1
        case .notRepo: break
        }
        v["history.restoreRate"] = ruleRestoreRate
        self.values = v
    }
}

/// A tiny logistic-regression model: P(user would regret deleting this).
/// Cold start uses hand-set priors from real cleanups; `fit` re-trains on decision records.
public struct RegretModel: Codable, Sendable, Equatable {
    public var bias: Double
    public var weights: [String: Double]
    public var trainedOn: Int

    public static let prior = RegretModel(
        bias: -2.4,
        weights: [
            "tier.rebuildable": 0.8, "tier.yours": 2.6,
            "regen.minutes": 0.3, "regen.hours": 0.9,
            "size.log": 0.2, "age.years": -0.4,
            "git.dirty": 2.4, "git.unpushed": 2.2, "git.noRemote": 1.6, "git.pushed": -1.0,
            "history.restoreRate": 3.0,
        ], trainedOn: 0)

    public func predict(_ f: ScoreFeatures) -> Double {
        var z = bias
        for (k, x) in f.values { z += (weights[k] ?? 0) * x }
        return 1 / (1 + exp(-z))
    }

    /// Mini-batch-free SGD with L2 pull toward the prior, so a handful of examples can't wreck sane behaviour.
    public func fitted(on examples: [(ScoreFeatures, label: Double, weight: Double)],
                       epochs: Int = 40, learningRate: Double = 0.15, l2: Double = 0.02) -> RegretModel {
        guard !examples.isEmpty else { return self }
        var m = self
        let prior = RegretModel.prior
        for _ in 0..<epochs {
            for (f, y, w) in examples {
                let p = m.predict(f)
                let g = (p - y) * w
                m.bias -= learningRate * (g + l2 * (m.bias - prior.bias))
                for (k, x) in f.values {
                    let cur = m.weights[k] ?? 0
                    m.weights[k] = cur - learningRate * (g * x + l2 * (cur - (prior.weights[k] ?? 0)))
                }
            }
        }
        m.trainedOn = self.trainedOn + examples.count
        return m
    }
}

public final class RegretScorer: @unchecked Sendable {
    public private(set) var model: RegretModel
    private let paths: AppPaths?

    public init(paths: AppPaths? = nil) {
        self.paths = paths
        if let paths, let data = try? Data(contentsOf: paths.model), let m = try? JSONDecoder().decode(RegretModel.self, from: data) {
            model = m
        } else { model = .prior }
    }

    /// Per-rule share of deletions the user later restored. Feeds back into `history.restoreRate`.
    public static func restoreRates(from records: [DecisionRecord]) -> [String: Double] {
        var seen: [String: (deleted: Int, restored: Int)] = [:]
        for r in records {
            var s = seen[r.ruleID] ?? (0, 0)
            switch r.outcome { case .deleted: s.deleted += 1; case .restored: s.restored += 1; case .declined: break }
            seen[r.ruleID] = s
        }
        return seen.mapValues { $0.deleted + $0.restored == 0 ? 0 : Double($0.restored) / Double($0.deleted + $0.restored) }
    }

    public func regret(for c: Candidate, restoreRates: [String: Double] = [:]) -> Double {
        let p = model.predict(ScoreFeatures(candidate: c, ruleRestoreRate: restoreRates[c.ruleID] ?? 0))
        // One-way safety: learning may make us MORE cautious about the yours tier, never less.
        return c.tier == .yours ? max(p, 0.5) : p
    }

    /// Re-trains from local decision history. restored → regret; declined → mild regret; deleted → fine.
    public func retrain(from records: [DecisionRecord]) {
        let rates = Self.restoreRates(from: records)
        let examples: [(ScoreFeatures, label: Double, weight: Double)] = records.map { r in
            let f = ScoreFeatures(Self.features(of: r, restoreRate: rates[r.ruleID] ?? 0))
            switch r.outcome {
            case .restored: return (f, 1, 1.0)
            case .declined: return (f, 1, 0.5)
            case .deleted: return (f, 0, 1.0)
            }
        }
        model = model.fitted(on: examples)
        save()
    }

    static func features(of r: DecisionRecord, restoreRate: Double) -> [String: Double] {
        var v: [String: Double] = [:]
        v["tier.rebuildable"] = r.tier == .rebuildable ? 1 : 0
        v["tier.yours"] = r.tier == .yours ? 1 : 0
        v["size.log"] = min(1, max(0, Double(r.sizeBucket) / 13))   // 2^13 MB ≈ 8 GB
        v["age.years"] = min(3, Double(r.ageBucket) / 12)
        switch r.git {
        case "dirty": v["git.dirty"] = 1; case "unpushed": v["git.unpushed"] = 1
        case "noRemote": v["git.noRemote"] = 1; case "pushed": v["git.pushed"] = 1
        default: break
        }
        v["history.restoreRate"] = restoreRate
        return v
    }

    public func save() {
        guard let paths else { return }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(model) { try? data.write(to: paths.model, options: .atomic) }
    }
}
