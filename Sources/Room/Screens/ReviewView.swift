import SwiftUI
import RoomCore

struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var tier: RiskTier? = nil

    private var rows: [Candidate] {
        model.candidates.filter { c in
            (tier == nil || c.tier == tier) &&
            (search.isEmpty || c.title.localizedCaseInsensitiveContains(search) || c.displayPath.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        DSCard(padding: 0) {
            VStack(spacing: 0) { toolbar; header; Divider().overlay(DS.line); list }
        }
        .overlay(alignment: .trailing) {
            if let c = model.inspected {
                Inspector(model: model, candidate: c).frame(width: 340).padding(12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if !model.selection.isEmpty { actionBar.padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .padding(32).belowFloatingNav().frame(maxWidth: 1400)
        .onAppear { if let q = model.reviewSearch { search = q; tier = nil; model.reviewSearch = nil } }      // arrived from the map
        .motion(.panel, value: model.inspectedID)
        .motion(.panel, value: model.selection.isEmpty)
    }

    // MARK: Toolbar: title, count, search, filter

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("Review").dsText(Token.h4)
            Text("\(rows.count) item\(rows.count == 1 ? "" : "s")").dsText(Token.small, color: DS.textMuted)
            Spacer()
            TextField("", text: $search, prompt: Text("Search items").foregroundStyle(DS.placeholder))
                .textFieldStyle(DSFieldStyle()).frame(width: 220).accessibilityLabel("Search items")
            DSSegmented(options: [(nil, "All"), (RiskTier.safe, "Safe"), (RiskTier.rebuildable, "Rebuildable"), (RiskTier.yours, "Yours")], selection: $tier)
        }.padding(20)
    }

    // MARK: Bulk bar

    /// A glass capsule that floats over the rows and morphs in when you tick something.
    private var actionBar: some View {
        GlassEffectContainer {
            HStack(spacing: 14) {
                Text("\(model.selection.count) selected").dsText(.init(14, 500))
                DataText(text: ByteFormat.string(model.selectedBytes), color: DS.textSoft)
                if model.selectedItems.contains(where: { $0.tier == .yours }) { DSBadge(text: "Includes your files", dot: DS.sindoor) }
                PillButton(title: "Clear", variant: .ghost, size: .small, icon: nil) { model.selection = [] }
                PillButton(title: "Free up \(ByteFormat.string(model.selectedBytes))", size: .small, isLoading: model.isCleaning) { model.requestClean() }
            }
            .padding(.leading, 22).padding(.trailing, 10).frame(height: 56)
            .background(Capsule().fill(DS.card.opacity(0.45)))
            .cinnabarGlass(Capsule())
        }
    }

    // MARK: Header row (no fill, sentence case)

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 44)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Risk").frame(width: 120, alignment: .leading)
            Text("Rebuild").frame(width: 140, alignment: .leading)
            Text("Changed").frame(width: 110, alignment: .leading)
            Text("Size").frame(width: 210, alignment: .trailing)
        }
        .font(.ds(.init(12, 500))).foregroundStyle(DS.textMuted)
        .padding(.horizontal, 20).frame(height: 36)
    }

    @ViewBuilder private var list: some View {
        ZStack { listContent }.motion(.panel, value: model.scanState == .idle ? 0 : { if case .done = model.scanState { return 2 } else { return 1 } }())
    }

    @ViewBuilder private var listContent: some View {
        switch model.scanState {
        case .idle, .scanning:
            VStack(spacing: 0) { ForEach(0..<7, id: \.self) { i in
                HStack(spacing: 16) { DSSkeleton(width: 20, height: 20); DSSkeleton(width: i % 2 == 0 ? 280 : 200, height: 14); Spacer(); DSSkeleton(width: 80, height: 14) }
                    .padding(.horizontal, 20).frame(height: 52)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: Token.hairline) }
            } }.transition(.opacity)
        case .done:
            if rows.isEmpty {
                DSEmptyState(title: search.isEmpty && tier == nil ? "Nothing to review" : "No results for \u{201C}\(search.isEmpty ? (tier?.title ?? "") : search)\u{201D}",
                             message: search.isEmpty && tier == nil ? "Room found no caches, stale dependencies or large untouched files." : "Try a different search or show all items.",
                             actionTitle: search.isEmpty && tier == nil ? nil : "Clear filters", action: { search = ""; tier = nil }).transition(.opacity)
            } else {
                ScrollView { LazyVStack(spacing: 0) { ForEach(rows) { c in
                    ReviewRow(candidate: c, selected: model.selection.contains(c.id), inspected: model.inspectedID == c.id,
                              toggle: { model.toggle(c.id) }, inspect: { Haptics.play(.select); model.inspectedID = (model.inspectedID == c.id) ? nil : c.id })
                        .transition(.row)
                } }.padding(.bottom, model.selection.isEmpty ? 0 : 84)
                    .motion(.panel, value: rows.map(\.id))              // filtering slides rows in and out instead of jumping
                    .motion(.panel, value: model.selection.isEmpty)
                }.transition(.opacity)
            }
        }
    }
}

