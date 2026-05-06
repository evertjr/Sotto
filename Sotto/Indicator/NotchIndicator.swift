import AppKit
import Combine
import SwiftUI

// MARK: - Notch Shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Notch Geometry

@Observable
@MainActor
final class NotchGeometry {
    var notchWidth: CGFloat = 185
    var safeAreaTop: CGFloat = 0
    var hasNotch = false

    func update(for screen: NSScreen) {
        hasNotch = screen.safeAreaInsets.top > 0
        safeAreaTop = screen.safeAreaInsets.top
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - left - right + 4
        } else {
            notchWidth = 200
        }
    }
}

// MARK: - Controller

@MainActor
final class NotchIndicatorController {
    private var panel: NSPanel?
    private var stateSubscription: AnyCancellable?
    private let geometry = NotchGeometry()
    private static let panelSize: CGFloat = 500

    func startObserving(_ coordinator: DictationCoordinator) {
        stateSubscription = coordinator.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let isActive: Bool
                switch state {
                case .recording, .processing: isActive = true
                default: isActive = false
                }
                if isActive && coordinator.indicatorStyle == .notch {
                    self?.show(coordinator: coordinator)
                } else {
                    self?.dismiss()
                }
            }
    }

    private func show(coordinator: DictationCoordinator) {
        guard let screen = NSScreen.main else { return }
        geometry.update(for: screen)
        guard geometry.hasNotch else { return }
        if panel != nil { return }

        let view = NotchIndicatorContainer(coordinator: coordinator, geometry: geometry)
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []

        let size = Self.panelSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.level = .statusBar + 1
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView

        let screenFrame = screen.frame
        let x = screenFrame.midX - size / 2
        let y = screenFrame.origin.y + screenFrame.height - size
        panel.setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Container

private struct NotchIndicatorContainer: View {
    let coordinator: DictationCoordinator
    let geometry: NotchGeometry
    @State private var expanded = false

    private var shouldShow: Bool {
        switch coordinator.state {
        case .recording, .processing: true
        default: false
        }
    }

    private var isWorking: Bool {
        if case .processing = coordinator.state { return true }
        return coordinator.isRefining
    }

    private let expandedHeight: CGFloat = 50
    private let collapsedHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(cornerRadius: expanded ? 18 : 10)
                    .fill(.black)
                    .frame(
                        width: geometry.notchWidth + (expanded ? 30 : -8),
                        height: geometry.safeAreaTop + (expanded ? expandedHeight : -4)
                    )

                if expanded {
                    AuroraWaveform(level: coordinator.audioLevel, preset: coordinator.waveformPreset)
                        .frame(
                            width: geometry.notchWidth - 10,
                            height: expandedHeight - 14
                        )
                        .padding(.top, geometry.safeAreaTop + 4)
                        .transition(.opacity)

                    if isWorking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                            .colorScheme(.dark)
                            .padding(.top, geometry.safeAreaTop + 12)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: expanded)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                expanded = true
            }
        }
        .onChange(of: shouldShow) { _, show in
            if !show { expanded = false }
        }
    }
}
