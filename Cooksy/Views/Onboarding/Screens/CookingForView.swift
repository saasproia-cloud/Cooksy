import SwiftUI

/// B-new — "Tu cuisines pour qui ?" Single-select with 5 BigChoiceCards.
struct CookingForView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Tu cuisines surtout pour qui ?",
            subtitle: "On adapte le ton, la portion et l'inspiration des recettes.",
            canAdvance: coordinator.canAdvance(from: .cookingFor),
            progress: progress(for: .cookingFor),
            showsBack: OnboardingStep.cookingFor.allowsBack,
            showsSkip: OnboardingStep.cookingFor.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingCookingFor.allCases) { option in
                    BigChoiceCard(
                        systemImage: option.systemImage,
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: coordinator.answers.cookingFor == option
                    ) {
                        coordinator.selectCookingFor(option)
                    }
                }
            }
        }
    }
}