private struct ReviewRow: View {
    let candidate: Candidate
    let selected: Bool
    let inspected: Bool
    let toggle: () -> Void
    let inspect: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ZStack { if selected { SindoorDot(size: 3).transition(.pop) } }.frame(width: 3, height: 3)
                Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() })).toggleStyle(DSCheckboxStyle()).labelsHidden()
                    .accessibilityLabel("Select \(candidate.title)")
            }.frame(width: 44, alignment: .leading)
            Button(action: inspect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).dsText(Token.small, color: inspected ? DS.sindoorText : DS.text).lineLimit(1)
                    Text(candidate.displayPath).dsText(Token.monoTiny, mono: true, color: DS.textFaint).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            candidate.riskBadge.frame(width: 120, alignment: .leading)
            Text(candidate.regen.title).dsText(.init(13, 400), color: DS.textMuted).frame(width: 140, alignment: .leading)
            Text(candidate.changedText).dsText(.init(13, 400), color: DS.textMuted).frame(width: 110, alignment: .leading)
            DataText(text: candidate.estimate.display).lineLimit(1).minimumScaleFactor(0.85).frame(width: 210, alignment: .trailing)   // amounts align right, in mono
        }
        .padding(.horizontal, 20).frame(height: 52)
        .background(selected ? DS.sindoorTint : (hover ? DS.raised : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: Token.hairline) }
        .onHover { hover = $0 }
        .motion(.fast, value: selected).motion(.fast, value: hover).motion(.fast, value: inspected)      // selection, hover and focus fade
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.title), \(candidate.tier.title), \(ByteFormat.string(candidate.estimate.planning))")
    }
}

// MARK: - Inspector

private struct Inspector: View {
    @Bindable var model: AppModel
    let candidate: Candidate

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { candidate.riskBadge; Spacer()
                    Button { model.inspectedID = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(DS.textFaint) }
                        .buttonStyle(.plain).help("Close") }
                Text(candidate.title).dsText(Token.h4)
                Text(candidate.why).dsText(Token.small, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    row("Frees", ByteFormat.string(candidate.estimate.planning))
                    row("Rebuild", candidate.regen.title)
                    if candidate.lastModified != nil { row("Changed", candidate.changedText) }
                    if candidate.git != .notRepo { row("Backup", candidate.git.label) }
                }
                if candidate.estimate.isAmbiguous {
                    Text("At least \(ByteFormat.string(candidate.estimate.guaranteed)), up to \(ByteFormat.string(candidate.estimate.allocated)). Part of this is shared with other files, so deleting it frees less than its size.")
                        .dsText(Token.micro, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                DataText(text: candidate.displayPath, style: Token.monoSmall, color: DS.textFaint).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let e = model.explanations[candidate.id] {
                    Text(e).dsText(Token.small, color: DS.textSoft).fixedSize(horizontal: false, vertical: true)
                        .padding(12).background(RoundedRectangle(cornerRadius: Token.radiusSM).fill(DS.raised))
                } else {
                    PillButton(title: "Explain this", variant: .ghost, size: .small, icon: nil) { model.explain(candidate) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: Token.radiusXL, style: .continuous).fill(DS.card.opacity(0.78)))   // keeps text legible on glass
        .cinnabarGlass(RoundedRectangle(cornerRadius: Token.radiusXL, style: .continuous))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(k).dsText(Token.micro, color: DS.textMuted).frame(width: 64, alignment: .leading); Text(v).dsText(Token.small, color: DS.textSoft) }
    }
}

