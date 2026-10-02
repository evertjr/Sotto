import SwiftUI
import UniformTypeIdentifiers

struct RecorderTranscriberView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @State private var viewModel = RecorderTranscriberViewModel()
    @State private var showFilePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                modelStatusSection
                recordingSection
                fileImportSection
                resultSection
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            viewModel.modelManager = coordinator.modelManager
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .aiff, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.transcribeFile(at: url)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.badge.mic")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Transcribe Audio")
                .font(.title2.bold())
            Text("Record yourself or import an audio file, then copy the full transcription.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Model Status

    @ViewBuilder
    private var modelStatusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.canTranscribe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(viewModel.canTranscribe ? .green : .orange)
            if let name = viewModel.activeModelName {
                Text("Active model: \(name)")
                    .font(.callout)
            } else {
                Text("No model loaded — go to Settings → Model to download one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Recording

    @ViewBuilder
    private var recordingSection: some View {
        VStack(spacing: 12) {
            Text("Record")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                if case .recording = viewModel.phase {
                    Button(role: .destructive) {
                        viewModel.stopRecording()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    VStack(alignment: .leading) {
                        Text(formatDuration(viewModel.recordingDuration))
                            .font(.title3.monospacedDigit())
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Button {
                        viewModel.startRecording()
                    } label: {
                        Label("Record", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - File Import

    @ViewBuilder
    private var fileImportSection: some View {
        VStack(spacing: 12) {
            Text("Import File")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showFilePicker = true
            } label: {
                Label("Choose Audio File...", systemImage: "doc")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Supports WAV, MP3, M4A, AIFF, CAF")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .idle, .recording:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading audio file...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Transcribing...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .done(let text):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transcription")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.copyText()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))

                if viewModel.recordingDuration > 0 {
                    Text("Duration: \(formatDuration(viewModel.recordingDuration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.reset()
                } label: {
                    Label("New Transcription", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        case .error(let message):
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                }
                Button {
                    viewModel.reset()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
