import SwiftUI

/// Custom horizontal slider with a gradient-filled track and a drop-shadowed thumb.
/// Emits haptic selection ticks each time the rounded value changes.
struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var dragStartValue: Double?
    @State private var lastHaptic: Double = -1

    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clamped = max(0, min(1, progress))
            let thumbX = clamped * (totalWidth - thumbSize) + thumbSize / 2

            ZStack(alignment: .leading) {
                // Track background
                Capsule(style: .continuous)
                    .fill(CooksyTheme.stroke.opacity(0.6))
                    .frame(height: trackHeight)

                // Filled portion
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: max(thumbSize / 2, thumbX), height: trackHeight)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 8, y: 3)

                // Thumb
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Circle()
                                .stroke(CooksyTheme.ctaOrange, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)

                    Circle()
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: thumbSize * 0.38, height: thumbSize * 0.38)
                }
                .frame(width: thumbSize, height: thumbSize)
                .offset(x: thumbX - thumbSize / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = value
                                OnboardingHaptics.light()
                            }
                            let location = gesture.location.x
                            let ratio = max(0, min(1, (location - thumbSize / 2) / max(totalWidth - thumbSize, 1)))
                            let raw = Double(ratio) * (range.upperBound - range.lowerBound) + range.lowerBound
                            let snapped = (raw / step).rounded() * step
                            if snapped != value {
                                value = snapped
                                if abs(snapped - lastHaptic) >= step {
                                    OnboardingHaptics.selection()
                                    lastHaptic = snapped
                                }
                            }
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            OnboardingHaptics.light()
                        }
                )
            }
            .frame(height: thumbSize)
        }
        .frame(height: thumbSize)
    }
}
