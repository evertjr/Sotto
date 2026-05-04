import SwiftUI
import AVFoundation

@main
struct SottoApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var coordinator = DictationCoordinator()
    @State private var didLaunch = false

    private var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }

    var body: some Scene {
        MenuBarExtra("Sotto", systemImage: "waveform") {
            MenuBarContentView(openWindow: openWindow)
                .onAppear {
                    guard !didLaunch else { return }
                    didLaunch = true
                    if needsOnboarding {
                        openWindow(id: "onboarding")
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
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

        Window("Welcome", id: "onboarding") {
            OnboardingView(coordinator: coordinator) {
                NSApp.setActivationPolicy(.accessory)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window.identifier?.rawValue.contains("onboarding") == true else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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
