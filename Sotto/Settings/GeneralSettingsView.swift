import SwiftUI
import AVFoundation

struct GeneralSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coord = coordinator

        VStack(spacing: 0) {
            if !coordinator.needsMicPermission {
                AuroraWaveform(level: coordinator.audioDeviceService.previewAudioLevel)
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

                Section("Feedback") {
                    Toggle("Sound feedback", isOn: $coord.soundFeedbackEnabled)
                }
            }
            .formStyle(.grouped)
        }
    }
}
