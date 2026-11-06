import Foundation

/// The layer between the Ask screen and whichever advisor is switched on.
///
/// Small on-device models echo their input and answer everything, including "what is my name?". So code handles
/// what code can answer exactly, refuses what isn't about storage, and cleans whatever the model writes. Anything that
/// still reads like data falls back to the built-in answer.
public enum Assistant {
    public enum Route: Equatable, Sendable { case offTopic, largest, growth, summary, model }

    public struct Answer: Sendable, Equatable {
        public var text: String
        public var source: String
    }

    static let storageWords = [
        "disk", "space", "storage", "file", "folder", "delet", "clean", "cache", "free", "full", "gb", "mb", "big", "large", "size",
        "safe", "vault", "node_modules", "simulator", "docker", "backup", "install", "download", "grow", "grew", "remov", "junk", "clear",
        "trash", "scan", "rebuil", "drive", "ssd", "icloud", "photo", "video", "xcode", "brew", "git", "project", "old", "unused",
        "duplicate", "zip", "dmg", "mac", "computer", "eating", "taking up", "using", "hog", "heavy", "slow", "room", "what can",
        "how much", "biggest", "largest", "tidy", "free up", "reclaim",
    ]

    public static func route(_ question: String) -> Route {
        let q = question.lowercased()
        guard storageWords.contains(where: { q.contains($0) }) else { return .offTopic }
        if ["largest", "biggest", "bigger than", "heaviest"].contains(where: { q.contains($0) }) { return .largest }
        if ["grew", "grow", "growth", "filling", "lost space", "changed"].contains(where: { q.contains($0) }) { return .growth }
        if ["safe to delete", "safely delete", "what can i delete", "what can i free", "how much can i", "what should i delete", "what can i remove"].contains(where: { q.contains($0) }) { return .summary }
        return .model
    }

    // MARK: Answering

    public static func answer(_ question: String, advisor: any Advisor, context: AdvisorContext) async -> Answer {
        let rules = Answer(text: "", source: "Built-in rules")
        switch route(question) {
        case .offTopic:
            return .init(text: "I can only help with the storage on this Mac. Try “What can I safely delete?” or “What grew this week?”", source: "Room")
        case .largest:
            return .init(text: largest(context), source: "Room")
        case .growth:
            if let text = try? await RuleAdvisor().answer(question, context: context) { return .init(text: text, source: "Room") }
            return rules
        case .summary:
            return .init(text: summary(context), source: "Room")
        case .model:
            if advisor is RuleAdvisor {
                return .init(text: (try? await advisor.answer(question, context: context)) ?? summary(context), source: advisor.name)
            }
            if let raw = try? await advisor.answer(question, context: context) {
                let text = clean(raw, context: context)
                if isUsable(text) { return .init(text: text, source: advisor.name) }
            }
            return .init(text: "I couldn't put that into words just now. " + summary(context), source: "Built-in rules")
        }
    }

    public static func explain(_ item: AdvisorContext.Item, advisor: any Advisor) async -> String {
        if !(advisor is RuleAdvisor), let raw = try? await advisor.explain(item) {
            let text = clean(raw, context: nil, items: [item])
            if isUsable(text) { return text }
        }
        return (try? await RuleAdvisor().explain(item)) ?? item.why
    }

    // MARK: Exact answers

    /// A short, exact overview built from the data, with no model involved.
    public static func summary(_ c: AdvisorContext) -> String {
        let safe = c.items.filter { $0.tier == .safe }
        let rebuild = c.items.filter { $0.tier == .rebuildable }
        let safeTotal = safe.reduce(Int64(0)) { $0 + $1.bytes }, rebuildTotal = rebuild.reduce(Int64(0)) { $0 + $1.bytes }
        guard safeTotal + rebuildTotal > 0 else { return "Room hasn't found anything safe to clear yet. Scan again in a moment." }
        var text = "You can free about \(ByteFormat.string(safeTotal)) with no risk (caches), and \(ByteFormat.string(rebuildTotal)) more that can be rebuilt."
        let top = safe.sorted { $0.bytes > $1.bytes }.prefix(3)
        if !top.isEmpty { text += " The biggest safe ones: " + top.map { "\($0.title) (\(ByteFormat.string($0.bytes)))" }.joined(separator: ", ") + "." }
        return text
    }

    /// The biggest things Room found. It only knows what it can clean, so it says where to look for the rest.
    static func largest(_ c: AdvisorContext) -> String {
        let top = c.items.sorted { $0.bytes > $1.bytes }.prefix(3)
        guard let first = top.first else { return "Room hasn't found anything yet. Scan again in a moment, or open the Map to see your biggest folders." }
        var text = "The biggest thing Room found is \(first.title), about \(ByteFormat.string(first.bytes)). It is \(safetyPhrase(first.tier))."
        let rest = top.dropFirst()
        if !rest.isEmpty { text += " Next: " + rest.map { "\($0.title) (\(ByteFormat.string($0.bytes)))" }.joined(separator: ", ") + "." }
        return text + " Room only lists what it can clean. To see the biggest folders on your whole disk, open the Map."
    }

    // MARK: Cleaning model output

    /// Replaces ids with names and raw byte counts with sizes people read.
    public static func clean(_ raw: String, context: AdvisorContext?, items: [AdvisorContext.Item] = []) -> String {
        var text = raw
        let known = (context?.items ?? []) + items
        for it in known.sorted(by: { $0.id.count > $1.id.count }) { text = text.replacingOccurrences(of: it.id, with: it.title) }
        text = text.replacingOccurrences(of: #"\b[a-z][a-z0-9]*(?:\.[a-z0-9_-]+)+#[0-9a-f]{6,}"#, with: "one of the items", options: .regularExpression)
        text = replacing(#"(\d[\d,]{5,})\s*bytes"#, in: text) { ByteFormat.string(Int64($0.replacingOccurrences(of: ",", with: "")) ?? 0) }
        text = text.replacingOccurrences(of: " — ", with: ", ").replacingOccurrences(of: "—", with: ", ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// False when the text still reads like data instead of a sentence for a person.
    public static func isUsable(_ text: String) -> Bool {
        let t = text.lowercased()
        guard text.count >= 12, text.count <= 900 else { return false }
        if t.range(of: #"\b(item id|id:|regen|tier|json|bytes|optional\()"#, options: .regularExpression) != nil || t.contains("one of the items") { return false }
        return text.range(of: #"#[0-9a-f]{6,}"#, options: .regularExpression) == nil
    }

    // MARK: Plain-words helpers

    public static func safetyPhrase(_ tier: RiskTier) -> String {
        switch tier {
        case .safe: "safe to clear"
        case .rebuildable: "can be rebuilt if you need it again"
        case .yours: "your own file, so only you can judge it"
        }
    }

    public static func ageText(_ days: Int) -> String {
        switch days {
        case ..<1: "today"
        case 1: "yesterday"
        case 2..<14: "\(days) days ago"
        case 14..<60: "\(days / 7) weeks ago"
        case 60..<365: "\(days / 30) months ago"
        default: "\(days / 365) year\(days / 365 == 1 ? "" : "s") ago"
        }
    }

    private static func replacing(_ pattern: String, in text: String, _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var out = text
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(m.range, in: out), let digits = Range(m.range(at: 1), in: out) else { continue }
            out.replaceSubrange(whole, with: transform(String(out[digits])))
        }
        return out
    }
}
