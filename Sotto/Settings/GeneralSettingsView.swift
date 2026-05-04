import SwiftUI
import AVFoundation

struct GeneralSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

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

                Section("Feedback") {
                    Toggle("Sound feedback", isOn: $coord.soundFeedbackEnabled)
                }
            }
            .formStyle(.grouped)
        }
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
