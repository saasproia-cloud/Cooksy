import SwiftUI

/// B15 — Shopping habits. Multi-select pills, optional (skip allowed).
struct ShoppingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Où fais-tu\ntes courses ?",
            subtitle: "On adapte les ingrédients à ce que tu trouves vraiment.",
            canAdvance: coordinator.canAdvance(from: .shopping),
            progress: progress(for: .shopping),
            showsBack: OnboardingStep.shopping.allowsBack,
            showsSkip: OnboardingStep.shopping.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingShopping.allCases) { place in
                    ChoicePill(
                        title: place.title,
                        systemImage: place.systemImage,
                        isSelected: coordinator.answers.shoppingPlaces.contains(place)
                    ) {
                        coordinator.toggleShopping(place)
                    }
                }
            }
        }
    }
}
