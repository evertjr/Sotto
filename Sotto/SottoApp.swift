import SwiftUI
import AVFoundation

@main
struct SottoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var coordinator = DictationCoordinator()

    var body: some Scene {
        MenuBarExtra("Sotto", systemImage: "waveform") {
            MenuBarContentView(openWindow: openWindow)
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(coordinator)
                .frame(minWidth: 500, minHeight: 400)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                    guard let window = notification.object as? NSWindow,
                          window.identifier?.rawValue.contains("settings") == true else { return }
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 500)
    }

    init() {
        let coord = DictationCoordinator()
        _coordinator = State(initialValue: coord)

        Task { @MainActor in
            coord.start()
        }
    }
}

private struct MenuBarContentView: View {
    let openWindow: OpenWindowAction

    var body: some View {
        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Sotto") {
            NSApp.terminate(nil)
        }
    }
}
