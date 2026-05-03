import SwiftUI

/// B12 — Equipment available. Multi-select pills, optional (skip allowed).
struct EquipmentView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Quels équipements\nas-tu en cuisine ?",
            subtitle: "Plusieurs choix. On évitera les recettes qui demandent du matériel que tu n'as pas.",
            canAdvance: coordinator.canAdvance(from: .equipment),
            progress: progress(for: .equipment),
            showsBack: OnboardingStep.equipment.allowsBack,
            showsSkip: OnboardingStep.equipment.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingEquipment.allCases) { equipment in
                    ChoicePill(
                        title: equipment.title,
                        systemImage: equipment.systemImage,
                        isSelected: coordinator.answers.equipment.contains(equipment)
                    ) {
                        coordinator.toggleEquipment(equipment)
                    }
                }
            }
        }
    }
}
