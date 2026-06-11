import SwiftUI

/// B-new — "Ton objectif sur le long terme ?" Single-select.
struct LifestyleGoalView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Ton objectif sur le long terme ?",
            subtitle: "On t'aide à orienter chaque recette dans cette direction.",
            canAdvance: coordinator.canAdvance(from: .lifestyleGoal),
            progress: progress(for: .lifestyleGoal),
            showsBack: OnboardingStep.lifestyleGoal.allowsBack,
            showsSkip: OnboardingStep.lifestyleGoal.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingLifestyleGoal.allCases) { option in
                    BigChoiceCard(
                        systemImage: option.systemImage,
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: coordinator.answers.lifestyleGoal == option
                    ) {
                        coordinator.selectLifestyleGoal(option)
                    }
                }
            }
        }
    }
}
