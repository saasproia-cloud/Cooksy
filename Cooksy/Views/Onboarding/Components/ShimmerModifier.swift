import SwiftUI

/// Modifier that sweeps a bright gradient across its content every `period` seconds.
/// Used for the paywall CTA to draw the eye.
struct ShimmerModifier: ViewModifier {
    var period: Double = 3.0

    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: period)) / period // 0…1
                shimmerOverlay(phase: phase)
            }
            .allowsHitTesting(false)
        )
    }

    private func shimmerOverlay(phase: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let xOffset = (phase * 2.0 - 0.5) * width // sweeps from -0.5w to 1.5w
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.35),
                    Color.white.opacity(0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.4)
            .offset(x: xOffset)
            .blendMode(.plusLighter)
        }
        .mask(
            Capsule(style: .continuous)
        )
    }
}

extension View {
    func shimmer(period: Double = 3.0) -> some View {
        modifier(ShimmerModifier(period: period))
    }
}
