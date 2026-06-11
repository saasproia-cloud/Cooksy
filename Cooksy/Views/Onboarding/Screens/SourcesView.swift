import SwiftUI

/// B2 — "Where do your favorite recipes come from?" Multi-select pills, min 1.
struct SourcesView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "D'où viennent tes recettes préférées ?",
            subtitle: "Plusieurs choix possibles. On priorisera ces sources dans ton feed.",
            canAdvance: coordinator.canAdvance(from: .sources),
            progress: progress(for: .sources),
            showsBack: OnboardingStep.sources.allowsBack,
            showsSkip: OnboardingStep.sources.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingSource.allCases) { source in
                    ChoicePill(
                        title: source.title,
                        systemImage: source.systemImage,
                        isSelected: coordinator.answers.sources.contains(source)
                    ) {
                        coordinator.toggleSource(source)
                    }
                }
            }
        }
    }
}
