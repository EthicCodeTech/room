import SwiftUI
import RoomCore

@main
struct RoomApp: App {
    @State private var model = AppModel()

    init() { DSFonts.register() }

    var body: some Scene {
        Window("Room", id: "main") { RootView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1240, height: 820)
            .windowResizability(.contentMinSize)

        MenuBarExtra { MenuPanel(model: model) } label: { MenuLabel(model: model) }
            .menuBarExtraStyle(.window)

        Settings { SettingsView(model: model) }
    }
}
