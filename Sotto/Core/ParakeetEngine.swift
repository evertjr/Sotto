import Foundation
import FluidAudio
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "ParakeetEngine")

@MainActor
final class ParakeetEngine: TranscriptionEngine {
    let engineName = "Parakeet"

    private var asrManager: AsrManager?

    func loadModel(_ model: SottoModel, onPhaseChange: @escaping (LoadPhase) -> Void) async throws {
        let version = parakeetVersion(for: model)

        onPhaseChange(.downloading(progress: 0.1))
        let models = try await AsrModels.downloadAndLoad(version: version)
        try Task.checkCancellation()
        onPhaseChange(.loading)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        try Task.checkCancellation()

        asrManager = manager
        logger.info("Parakeet model loaded: \(model.displayName)")
    }

    func unloadModel() {
        asrManager = nil
    }

    func deleteModel(_ model: SottoModel) {
        let version = parakeetVersion(for: model)
        let cacheDir = AsrModels.defaultCacheDirectory(for: version)
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func isModelDownloaded(_ model: SottoModel) -> Bool {
        let version = parakeetVersion(for: model)
        let cacheDir = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: cacheDir, version: version)
    }

    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription {
        guard let asrManager else { throw TranscriptionError.engineNotConfigured }

        let paddedSamples = samples.count < 16_000 ? samples + [Float](repeating: 0, count: 16_000 - samples.count) : samples

        let fluidLanguage: Language? = language.flatMap { code in
            let primary = code.split(separator: "-").first.map(String.init) ?? code
            return Language(rawValue: primary.lowercased())
        }

        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            paddedSamples,
            decoderState: &decoderState,
            language: fluidLanguage
        )

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = result.tokenTimings?.last.map { TimeInterval($0.endTime) } ?? 0

        return SottoTranscription(text: text, detectedLanguage: nil, duration: duration)
    }

    private func parakeetVersion(for model: SottoModel) -> AsrModelVersion {
        model.id.contains("v3") ? .v3 : .v2
    }
}
