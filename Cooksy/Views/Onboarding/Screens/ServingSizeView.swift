import SwiftUI

/// B8 — Typical serving size. Four ServingCards laid out in a 2×2 grid; each
/// card draws animated silhouettes when selected.
struct ServingSizeView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Tu cuisines pour combien de personnes ?",
            subtitle: "On adapte automatiquement les quantités. Tu pourras toujours ajuster une recette au cas par cas.",
            canAdvance: coordinator.canAdvance(from: .servings),
            progress: progress(for: .servings),
            showsBack: OnboardingStep.servings.allowsBack,
            showsSkip: OnboardingStep.servings.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(OnboardingServings.allCases) { servings in
                    ServingCard(
                        title: servings.title,
                        subtitle: servings.subtitle,
                        silhouetteCount: servings.silhouetteCount,
                        isSelected: coordinator.answers.typicalServings == servings
                    ) {
                        coordinator.selectServings(servings)
                    }
                }
            }
        }
    }
}
