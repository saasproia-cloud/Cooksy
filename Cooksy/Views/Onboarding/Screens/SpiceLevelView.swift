import SwiftUI

/// B11 — Spice tolerance. Four full-width cards with cascading flame icons.
struct SpiceLevelView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Tu aimes ça\népicé ?",
            subtitle: "Pour qu'on dose le piment des recettes au bon niveau pour toi.",
            canAdvance: coordinator.canAdvance(from: .spiceLevel),
            progress: progress(for: .spiceLevel),
            showsBack: OnboardingStep.spiceLevel.allowsBack,
            showsSkip: OnboardingStep.spiceLevel.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingSpiceLevel.allCases) { level in
                    SpiceLevelCard(
                        title: level.title,
                        subtitle: level.subtitle,
                        filledFlames: level.filledDots,
                        isSelected: coordinator.answers.spiceLevel == level
                    ) {
                        coordinator.selectSpiceLevel(level)
                    }
                }
            }
        }
    }
}

// MARK: - Card

private struct SpiceLevelCard: View {
    let title: String
    let subtitle: String
    let filledFlames: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            OnboardingHaptics.light()
            action()
        }) {
            HStack(spacing: 16) {
                flamesColumn

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

    private var flamesColumn: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                let isFilled = index < filledFlames
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        isFilled
                            ? AnyShapeStyle(CooksyTheme.accentGradient)
                            : AnyShapeStyle(CooksyTheme.stroke.opacity(0.7))
                    )
                    .scaleEffect(isSelected && isFilled ? 1.12 : 1.0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.06),
                        value: isSelected
                    )
            }
        }
        .frame(width: 80, alignment: .leading)
    }
}
