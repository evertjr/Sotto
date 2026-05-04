import SwiftUI
import AVFoundation

struct GeneralSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @State private var languageChanged = false
    @State private var initialLanguage = AppleLanguages.current

    var body: some View {
        @Bindable var coord = coordinator

        VStack(spacing: 0) {
            if !coordinator.needsMicPermission {
                AuroraWaveform(level: coordinator.audioDeviceService.previewAudioLevel, preset: coordinator.waveformPreset)
                    .frame(height: 60)
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .onAppear { coordinator.audioDeviceService.startPreview() }
                    .onDisappear { coordinator.audioDeviceService.stopPreview() }
            }

            Form {
                if coordinator.needsMicPermission {
                    Section {
                        HStack {
                            Label("Microphone access required", systemImage: "mic.slash")
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Grant Access") {
                                Task {
                                    _ = await coordinator.audioCaptureService.requestMicrophonePermission()
                                }
                            }
                        }
                    }
                } else {
                    Section("Microphone") {
                        Picker("Input Device", selection: Binding(
                            get: { coordinator.audioDeviceService.selectedDeviceUID },
                            set: { coordinator.audioDeviceService.selectedDeviceUID = $0 }
                        )) {
                            Text("System Default").tag(nil as String?)
                            ForEach(coordinator.audioDeviceService.inputDevices) { device in
                                Text(device.name).tag(device.uid as String?)
                            }
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Waveform Color", selection: $coord.waveformPreset) {
                        ForEach(WaveformColorPreset.allCases) { preset in
                            HStack(spacing: 6) {
                                WaveformPresetSwatch(preset: preset)
                                Text(preset.displayName)
                            }
                            .tag(preset)
                        }
                    }
                }

                Section("Language") {
                    Picker("Language", selection: appLanguageBinding) {
                        Text("System Default").tag("")
                        ForEach(AppLanguage.supported, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    if languageChanged {
                        HStack {
                            Text("Restart to apply the new language.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Restart") {
                                let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
                                    .deletingLastPathComponent()
                                    .deletingLastPathComponent()
                                    .absoluteURL
                                let task = Process()
                                task.launchPath = "/usr/bin/open"
                                task.arguments = [url.path]
                                task.launch()
                                NSApp.terminate(nil)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Feedback") {
                    Toggle("Sound feedback", isOn: $coord.soundFeedbackEnabled)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var appLanguageBinding: Binding<String> {
        Binding(
            get: { AppleLanguages.current },
            set: { code in
                AppleLanguages.set(code)
                languageChanged = code != initialLanguage
            }
        )
    }
}

enum AppLanguage {
    struct Info {
        let code: String
        let name: String
    }

    static let supported: [Info] = [
        Info(code: "en", name: "English"),
        Info(code: "de", name: "Deutsch"),
        Info(code: "es", name: "Español"),
        Info(code: "fr", name: "Français"),
        Info(code: "ja", name: "日本語"),
        Info(code: "pt-BR", name: "Português (Brasil)"),
        Info(code: "zh-Hans", name: "简体中文"),
    ]
}

enum AppleLanguages {
    static var current: String {
        guard let raw = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first else {
            return ""
        }
        return matchSupported(raw)
    }

    static func set(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    private static func matchSupported(_ raw: String) -> String {
        let codes = AppLanguage.supported.map(\.code)
        if codes.contains(raw) { return raw }
        let prefix = raw.split(separator: "-").first.map(String.init) ?? raw
        return codes.first { $0 == prefix } ?? ""
    }
}

private struct WaveformPresetSwatch: View {
    let preset: WaveformColorPreset

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<min(preset.colors.count, 4), id: \.self) { i in
                Circle()
                    .fill(preset.colors[i])
                    .frame(width: 8, height: 8)
            }
        }
    }
}
