import SwiftUI

struct SettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(coordinator)
                .tabItem { Label("General", systemImage: "gear") }

            HotkeySettingsView()
                .environment(coordinator)
                .tabItem { Label("Shortcut", systemImage: "keyboard") }

            ModelSettingsView()
                .environment(coordinator)
                .tabItem { Label("Model", systemImage: "cpu") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
