import SwiftUI

enum WaveformColorPreset: String, CaseIterable, Identifiable {
    case aurora
    case ocean
    case violet
    case rose
    case emerald
    case mono
    case vice
    case borealis
    case lagoon
    case ember
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
        case .vice: "Vice"
        case .borealis: "Borealis"
        case .lagoon: "Lagoon"
        case .ember: "Ember"
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
        case .vice:
            // A Miami sunset: indigo sky into magenta, hot pink, orange and gold.
            [
                Self.rgb(0x4B3FD1), Self.rgb(0x8A4FE0), Self.rgb(0xD94FD0), Self.rgb(0xFF4F9A),
                Self.rgb(0xFF7A59), Self.rgb(0xFFA43D), Self.rgb(0xFFD27A), Self.rgb(0xC48BE8),
            ]
        case .borealis:
            // Northern lights: green and teal rising into blue, violet and magenta.
            [
                Self.rgb(0x2EF2A0), Self.rgb(0x18D9C5), Self.rgb(0x2FA8FF), Self.rgb(0x6E5BFF),
                Self.rgb(0xB04DFF), Self.rgb(0xFF5FC8), Self.rgb(0x7CFF6B),
            ]
        case .lagoon:
            // Tropical water: turquoise, aqua, deep blue and seafoam.
            [
                Self.rgb(0x00E5D4), Self.rgb(0x2FD3FF), Self.rgb(0x4F8CFF), Self.rgb(0x7EF2E0),
                Self.rgb(0x00B3A6), Self.rgb(0xA8F0FF),
            ]
        case .ember:
            // Firelight: red and orange through amber and gold, with a rose glow.
            [
                Self.rgb(0xFF3B30), Self.rgb(0xFF6A2B), Self.rgb(0xFF9F0A), Self.rgb(0xFFD60A),
                Self.rgb(0xFF7A8A), Self.rgb(0xE0447A),
            ]
        case .pride:
            // The intersex-inclusive Progress Pride flag, stripe by stripe. Black is left out: the
            // waveform draws additively, so black would show as a gap rather than a color.
            [
                Self.rgb(0xE40303), Self.rgb(0xFF8C00), Self.rgb(0xFFED00), Self.rgb(0x008026),
                Self.rgb(0x24408E), Self.rgb(0x732982), Self.rgb(0x613915), Self.rgb(0x5BCEFA),
                Self.rgb(0xF5A9B8), .white, Self.rgb(0xFFD800), Self.rgb(0x7902AA),
            ]
        }
    }

    /// Whether lines drift through the whole palette over time, instead of keeping one color each.
    var cyclesColors: Bool {
        switch self {
        case .aurora, .ocean, .violet, .rose, .emerald, .mono: false
        case .vice, .borealis, .lagoon, .ember, .pride: true
        }
    }

    /// The color of line `index` (of `lineCount`) at `time`.
    func color(forLine index: Int, lineCount: Int, at time: Double) -> Color {
        guard cyclesColors else { return colors[index % colors.count] }
        let count = Double(colors.count)
        // Lines start spread across the palette, then drift through it half a color per second.
        let position = (time * 0.5 + Double(index) * count / Double(lineCount))
            .truncatingRemainder(dividingBy: count)
        let lower = Int(position)
        let upper = (lower + 1) % colors.count
        return colors[lower].mix(with: colors[upper], by: position - Double(lower))
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct AuroraWaveform: View {
    let level: Float
    var preset: WaveformColorPreset = .aurora
    enum Glow {
        /// A soft halo around each line.
        case halo
        /// Wider light with hot white cores, so the lines read as light on dark glass.
        case bloom
    }

    var glow: Glow = .halo

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

                let lines = Self.waveMotion.enumerated().map { i, motion in
                    let points = wavePoints(
                        in: size, time: t,
                        frequency: motion.freq, speed: motion.speed,
                        phaseOffset: motion.phase, amplitudeScale: motion.amp,
                        amplitude: amplitude, midY: midY
                    )
                    let color = preset.color(forLine: i, lineCount: Self.waveMotion.count, at: t)
                    return (path: smoothPath(through: points), color: color)
                }

                // Each glow pass blurs all lines in one layer, instead of one blur per line.
                func glowPass(blur: CGFloat, opacity: Double, lineWidth: CGFloat) {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: blur))
                        for line in lines {
                            layer.stroke(line.path, with: .color(line.color.opacity(opacity)), lineWidth: lineWidth)
                        }
                    }
                }

                switch glow {
                case .halo:
                    glowPass(blur: 3, opacity: 0.4, lineWidth: 2.5)
                    for line in lines {
                        context.stroke(line.path, with: .color(line.color.opacity(0.9)), lineWidth: 1)
                    }
                case .bloom:
                    glowPass(blur: 6, opacity: 0.25, lineWidth: 3)
                    glowPass(blur: 2, opacity: 0.45, lineWidth: 1.5)
                    for line in lines {
                        context.stroke(line.path, with: .color(line.color), lineWidth: 1)
                        context.stroke(line.path, with: .color(.white.opacity(0.4)), lineWidth: 0.4)
                    }
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
