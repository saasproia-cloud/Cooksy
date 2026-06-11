import SwiftUI

/// B6 — Dietary restrictions. Multi-select with "Aucun" that clears the others.
/// 2×4 grid of ChoicePills, with "Aucun" pinned to the first cell so the eye
/// lands on it before the more specific options.
struct DietView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Tu suis un régime particulier ?",
            subtitle: "On filtre les recettes qu'on te propose. Touche « Aucun » si ça ne te concerne pas.",
            canAdvance: coordinator.canAdvance(from: .diet),
            progress: progress(for: .diet),
            showsBack: OnboardingStep.diet.allowsBack,
            showsSkip: OnboardingStep.diet.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingDiet.allCases) { diet in
                    ChoicePill(
                        title: diet.title,
                        systemImage: diet.systemImage,
                        isSelected: coordinator.answers.diets.contains(diet)
                    ) {
                        coordinator.toggleDiet(diet)
                    }
                }
            }
        }
    }
}
