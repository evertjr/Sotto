import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
