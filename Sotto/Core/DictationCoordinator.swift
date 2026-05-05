import AppKit
import AVFoundation
import Combine
import Foundation
import os

private let logger = Logger(subsystem: "com.sotto.app", category: "Dictation")

@Observable
@MainActor
final class DictationCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case inserting
        case error(String)
    }

    // MARK: - Published State

    var state: State = .idle
    var audioLevel: Float = 0
    var recordingDuration: TimeInterval = 0
    var partialText: String = ""
    var lastTranscribedText: String?
    var isRefining = false
    var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: UserDefaultsKeys.soundFeedbackEnabled) }
    }
    var waveformPreset: WaveformColorPreset {
        didSet { UserDefaults.standard.set(waveformPreset.rawValue, forKey: UserDefaultsKeys.waveformColorPreset) }
    }
    var indicatorStyle: IndicatorStyle {
        didSet { UserDefaults.standard.set(indicatorStyle.rawValue, forKey: UserDefaultsKeys.indicatorStyle) }
    }
    var polishEnabled: Bool {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: UserDefaultsKeys.refineEnabled) }
    }
    var translateEnabled: Bool {
        didSet { UserDefaults.standard.set(translateEnabled, forKey: UserDefaultsKeys.translateEnabled) }
    }
    var translateTargetLanguage: String {
        didSet { UserDefaults.standard.set(translateTargetLanguage, forKey: UserDefaultsKeys.translateTargetLanguage) }
    }

    let statePublisher = PassthroughSubject<State, Never>()

    // MARK: - Services

    let audioCaptureService: AudioCaptureService
    let textInsertionService: TextInsertionService
    let hotkeyService: HotkeyService
    let modelManager: ModelManager
    let aiService: AIService
    let audioDeviceService: AudioDeviceService

    // MARK: - Private

    private var transcriptionTask: Task<Void, Never>?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var errorResetTask: Task<Void, Never>?
    private var insertingResetTask: Task<Void, Never>?
    private var isStopInFlight = false
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Init

    init() {
        self.audioCaptureService = AudioCaptureService()
        self.textInsertionService = TextInsertionService()
        self.hotkeyService = HotkeyService()
        self.modelManager = ModelManager()
        self.audioDeviceService = AudioDeviceService()
        self.aiService = AIService()

        self.soundFeedbackEnabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.soundFeedbackEnabled) as? Bool ?? true
        self.waveformPreset = UserDefaults.standard.string(forKey: UserDefaultsKeys.waveformColorPreset)
            .flatMap { WaveformColorPreset(rawValue: $0) } ?? .aurora
        let hasNotch = NSScreen.main?.safeAreaInsets.top ?? 0 > 0
        self.indicatorStyle = UserDefaults.standard.string(forKey: UserDefaultsKeys.indicatorStyle)
            .flatMap { IndicatorStyle(rawValue: $0) } ?? (hasNotch ? .notch : .pill)
        self.polishEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.refineEnabled)
        self.translateEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.translateEnabled)
        self.translateTargetLanguage = UserDefaults.standard.string(forKey: UserDefaultsKeys.translateTargetLanguage) ?? ""
    }

    private var floatingIndicator: FloatingIndicatorController?
    private var notchIndicator: NotchIndicatorController?

    func start() {
        setupBindings()
        hotkeyService.setup()

        let pill = FloatingIndicatorController()
        pill.startObserving(self)
        floatingIndicator = pill

        let notch = NotchIndicatorController()
        notch.startObserving(self)
        notchIndicator = notch

        Task { @MainActor in
            await modelManager.restoreLastModel()
        }
    }

    // MARK: - Hotkey Bindings

    private func setupBindings() {
        hotkeyService.onDictationStart = { [weak self] in
            self?.startDictation()
        }

        hotkeyService.onDictationStop = { [weak self] in
            self?.stopDictation()
        }

        hotkeyService.onCancelPressed = { [weak self] in
            self?.cancelDictation()
        }

        hotkeyService.discardPushToTalkRecordingOnExtraKeyPress = true
    }

    var canDictate: Bool {
        modelManager.canTranscribe
    }

    var needsMicPermission: Bool {
        !audioCaptureService.hasMicrophonePermission
    }

    var needsAccessibilityPermission: Bool {
        !textInsertionService.isAccessibilityGranted
    }

    // MARK: - Start Recording

    func startDictation() {
        Task { await _startDictation() }
    }

    private func _startDictation() async {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        insertingResetTask?.cancel()
        insertingResetTask = nil
        errorResetTask?.cancel()
        errorResetTask = nil

        guard canDictate else {
            showError("No model loaded. Please download and select a model first.")
            return
        }

        guard audioCaptureService.hasMicrophonePermission else {
            showError("Microphone permission required.")
            return
        }

        do {
            audioDeviceService.stopPreview()
            setState(.recording)

            if soundFeedbackEnabled {
                await playActivationSound()
            }

            audioCaptureService.selectedDeviceID = audioDeviceService.selectedDeviceID
            try audioCaptureService.startCapture()
            hotkeyService.resetKeyDownTime()
            partialText = ""
            isStopInFlight = false
            recordingStartTime = Date()
            startRecordingTimer()

            logger.info("Recording started")
        } catch {
            showError(error.localizedDescription)
            hotkeyService.cancelDictation()
        }
    }

    // MARK: - Stop Recording & Transcribe

    func stopDictation() {
        guard state == .recording, !isStopInFlight else { return }
        isStopInFlight = true

        Task {
            await finalizeStopDictation()
        }
    }

    private func finalizeStopDictation() async {
        stopRecordingTimer()

        let samples = audioCaptureService.stopCapture()

        guard !samples.isEmpty else {
            showError("No audio data was recorded.")
            return
        }

        let duration = Double(samples.count) / 16_000
        guard duration >= 0.3 else {
            showFeedback("Too short, hold the hotkey a bit longer")
            return
        }

        setState(.processing)

        transcriptionTask = Task {
            do {
                let language = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedLanguage)
                logger.info("Starting transcription with \(samples.count) samples")
                let result = try await modelManager.transcribe(samples: samples, language: language)
                logger.info("Transcription result: '\(result.text.prefix(100))'")

                guard !Task.isCancelled else { return }

                var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    resetState()
                    return
                }

                text = await processWithAI(text)
                guard !Task.isCancelled else { return }

                _ = try await textInsertionService.insertText(text, preserveClipboard: true)

                lastTranscribedText = text
                partialText = ""

                setState(.inserting)
                insertingResetTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    resetState()
                }
            } catch {
                guard !Task.isCancelled else { return }
                showError(error.localizedDescription)
            }
            self.transcriptionTask = nil
        }
    }

    // MARK: - Cancel

    func cancelDictation() {
        switch state {
        case .recording:
            _ = audioCaptureService.stopCapture()
            stopRecordingTimer()
            resetState()
        case .processing:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            resetState()
        default:
            break
        }
    }

    // MARK: - State Management

    private func setState(_ newState: State) {
        state = newState
        statePublisher.send(newState)
    }

    private func resetState() {
        errorResetTask?.cancel()
        insertingResetTask?.cancel()
        isStopInFlight = false
        recordingStartTime = nil
        partialText = ""
        setState(.idle)
    }

    private func showError(_ message: String) {
        setState(.error(message))
        errorResetTask?.cancel()
        errorResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            resetState()
        }
    }

    private func showFeedback(_ message: String) {
        setState(.error(message))
        errorResetTask?.cancel()
        errorResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            resetState()
        }
    }

    // MARK: - AI Processing

    private func processWithAI(_ text: String) async -> String {
        guard aiService.isAvailable else { return text }

        var result = text
        isRefining = true
        defer { isRefining = false }

        if polishEnabled {
            let input = result
            do {
                logger.info("Polishing transcription...")
                result = try await withAITimeout(seconds: 10) { [aiService] in
                    try await aiService.polish(input)
                }
                logger.info("Polished: '\(result.prefix(100))'")
            } catch {
                logger.warning("Polish failed, using original: \(error.localizedDescription)")
            }
        }

        if translateEnabled, !translateTargetLanguage.isEmpty {
            let input = result
            let targetLang = translateTargetLanguage
            do {
                logger.info("Translating to \(targetLang)...")
                result = try await withAITimeout(seconds: 15) { [aiService] in
                    try await aiService.translate(input, to: targetLang)
                }
                logger.info("Translated: '\(result.prefix(100))'")
            } catch {
                logger.warning("Translate failed, using previous: \(error.localizedDescription)")
            }
        }

        return result
    }

    // MARK: - Recording Timer

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
                self.audioLevel = self.audioCaptureService.audioLevel
            }
        }
    }

    private func playActivationSound() async {
        guard let url = Bundle.main.url(forResource: "recording_start", withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer = player
        player.play()
        try? await Task.sleep(for: .seconds(player.duration))
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
