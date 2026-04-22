import SwiftUI

/// Gentle drifting sparkles used behind the paywall and success states.
/// Pure Canvas — no assets.
struct SparkleCanvas: View {
    let count: Int
    let baseColor: Color

    private let seeds: [SparkleSeed]

    init(count: Int = 28, baseColor: Color = CooksyTheme.sparkleYellow) {
        self.count = count
        self.baseColor = baseColor
        self.seeds = (0..<count).map { _ in SparkleSeed.random() }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for seed in seeds {
                    let localT = (t + seed.phase) * seed.speed
                    let x = seed.x * size.width + CGFloat(sin(localT) * 14)
                    let y = (seed.y * size.height + CGFloat(localT).truncatingRemainder(dividingBy: size.height))
                        .truncatingRemainder(dividingBy: size.height)
                    let opacity = (sin(localT * 2) + 1) * 0.35 + 0.1
                    let radius = seed.size
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(baseColor.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SparkleSeed {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let speed: Double
    let phase: Double

    static func random() -> SparkleSeed {
        SparkleSeed(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 1.2...2.8),
            speed: Double.random(in: 0.3...0.7),
            phase: Double.random(in: 0...(2 * .pi))
        )
    }
}
