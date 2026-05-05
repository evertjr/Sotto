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

            Text("The simplest voice dictation for macOS")
                .foregroundStyle(.secondary)

            Text("Made by [Evert Junior](https://github.com/evertjr)")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/evertjr/Sotto")!) {
                    Label("View on GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Show Setup Guide") {
                    UserDefaults.standard.set(false, forKey: "onboardingCompleted")
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
