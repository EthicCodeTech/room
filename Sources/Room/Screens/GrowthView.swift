import SwiftUI
import Charts
import RoomCore

struct GrowthView: View {
    @Bindable var model: AppModel

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Growth")
                        Text("What keeps filling your Mac").dsText(Token.h1)
                        Text("Room measures the same places over time. Cleaning a cache is a short fix; knowing what grows is the long one.")
                            .dsText(Token.bodyLg, color: DS.textMuted).frame(maxWidth: 620, alignment: .leading)
                    }
                    Spacer()
                    if model.snapshots.count >= 2 {
                        PillButton(title: model.isMeasuring ? "Measuring" : "Take snapshot", variant: .secondary, icon: nil, isLoading: model.isMeasuring) { model.takeSnapshot() }
                    }
                }
                if model.snapshots.count < 2 {
                    DSCard { DSEmptyState(title: "Not enough history yet",
                                          message: "Room needs two snapshots to compare. It takes one when you scan, at most twice a day. Take one now and another in a few days.",
                                          actionTitle: model.isMeasuring ? nil : "Take snapshot", action: { model.takeSnapshot() }) }.transition(.rise)
                } else {
                    DSCard(padding: 24) { VStack(alignment: .leading, spacing: 14) {
                        Text("Free space over time").dsText(Token.h4)
                        chart.frame(height: 240)
                    } }.transition(.rise)
                    if let g = model.growth { deltas(g.from, g.to, g.deltas).transition(.rise) }
                }
            }
            .motion(.panel, value: model.snapshots.count < 2)
        }
        .onAppear { model.refreshGrowth() }
    }

    private var chart: some View {
        Chart(model.snapshots, id: \.date) { s in
            LineMark(x: .value("Date", s.date), y: .value("Free GB", Double(s.freeBytes) / 1e9)).foregroundStyle(DS.sindoor).lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Date", s.date), y: .value("Free GB", Double(s.freeBytes) / 1e9)).foregroundStyle(DS.sindoor).symbolSize(28)
        }
        .chartYAxis { AxisMarks(position: .leading) { v in
            AxisGridLine().foregroundStyle(Color(hex: Token.line))
            AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) GB").font(.ds(Token.monoTiny, mono: true)).foregroundStyle(DS.textMuted) } }
        } }
        .chartXAxis { AxisMarks { _ in
            AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.ds(Token.monoTiny, mono: true)).foregroundStyle(DS.textMuted)
        } }
    }

    private func deltas(_ from: GrowthSnapshot, _ to: GrowthSnapshot, _ list: [GrowthDelta]) -> some View {
        DSCard(padding: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Since \(from.date.formatted(date: .abbreviated, time: .omitted))").dsText(Token.h4)
                DataText(text: "Free space: \(ByteFormat.string(from.freeBytes)) to \(ByteFormat.string(to.freeBytes))", color: DS.textMuted).padding(.bottom, 10)
                if list.isEmpty { Text("Nothing changed by more than 100 MB.").dsText(Token.small, color: DS.textMuted) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, d in
                    HStack(spacing: 10) {
                        if i == 0 && d.delta > 1_000_000_000 { SindoorDot(size: 6) } else { Color.clear.frame(width: 6, height: 6) }
                        Text(d.name).dsText(Token.small)
                        Spacer()
                        DataText(text: "\(d.delta >= 0 ? "+" : "\u{2212}") \(ByteFormat.string(abs(d.delta)))", color: DS.textSoft)
                    }.frame(height: 44).overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: Token.hairline) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
