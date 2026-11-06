import SwiftUI
import RoomCore

/// Product-name eyebrow used at the top of cards: mono, sindoor.
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text).dsText(Token.monoSmall, mono: true, color: DS.sindoorText) }
}

/// Sizes, IDs and amounts are data, so they are always set in mono.
struct DataText: View {
    let text: String
    var style: Token.TypeStyle = Token.mono
    var color: Color = DS.text
    var body: some View {
        Text(text).dsText(style, mono: true, color: color)
            .contentTransition(.numericText()).motion(.base, value: text)      // digits roll instead of jumping
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { content.frame(maxWidth: 1200, alignment: .leading).padding(.horizontal, 32).padding(.top, 32 + 76).padding(.bottom, 32).frame(maxWidth: .infinity) }
            .scrollContentBackground(.hidden)
    }
}

extension Candidate {
    var riskBadge: DSBadge { DSBadge(text: tier.title, dot: tier.dot) }
    var changedText: String {
        guard lastModified != nil else { return "" }
        let d = ageDays
        func unit(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s") ago" }
        if d < 1 { return "Today" }
        if d < 30 { return unit(d, "day") }
        if d < 365 { return unit(d / 30, "month") }
        return unit(d / 365, "year")
    }
}

extension Date {
    /// "In 6 days" style countdown for the vault.
    func countdown(from now: Date = Date()) -> String {
        let secs = timeIntervalSince(now)
        if secs <= 0 { return "Expired" }
        let days = Int(secs / 86_400)
        return days >= 1 ? "\(days) day\(days == 1 ? "" : "s") left" : "Under a day left"
    }
}
