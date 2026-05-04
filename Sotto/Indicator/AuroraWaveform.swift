import SwiftUI

enum WaveformColorPreset: String, CaseIterable, Identifiable {
    case aurora
    case ocean
    case violet
    case rose
    case emerald
    case mono
    case pride

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: "Aurora"
        case .ocean: "Ocean"
        case .violet: "Violet"
        case .rose: "Rosé"
        case .emerald: "Emerald"
        case .mono: "Mono"
        case .pride: "Pride"
        }
    }

    var colors: [Color] {
        switch self {
        case .aurora:
            [.cyan, .cyan.opacity(0.5), .purple, .purple.opacity(0.4), .blue, .mint.opacity(0.5)]
        case .ocean:
            [.blue, .blue.opacity(0.5), .cyan, .teal.opacity(0.6), .indigo.opacity(0.5), .mint.opacity(0.4)]
        case .violet:
            [.purple, .purple.opacity(0.5), .indigo, .indigo.opacity(0.5), .pink.opacity(0.4), .blue.opacity(0.3)]
        case .rose:
            [.pink, .pink.opacity(0.5), .red.opacity(0.6), .orange.opacity(0.4), .purple.opacity(0.4), .pink.opacity(0.3)]
        case .emerald:
            [.green, .green.opacity(0.5), .mint, .teal.opacity(0.5), .cyan.opacity(0.4), .green.opacity(0.3)]
        case .mono:
            [.white, .white.opacity(0.5), .gray, .gray.opacity(0.5), .white.opacity(0.4), .gray.opacity(0.3)]
        case .pride:
            [.red, .orange, .yellow, .green, .blue, .purple]
        }
    }
}

struct AuroraWaveform: View {
    let level: Float
    var preset: WaveformColorPreset = .aurora

    @State private var smoothedLevel: Float = 0
    @State private var lastTime: Double = 0

    private static let waveMotion: [(freq: Double, speed: Double, phase: Double, amp: Double)] = [
        (2.0, 2.5, 0.0, 0.7),
        (3.5, 1.8, 1.2, 0.5),
        (1.8, 3.0, 2.5, 0.8),
        (4.0, 1.4, 4.0, 0.4),
        (2.8, 2.2, 5.0, 0.6),
        (5.0, 3.5, 6.0, 0.35),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let dt = lastTime > 0 ? min(Float(t - lastTime), 0.05) : 0.016
            let rise: Float = 12
            let fall: Float = 6
            let speed = level > smoothedLevel ? rise : fall
            let interp = 1 - exp(-speed * dt)
            let currentLevel = smoothedLevel + (level - smoothedLevel) * interp

            Canvas { context, size in
                let midY = size.height / 2
                let amplitude = CGFloat(currentLevel) * midY * 0.9 + midY * 0.03
                let colors = preset.colors

                for (i, motion) in Self.waveMotion.enumerated() {
                    let color = colors[i % colors.count]
                    let points = wavePoints(
                        in: size, time: t,
                        frequency: motion.freq, speed: motion.speed,
                        phaseOffset: motion.phase, amplitudeScale: motion.amp,
                        amplitude: amplitude, midY: midY
                    )
                    let path = smoothPath(through: points)

                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: 3))
                        glow.stroke(path, with: .color(color.opacity(0.4)), lineWidth: 2.5)
                    }

                    context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1)
                }
            }
            .blendMode(.plusLighter)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.15),
                        .init(color: .white, location: 0.85),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .onChange(of: t) { _, _ in
                smoothedLevel = currentLevel
                lastTime = t
            }
        }
    }

    private func wavePoints(
        in size: CGSize,
        time: Double,
        frequency: Double,
        speed: Double,
        phaseOffset: Double,
        amplitudeScale: Double,
        amplitude: CGFloat,
        midY: CGFloat
    ) -> [CGPoint] {
        let steps = 100
        let stepWidth = size.width / CGFloat(steps)

        return (0...steps).map { i in
            let x = CGFloat(i) * stepWidth
            let t = Double(i) / Double(steps)
            let centered = (t - 0.5) * 2.4
            let envelope = max(0, 1 - centered * centered)
            let sharp = envelope * envelope * envelope
            let wave = sin(t * frequency * .pi * 2 + time * speed + phaseOffset)
            let y = midY - CGFloat(wave * sharp * amplitudeScale) * amplitude
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothPath(through points: [CGPoint]) -> Path {
        guard points.count > 2 else {
            var p = Path()
            if let f = points.first { p.move(to: f) }
            for pt in points.dropFirst() { p.addLine(to: pt) }
            return p
        }

        var path = Path()
        path.move(to: points[0])

        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let cp1x = prev.x + (curr.x - prev.x) * 0.5
            let cp2x = curr.x - (curr.x - prev.x) * 0.5
            path.addCurve(
                to: curr,
                control1: CGPoint(x: cp1x, y: prev.y),
                control2: CGPoint(x: cp2x, y: curr.y)
            )
        }

        return path
    }
}
