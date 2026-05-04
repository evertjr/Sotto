import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Sotto")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(AppConstants.appVersion)")
                .foregroundStyle(.secondary)

            Text("Minimal voice dictation for macOS")
                .foregroundStyle(.secondary)

            Button("Show Setup Guide") {
                UserDefaults.standard.set(false, forKey: "onboardingCompleted")
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
