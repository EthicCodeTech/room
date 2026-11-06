import SwiftUI
import RoomCore

struct OverviewView: View {
    @Bindable var model: AppModel
    var goToReview: () -> Void
    var goToAsk: () -> Void

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(alignment: .top, spacing: 20) { freeCard; goalCard }
                planCard
                HStack(alignment: .top, spacing: 20) { growthCard; resultCard }
            }
        }
    }

    // MARK: Header (problem first)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Storage")
            (Text("Your Mac has ").font(.ds(Token.h1)) + Text(ByteFormat.string(model.freeBytes)).font(.ds(.init(42, 500), mono: true)) + Text(" left.").font(.ds(Token.h1)))
                .tracking(Token.h1.size * Token.h1.tracking).foregroundStyle(DS.text)
                .contentTransition(.numericText()).motion(.base, value: model.freeBytes)
            Text(model.isLow
                 ? "That is tight. Updates and downloads can fail below this. Room finds what can go without touching your files."
                 : "You have room to work. Keep an eye on what grows, so it does not sneak up on you.")
                .dsText(Token.bodyLg, color: DS.textMuted).frame(maxWidth: 640, alignment: .leading)
        }
    }

    // MARK: Free space

    /// Bytes the current selection (or, failing that, the plan) would free. Drives the marker on the tank.
    private var previewBytes: Int64 {
        if let gb = Dev.env("ROOM_DEV_PREVIEWGB").flatMap(Double.init) { return Int64(gb * 1e9) }      // dev only
        return model.selection.isEmpty ? (model.plan?.guaranteedBytes ?? 0) : model.selectedBytes
    }
    private var previewLevel: Double? {
        guard previewBytes > 0, model.totalBytes > 0 else { return nil }
        return max(0, model.usedFraction - Double(previewBytes) / Double(model.totalBytes))
    }

    /// Your disk as a tank of sindoor liquid: the card fills as the disk fills, and the marker shows where cleaning lands.
    private var freeCard: some View {
        ZStack(alignment: .topLeading) {
            LiquidTank(level: model.usedFraction, preview: previewLevel,
                       previewLabel: "\(ByteFormat.string(model.freeBytes + previewBytes)) free after cleanup",
                       motion: model.motion, calibration: model.settings.tilt, tiltEnabled: model.settings.tiltEnabled,
                       onCalibrate: { model.calibrateTilt() },
                       devTiltDegrees: Dev.env("ROOM_DEV_TILT").flatMap(Double.init))
            VStack(alignment: .leading, spacing: 14) {
                Text("Free space").dsText(Token.h4)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DataText(text: ByteFormat.string(model.freeBytes), style: Token.dataLarge)
                    DataText(text: "of \(ByteFormat.string(model.totalBytes))", style: Token.mono, color: DS.textMuted)
                }
                Spacer(minLength: 0)
                DataText(text: "\(Int((model.usedFraction * 100).rounded()))% used", style: Token.monoSmall, color: DS.textSoft)
                if model.vault.totalBytes() > 0 {
                    HStack(spacing: 8) {
                        SindoorDot(size: 6)
                        Text("\(ByteFormat.string(model.vault.totalBytes())) is waiting in the vault. Empty it to get that space back.")
                            .dsText(Token.small, color: DS.textSoft)
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Free space \(ByteFormat.string(model.freeBytes)) of \(ByteFormat.string(model.totalBytes))")
    }

    // MARK: Goal

    private var goalCard: some View {
        DSCard(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("How much room do you need?").dsText(Token.h4)
                Text("A macOS update needs about 24 GB free. Pick a target and Room plans the safest way to reach it.")
                    .dsText(Token.small, color: DS.textMuted)
                DSSegmented(options: [(10, "10 GB"), (24, "24 GB"), (50, "50 GB"), (100, "100 GB")], selection: $model.goalGB)
                    .accessibilityLabel("Target free space")
                HStack(spacing: 10) {
                    PillButton(title: "Plan \(model.goalGB) GB", variant: .secondary, size: .small, icon: nil) { model.replan() }
                    PillButton(title: "Ask the assistant", variant: .ghost, size: .small, icon: nil) { model.askForPlan(); goToAsk() }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 252, alignment: .topLeading)
        }
        .frame(height: 300)
    }

    // MARK: Plan

    private var planCard: some View {
        DSCard(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                switch model.scanState {
                case .idle, .scanning:
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Looking for space").dsText(Token.h3)
                        if case .scanning(let step) = model.scanState { Text(step).dsText(Token.small, color: DS.textMuted) }
                        ForEach(0..<4, id: \.self) { i in HStack { DSSkeleton(width: i % 2 == 0 ? 260 : 180, height: 14); Spacer(); DSSkeleton(width: 70, height: 14) }.frame(height: 40) }
                    }.transition(.opacity)
                case .done:
                    if let plan = model.plan, !plan.items.isEmpty { VStack(alignment: .leading, spacing: 18) { planBody(plan) }.transition(.opacity) }
                    else { DSEmptyState(title: "Nothing safe to remove right now", message: "Room found no caches or rebuildable items worth clearing. Your biggest files are in Review, and they are yours to judge.", actionTitle: "Open review", action: goToReview).transition(.opacity) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            .motion(.panel, value: model.scanState == .idle || { if case .scanning = model.scanState { return true } else { return false } }())
        }
    }

    @ViewBuilder private func planBody(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Plan")
            if plan.reachesGoal {
                Text("Room can free \(ByteFormat.string(plan.guaranteedBytes)) without touching your files.").dsText(Token.h3).contentTransition(.numericText()).motion(.base, value: plan.guaranteedBytes)
            } else {
                Text("Room can free \(ByteFormat.string(plan.guaranteedBytes)) safely. That is \(ByteFormat.string(plan.shortfall)) short of \(model.goalGB) GB.").dsText(Token.h3)
                Text("The rest is in files only you can judge. Look in Review, where nothing is ticked for you.").dsText(Token.small, color: DS.textMuted)
            }
        }
        VStack(spacing: 0) {
            ForEach(plan.items.prefix(6)) { c in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).dsText(Token.small).lineLimit(1)
                        Text(c.regen.title).dsText(Token.micro, color: DS.textFaint)
                    }
                    Spacer()
                    c.riskBadge
                    DataText(text: c.estimate.display).lineLimit(1).frame(width: 210, alignment: .trailing)
                }
                .frame(height: 52)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: Token.hairline) }
                .transition(.row)
            }
            if plan.items.count > 6 {
                Text("and \(plan.items.count - 6) more in Review").dsText(Token.small, color: DS.textMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
        }
        .motion(.panel, value: plan.items.map(\.id))
        if plan.items.contains(where: { $0.estimate.isAmbiguous }) {
            Text("Some items share space with other files (APFS clones), so Room counts only what is guaranteed to come back.")
                .dsText(Token.micro, color: DS.textFaint)
        }
        HStack(spacing: 12) {
            PillButton(title: "Free up \(ByteFormat.string(plan.guaranteedBytes))", isLoading: model.isCleaning) { model.applyPlanToSelection(); model.requestClean() }
            PillButton(title: "Review items", variant: .secondary, icon: nil) { model.applyPlanToSelection(); goToReview() }
        }
    }

    // MARK: What grew

    private var growthCard: some View {
        DSCard(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Growth")
                Text("What grew since last week").dsText(Token.h4)
                if let g = model.growth, !g.deltas.isEmpty {
                    ForEach(Array(g.deltas.prefix(5).enumerated()), id: \.element.id) { i, d in
                        HStack(spacing: 10) {
                            if i == 0 && d.delta > 1_000_000_000 { SindoorDot(size: 6) } else { Color.clear.frame(width: 6, height: 6) }
                            Text(d.name).dsText(Token.small)
                            Spacer()
                            DataText(text: "\(d.delta >= 0 ? "+" : "\u{2212}") \(ByteFormat.string(abs(d.delta)))", color: DS.textSoft)
                        }.frame(height: 32)
                    }
                } else {
                    Text("No history yet. Room compares snapshots over time, so after a week it can tell you exactly what grew.").dsText(Token.small, color: DS.textMuted)
                    PillButton(title: model.isMeasuring ? "Measuring" : "Take a snapshot", variant: .secondary, size: .small, icon: nil, isLoading: model.isMeasuring) { model.takeSnapshot() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Last cleanup

    private var resultCard: some View {
        DSCard(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Result")
                Text("Last cleanup").dsText(Token.h4)
                if let r = model.lastReport {
                    DataText(text: ByteFormat.string(r.measuredFreed), style: Token.h2)
                    Text("Measured on disk, not estimated.").dsText(Token.small, color: DS.textMuted)
                    DataText(text: "\(ByteFormat.string(r.freeBefore)) to \(ByteFormat.string(r.freeAfter)) free", color: DS.textSoft)
                } else {
                    Text("Nothing cleaned yet. After each cleanup Room shows the space that really came back, so you can trust the numbers.").dsText(Token.small, color: DS.textMuted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
