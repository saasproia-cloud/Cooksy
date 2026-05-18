import SwiftUI

/// B-new — "Comment tu organises tes repas ?" Single-select.
struct PlanningStyleView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Comment tu organises\ntes repas ?",
            subtitle: "Pour ajuster les suggestions à ton vrai rythme de vie.",
            canAdvance: coordinator.canAdvance(from: .planningStyle),
            progress: progress(for: .planningStyle),
            showsBack: OnboardingStep.planningStyle.allowsBack,
            showsSkip: OnboardingStep.planningStyle.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingPlanningStyle.allCases) { option in
                    BigChoiceCard(
                        systemImage: option.systemImage,
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: coordinator.answers.planningStyle == option
                    ) {
                        coordinator.selectPlanningStyle(option)
                    }
                }
            }
        }
    }
}
