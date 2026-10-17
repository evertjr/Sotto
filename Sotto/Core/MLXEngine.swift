import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import HuggingFace
import os.log

private let logger = Logger(subsystem: "com.sotto.app", category: "MLXEngine")

@MainActor
final class MLXEngine: TranscriptionEngine {
    let engineName = "MLX Audio"

    private var model: (any STTGenerationModel)?
    private var loadedModelId: String?
    private let modelsDirectory: URL

    init() {
        self.modelsDirectory = AppConstants.appSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - TranscriptionEngine

    func loadModel(_ sottoModel: SottoModel, onPhaseChange: @escaping (LoadPhase) -> Void) async throws {
        guard let def = mlxModelDef(for: sottoModel) else {
            throw TranscriptionError.unknownModel(sottoModel.id)
        }

        let cache = HubCache(cacheDirectory: modelsDirectory)
        let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]

        guard let repoID = Repo.ID(rawValue: def.repoId) else {
            throw MLXEngineError.invalidRepoId(def.repoId)
        }

        let client: HubClient
        if let hfToken, !hfToken.isEmpty {
            client = HubClient(host: HubClient.defaultHost, bearerToken: hfToken, cache: cache)
        } else {
            client = HubClient(cache: cache)
        }
        let resolvedCache = client.cache ?? cache

        // Download with progress reporting using the lower-level overload
        // that accepts a progressHandler.
        let modelDir = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: resolvedCache,
            repoID: repoID,
            requiredExtension: "safetensors",
            progressHandler: { @MainActor progress in
                let fraction = progress.totalUnitCount > 0
                    ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    : 0
                onPhaseChange(.downloading(progress: fraction))
            }
        )

        try Task.checkCancellation()
        onPhaseChange(.loading)

        // Load from the already-downloaded directory instead of calling
        // fromPretrained, which would re-download without progress reporting.
        let loaded: any STTGenerationModel
        switch def.architecture {
        case .qwen3:
            loaded = try await Qwen3ASRModel.fromModelDirectory(modelDir)
        case .senseVoice:
            loaded = try SenseVoiceModel.fromDirectory(modelDir)
        }

        try Task.checkCancellation()

        self.model = loaded
        loadedModelId = sottoModel.id
        logger.info("MLX model loaded: \(sottoModel.displayName) (\(def.architecture.rawValue))")
    }

    func unloadModel() {
        model = nil
        loadedModelId = nil
    }

    func deleteModel(_ sottoModel: SottoModel) {
        guard let def = mlxModelDef(for: sottoModel) else { return }
        let modelSubdir = def.repoId.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = modelsDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
        try? FileManager.default.removeItem(at: mlxAudioDir)
        let hubDir = modelsDirectory
            .appendingPathComponent("models--" + def.repoId.replacingOccurrences(of: "/", with: "--"))
        try? FileManager.default.removeItem(at: hubDir)
    }

    func isModelDownloaded(_ sottoModel: SottoModel) -> Bool {
        guard let def = mlxModelDef(for: sottoModel) else { return false }
        let modelSubdir = def.repoId.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = modelsDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mlxAudioDir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // Verify there's at least one non-zero safetensors file
        let files = try? FileManager.default.contentsOfDirectory(at: mlxAudioDir, includingPropertiesForKeys: [.fileSizeKey])
        return files?.contains { file in
            guard file.pathExtension == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        } ?? false
    }

    func transcribe(samples: [Float], language: String?) async throws -> SottoTranscription {
        guard let model else { throw TranscriptionError.engineNotConfigured }

        // Cheap signal check. A silent buffer decodes to an empty string with no
        // error, so log enough to tell "bad audio in" apart from "bad decode".
        let peak = samples.reduce(Float(0)) { Swift.max($0, Swift.abs($1)) }
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(Swift.max(samples.count, 1))).squareRoot()
        logger.info("Transcribing \(samples.count) samples (peak=\(peak), rms=\(rms), language=\(language ?? "nil"))")

        let params = STTGenerateParameters(
            maxTokens: 8192,
            temperature: 0.0,
            language: language
        )

        // The app is LSUIElement, so during push-to-talk it is a background app and
        // eligible for App Nap, which the debugger and an open Settings window both
        // suppress. Assert the work is user-initiated for its whole duration.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Speech transcription"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        // MLX is not thread safe: array creation, graph building and evaluation must
        // all happen on one thread. Task.detached hands out an arbitrary cooperative
        // pool thread per call, and building the MLXArray here on the MainActor split
        // the work across two of them. Everything MLX touches runs on mlxQueue instead.
        let boxedModel = UncheckedBox(model)
        let output: STTOutput = await withCheckedContinuation { continuation in
            Self.mlxQueue.async {
                let audioArray = MLXArray(samples)
                continuation.resume(returning: boxedModel.value.generate(
                    audio: audioArray,
                    generationParameters: params
                ))
            }
        }

        let text = output.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            logger.error("Model decoded no tokens for \(samples.count) samples (peak=\(peak), rms=\(rms))")
        }

        return SottoTranscription(
            text: text,
            detectedLanguage: output.language,
            duration: output.totalTime
        )
    }

    /// Single thread for every MLX call. See the note in `transcribe`.
    private static let mlxQueue = DispatchQueue(label: "com.sotto.mlx", qos: .userInitiated)

    // MARK: - Model Definitions

    struct MLXModelDef {
        let repoId: String
        let architecture: Architecture

        enum Architecture: String {
            case qwen3
            case senseVoice
        }
    }

    private func mlxModelDef(for sottoModel: SottoModel) -> MLXModelDef? {
        switch sottoModel.id {
        case "qwen3-asr-0.6b":
            MLXModelDef(repoId: "mlx-community/Qwen3-ASR-0.6B-8bit", architecture: .qwen3)
        case "qwen3-asr-1.7b":
            MLXModelDef(repoId: "mlx-community/Qwen3-ASR-1.7B-4bit", architecture: .qwen3)
        case "sensevoice-small":
            MLXModelDef(repoId: "mlx-community/SenseVoiceSmall", architecture: .senseVoice)
        default:
            nil
        }
    }
}

/// Carries a non-Sendable model reference onto `mlxQueue`. Safe because the queue is
/// serial and is the only place the model is ever used. `nonisolated` opts out of the
/// target's default MainActor isolation so the queue can read `value`.
nonisolated private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

enum MLXEngineError: LocalizedError {
    case invalidRepoId(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepoId(let id):
            return "Invalid HuggingFace repository ID: \(id)"
        }
    }
}
