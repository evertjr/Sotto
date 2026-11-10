import AppKit
import Combine
import SwiftUI

// MARK: - Geometry

/// The notch on a screen, if it has one. See `IslandLayout` for how the island uses it.
@Observable
@MainActor
final class IslandGeometry {
    /// Notches on current MacBook Pros are 185 to 220pt wide. Anything narrower, like the camera
    /// hole on Dynamic Island Macs, isn't treated as a notch, so it gets the floating capsule.
    private static let minimumNotchWidth: CGFloat = 150

    /// The notch the island grows out of, or nil on screens without one.
    var notch: CGSize?

    func update(for screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        guard top > 0,
              let left = screen.auxiliaryTopLeftArea?.width,
              let right = screen.auxiliaryTopRightArea?.width else {
            notch = nil
            return
        }

        let width = screen.frame.width - left - right
        notch = width >= Self.minimumNotchWidth ? CGSize(width: width, height: top) : nil
    }
}

// MARK: - Controller

@MainActor
final class IslandIndicatorController {
    private var panel: NSPanel?
    private var stateSubscription: AnyCancellable?
    private let geometry = IslandGeometry()
    private static let panelSize: CGFloat = 500

    func startObserving(_ coordinator: DictationCoordinator) {
        stateSubscription = coordinator.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let isActive: Bool
                switch state {
                case .recording, .processing, .copiedToClipboard, .error: isActive = true
                case .idle, .inserting: isActive = false
                }
                if isActive && coordinator.indicatorStyle == .island {
                    self?.show(coordinator: coordinator)
                } else {
                    self?.dismiss()
                }
            }
    }

    private func show(coordinator: DictationCoordinator) {
        guard panel == nil, let screen = NSScreen.main else { return }
        geometry.update(for: screen)

        let view = IslandContainer(coordinator: coordinator, geometry: geometry)
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []

        let size = Self.panelSize
        let panel = IslandPanel(
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
        // Leaves time for the closing animation, so the island finishes collapsing before the panel goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Panel

/// The island must never become key, or it would take keyboard focus from the app being dictated
/// into. But Liquid Glass renders flat, with no refraction, in a window that doesn't look active.
/// These private `NSWindow` hooks make AppKit draw the panel with an active appearance anyway.
/// If Apple removes them they're simply never called, and the glass goes back to rendering flat.
private final class IslandPanel: NSPanel {
    @objc(_hasActiveAppearance)
    private func hasActiveAppearance() -> Bool { true }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    @objc(_hasKeyAppearance)
    private func hasKeyAppearance() -> Bool { true }
}

// MARK: - Layout

/// Sizes and shape for the island on a screen. With a notch, it grows down out of the notch,
/// flush with the bezel, and the content sits below the notch. Without one, it's a capsule
/// floating just below the top edge.
private struct IslandLayout {
    let hasNotch: Bool
    let topInset: CGFloat
    /// Height of the band at the top that stays solid black, hiding the notch or camera. Content sits below it.
    let solidHeight: CGFloat
    let collapsed: CGSize
    let expanded: CGSize
    /// Notices need more room than the waveform on the floating capsule.
    let expandedWithNotice: CGSize

    init(notch: CGSize?) {
        guard let notch else {
            hasNotch = false
            topInset = 6
            // On Dynamic Island Macs the camera sits about 16 to 19pt from the top of the screen
            // (measured from Apple's screenshots), so this band keeps it in solid black, above the waveform.
            solidHeight = 20
            collapsed = CGSize(width: 80, height: 24)
            expanded = CGSize(width: 160, height: 58)
            expandedWithNotice = CGSize(width: 320, height: 58)
            return
        }
        hasNotch = true
        topInset = 0
        solidHeight = notch.height
        // At rest it's tucked inside the notch with a little margin, shoulders included. The reported
        // safe area can be a hair larger than the visible notch, so matching it exactly leaks at the edges.
        collapsed = CGSize(
            width: notch.width - 4 - IslandNotchShape.shoulderRadius * 2,
            height: notch.height - 4
        )
        expanded = CGSize(width: max(notch.width + 120, 360), height: notch.height + 52)
        expandedWithNotice = expanded
    }

    func shape(for size: CGSize) -> AnyShape {
        guard hasNotch else { return AnyShape(Capsule(style: .continuous)) }
        return AnyShape(IslandNotchShape(bottomRadius: min(size.height / 2, 28)))
    }

    /// The notch shape draws its shoulders outside the body, so its frame is wider.
    func frameWidth(for size: CGSize) -> CGFloat {
        hasNotch ? size.width + IslandNotchShape.shoulderRadius * 2 : size.width
    }
}

/// The notch's own silhouette, grown: flush with the bezel at the top, with small concave
/// shoulders where it meets the screen edge and rounded bottom corners.
private struct IslandNotchShape: Shape {
    static let shoulderRadius: CGFloat = 6
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = Self.shoulderRadius
        let body = CGRect(x: rect.minX + s, y: rect.minY, width: rect.width - s * 2, height: rect.height)
        let r = min(bottomRadius, body.height, body.width / 2)

        // Square top so it stays flush with the bezel, Apple's continuous curve at the bottom.
        var path = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0),
            style: .continuous
        )
        .path(in: body)

        var leftShoulder = Path()
        leftShoulder.move(to: CGPoint(x: rect.minX, y: rect.minY))
        leftShoulder.addQuadCurve(
            to: CGPoint(x: body.minX, y: rect.minY + s),
            control: CGPoint(x: body.minX, y: rect.minY)
        )
        leftShoulder.addLine(to: CGPoint(x: body.minX, y: rect.minY))
        leftShoulder.closeSubpath()

        var rightShoulder = Path()
        rightShoulder.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        rightShoulder.addQuadCurve(
            to: CGPoint(x: body.maxX, y: rect.minY + s),
            control: CGPoint(x: body.maxX, y: rect.minY)
        )
        rightShoulder.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
        rightShoulder.closeSubpath()

        path.addPath(leftShoulder)
        path.addPath(rightShoulder)
        return path
    }
}

