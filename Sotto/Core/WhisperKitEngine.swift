import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "WhisperKitEngine")

@MainActor
final class WhisperKitEngine: TranscriptionEngine {
    let engineName = "WhisperKit"

    private var whisperKit: WhisperKit?
    private let modelsDirectory: URL

    init() {
        self.modelsDirectory = AppConstants.appSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    func loadModel(_ model: SottoModel, onProgress: @escaping (Double) -> Void) async throws {
        let modelPath = modelPath(for: model)

        let modelFolder: URL
        if FileManager.default.fileExists(atPath: modelPath.path) {
            modelFolder = modelPath
        } else {
            modelFolder = try await WhisperKit.download(
                variant: model.id,
                downloadBase: modelsDirectory
            ) { progress in
                onProgress(progress.fractionCompleted)
            }
        }

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
        logger.info("WhisperKit model loaded: \(model.displayName)")
    }

    func unloadModel() {
        whisperKit = nil
    }

    func deleteModel(_ model: SottoModel) {
        let path = modelPath(for: model)
        try? FileManager.default.removeItem(at: path)
    }

    func isModelDownloaded(_ model: SottoModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription {
        guard let whisperKit else { throw TranscriptionError.engineNotConfigured }

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

        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = results.first?.language
        let duration = results.flatMap { $0.segments }.last.map { TimeInterval($0.end) } ?? 0

        return SottoTranscription(text: text, detectedLanguage: detectedLanguage, duration: duration)
    }

    private func modelPath(for model: SottoModel) -> URL {
        modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.id)
    }
}
