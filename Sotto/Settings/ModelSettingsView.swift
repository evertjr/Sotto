import SwiftUI

struct ModelSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        let mm = coordinator.modelManager

        Form {
            Section("WhisperKit Models") {
                ForEach(ModelManager.availableModels) { model in
                    ModelRow(
                        model: model,
                        isLoaded: mm.loadedModelId == model.id,
                        isActive: mm.selectedModelId == model.id,
                        isDownloaded: mm.isModelDownloaded(model),
                        state: mm.state,
                        onLoad: { Task { await mm.loadModel(model) } },
                        onUnload: { mm.unloadModel() },
                        onDelete: { mm.deleteModel(model) }
                    )
                }
            }

            if case .error(let message) = mm.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    let isLoaded: Bool
    let isActive: Bool
    let isDownloaded: Bool
    let state: ModelManager.ModelState
    let onLoad: () -> Void
    let onUnload: () -> Void
    let onDelete: () -> Void

    private var isBusy: Bool {
        switch state {
        case .downloading, .loading: true
        default: false
        }
    }

    private var isThisModelBusy: Bool {
        guard isActive else { return false }
        return isBusy
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(isLoaded ? .semibold : .regular)
                    if isDownloaded && !isLoaded && !isThisModelBusy {
                        Text("Downloaded")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(model.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoaded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Unload") { onUnload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Remove", role: .destructive) { onDelete() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if isActive, case .downloading(let progress) = state {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
            } else if isActive, case .loading = state {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                }
            } else {
                HStack(spacing: 8) {
                    Button(isDownloaded ? "Load" : "Download & Load") { onLoad() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBusy)

                    if isDownloaded {
                        Button("Remove", role: .destructive) { onDelete() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
