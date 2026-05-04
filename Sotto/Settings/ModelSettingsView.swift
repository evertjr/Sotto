import SwiftUI

struct ModelSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        let mm = coordinator.modelManager

        ScrollView {
            VStack(spacing: 0) {
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

                    if model.id != ModelManager.availableModels.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .padding()

            if case .error(let message) = mm.state {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                }
                .padding(.horizontal)
            }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .font(.body)
                Text(model.size)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isLoaded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        } else if isActive, case .downloading = state {
            ProgressView()
                .controlSize(.small)
        } else if isActive, case .loading = state {
            ProgressView()
                .controlSize(.small)
        } else if isDownloaded {
            Image(systemName: "circle.fill")
                .foregroundStyle(.quaternary)
                .font(.caption2)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isLoaded {
            Menu {
                Button("Unload Model") { onUnload() }
                Button("Delete Files", role: .destructive) { onDelete() }
            } label: {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if isActive, case .downloading(let progress) = state {
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else if isActive, case .loading = state {
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                if isDownloaded {
                    Button("Load") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                } else {
                    Button("Download") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy)
                }
            }
        }
    }
}
