import SwiftUI
@preconcurrency import AVFoundation
import UniformTypeIdentifiers

@Observable
@MainActor
final class RecorderTranscriberViewModel {
    enum Phase: Equatable { case idle, recording, loading, transcribing, done(String), error(String) }

    var phase: Phase = .idle
    var recordingDuration: TimeInterval = 0
    var audioLevel: Float = 0

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    // Reusable capture service for recording (separate from the dictation one
    // so we don't interfere with an active push-to-talk session).
    private let captureService = AudioCaptureService()

    var canTranscribe: Bool { modelManager?.isModelReady ?? false }
    var activeModelName: String? { modelManager?.activeModelName }

    weak var modelManager: ModelManager?

    // MARK: - Recording

    func startRecording() {
        guard captureService.hasMicrophonePermission else {
            phase = .error("Microphone permission required.")
            return
        }
        do {
            captureService.selectedDeviceID = nil
            try captureService.startCapture()
            recordingStartTime = Date()
            phase = .recording
            startTimer()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        let samples = captureService.stopCapture()
        recordingDuration = Double(samples.count) / 16_000
        audioLevel = 0

        guard !samples.isEmpty, recordingDuration >= 0.3 else {
            phase = .error("Recording too short.")
            return
        }
        transcribe(samples: samples)
    }

    // MARK: - File Import

    func transcribeFile(at url: URL) {
        phase = .loading
        Task {
            do {
                let samples = try await loadAudioSamples(from: url)
                guard !samples.isEmpty else {
                    phase = .error("No audio data in file.")
                    return
                }
                recordingDuration = Double(samples.count) / 16_000
                transcribe(samples: samples)
            } catch {
                phase = .error("Could not load audio: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transcription

    private func transcribe(samples: [Float]) {
        guard let mm = modelManager, mm.isModelReady else {
            phase = .error("No model loaded. Please download and select a model in Settings.")
            return
        }
        phase = .transcribing
        Task {
            do {
                let language = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedLanguage)
                let result = try await mm.transcribe(samples: samples, language: language)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = text.isEmpty ? .error("No speech detected.") : .done(text)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Utilities

    func copyText() {
        guard case .done(let text) = phase else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func reset() {
        phase = .idle
        recordingDuration = 0
    }

    var hasResult: Bool { if case .done = phase { return true } else { return false } }

    var resultText: String { if case .done(let t) = phase { return t } else { return "" } }

    var isBusy: Bool {
        switch phase {
        case .recording, .loading, .transcribing: true
        default: false
        }
    }

    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
                self.audioLevel = self.captureService.audioLevel
            }
        }
    }
}

// MARK: - Audio file loading

private func loadAudioSamples(from url: URL) async throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat

    guard let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ), let converter = AVAudioConverter(from: format, to: targetFormat) else {
        // Already 16kHz mono?
        if format.sampleRate == 16_000 && format.channelCount == 1 {
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return [Float]() }
            try file.read(into: buffer)
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        throw NSError(domain: "Recorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
    }

    let frameCount = AVAudioFrameCount(file.length)
    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw NSError(domain: "Recorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate input buffer"])
    }
    try file.read(into: inputBuffer)

    let ratio = targetFormat.sampleRate / format.sampleRate
    let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
        throw NSError(domain: "Recorder", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate output buffer"])
    }

    var error: NSError?
    var consumed = false
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        if consumed {
            outStatus.pointee = .noDataNow
            return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return inputBuffer
    }

    if let error { throw error }

    guard let channelData = outputBuffer.floatChannelData?[0] else { return [Float]() }
    return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
}
