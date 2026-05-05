import SwiftUI

struct AISettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coord = coordinator

        Form {
            availabilitySection

            Section("Polish") {
                Toggle("Polish transcriptions", isOn: $coord.polishEnabled)
                Text("Rewrites your spoken text into clean, well-structured writing. Removes filler words, fixes grammar, and formats lists and steps automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!coordinator.aiService.isAvailable)

            Section("Translate") {
                Toggle("Translate after transcription", isOn: $coord.translateEnabled)

                if coordinator.translateEnabled {
                    Picker("Target Language", selection: $coord.translateTargetLanguage) {
                        Text("Select a language").tag("")
                        ForEach(AILanguage.supported, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }

                Text("Translates your spoken words into the selected language before inserting. Speak in any language — the output will be in your target language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!coordinator.aiService.isAvailable)
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var availabilitySection: some View {
        if !coordinator.aiService.isAvailable {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "apple.intelligence")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence Required")
                            .font(.headline)
                        Text(coordinator.aiService.unavailableReason ?? "Apple Intelligence is not available on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "apple.intelligence")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence")
                            .font(.headline)
                        Text("On-device language model ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

enum AILanguage {
    struct Info {
        let code: String
        let name: String
    }

    static let supported: [Info] = [
        Info(code: "English", name: "English"),
        Info(code: "Chinese (Simplified)", name: "中文 (简体)"),
        Info(code: "Chinese (Traditional)", name: "中文 (繁體)"),
        Info(code: "French", name: "Français"),
        Info(code: "German", name: "Deutsch"),
        Info(code: "Italian", name: "Italiano"),
        Info(code: "Japanese", name: "日本語"),
        Info(code: "Korean", name: "한국어"),
        Info(code: "Portuguese", name: "Português"),
        Info(code: "Spanish", name: "Español"),
        Info(code: "Vietnamese", name: "Tiếng Việt"),
    ]

    static func shortCode(for language: String) -> String {
        switch language {
        case "English": return "EN"
        case "Chinese (Simplified)": return "简"
        case "Chinese (Traditional)": return "繁"
        case "French": return "FR"
        case "German": return "DE"
        case "Italian": return "IT"
        case "Japanese": return "日"
        case "Korean": return "한"
        case "Portuguese": return "PT"
        case "Spanish": return "ES"
        case "Vietnamese": return "VI"
        default: return String(language.prefix(2)).uppercased()
        }
    }
}
