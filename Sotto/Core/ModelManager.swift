import Foundation
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "ModelManager")

struct SottoTranscription: Sendable {
    let text: String
    let detectedLanguage: String?
    let duration: TimeInterval
}

struct SottoModel: Identifiable {
    let id: String
    let displayName: String
    let size: String
    let engine: Engine
    let speed: Double        // 0...1
    let accuracy: Double     // 0...1
    let languages: String
    let description: String

    enum Engine: String, CaseIterable {
        case whisperKit = "WhisperKit"
        case parakeet = "Parakeet"
    }
}

enum LoadPhase: Sendable {
    case downloading(progress: Double)
    case loading
}

@MainActor
protocol TranscriptionEngine {
    var engineName: String { get }
    func loadModel(_ model: SottoModel, onPhaseChange: @escaping (LoadPhase) -> Void) async throws
    func unloadModel()
    func deleteModel(_ model: SottoModel)
    func isModelDownloaded(_ model: SottoModel) -> Bool
    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription
}

@Observable
@MainActor
final class ModelManager {
    enum ModelState: Equatable {
        case notLoaded
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)
    }

    private(set) var state: ModelState = .notLoaded
    private(set) var selectedModelId: String?
    private(set) var loadedModelId: String?
    private(set) var downloadedModelIds: Set<String> = []

    private var activeEngine: (any TranscriptionEngine)?
    private let engines: [SottoModel.Engine: any TranscriptionEngine]

    static let availableModels: [SottoModel] = [
        SottoModel(id: "openai_whisper-tiny", displayName: "Whisper Tiny", size: "~39 MB", engine: .whisperKit,
                   speed: 0.95, accuracy: 0.4, languages: "99+ languages",
                   description: "Fastest Whisper model, good for quick notes"),
        SottoModel(id: "openai_whisper-base", displayName: "Whisper Base", size: "~74 MB", engine: .whisperKit,
                   speed: 0.85, accuracy: 0.55, languages: "99+ languages",
                   description: "Good balance for everyday use"),
        SottoModel(id: "openai_whisper-small", displayName: "Whisper Small", size: "~244 MB", engine: .whisperKit,
                   speed: 0.7, accuracy: 0.7, languages: "99+ languages",
                   description: "Reliable accuracy across many languages"),
        SottoModel(id: "openai_whisper-large-v3_turbo", displayName: "Whisper Large Turbo", size: "~800 MB", engine: .whisperKit,
                   speed: 0.6, accuracy: 0.85, languages: "99+ languages",
                   description: "Near-best accuracy with faster inference"),
        SottoModel(id: "openai_whisper-large-v3", displayName: "Whisper Large v3", size: "~1.5 GB", engine: .whisperKit,
                   speed: 0.35, accuracy: 0.95, languages: "99+ languages",
                   description: "Highest accuracy for professional transcription"),
        SottoModel(id: "parakeet-tdt-0.6b-v2", displayName: "Parakeet v2", size: "~600 MB", engine: .parakeet,
                   speed: 0.95, accuracy: 0.9, languages: "English only",
                   description: "Extremely fast, optimized for English"),
        SottoModel(id: "parakeet-tdt-0.6b-v3", displayName: "Parakeet v3", size: "~600 MB", engine: .parakeet,
                   speed: 0.9, accuracy: 0.9, languages: "25 European languages",
                   description: "Fast and accurate with multilingual support"),
    ]

    var isModelReady: Bool { activeEngine != nil && loadedModelId != nil }
    var canTranscribe: Bool { isModelReady }

    var activeModelName: String? {
        guard let loadedModelId else { return nil }
        return Self.availableModels.first { $0.id == loadedModelId }?.displayName
    }

    var activeEngineName: String? {
        activeEngine?.engineName
    }

    init() {
        self.engines = [
            .whisperKit: WhisperKitEngine(),
            .parakeet: ParakeetEngine(),
        ]

        let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedModelId)
        self.selectedModelId = savedId

        if let savedId, Self.availableModels.contains(where: { $0.id == savedId }) {
            self.state = .loading
        }

        self.downloadedModelIds = Set(
            Self.availableModels
                .filter { self.engines[$0.engine]?.isModelDownloaded($0) ?? false }
                .map(\.id)
        )
    }

    func loadModel(_ model: SottoModel) async {
        guard let engine = engines[model.engine] else { return }

        activeEngine?.unloadModel()
        activeEngine = nil
        loadedModelId = nil

        selectedModelId = model.id
        UserDefaults.standard.set(model.id, forKey: UserDefaultsKeys.selectedModelId)

        do {
            if engine.isModelDownloaded(model) {
                state = .loading
            } else {
                state = .downloading(progress: 0)
            }

            try await engine.loadModel(model) { [weak self] phase in
                Task { @MainActor in
                    switch phase {
                    case .downloading(let progress):
                        self?.state = .downloading(progress: progress)
                    case .loading:
                        self?.state = .loading
                    }
                }
            }

            activeEngine = engine
            loadedModelId = model.id
            downloadedModelIds.insert(model.id)
            state = .ready
            logger.info("Model \(model.displayName) (\(model.engine.rawValue)) loaded")
        } catch {
            activeEngine = nil
            loadedModelId = nil
            state = .error(error.localizedDescription)
            logger.error("Failed to load model: \(error.localizedDescription)")
        }
    }

    func unloadModel() {
        activeEngine?.unloadModel()
        activeEngine = nil
        loadedModelId = nil
        state = .notLoaded
    }

    func deleteModel(_ model: SottoModel) {
        if loadedModelId == model.id { unloadModel() }
        engines[model.engine]?.deleteModel(model)
        downloadedModelIds.remove(model.id)
    }

    func isModelDownloaded(_ model: SottoModel) -> Bool {
        downloadedModelIds.contains(model.id)
    }

    func restoreLastModel() async {
        guard let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedModelId),
              let model = Self.availableModels.first(where: { $0.id == savedId }),
              isModelDownloaded(model) else { return }
        await loadModel(model)
    }

    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription {
        guard let engine = activeEngine else {
            throw TranscriptionError.engineNotConfigured
        }
        return try await engine.transcribe(samples: samples, language: language)
    }
}

enum TranscriptionError: LocalizedError {
    case engineNotConfigured

    var errorDescription: String? {
        "No model loaded. Please download and select a model in Settings."
    }
}
