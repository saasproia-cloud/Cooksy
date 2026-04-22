import SwiftUI

/// Large single-choice card used on screens like B1 (primary goal) and B3 (skill level).
/// Left: gradient square with an SF Symbol.
/// Right: bolded title + muted subtitle.
/// Far right: animated checkmark when selected.
struct BigChoiceCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @State private var pressedTick: Bool = false

    var body: some View {
        Button(action: {
            OnboardingHaptics.light()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                pressedTick.toggle()
            }
            action()
        }) {
            HStack(spacing: 16) {
                iconSquare
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CheckmarkBadge(isOn: isSelected, size: 24)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(background)
            .overlay(border)
            .shadow(color: isSelected ? CooksyTheme.primaryAccent.opacity(0.18) : CooksyTheme.softShadow, radius: isSelected ? 14 : 10, y: 6)
            .scaleEffect(isSelected ? 1.015 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var iconSquare: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.accentGradient)
                .frame(width: 52, height: 52)

            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.28), radius: 10, y: 4)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
            .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.5) : CooksyTheme.elevatedSurface)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
            .stroke(
                isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke,
                lineWidth: isSelected ? 1.5 : 1
            )
    }
}
