import SwiftUI

/// B-new — "Quel style de cuisine te ressemble ?" Multi-select pills.
struct CookingStyleView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Quel style de cuisine\nte ressemble ?",
            subtitle: "Plusieurs choix. On mixera ces ambiances dans tes suggestions.",
            canAdvance: coordinator.canAdvance(from: .cookingStyle),
            progress: progress(for: .cookingStyle),
            showsBack: OnboardingStep.cookingStyle.allowsBack,
            showsSkip: OnboardingStep.cookingStyle.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingCookingStyle.allCases) { style in
                    ChoicePill(
                        title: style.title,
                        systemImage: style.systemImage,
                        isSelected: coordinator.answers.cookingStyles.contains(style)
                    ) {
                        coordinator.toggleCookingStyle(style)
                    }
                }
            }
        }
    }
}
