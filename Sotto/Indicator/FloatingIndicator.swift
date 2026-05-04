import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingIndicatorController {
    private var panel: NSPanel?
    private var stateSubscription: AnyCancellable?

    func startObserving(_ coordinator: DictationCoordinator) {
        stateSubscription = coordinator.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateVisibility(state: state, coordinator: coordinator)
            }
    }

    private func updateVisibility(state: DictationCoordinator.State, coordinator: DictationCoordinator) {
        switch state {
        case .idle, .inserting:
            dismiss()
        case .recording, .processing, .error:
            show(coordinator: coordinator)
        }
    }

    private func show(coordinator: DictationCoordinator) {
        if panel != nil { return }

        let view = FloatingPillContainer(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: view)
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 60
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        panel.alphaValue = 0

        positionPanel(panel)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    private func dismiss() {
        guard let panel else { return }
        let panelRef = panel
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panelRef.animator().alphaValue = 0
        }, completionHandler: {
            panelRef.orderOut(nil)
        })
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - panel.frame.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Container

private struct FloatingPillContainer: View {
    let coordinator: DictationCoordinator

    var body: some View {
        FloatingPillView(coordinator: coordinator)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pill

private struct FloatingPillView: View {
    let coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .recording:
                recordingContent
            case .processing:
                statusContent(icon: nil, text: "Transcribing...", showSpinner: true)
            case .inserting:
                EmptyView()
            case .error(let message):
                statusContent(icon: nil, text: message, showSpinner: false)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black, in: Capsule())
        .fixedSize()
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: coordinator.state)
    }

    private var recordingContent: some View {
        AuroraWaveform(level: coordinator.audioLevel)
            .frame(width: 140, height: 28)
    }

    private func statusContent(icon: String?, text: String, showSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showSpinner {
                ProgressView().controlSize(.small)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
            }
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .lineLimit(1)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

