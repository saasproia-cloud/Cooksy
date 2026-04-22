import SwiftUI

/// B9 — Cuisines preferred. 3×3 grid of CuisineTile cards with a 3D flip on tap.
/// Multi-select, each cuisine has its own gradient so the grid feels like a
/// mosaic of worlds rather than a list.
struct CuisinesGridView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Quelles cuisines\nveux-tu explorer ?",
            subtitle: "Plusieurs choix bienvenus. Tap pour retourner la tuile.",
            canAdvance: coordinator.canAdvance(from: .cuisines),
            progress: progress(for: .cuisines),
            showsBack: OnboardingStep.cuisines.allowsBack,
            showsSkip: OnboardingStep.cuisines.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingCuisine.allCases) { cuisine in
                    CuisineTile(
                        title: cuisine.title,
                        systemImage: cuisine.systemImage,
                        gradient: gradient(for: cuisine),
                        isSelected: coordinator.answers.cuisines.contains(cuisine)
                    ) {
                        coordinator.toggleCuisine(cuisine)
                    }
                }
            }
        }
    }

    /// Each cuisine has its own warm gradient to feel distinct in the grid.
    /// Colors stay inside the Cooksy palette (ochres, burnt oranges, reds) to
    /// keep the onboarding visually unified.
    private func gradient(for cuisine: OnboardingCuisine) -> LinearGradient {
        let pair: (Color, Color)
        switch cuisine {
        case .french:        pair = (Color(hex: 0xF2B05E), Color(hex: 0xD97839))
        case .italian:       pair = (Color(hex: 0xE67C52), Color(hex: 0xB24527))
        case .asian:         pair = (Color(hex: 0xE04F42), Color(hex: 0x8C1E1E))
        case .indian:        pair = (Color(hex: 0xF0A04B), Color(hex: 0xC24E1E))
        case .mexican:       pair = (Color(hex: 0xF2C14B), Color(hex: 0xD45829))
        case .mediterranean: pair = (Color(hex: 0xE9A368), Color(hex: 0xA64E23))
        case .middleEastern: pair = (Color(hex: 0xC78C5A), Color(hex: 0x6B3A1C))
        case .american:      pair = (Color(hex: 0xEF7B3B), Color(hex: 0xA93418))
        case .african:       pair = (Color(hex: 0xE6823F), Color(hex: 0x8A3714))
        }
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