// MARK: - Container

private struct IslandContainer: View {
    let coordinator: DictationCoordinator
    let geometry: IslandGeometry
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: IslandLayout {
        IslandLayout(notch: geometry.notch)
    }

    private var size: CGSize {
        guard expanded else { return layout.collapsed }
        return notice == nil ? layout.expanded : layout.expandedWithNotice
    }

    private var shouldShow: Bool {
        switch coordinator.state {
        case .recording, .processing, .copiedToClipboard, .error: true
        case .idle, .inserting: false
        }
    }

    private var notice: IndicatorNotice? {
        IndicatorNotice(state: coordinator.state)
    }

    private var isWorking: Bool {
        if case .processing = coordinator.state { return true }
        return coordinator.isRefining
    }

    // Opening uses the bouncy spring shipping notch apps use (DynamicNotchKit). Closing keeps spring
    // motion but is slightly overdamped (negative bounce), so it doesn't settle back on the way out.
    private var openAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .bouncy(duration: 0.4)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.35, bounce: -0.1)
    }

    private var swapAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.4)
    }

    var body: some View {
        let solidFraction = layout.solidHeight / size.height

        ZStack(alignment: .top) {
            IslandSurface(shape: layout.shape(for: size), solidFraction: solidFraction)
                .frame(width: layout.frameWidth(for: size), height: size.height)
                .opacity(expanded || layout.hasNotch ? 1 : 0)

            if expanded {
                IslandGlow(
                    level: coordinator.audioLevel,
                    preset: coordinator.waveformPreset,
                    reduceMotion: reduceMotion
                )
                .frame(width: layout.frameWidth(for: size), height: size.height)
                .clipShape(layout.shape(for: size))
                .transition(.opacity)

                content
                    .frame(width: size.width, height: size.height - layout.solidHeight)
                    .padding(.top, layout.solidHeight)
                    .transition(.islandContent(reduceMotion: reduceMotion))
            }
        }
        .padding(.top, layout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(expanded ? openAnimation : closeAnimation, value: expanded)
        .animation(swapAnimation, value: notice)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                expanded = true
            }
        }
        .onChange(of: shouldShow) { _, show in
            if !show { expanded = false }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let notice {
            IndicatorNoticeLabel(notice: notice)
                // Text keeps clear of the rounded ends.
                .padding(.horizontal, 24)
                .transition(.islandContent(reduceMotion: reduceMotion))
        } else {
            ZStack {
                // Spans nearly the full width. Its own edge fade blends it into the rounded ends.
                AuroraWaveform(level: coordinator.audioLevel, preset: coordinator.waveformPreset, glow: .bloom)
                    .frame(height: 32)
                    .padding(.horizontal, 8)

                if isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                        .colorScheme(.dark)
                }
            }
            .animation(.smooth(duration: 0.25), value: isWorking)
            .transition(.islandContent(reduceMotion: reduceMotion))
        }
    }
}

