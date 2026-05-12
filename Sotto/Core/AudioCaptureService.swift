import AppKit
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: "com.sotto.app", category: "AudioCapture")

@Observable
final class AudioCaptureService: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case microphonePermissionDenied
        case noMicrophoneDetected
        case engineStartFailed(String)
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                "Microphone permission denied. Please grant access in System Settings."
            case .noMicrophoneDetected:
                "No microphone detected."
            case .engineStartFailed(let detail):
                "Failed to start audio engine: \(detail)"
            case .noAudioData:
                "No audio data was recorded."
            }
        }
    }

    private(set) var isCapturing = false
    private(set) var audioLevel: Float = 0
    private(set) var micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    private(set) var waveformLevels: [Float] = Array(repeating: 0, count: 40)

    var selectedDeviceID: AudioDeviceID?

    private var engine: AVAudioEngine?
    private var configChangeObserver: NSObjectProtocol?
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.sotto.audio-processing", qos: .userInteractive)
    private var restartAttempt = 0
    private static let maxRestartAttempts = 3
    private static let targetSampleRate: Double = 16_000
    private static let captureTapFrames: AVAudioFrameCount = 1024
    private static let retryDelays: [TimeInterval] = [0.15, 0.30, 0.50]

    var hasMicrophonePermission: Bool { micPermissionGranted }

    func requestMicrophonePermission() async -> Bool {
        if micPermissionGranted { return true }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micPermissionGranted = granted
        return granted
    }

    var totalBufferDuration: TimeInterval {
        bufferLock.withLock {
            Double(sampleBuffer.count) / Self.targetSampleRate
        }
    }

    func getCurrentBuffer() -> [Float] {
        bufferLock.withLock { Array(sampleBuffer) }
    }

    func getRecentBuffer(maxDuration: TimeInterval) -> [Float] {
        bufferLock.withLock {
            let maxSamples = Int(maxDuration * Self.targetSampleRate)
            if sampleBuffer.count <= maxSamples { return sampleBuffer }
            return Array(sampleBuffer.suffix(maxSamples))
        }
    }

    func getBufferDelta(since sampleOffset: Int) -> (samples: [Float], nextOffset: Int) {
        bufferLock.withLock {
            let clamped = max(0, min(sampleOffset, sampleBuffer.count))
            let samples = Array(sampleBuffer.dropFirst(clamped))
            return (samples, sampleBuffer.count)
        }
    }

    // MARK: - Start / Stop

    func startCapture() throws {
        guard hasMicrophonePermission else {
            throw CaptureError.microphonePermissionDenied
        }

        clearBuffer()
        restartAttempt = 0
        try buildAndStartEngine()
    }

    func stopCapture() -> [Float] {
        removeConfigChangeObserver()

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }

        processingQueue.sync {}

        let samples = drainBuffer()
        isCapturing = false
        audioLevel = 0
        return samples
    }

    // MARK: - Engine Setup

    private func buildAndStartEngine() throws {
        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode

        if let deviceID = selectedDeviceID {
            do {
                try inputNode.auAudioUnit.setDeviceID(deviceID)
            } catch {
                logger.warning("Failed to bind input to device \(deviceID), falling back to default: \(error.localizedDescription)")
            }
        }

        let inputFormat = try Self.validInputFormat(
            inputNode.outputFormat(forBus: 0),
            failureMessage: "No audio input available"
        )
        let tapFormat = Self.monoTapFormat(for: inputFormat)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.engineStartFailed("Cannot create target audio format")
        }
        guard let converter = AVAudioConverter(from: tapFormat, to: targetFormat) else {
            throw CaptureError.engineStartFailed("Cannot create audio converter")
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: Self.captureTapFrames, format: tapFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try startEngineWithRetry(newEngine)
        } catch {
            inputNode.removeTap(onBus: 0)
            newEngine.stop()
            throw error
        }

        engine = newEngine
        installConfigChangeObserver(for: newEngine)
        isCapturing = true
        logger.info("Audio capture started")
    }

    private static func validInputFormat(
        _ format: AVAudioFormat,
        failureMessage: String
    ) throws -> AVAudioFormat {
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.engineStartFailed(failureMessage)
        }
        return format
    }

    private static func monoTapFormat(for inputFormat: AVAudioFormat) -> AVAudioFormat {
        if inputFormat.channelCount > 1,
           let mono = AVAudioFormat(
               commonFormat: .pcmFormatFloat32,
               sampleRate: inputFormat.sampleRate,
               channels: 1,
               interleaved: false
           ) {
            return mono
        }
        return inputFormat
    }

    private func startEngineWithRetry(_ engine: AVAudioEngine) throws {
        var lastError: Error?
        for (index, delay) in Self.retryDelays.enumerated() {
            do {
                try engine.start()
                return
            } catch {
                lastError = error
                logger.warning("Engine start attempt \(index + 1) failed: \(error.localizedDescription)")
                Thread.sleep(forTimeInterval: delay)
            }
        }
        throw CaptureError.engineStartFailed(lastError?.localizedDescription ?? "Unknown error")
    }

    // MARK: - Config Change Recovery

    private func installConfigChangeObserver(for engine: AVAudioEngine) {
        removeConfigChangeObserver()
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigChange()
        }
    }

    private func removeConfigChangeObserver() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
    }

    private func handleConfigChange() {
        guard isCapturing else { return }

        restartAttempt += 1
        guard restartAttempt <= Self.maxRestartAttempts else {
            logger.error("Config change recovery exceeded \(Self.maxRestartAttempts) attempts, giving up")
            isCapturing = false
            return
        }

        logger.info("Engine config changed, restarting (attempt \(self.restartAttempt))")

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        removeConfigChangeObserver()

        do {
            try buildAndStartEngine()
        } catch {
            logger.error("Engine restart failed: \(error.localizedDescription)")
            isCapturing = false
        }
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * Self.targetSampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        let consumed = OSAllocatedUnfairLock(initialState: false)

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            let wasConsumed = consumed.withLock { flag in
                let prev = flag
                flag = true
                return prev
            }
            if wasConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, convertedBuffer.frameLength > 0 else { return }
        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))

        processingQueue.async { [weak self] in
            self?.processConvertedSamples(samples)
        }
    }

    private func processConvertedSamples(_ samples: [Float]) {
        bufferLock.withLock {
            sampleBuffer.append(contentsOf: samples)
        }

        let chunkSize = max(1, samples.count / 4)
        var levels: [Float] = []
        for start in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(start + chunkSize, samples.count)
            let chunk = samples[start..<end]
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            levels.append(AudioLevelMeter.normalizedLevel(rms: rms))
        }

        let overallRms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let overallLevel = AudioLevelMeter.normalizedLevel(rms: overallRms)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioLevel = overallLevel
            let drop = min(levels.count, self.waveformLevels.count)
            self.waveformLevels.removeFirst(drop)
            self.waveformLevels.append(contentsOf: levels)
        }
    }

    // MARK: - Buffer Management

    private func clearBuffer() {
        bufferLock.withLock {
            sampleBuffer.removeAll()
        }
    }

    private func drainBuffer() -> [Float] {
        bufferLock.withLock {
            let samples = sampleBuffer
            sampleBuffer.removeAll()
            return samples
        }
    }
}

// MARK: - Utilities

enum AudioLevelMeter {
    private static let minimumDecibels: Float = -55
    private static let maximumDecibels: Float = -18

    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels > minimumDecibels else { return 0 }
        let normalized = (decibels - minimumDecibels) / (maximumDecibels - minimumDecibels)
        return min(1, max(0, normalized))
    }
}
