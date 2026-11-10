import SwiftUI

struct HotkeySettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section("Dictation") {
                ShortcutRow(
                    slot: .hybrid,
                    title: String(localized: "Dictation shortcut"),
                    subtitle: String(localized: "Hold to talk, tap to toggle")
                )
                ShortcutRow(
                    slot: .pasteLastTranscription,
                    title: String(localized: "Paste last transcription"),
                    subtitle: String(localized: "Pastes your latest dictation at the cursor")
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            HotkeyRecorderView.hotkeyService = coordinator.hotkeyService
        }
    }
}

private struct ShortcutRow: View {
    @Environment(DictationCoordinator.self) private var coordinator
    let slot: HotkeySlotType
    let title: String
    let subtitle: String

    @State private var label = ""
    @State private var isConflicting = false

    private var conflictMessage: String {
        String(localized: "This shortcut is already in use.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HotkeyRecorderView(
                label: label,
                title: title,
                subtitle: subtitle,
                onRecord: record,
                onClear: {
                    coordinator.hotkeyService.clearHotkey(for: slot)
                    label = ""
                    isConflicting = false
                }
            )

            if isConflicting {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { label = loadLabel() }
    }

    private func record(_ hotkey: UnifiedHotkey) {
        guard coordinator.hotkeyService.isHotkeyAssigned(hotkey, excluding: slot) == nil else {
            isConflicting = true
            AccessibilityNotification.Announcement(conflictMessage).post()
            return
        }
        isConflicting = false
        coordinator.hotkeyService.updateHotkey(hotkey, for: slot)
        label = HotkeyService.displayName(for: hotkey)
    }

    private func loadLabel() -> String {
        guard let data = UserDefaults.standard.data(forKey: slot.defaultsKey),
              let hotkey = try? JSONDecoder().decode(UnifiedHotkey.self, from: data) else {
            return ""
        }
        return HotkeyService.displayName(for: hotkey)
    }
}