// MARK: - Glow

/// The waveform's light catching the bottom rim of the glass: a few soft blooms in the waveform's
/// colors. With the voice they brighten, swell and sway, each slightly out of step so the light
/// shimmers. In silence they settle to a faint, still glow, so the waveform stays the one visualization.
private struct IslandGlow: View {
    let level: Float
    let preset: WaveformColorPreset
    let reduceMotion: Bool

    @State private var smoothedLevel: Float = 0
    @State private var lastTime: Double = 0
    @State private var appearedAt = Date()

    private static let blooms: [(x: CGFloat, width: CGFloat, speed: Double, phase: Double)] = [
        (0.36, 0.30, 1.3, 0.0),
        (0.50, 0.36, 1.7, 2.1),
        (0.64, 0.30, 1.1, 4.2),
    ]
    private static let flareDuration: Double = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Same fast-attack, slow-release smoothing as the waveform, so they move together.
            let dt = lastTime > 0 ? min(Float(t - lastTime), 0.05) : 0.016
            let speed: Float = level > smoothedLevel ? 12 : 6
            let currentLevel = smoothedLevel + (level - smoothedLevel) * (1 - exp(-speed * dt))
            let flare = flareAmount(at: timeline.date)

            Canvas { context, size in
                let voice = CGFloat(min(max(currentLevel, 0), 1))
                context.blendMode = .plusLighter
                context.addFilter(.blur(radius: 12))

                for (i, bloom) in Self.blooms.enumerated() {
                    let color = preset.color(forLine: i, lineCount: Self.blooms.count, at: t)
                    let shimmer = reduceMotion ? 1 : 0.6 + 0.4 * sin(t * bloom.speed * 2 + bloom.phase)
                    let energy = voice * CGFloat(shimmer)
                    let sway = reduceMotion ? 0 : CGFloat(sin(t * bloom.speed + bloom.phase)) * size.width * 0.12 * voice
                    let width = size.width * (bloom.width + energy * 0.35 + flare * 0.2)
                    let height = 10 + energy * 14 + flare * 6
                    let rect = CGRect(
                        x: size.width * bloom.x + sway - width / 2,
                        y: size.height - 4 - height / 2,
                        width: width,
                        height: height
                    )
                    context.opacity = Double(0.25 + energy * 0.6 + flare * 0.3)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .onChange(of: t) { _, _ in
                smoothedLevel = currentLevel
                lastTime = t
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A brief brightening as the island opens, easing out to the voice-driven glow.
    private func flareAmount(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let progress = min(date.timeIntervalSince(appearedAt) / Self.flareDuration, 1)
        return CGFloat(pow(1 - progress, 2))
    }
}

// MARK: - Surface

/// Siri's look: clear Liquid Glass (see `IslandGlass`), covered by black that's solid at the top
/// and fades out toward the bottom, so the desktop shows through the glass more the lower you look.
private struct IslandSurface: View {
    let shape: AnyShape
    /// How much of the height, from the top, stays solid black.
    let solidFraction: CGFloat

    var body: some View {
        let solidEnd = min(max(solidFraction, 0), 1)

        shape
            .fill(LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: solidEnd),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .background {
                IslandGlass { shape.path(in: $0) }
                    // The glass draws refraction and shadow past its frame, so clip it back. No
                    // compositing group: flattening it offscreen would cut it off from the backdrop.
                    .clipShape(shape)
            }
    }
}

// MARK: - Content Transition

private struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private extension AnyTransition {
    /// Content blurs and grows out of the island as it opens, the mix DynamicNotchKit uses.
    static func islandContent(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
            .combined(with: .scale(scale: 0.6, anchor: .top))
            .combined(with: .opacity)
    }
}
