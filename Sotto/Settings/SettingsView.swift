import SwiftUI

enum SettingsTab: String {
    case general, shortcut, model, transcribe, ai, about
}

struct SettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @AppStorage(UserDefaultsKeys.selectedSettingsTab) private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environment(coordinator)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            HotkeySettingsView()
                .environment(coordinator)
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
                .tag(SettingsTab.shortcut)

            ModelSettingsView()
                .environment(coordinator)
                .tabItem { Label("Model", systemImage: "cpu") }
                .tag(SettingsTab.model)

            RecorderTranscriberView()
                .environment(coordinator)
                .tabItem { Label("Transcribe", systemImage: "waveform.badge.mic") }
                .tag(SettingsTab.transcribe)

            AISettingsView()
                .environment(coordinator)
                .tabItem { Label("AI", systemImage: "apple.intelligence") }
                .tag(SettingsTab.ai)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
