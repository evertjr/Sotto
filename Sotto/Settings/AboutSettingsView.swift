import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

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
