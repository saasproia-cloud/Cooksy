import SwiftUI

/// Toggleable pill used for multi-select screens (sources, diet, allergies, challenges).
/// Icon optional. Tap → fill transitions, border becomes orange, subtle scale pulse.
struct ChoicePill: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    var fillWidth: Bool = true
    let action: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    pulse = false
                }
            }
            action()
        }) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText)
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? CooksyTheme.ctaOrangeDark : CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .background(background)
            .overlay(border)
            .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var background: some View {
        Capsule(style: .continuous)
            .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.85) : CooksyTheme.elevatedSurface)
    }

    private var border: some View {
        Capsule(style: .continuous)
            .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
    }
}
