import SwiftUI

/// B10 — What stops the user in the kitchen. Full-width checkbox rows,
/// multi-select, optional (skip allowed).
struct ChallengesView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Qu'est-ce qui te freine le plus en cuisine ?",
            subtitle: "Plusieurs choix. Ça nous aide à choisir les recettes qui lèvent tes vrais blocages.",
            canAdvance: coordinator.canAdvance(from: .challenges),
            progress: progress(for: .challenges),
            showsBack: OnboardingStep.challenges.allowsBack,
            showsSkip: OnboardingStep.challenges.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingChallenge.allCases) { challenge in
                    ChallengeRow(
                        title: challenge.title,
                        isSelected: coordinator.answers.challenges.contains(challenge)
                    ) {
                        coordinator.toggleChallenge(challenge)
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct ChallengeRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            OnboardingHaptics.selection()
            action()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.elevatedSurface, CooksyTheme.elevatedSurface], startPoint: .top, endPoint: .bottom))
                        .frame(width: 26, height: 26)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.clear : CooksyTheme.stroke, lineWidth: 1)
                        .frame(width: 26, height: 26)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? CooksyTheme.ctaOrangeDark : CooksyTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.55) : CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: CooksyTheme.softShadow, radius: 6, y: 3)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }
}
