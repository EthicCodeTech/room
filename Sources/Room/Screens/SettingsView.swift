import SwiftUI
import AppKit
import RoomCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var keySaved = ClaudeAdvisor().isAvailable
    @State private var records = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").dsText(Token.h2)
                appearance
                haptics
                water
                assistant
                privacy
                cleaning
                about
            }.padding(32).frame(maxWidth: 720, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 640).background(DS.bg).preferredColorScheme(model.colorScheme)
        .onAppear { DSFonts.register(); records = model.log.count() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        DSCard(padding: 24) { VStack(alignment: .leading, spacing: 16) { Text(title).dsText(Token.h4); content() }.frame(maxWidth: .infinity, alignment: .leading) }
            .motion(.panel, value: model.settings.advisorMode).motion(.panel, value: model.settings.hapticLevel)
            .motion(.panel, value: model.settings.tiltEnabled).motion(.panel, value: model.settings.tilt.isCalibrated).motion(.panel, value: keySaved)
    }

    // MARK: Appearance

    private var appearance: some View {
        section("Appearance") {
            DSSegmented(options: Appearance.allCases.map { ($0, $0.title) }, selection: $model.settings.appearance)
            Text("System follows your Mac and switches between light and dark on its own.").dsText(Token.small, color: DS.textMuted)
        }
    }

    // MARK: Assistant

    private var assistant: some View {
        section("Assistant") {
            DSSegmented(options: AdvisorMode.allCases.map { ($0, $0.title) }, selection: $model.settings.advisorMode)
            Text(blurb).dsText(Token.small, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            if model.settings.advisorMode == .claude {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anthropic API key").dsText(Token.micro, color: DS.textMuted)
                        SecureField("", text: $apiKey, prompt: Text(keySaved ? "Saved in your Keychain" : "sk-ant-...").foregroundStyle(DS.placeholder))
                            .textFieldStyle(DSFieldStyle(mono: true))
                    }
                    PillButton(title: "Save key", variant: .secondary, icon: nil) {
                        if Keychain.write(ClaudeAdvisor.keyAccount, apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) { keySaved = true; apiKey = ""; model.toasts.show(.success, "Key saved", detail: "Stored in your Keychain") }
                    }.disabled(apiKey.isEmpty)
                    if keySaved { PillButton(title: "Remove", variant: .ghost, icon: nil) { Keychain.delete(ClaudeAdvisor.keyAccount); keySaved = false }.transition(.opacity) }
                }
            }
        }
    }

    private var blurb: String {
        switch model.settings.advisorMode {
        case .off: "Room answers from its built-in rules only."
        case .onDevice: "Uses the model built into your Mac. Private, offline and free. If your Mac doesn't support it, built-in rules answer instead."
        case .claude: "Sends only sizes, categories and generic names, never file names, paths or contents. You pay for your own usage."
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        section("Help improve Room") {
            Toggle(isOn: Binding(get: { model.settings.learningOptIn }, set: { on in
                model.settings.learningOptIn = on; model.settings.learningConsentDate = on ? Date() : nil })) {
                Text("Share anonymous cleanup records").dsText(Token.small)
            }.toggleStyle(DSToggleStyle())
            Text("A record says which kind of item it was, a rough size and age, and whether you kept it or restored it. It never contains file names, paths or contents. You can read every record before sharing.")
                .dsText(Token.small, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            if RoomConfig.learningEndpoint == nil {
                Text("This build has no upload server, so nothing is sent, even with this on.").dsText(Token.small, color: DS.textMuted)
            }
            HStack(spacing: 10) {
                DataText(text: "\(records) records on this Mac", style: Token.monoSmall, color: DS.textMuted)
                Spacer()
                PillButton(title: "Export to review", variant: .secondary, size: .small, icon: nil) { export() }
                PillButton(title: "Delete history", variant: .ghost, size: .small, icon: nil) { model.log.deleteAll(); records = 0 }
            }
        }
    }

    private func export() {
        guard model.settings.learningOptIn else { model.toasts.show(.pending, "Turn on sharing first", detail: "Export needs your opt-in"); return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "room-anonymous-records.jsonl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let n = try model.log.export(to: url, optedIn: true); model.toasts.show(.success, "Exported \(n) records", detail: url.lastPathComponent) }
        catch { model.toasts.show(.failed, "Could not export", detail: error.localizedDescription) }
    }

    // MARK: Cleaning

    private var haptics: some View {
        section("Haptics") {
            DSSegmented(options: HapticLevel.allCases.map { ($0, $0.title) }, selection: $model.settings.hapticLevel)
            Text(model.settings.hapticLevel.blurb).dsText(Token.small, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            Text("Feedback plays through the trackpad, so rest a finger on it. Every haptic is paired with something you can see.").dsText(Token.micro, color: DS.textFaint)
            if model.settings.hapticLevel != .off {
                Text("Feel each one").dsText(Token.micro, color: DS.textMuted)
                HStack(spacing: 8) {
                    ForEach([Haptics.Pattern.select, .confirm, .attention, .decline, .pending, .spark] + (model.settings.hapticLevel == .full ? [Haptics.Pattern.detent, .thump] : []), id: \.self) { p in
                        Button { Haptics.play(p) } label: {
                            Text(p.title).font(.ds(.init(13, 500))).foregroundStyle(DS.textSoft).padding(.horizontal, 12).frame(height: 30)
                                .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: Token.hairline))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var water: some View {
        section("Water") {
            Toggle(isOn: $model.settings.tiltEnabled) { Text("Tilt the water with your Mac").dsText(Token.small) }.toggleStyle(DSToggleStyle())
            Text(model.motion.isAvailable
                 ? "The free-space tank follows your Mac like water in a container: it stays level as you tilt and sloshes when you move. It reads the motion sensor built into your Mac and only runs while the tank is on screen."
                 : "This Mac has no usable motion sensor, so the tank stays still. (\(unavailableReason))")
                .dsText(Token.small, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            if model.motion.isAvailable && model.settings.tiltEnabled {
                HStack {
                    DSBadge(text: model.settings.tilt.isCalibrated ? "Calibrated" : "Not calibrated", dot: model.settings.tilt.isCalibrated ? Color(hex: Token.successText) : DS.pending)
                    Spacer()
                    PillButton(title: model.settings.tilt.isCalibrated ? "Calibrate again" : "Calibrate", variant: .secondary, size: .small, icon: nil) { model.recalibrateTilt() }
                }
            }
        }
    }

    private var unavailableReason: String { if case .unavailable(let why) = model.motion.state { return why } else { return "" } }

    private var cleaning: some View {
        section("Cleaning") {
            row("Stale projects") { DSSegmented(options: [(30, "30 days"), (60, "60 days"), (90, "90 days")], selection: $model.settings.staleProjectDays) }
            Text("node_modules in projects untouched this long are offered for removal.").dsText(Token.micro, color: DS.textFaint)
            row("Low space alert") { DSSegmented(options: [(10, "10 GB"), (15, "15 GB"), (25, "25 GB")], selection: $model.settings.lowSpaceAlertGB) }
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(label).dsText(Token.small); Spacer(); control() }
    }

    private var about: some View {
        section("About") {
            HStack(spacing: 16) {
                LogoMark(height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room").dsText(.init(15, 600))
                    DataText(text: "Version \(RoomConfig.appVersion) · rules catalog v\(model.catalog.version)", style: Token.monoSmall, color: DS.textMuted)
                }
            }
            Text("Built by EthicCode. Trust is the feature.").dsText(Token.small, color: DS.textMuted)
        }
    }
}
