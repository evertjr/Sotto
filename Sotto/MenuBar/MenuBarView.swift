import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Transcribe Audio...") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

        Button("Settings...") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Sotto") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
