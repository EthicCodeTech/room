import SwiftUI
import AppKit
import RoomCore

enum MenuBarIcon {
    /// The door, as a template image so macOS tints it for light and dark menu bars. Absent when run outside the app bundle.
    static let image: NSImage? = {
        guard let img = NSImage(named: "RoomMenuBarTemplate") else { return nil }   // finds the @2x and @3x files too
        img.size = NSSize(width: 18, height: 18); img.isTemplate = true; return img
    }()
}

struct MenuLabel: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 4) {
            if let door = MenuBarIcon.image { Image(nsImage: door) }
            if model.isLow { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(DS.sindoor) }   // "look here"
            Text(ByteFormat.string(model.freeBytes)).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

struct MenuPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var safeItems: [Candidate] { model.candidates.filter { $0.tier == .safe && $0.preselected } }
    private var safeBytes: Int64 { safeItems.reduce(0) { $0 + $1.estimate.planning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { LogoMark(height: 18); Text("Room").dsText(.init(14, 600)); Spacer()
                if model.isLow { DSBadge(text: "Low", dot: DS.sindoor) } }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DataText(text: ByteFormat.string(model.freeBytes), style: Token.h2)
                DataText(text: "free of \(ByteFormat.string(model.totalBytes))", style: Token.monoSmall, color: DS.textMuted)
            }
            DSProgressBar(value: model.usedFraction)
            if case .done = model.scanState {
                Text(safeBytes > 0 ? "\(ByteFormat.string(safeBytes)) of caches can go with no risk." : "No safe caches to clear right now.").dsText(Token.small, color: DS.textMuted)
            } else { Text("Looking for space").dsText(Token.small, color: DS.textMuted) }
            HStack(spacing: 10) {
                PillButton(title: "Clear safe caches", size: .small) {
                    model.selection = Set(safeItems.map(\.id)); open(); model.requestClean()
                }.disabled(safeItems.isEmpty)
                PillButton(title: "Open Room", variant: .secondary, size: .small, icon: nil) { open() }
            }
        }
        .padding(20).frame(width: 320).background(DS.bg)
        .task { if model.scanState == .idle { model.scan() } }
    }

    private func open() { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
}
