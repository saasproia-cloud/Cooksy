import SwiftUI

/// B1 — "What brings you to Cooksy?" Single-select with 4 large cards.
struct PrimaryGoalView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Qu'est-ce qui t'amène\nsur Cooksy ?",
            subtitle: "Une seule réponse. Tu pourras changer d'avis plus tard.",
            canAdvance: coordinator.canAdvance(from: .primaryGoal),
            progress: progress(for: .primaryGoal),
            showsBack: OnboardingStep.primaryGoal.allowsBack,
            showsSkip: OnboardingStep.primaryGoal.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingGoal.allCases) { goal in
                    BigChoiceCard(
                        systemImage: goal.systemImage,
                        title: goal.title,
                        subtitle: goal.subtitle,
                        isSelected: coordinator.answers.primaryGoal == goal
                    ) {
                        coordinator.selectGoal(goal)
                    }
                }
            }
        }
    }
}

/// Helper shared by all question screens — maps a step to a 0…1 progress value.
func progress(for step: OnboardingStep) -> Double {
    guard let qIndex = step.questionIndex else { return 0 }
    return Double(qIndex) / Double(OnboardingStep.totalQuestions)
}
