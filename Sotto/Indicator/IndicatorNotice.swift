import SwiftUI

/// A short message the recording indicator shows after a take: an error, or a hint
/// that the transcript was left on the clipboard because the paste didn't land.
struct IndicatorNotice: Equatable {
    let message: String
    let systemImage: String

    init?(state: DictationCoordinator.State) {
        switch state {
        case .copiedToClipboard:
            message = String(localized: "Copied. Press ⌘V to paste.")
            systemImage = "doc.on.clipboard"
        case .error(let message):
            self.message = message
            systemImage = "exclamationmark.triangle.fill"
        case .idle, .recording, .processing, .inserting:
            return nil
        }
    }
}

struct IndicatorNoticeLabel: View {
    let notice: IndicatorNotice

    var body: some View {
        Label(notice.message, systemImage: notice.systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .onAppear(perform: announce)
            .onChange(of: notice) { announce() }
    }

    /// The indicator panels never take focus, so VoiceOver wouldn't read the notice on its own.
    private func announce() {
        AccessibilityNotification.Announcement(notice.message).post()
    }
}
