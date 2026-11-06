import SwiftUI
import RoomCore

struct RootView: View {
    @Bindable var model: AppModel
    @State private var section: Section = Section(rawValue: (Dev.env("ROOM_SECTION") ?? "").capitalized) ?? .overview
    @Environment(\.openSettings) private var openSettings
    @State private var forward = true
    @State private var appeared = false

    /// Navigating records which way we moved, so the new page arrives from the side it sits on.
    private func go(_ new: Section) {
        guard new != section else { return }
        forward = (Section.allCases.firstIndex(of: new) ?? 0) >= (Section.allCases.firstIndex(of: section) ?? 0)
        section = new
    }
    private var sectionBinding: Binding<Section> { Binding(get: { section }, set: { go($0) }) }

    private var primaryTitle: String {
        if case .scanning = model.scanState { return "Scanning" }
        return model.selection.isEmpty ? "Scan again" : "Free up \(ByteFormat.string(model.selectedBytes))"
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ZStack { content.id(section).transition(.page(forward: forward)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .motion(.panel, value: section)
                NavBar(section: sectionBinding, vaultCount: model.vaultBatches.count, reviewCount: model.candidates.count,
                       primaryTitle: primaryTitle, primaryLoading: { if case .scanning = model.scanState { return true } else { return false } }(),
                       primaryAction: { if model.selection.isEmpty { model.rescanAfterClean() } else { model.requestClean() } },
                       settingsAction: { openSettings() })
            }
            if model.showConfirm { ConfirmCleanDialog(model: model).transition(.opacity) }
            if model.isCleaning { cleaningOverlay.transition(.opacity) }
            VStack { Spacer(); HStack { Spacer(); ToastHost(center: model.toasts) } }.allowsHitTesting(!model.toasts.items.isEmpty)
        }
        .frame(minWidth: 1080, minHeight: 720)
        .background(DS.bg)
        .containerBackground(DS.bg, for: .window)
        .motion(.panel, value: model.showConfirm).motion(.panel, value: model.isCleaning)
        .opacity(appeared ? 1 : 0)                                                     // the app eases in instead of popping
        .onAppear { Motion.run(.slow) { appeared = true } }
        .task {
            if model.scanState == .idle { model.scan() }
            if Dev.env("ROOM_DEV_SETTINGS") != nil { openSettings() }      // dev only
            // dev only: "ROOM_DEV_NAVSEQ=review@6" navigates after 6 seconds, to capture a transition mid-flight
            if let seq = Dev.env("ROOM_DEV_NAVSEQ"), let at = seq.split(separator: "@").last.flatMap({ Double($0) }),
               let name = seq.split(separator: "@").first, let target = Section(rawValue: String(name).capitalized) {
                try? await Task.sleep(for: .seconds(at)); go(target)
            }
        }
        .preferredColorScheme(model.colorScheme)
        .onChange(of: model.pendingSection) { _, new in if let s = new { go(s); model.pendingSection = nil } }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .overview: OverviewView(model: model, goToReview: { go(.review) }, goToAsk: { go(.ask) })
        case .review: ReviewView(model: model)
        case .map: MapView(model: model)
        case .vault: VaultView(model: model)
        case .growth: GrowthView(model: model)
        case .ask: AskView(model: model)
        }
    }

    private var cleaningOverlay: some View {
        ZStack {
            DS.obsidian.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 20) {
                SparkTraceLoader(isRunning: true, height: 80)
                Text("Freeing space").dsText(Token.h4)
                Text("Room will measure what really came back when it finishes.").dsText(Token.small, color: DS.textMuted)
                DSProgressBar(value: nil).frame(width: 220)
            }
        }
    }
}
