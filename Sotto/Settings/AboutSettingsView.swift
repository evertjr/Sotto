import SwiftUI

struct AboutSettingsView: View {
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
