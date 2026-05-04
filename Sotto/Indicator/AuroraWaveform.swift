import SwiftUI

struct AuroraWaveform: View {
    let level: Float

    private static let waveConfigs: [(color: Color, freq: Double, speed: Double, phase: Double, amp: Double)] = [
        (.cyan,            2.0, 2.5, 0.0, 0.7),
        (.cyan.opacity(0.5), 3.5, 1.8, 1.2, 0.5),
        (.purple,          1.8, 3.0, 2.5, 0.8),
        (.purple.opacity(0.4), 4.0, 1.4, 4.0, 0.4),
        (.blue,            2.8, 2.2, 5.0, 0.6),
        (.mint.opacity(0.5), 5.0, 3.5, 6.0, 0.35),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let midY = size.height / 2
                let amplitude = CGFloat(level) * midY * 0.9 + midY * 0.03

                for config in Self.waveConfigs {
                    let points = wavePoints(
                        in: size, time: t,
                        frequency: config.freq, speed: config.speed,
                        phaseOffset: config.phase, amplitudeScale: config.amp,
                        amplitude: amplitude, midY: midY
                    )
                    let path = smoothPath(through: points)

                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: 3))
                        glow.stroke(path, with: .color(config.color.opacity(0.4)), lineWidth: 2.5)
                    }

                    context.stroke(path, with: .color(config.color.opacity(0.9)), lineWidth: 1)
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
