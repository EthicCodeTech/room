import SwiftUI
import RoomCore

struct VaultView: View {
    @Bindable var model: AppModel

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Vault")
                        Text("Changed your mind? Undo here.").dsText(Token.h1)
                        Text("Anything of yours that you delete waits here for 7 days. The space only comes back when the vault is emptied.")
                            .dsText(Token.bodyLg, color: DS.textMuted).frame(maxWidth: 620, alignment: .leading)
                    }
                    Spacer()
                    if !model.vaultBatches.isEmpty {
                        PillButton(title: "Empty vault", variant: .secondary, icon: nil) { model.emptyVaultNow() }.transition(.opacity)
                    }
                }
                if model.vaultBatches.isEmpty {
                    DSCard { DSEmptyState(title: "The vault is empty", message: "When you delete something that is yours, it waits here so you can put it back.") }.transition(.rise)
                } else {
                    DataText(text: "\(ByteFormat.string(model.vault.totalBytes())) in \(model.vaultBatches.count) batch\(model.vaultBatches.count == 1 ? "" : "es")", color: DS.textMuted)
                    VStack(spacing: 12) { ForEach(model.vaultBatches) { b in batch(b).transition(.row) } }
                }
            }
            .motion(.panel, value: model.vaultBatches.map(\.id))             // restoring or deleting a batch slides it away
        }
        .onAppear { model.refreshVault() }
    }

    private func batch(_ b: VaultManifest) -> some View {
        DSCard(padding: 20, interactive: true) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(b.label).dsText(Token.h4).lineLimit(1)
                    Text("\(b.entries.count) item\(b.entries.count == 1 ? "" : "s"), deleted \(b.created.formatted(date: .abbreviated, time: .shortened))").dsText(Token.small, color: DS.textMuted)
                }
                Spacer()
                DSBadge(text: b.expires.countdown(), dot: DS.pending)
                DataText(text: ByteFormat.string(b.totalBytes)).frame(width: 90, alignment: .trailing)
                PillButton(title: "Restore", variant: .secondary, size: .small, icon: nil) { model.restore(b) }
                PillButton(title: "Delete now", variant: .ghost, size: .small, icon: nil) { model.deleteBatchNow(b) }
            }
        }
    }
}
