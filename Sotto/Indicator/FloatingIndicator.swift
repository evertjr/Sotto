import AppKit
import AVFoundation
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
        let screenHasNotch = NSScreen.main?.safeAreaInsets.top ?? 0 > 0
        let shouldShow: Bool
        switch state {
        case .recording, .processing:
            shouldShow = coordinator.indicatorStyle == .pill || (coordinator.indicatorStyle == .notch && !screenHasNotch)
        default:
            shouldShow = false
        }

        if shouldShow {
            showIfNeeded(coordinator: coordinator)
        } else {
            dismissIfNeeded()
        }
    }

    private func showIfNeeded(coordinator: DictationCoordinator) {
        guard panel == nil else { return }

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

        positionPanel(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func dismissIfNeeded() {
        guard let panel else { return }
        self.panel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            panel.orderOut(nil)
        }
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
    @State private var appeared = false

    private var shouldShow: Bool {
        switch coordinator.state {
        case .recording, .processing: true
        default: false
        }
    }

    var body: some View {
        FloatingPillView(coordinator: coordinator)
            .scaleEffect(appeared && shouldShow ? 1 : 0.7)
            .blur(radius: appeared && shouldShow ? 0 : 12)
            .opacity(appeared && shouldShow ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: appeared)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShow)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    appeared = true
                }
            }
            .onChange(of: shouldShow) { _, show in
                if !show {
                    appeared = false
                }
            }
    }
}

// MARK: - Pill

private struct FloatingPillView: View {
    let coordinator: DictationCoordinator

    var body: some View {
        ZStack {
            AuroraWaveform(level: coordinator.audioLevel, preset: coordinator.waveformPreset)
                .frame(width: 140, height: 28)

            if coordinator.isRefining {
                Capsule()
                    .fill(.black.opacity(0.5))
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .frame(width: 140, height: 28)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black, in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: coordinator.isRefining)
    }
}
