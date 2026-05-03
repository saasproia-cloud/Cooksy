import SwiftUI

/// B13 — Cooking budget. Single-select cards, optional (skip allowed).
struct BudgetView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Quel budget\npour cuisiner ?",
            subtitle: "On adapte les recettes à ce qui rentre dans tes courses.",
            canAdvance: coordinator.canAdvance(from: .budget),
            progress: progress(for: .budget),
            showsBack: OnboardingStep.budget.allowsBack,
            showsSkip: OnboardingStep.budget.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingBudget.allCases) { budget in
                    BigChoiceCard(
                        systemImage: budget.systemImage,
                        title: budget.title,
                        subtitle: budget.subtitle,
                        isSelected: coordinator.answers.budget == budget
                    ) {
                        coordinator.selectBudget(budget)
                    }
                }
            }
        }
    }
}
