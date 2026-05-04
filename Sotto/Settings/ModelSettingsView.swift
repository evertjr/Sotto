import SwiftUI

struct ModelSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator

    var body: some View {
        let mm = coordinator.modelManager

        ScrollView {
            VStack(spacing: 20) {
                ForEach(SottoModel.Engine.allCases, id: \.rawValue) { engine in
                    let models = ModelManager.availableModels.filter { $0.engine == engine }
                    EngineSection(
                        engine: engine,
                        models: models,
                        modelManager: mm
                    )
                }
            }
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

private struct EngineSection: View {
    let engine: SottoModel.Engine
    let models: [SottoModel]
    let modelManager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(engine.rawValue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(models) { model in
                    ModelRow(
                        model: model,
                        isLoaded: modelManager.loadedModelId == model.id,
                        isActive: modelManager.selectedModelId == model.id,
                        isDownloaded: modelManager.isModelDownloaded(model),
                        state: modelManager.state,
                        onLoad: { Task { await modelManager.loadModel(model) } },
                        onUnload: { modelManager.unloadModel() },
                        onDelete: { modelManager.deleteModel(model) }
                    )

                    if model.id != models.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct ModelRow: View {
    let model: SottoModel
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
