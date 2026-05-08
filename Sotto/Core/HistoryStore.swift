import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.sotto.app", category: "HistoryStore")

struct HistoryEntry: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var date: Date
    var text: String
    var originalText: String
    var durationSeconds: Double
    var language: String?
    var modelName: String?
    var audioFileName: String?

    var hasAIChanges: Bool {
        let trimmedFinal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedOriginal.isEmpty && trimmedOriginal != trimmedFinal
    }
}

@Observable
@MainActor
final class HistoryStore {
    static let maxEntries = 100
    private static let sampleRate: Double = 16_000

    private(set) var entries: [HistoryEntry] = []

    private let directory: URL
    private let audioDirectory: URL
    private let indexURL: URL

    init() {
        let base = AppConstants.appSupportDirectory.appendingPathComponent("History", isDirectory: true)
        self.directory = base
        self.audioDirectory = base.appendingPathComponent("audio", isDirectory: true)
        self.indexURL = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    func audioURL(for entry: HistoryEntry) -> URL? {
        guard let name = entry.audioFileName else { return nil }
        return audioDirectory.appendingPathComponent(name)
    }

    func hasAudioFile(for entry: HistoryEntry) -> Bool {
        guard let url = audioURL(for: entry) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func record(
        samples: [Float],
        text: String,
        originalText: String,
        durationSeconds: Double,
        language: String?,
        modelName: String?
    ) {
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        let audioURL = audioDirectory.appendingPathComponent(fileName)

        let entry = HistoryEntry(
            id: id,
            date: Date(),
            text: text,
            originalText: originalText,
            durationSeconds: durationSeconds,
            language: language,
            modelName: modelName,
            audioFileName: fileName
        )
        entries.insert(entry, at: 0)
        pruneIfNeeded()
        saveToDisk()

        Task.detached(priority: .utility) {
            do {
                try writeWavFile(samples: samples, sampleRate: HistoryStore.sampleRate, to: audioURL)
            } catch {
                logger.error("Failed to write history audio for \(id): \(error.localizedDescription)")
            }
        }
    }

    func delete(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = entries.remove(at: index)
        if let url = audioURL(for: removed) {
            try? FileManager.default.removeItem(at: url)
        }
        saveToDisk()
    }

    func clearAll() {
        for entry in entries {
            if let url = audioURL(for: entry) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        entries.removeAll()
        saveToDisk()
    }

    private func pruneIfNeeded() {
        while entries.count > Self.maxEntries {
            let removed = entries.removeLast()
            if let url = audioURL(for: removed) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            logger.error("Failed to load history index: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save history index: \(error.localizedDescription)")
        }
    }
}

private func writeWavFile(samples: [Float], sampleRate: Double, to url: URL) throws {
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    ) else {
        throw NSError(
            domain: "Sotto.HistoryStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Cannot create audio format"]
        )
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
    ) else {
        throw NSError(
            domain: "Sotto.HistoryStore",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Cannot allocate audio buffer"]
        )
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        guard let dst = buffer.floatChannelData?[0], let base = src.baseAddress else { return }
        dst.update(from: base, count: samples.count)
    }
    try file.write(from: buffer)
}
