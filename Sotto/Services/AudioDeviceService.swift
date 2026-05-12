import Foundation
import CoreAudio
import AudioToolbox
@preconcurrency import AVFoundation
import Combine
import IOKit
import os

private let logger = Logger(subsystem: "com.sotto.app", category: "AudioDeviceService")

struct AudioInputDevice: Identifiable, Equatable {
    let deviceID: AudioDeviceID
    let name: String
    let uid: String
    let isContinuity: Bool

    var id: String { uid }
}

@Observable
@MainActor
final class AudioDeviceService: @unchecked Sendable {
    var inputDevices: [AudioInputDevice] = []
    var selectedDeviceUID: String? {
        didSet {
            guard selectedDeviceUID != oldValue else { return }
            UserDefaults.standard.set(selectedDeviceUID, forKey: "selectedInputDeviceUID")
            if isPreviewActive {
                stopPreview()
                startPreview()
            }
        }
    }
    var isPreviewActive = false
    var previewAudioLevel: Float = 0

    var selectedDeviceID: AudioDeviceID? {
        guard let uid = selectedDeviceUID else { return nil }
        return Self.audioDeviceID(fromUID: uid)
    }

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var previewEngine: AVAudioEngine?
    private var previewConfigChangeObserver: NSObjectProtocol?
    private let deviceChangeSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var previewRestartAttempt = 0

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID")
        inputDevices = listInputDevices()
        installDeviceListener()

        deviceChangeSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleDeviceChange()
            }
            .store(in: &cancellables)
    }

    nonisolated deinit {
        // Cleanup is handled by the service owner
    }

    // MARK: - Preview

    func startPreview() {
        guard !isPreviewActive else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else { return }

        previewRestartAttempt = 0

        do {
            try buildPreviewEngine()
            isPreviewActive = true
        } catch {
            logger.error("Preview start failed: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        removePreviewConfigObserver()
        if let engine = previewEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            previewEngine = nil
        }
        isPreviewActive = false
        previewAudioLevel = 0
    }

    private func buildPreviewEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = try Self.validInputFormat(
            inputNode.outputFormat(forBus: 0),
            failureMessage: "No audio input available for preview"
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0..<frames { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(frames))
            let level = AudioLevelMeter.normalizedLevel(rms: rms)
            DispatchQueue.main.async { self?.previewAudioLevel = level }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            throw error
        }

        previewEngine = engine
        installPreviewConfigObserver(for: engine)
    }

    private static func validInputFormat(
        _ format: AVAudioFormat,
        failureMessage: String
    ) throws -> AVAudioFormat {
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "AudioDeviceService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: failureMessage]
            )
        }
        return format
    }

    private func installPreviewConfigObserver(for engine: AVAudioEngine) {
        removePreviewConfigObserver()
        previewConfigChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handlePreviewConfigChange() }
        }
    }

    private func removePreviewConfigObserver() {
        if let observer = previewConfigChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            previewConfigChangeObserver = nil
        }
    }

    private func handlePreviewConfigChange() {
        guard isPreviewActive else { return }
        previewRestartAttempt += 1
        guard previewRestartAttempt <= 3 else {
            logger.error("Preview config change recovery exceeded 3 attempts")
            stopPreview()
            return
        }

        logger.info("Preview config changed, restarting (attempt \(self.previewRestartAttempt))")
        if let engine = previewEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            previewEngine = nil
        }
        removePreviewConfigObserver()

        do {
            try buildPreviewEngine()
        } catch {
            logger.error("Preview restart failed: \(error.localizedDescription)")
            stopPreview()
        }
    }

    // MARK: - Device Enumeration

    private func listInputDevices() -> [AudioInputDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceIDs
        )
        guard status == noErr else { return [] }

        var devices: [AudioInputDevice] = []
        for id in deviceIDs {
            guard Self.isInputDeviceAvailable(id) else { continue }
            guard let name = Self.deviceName(for: id),
                  let uid = Self.deviceUID(for: id) else { continue }
            let lowerName = name.lowercased()
            if lowerName.contains("cadefault") || lowerName.contains("aggregate") { continue }
            let isContinuity = Self.isContinuityCaptureDevice(id)
            devices.append(AudioInputDevice(deviceID: id, name: name, uid: uid, isContinuity: isContinuity))
        }
        return devices
    }

    var firstContinuityInputDevice: AudioInputDevice? {
        inputDevices.first(where: { $0.isContinuity })
    }

    /// True when the system default input device is missing, has no input channels,
    /// or is the laptop built-in mic with the lid closed (clamshell mode).
    static var isDefaultInputUsable: Bool {
        var defaultDevice: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &defaultDevice
        )
        guard status == noErr, defaultDevice != 0 else { return false }
        guard isInputDeviceAvailable(defaultDevice) else { return false }
        if isLaptopLidClosed, transportType(of: defaultDevice) == kAudioDeviceTransportTypeBuiltIn {
            return false
        }
        return true
    }

    private static var isLaptopLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let raw = IORegistryEntryCreateCFProperty(
            root,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return false }
        return (raw as? Bool) ?? false
    }

    private static func isContinuityCaptureDevice(_ deviceID: AudioDeviceID) -> Bool {
        let t = transportType(of: deviceID)
        return t == kAudioDeviceTransportTypeContinuityCaptureWireless
            || t == kAudioDeviceTransportTypeContinuityCaptureWired
    }

    private static func transportType(of deviceID: AudioDeviceID) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private static func isInputDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return false }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPointer)
        guard getStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPointer.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in bufferList { channels += Int(buffer.mNumberChannels) }
        return channels > 0
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return getCFStringProperty(deviceID: deviceID, address: &address)
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return getCFStringProperty(deviceID: deviceID, address: &address)
    }

    private static func getCFStringProperty(deviceID: AudioDeviceID, address: inout AudioObjectPropertyAddress) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let cf = value else { return nil }
        return cf.takeUnretainedValue() as String
    }

    static func audioDeviceID(fromUID uid: String) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: Unmanaged<CFString>? = Unmanaged.passUnretained(uid as CFString)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &cfUID,
            &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    // MARK: - Device Change Monitoring

    private func installDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.deviceChangeSubject.send()
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceListener() {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        listenerBlock = nil
    }

    private func handleDeviceChange() {
        let newDevices = listInputDevices()
        inputDevices = newDevices

        if let uid = selectedDeviceUID,
           !newDevices.contains(where: { $0.uid == uid }) {
            logger.info("Selected device disconnected")
            selectedDeviceUID = nil
            if isPreviewActive { stopPreview() }
        }
    }
}
