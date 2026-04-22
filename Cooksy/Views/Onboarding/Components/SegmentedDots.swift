import SwiftUI

/// Horizontal dot stepper used for "cooking frequency per week".
/// Tapping a dot fills all dots up to it in cascade.
struct SegmentedDots: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private let dotSize: CGFloat = 34
    private let spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(range), id: \.self) { idx in
                dot(for: idx)
            }
        }
    }

    private func dot(for idx: Int) -> some View {
        let isFilled = idx <= value
        return Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                value = idx
            }
        }) {
            ZStack {
                Circle()
                    .fill(isFilled ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.elevatedSurface, CooksyTheme.elevatedSurface], startPoint: .top, endPoint: .bottom))

                Circle()
                    .stroke(isFilled ? Color.clear : CooksyTheme.stroke, lineWidth: 1)

                Text("\(idx)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isFilled ? .white : CooksyTheme.secondaryText)
            }
            .frame(width: dotSize, height: dotSize)
            .shadow(color: isFilled ? CooksyTheme.primaryAccent.opacity(0.3) : .clear, radius: 6, y: 3)
            .scaleEffect(idx == value ? 1.15 : 1.0)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.72).delay(Double(idx - range.lowerBound) * 0.04),
                value: value
            )
        }
        .buttonStyle(.plain)
    }
}
