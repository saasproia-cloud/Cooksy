import SwiftUI

/// B14 — Meal moments. Multi-select pills, optional (skip allowed).
struct MealMomentsView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Quels moments\ncuisines-tu le plus ?",
            subtitle: "Plusieurs choix. On priorisera ces moments dans tes suggestions.",
            canAdvance: coordinator.canAdvance(from: .mealMoments),
            progress: progress(for: .mealMoments),
            showsBack: OnboardingStep.mealMoments.allowsBack,
            showsSkip: OnboardingStep.mealMoments.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingMealMoment.allCases) { moment in
                    ChoicePill(
                        title: moment.title,
                        systemImage: moment.systemImage,
                        isSelected: coordinator.answers.mealMoments.contains(moment)
                    ) {
                        coordinator.toggleMealMoment(moment)
                    }
                }
            }
        }
    }
}
