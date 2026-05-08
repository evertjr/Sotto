import SwiftUI

struct SettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.settingsTab) {
            GeneralSettingsView()
                .environment(coordinator)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            HotkeySettingsView()
                .environment(coordinator)
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
                .tag(SettingsTab.hotkey)

            ModelSettingsView()
                .environment(coordinator)
                .tabItem { Label("Model", systemImage: "cpu") }
                .tag(SettingsTab.model)

            AISettingsView()
                .environment(coordinator)
                .tabItem { Label("AI", systemImage: "apple.intelligence") }
                .tag(SettingsTab.ai)

            HistorySettingsView()
                .environment(coordinator)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
