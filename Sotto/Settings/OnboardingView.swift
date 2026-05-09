import SwiftUI
import AVFoundation

struct OnboardingView: View {
    let coordinator: DictationCoordinator
    @State private var step = 0
    @State private var shortcutLabel = ""
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: welcomeStep
            case 1: microphoneStep
            case 2: shortcutStep
            case 3: modelStep
            default: EmptyView()
            }
        }
        .frame(width: 520, height: 480)
        .background(.background)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Welcome to Sotto")
                .font(.largeTitle.weight(.bold))

            Text("The simplest voice dictation for macOS.\nSpeak naturally, and Sotto types it for you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Spacer()

            nextButton("Get Started")
        }
        .padding(40)
    }

    // MARK: - Microphone

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if micGranted {
                AuroraWaveform(level: coordinator.audioDeviceService.previewAudioLevel, preset: coordinator.waveformPreset)
                    .frame(height: 60)
                    .frame(maxWidth: 300)
                    .onAppear { coordinator.audioDeviceService.startPreview() }
                    .onDisappear { coordinator.audioDeviceService.stopPreview() }
            } else {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
            }

            Text("Microphone Access")
                .font(.title.weight(.bold))

            Text("Sotto needs your microphone to transcribe speech. Your audio is processed locally on your Mac — nothing is sent to the cloud.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            if micGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow Microphone Access") {
                    Task {
                        let granted = await coordinator.audioCaptureService.requestMicrophonePermission()
                        micGranted = granted
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()

            nextButton("Continue", enabled: micGranted)
        }
        .padding(40)
    }

    // MARK: - Shortcut

    private var shortcutStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "keyboard.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Set Your Shortcut")
                .font(.title.weight(.bold))

            Text("Choose a key to activate dictation.\nHold it to talk, release to transcribe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            HotkeyRecorderView(
                label: shortcutLabel,
                title: "",
                onRecord: { hotkey in
                    coordinator.hotkeyService.updateHotkey(hotkey, for: .hybrid)
                    shortcutLabel = HotkeyService.displayName(for: hotkey)
                },
                onClear: {
                    coordinator.hotkeyService.clearHotkey(for: .hybrid)
                    shortcutLabel = ""
                }
            )
            .onAppear {
                HotkeyRecorderView.hotkeyService = coordinator.hotkeyService
                if let data = UserDefaults.standard.data(forKey: HotkeySlotType.hybrid.defaultsKey),
                   let hotkey = try? JSONDecoder().decode(UnifiedHotkey.self, from: data) {
                    shortcutLabel = HotkeyService.displayName(for: hotkey)
                }
            }
            .frame(maxWidth: 300)

            Spacer()

            nextButton("Continue", enabled: !shortcutLabel.isEmpty)
        }
        .padding(40)
    }

    // MARK: - Model

    private var recommendedModel: SottoModel {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 16 {
            return ModelManager.availableModels.first { $0.id == "parakeet-tdt-0.6b-v3" }!
        } else if ramGB >= 8 {
            return ModelManager.availableModels.first { $0.id == "parakeet-tdt-0.6b-v3" }!
        } else {
            return ModelManager.availableModels.first { $0.id == "openai_whisper-small" }!
        }
    }

    private var otherModels: [SottoModel] {
        ModelManager.availableModels.filter { $0.id != recommendedModel.id }
    }

    private var modelStep: some View {
        VStack(spacing: 16) {
            Text("Choose a Model")
                .font(.title.weight(.bold))
                .padding(.top, 32)

            Text("You can change this later in Settings.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Recommended for your Mac")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        OnboardingModelCard(
                            model: recommendedModel,
                            isSelected: coordinator.modelManager.selectedModelId == recommendedModel.id,
                            isLoaded: coordinator.modelManager.loadedModelId == recommendedModel.id,
                            state: coordinator.modelManager.state,
                            onSelect: { coordinator.modelManager.loadModel(recommendedModel) },
                            onCancel: { coordinator.modelManager.cancelLoad() },
                            isRecommended: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("All Models")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        ForEach(otherModels) { model in
                            OnboardingModelCard(
                                model: model,
                                isSelected: coordinator.modelManager.selectedModelId == model.id,
                                isLoaded: coordinator.modelManager.loadedModelId == model.id,
                                state: coordinator.modelManager.state,
                                onSelect: { coordinator.modelManager.loadModel(model) },
                                onCancel: { coordinator.modelManager.cancelLoad() }
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            finishButton
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Navigation

    private func nextButton(_ title: String, enabled: Bool = true) -> some View {
        Button(title) { withAnimation(.spring(response: 0.4)) { step += 1 } }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled)
    }

    private var finishButton: some View {
        Button("Start Using Sotto") {
            UserDefaults.standard.set(true, forKey: "onboardingCompleted")
            onComplete()
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Model Card

private struct OnboardingModelCard: View {
    let model: SottoModel
    let isSelected: Bool
    let isLoaded: Bool
    let state: ModelManager.ModelState
    let onSelect: () -> Void
    let onCancel: () -> Void
    var isRecommended: Bool = false

    private var isThisActive: Bool {
        isSelected && !isLoaded
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.displayName)
                                .font(.headline)
                            Text(model.engine.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(model.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 16) {
                    StatBar(label: "Speed", value: model.speed)
                    StatBar(label: "Accuracy", value: model.accuracy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(model.size)
                            .font(.caption.weight(.medium))
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(model.languages)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isThisActive, case .downloading(let progress) = state {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                        Button("Cancel") { onCancel() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if isThisActive, case .loading = state {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Button("Cancel") { onCancel() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(
                isLoaded ? Color.accentColor.opacity(0.08) : (isRecommended ? Color.orange.opacity(0.04) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isLoaded ? Color.accentColor.opacity(0.3) : (isRecommended ? Color.orange.opacity(0.25) : Color.gray.opacity(0.2)),
                        lineWidth: isRecommended ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StatBar: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(width: 80, height: 6)
        }
    }
}