// MARK: - Confirm dialog (destructive: solid rose, exact action and amount)

struct ConfirmCleanDialog: View {
    @Bindable var model: AppModel

    private var items: [Candidate] { model.selectedItems }
    private var yours: [Candidate] { items.filter { $0.tier == .yours } }
    private var risky: [Candidate] { yours.filter { $0.git != .notRepo && !$0.git.isSafeCopyElsewhere } }
    private var ready: Bool { yours.allSatisfy { model.confirmYours.contains($0.id) } && risky.allSatisfy { model.confirmUnbacked.contains($0.id) } }
    private var amount: String { ByteFormat.string(model.selectedBytes) }

    var body: some View {
        DSModal(dismissOnBackdrop: false, onClose: { model.showConfirm = false }) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack { Circle().fill(DS.failedTint); Image(systemName: "trash").font(.system(size: 15, weight: .regular)).foregroundStyle(DS.failedText) }.frame(width: 40, height: 40)
                Text("Delete \(items.count) item\(items.count == 1 ? "" : "s") and free \(amount)?").dsText(Token.h3)
                VStack(alignment: .leading, spacing: 8) {
                    let direct = items.filter { $0.tier != .yours && model.policy(for: $0) == .immediate }
                    if !direct.isEmpty { Text("\(direct.count) cache\(direct.count == 1 ? "" : "s") and rebuildable item\(direct.count == 1 ? "" : "s") go right away. They come back by themselves or with one command.").dsText(Token.small, color: DS.textMuted) }
                    let waiting = items.filter { model.policy(for: $0) != .immediate }
                    if !waiting.isEmpty { Text("\(waiting.count) item\(waiting.count == 1 ? "" : "s") (your files, installers and zips\(model.settings.vaultRebuildable ? ", rebuildable folders" : "")) go to the undo vault for 7 days. The space returns when you empty the vault.").dsText(Token.small, color: DS.textMuted) }
                    if items.contains(where: { $0.estimate.isAmbiguous }) { Text("Some items share space with other files, so the amount that returns may be lower. Room measures it afterwards.").dsText(Token.micro, color: DS.textFaint) }
                }.fixedSize(horizontal: false, vertical: true)

                if !yours.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(yours) { c in
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { model.confirmYours.contains(c.id) }, set: { on in if on { model.confirmYours.insert(c.id) } else { model.confirmYours.remove(c.id) } })) {
                                    Text("I know \(c.title) is mine").dsText(Token.small).lineLimit(2)
                                }.toggleStyle(DSCheckboxStyle())
                                if c.git != .notRepo && !c.git.isSafeCopyElsewhere {
                                    Toggle(isOn: Binding(get: { model.confirmUnbacked.contains(c.id) }, set: { on in if on { model.confirmUnbacked.insert(c.id) } else { model.confirmUnbacked.remove(c.id) } })) {
                                        Text("It is not backed up: \(c.git.label)").dsText(Token.small, color: DS.failedText)
                                    }.toggleStyle(DSCheckboxStyle()).padding(.leading, 20)
                                }
                            }
                        }
                    }.padding(14).background(RoundedRectangle(cornerRadius: Token.radiusSM).fill(DS.raised))
                }
                HStack(spacing: 10) {
                    Spacer()
                    PillButton(title: "Cancel", variant: .secondary, icon: nil) { model.showConfirm = false }
                    PillButton(title: "Delete \(amount)", variant: .danger, icon: nil) { model.confirmClean() }.disabled(!ready).opacity(ready ? 1 : 0.5).motion(.base, value: ready)
                }
            }
        }
    }
}
