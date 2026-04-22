import SwiftUI

/// Full-width card showing a skill level with a 3-dot visual indicator.
/// Selected card scales up slightly and its dots fill in cascade.
struct LevelCard: View {
    let title: String
    let subtitle: String
    let filledDots: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            OnboardingHaptics.light()
            action()
        }) {
            HStack(spacing: 16) {
                dotsColumn

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CheckmarkBadge(isOn: isSelected, size: 24)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.5) : CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(color: isSelected ? CooksyTheme.primaryAccent.opacity(0.18) : CooksyTheme.softShadow,
                    radius: isSelected ? 14 : 10, y: 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var dotsColumn: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                // Dots fill bottom-up: dot at index 2 is bottom.
                let displayIndex = 2 - index
                let isFilled = displayIndex < filledDots
                Circle()
                    .fill(isFilled ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.stroke.opacity(0.6), CooksyTheme.stroke.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isSelected && isFilled ? 1.12 : 1.0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.75).delay(Double(displayIndex) * 0.08),
                        value: isSelected
                    )
            }
        }
        .frame(width: 20)
    }
}
