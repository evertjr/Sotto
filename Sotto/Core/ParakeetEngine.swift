import Foundation
import FluidAudio
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "ParakeetEngine")

@MainActor
final class ParakeetEngine: TranscriptionEngine {
    let engineName = "Parakeet"

    private var asrManager: AsrManager?

    init() {
        removeRetiredModels()
    }

    func loadModel(_ model: SottoModel, onPhaseChange: @escaping (LoadPhase) -> Void) async throws {
        guard let version = parakeetVersion(for: model) else {
            throw TranscriptionError.unknownModel(model.id)
        }

        onPhaseChange(.downloading(progress: 0))
        let models = try await AsrModels.downloadAndLoad(version: version) { progress in
            switch progress.phase {
            case .listing, .downloading:
                onPhaseChange(.downloading(progress: progress.fractionCompleted))
            case .compiling:
                onPhaseChange(.loading)
            }
        }
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
        guard let version = parakeetVersion(for: model) else { return }
        let cacheDir = AsrModels.defaultCacheDirectory(for: version)
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func isModelDownloaded(_ model: SottoModel) -> Bool {
        guard let version = parakeetVersion(for: model) else { return false }
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

    private func parakeetVersion(for model: SottoModel) -> AsrModelVersion? {
        switch model.id {
        case "parakeet-tdt-0.6b-v2": .v2
        case "parakeet-ultra": .ultra
        case "phonon-2": .phonon2
        default: nil
        }
    }

    /// Versions Sotto used to ship. Nothing in the model list can delete them anymore,
    /// so their files are removed here. Parakeet v3 was replaced by Ultra.
    private static let retiredVersions: [AsrModelVersion] = [.v3]

    private func removeRetiredModels() {
        for version in Self.retiredVersions {
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            guard FileManager.default.fileExists(atPath: cacheDir.path) else { continue }
            do {
                try FileManager.default.removeItem(at: cacheDir)
                logger.info("Removed retired model files at \(cacheDir.path)")
            } catch {
                logger.error("Could not remove retired model files: \(error.localizedDescription)")
            }
        }
    }
}
