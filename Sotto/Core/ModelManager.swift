import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "ModelManager")

struct SottoTranscription: Sendable {
    let text: String
    let detectedLanguage: String?
    let duration: TimeInterval
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

    private var whisperKit: WhisperKit?
    private let modelsDirectory: URL

    static let availableModels: [WhisperModel] = [
        WhisperModel(id: "openai_whisper-tiny", displayName: "Tiny", size: "~39 MB"),
        WhisperModel(id: "openai_whisper-base", displayName: "Base", size: "~74 MB"),
        WhisperModel(id: "openai_whisper-small", displayName: "Small", size: "~244 MB"),
        WhisperModel(id: "openai_whisper-large-v3_turbo", displayName: "Large v3 Turbo", size: "~800 MB"),
        WhisperModel(id: "openai_whisper-large-v3", displayName: "Large v3", size: "~1.5 GB"),
    ]

    var isModelReady: Bool { whisperKit != nil && loadedModelId != nil }
    var canTranscribe: Bool { isModelReady }

    var activeModelName: String? {
        guard let loadedModelId else { return nil }
        return Self.availableModels.first { $0.id == loadedModelId }?.displayName
    }

    init() {
        self.modelsDirectory = AppConstants.appSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedModelId)
        self.selectedModelId = savedId

        if let savedId, Self.availableModels.contains(where: { $0.id == savedId }) {
            self.state = .loading
        }
    }

    func loadModel(_ model: WhisperModel) async {
        selectedModelId = model.id
        UserDefaults.standard.set(model.id, forKey: UserDefaultsKeys.selectedModelId)

        do {
            let modelPath = modelsDirectory
                .appendingPathComponent("argmaxinc")
                .appendingPathComponent("whisperkit-coreml")
                .appendingPathComponent(model.id)

            let modelFolder: URL
            if FileManager.default.fileExists(atPath: modelPath.path) {
                state = .loading
                modelFolder = modelPath
            } else {
                state = .downloading(progress: 0)
                modelFolder = try await WhisperKit.download(
                    variant: model.id,
                    downloadBase: modelsDirectory
                ) { progress in
                    Task { @MainActor in
                        self.state = .downloading(progress: progress.fractionCompleted)
                    }
                }
            }

            state = .loading
            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: false,
                download: false
            )
            let kit = try await WhisperKit(config)
            try await kit.loadModels()
            try await kit.prewarmModels()

            whisperKit = kit
            loadedModelId = model.id
            state = .ready
            logger.info("Model \(model.displayName) loaded successfully")
        } catch {
            whisperKit = nil
            loadedModelId = nil
            state = .error(error.localizedDescription)
            logger.error("Failed to load model: \(error.localizedDescription)")
        }
    }

    func unloadModel() {
        whisperKit = nil
        loadedModelId = nil
        state = .notLoaded
    }

    func deleteModel(_ model: WhisperModel) {
        if loadedModelId == model.id { unloadModel() }
        let path = modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.id)
        try? FileManager.default.removeItem(at: path)
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.id)
        return FileManager.default.fileExists(atPath: path.path)
    }

    func restoreLastModel() async {
        guard let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedModelId),
              let model = Self.availableModels.first(where: { $0.id == savedId }),
              isModelDownloaded(model) else { return }
        await loadModel(model)
    }

    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription {
        guard let whisperKit else {
            throw TranscriptionError.engineNotConfigured
        }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            chunkingStrategy: .vad
        )

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = results.first?.language
        let duration = results.flatMap { $0.segments }.last.map { TimeInterval($0.end) } ?? 0

        logger.info("Transcription: \(text.prefix(80))")
        return SottoTranscription(text: text, detectedLanguage: detectedLanguage, duration: duration)
    }
}

struct WhisperModel: Identifiable {
    let id: String
    let displayName: String
    let size: String
}

enum TranscriptionError: LocalizedError {
    case engineNotConfigured

    var errorDescription: String? {
        "No model loaded. Please download and select a model in Settings."
    }
}
