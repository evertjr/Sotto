import AVFoundation
import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @State private var player: AVAudioPlayer?
    @State private var playingId: UUID?
    @State private var copiedId: UUID?

    var body: some View {
        let entries = coordinator.historyStore.entries

        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(entries) { entry in
                        HistoryRow(
                            entry: entry,
                            isPlaying: playingId == entry.id,
                            isCopied: copiedId == entry.id,
                            audioURL: coordinator.historyStore.audioURL(for: entry),
                            onPlay: { play(entry) },
                            onStop: stop,
                            onCopy: { copy(entry) },
                            onDelete: {
                                if playingId == entry.id { stop() }
                                coordinator.historyStore.delete(entry)
                            }
                        )
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        stop()
                        coordinator.historyStore.clearAll()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .onDisappear { stop() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .font(.headline)
            Text("Your recent dictations will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func play(_ entry: HistoryEntry) {
        stop()
        guard let url = coordinator.historyStore.audioURL(for: entry),
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            playingId = entry.id
        } catch {
            playingId = nil
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        let id = entry.id
        copiedId = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedId == id { copiedId = nil }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isPlaying: Bool
    let isCopied: Bool
    let audioURL: URL?
    let onPlay: () -> Void
    let onStop: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let model = entry.modelName, !model.isEmpty {
                    dot
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let language = entry.language, !language.isEmpty {
                    dot
                    Text(language.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(durationString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.hasAIChanges {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Text(entry.originalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 2)
            }

            HStack(spacing: 8) {
                if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        isPlaying ? onStop() : onPlay()
                    } label: {
                        Label(
                            isPlaying ? "Stop" : "Play",
                            systemImage: isPlaying ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: onCopy) {
                    Label(
                        isCopied ? "Copied" : "Copy",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var dot: some View {
        Text("•")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var durationString: String {
        let secs = entry.durationSeconds
        if secs < 60 { return String(format: "%.1fs", secs) }
        let m = Int(secs / 60)
        let s = Int(secs.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", m, s)
    }
}
