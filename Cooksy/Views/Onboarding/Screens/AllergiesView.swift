import SwiftUI

/// B7 — Allergies. Same grammar as DietView: "Aucune allergie" is the exclusive
/// pill that lives alone on the first row so it's easy to find when nothing applies.
struct AllergiesView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingChrome(
            title: "Des allergies\nà éviter ?",
            subtitle: "Sécurité d'abord — on retire automatiquement les recettes qui contiennent ces ingrédients.",
            canAdvance: coordinator.canAdvance(from: .allergies),
            progress: progress(for: .allergies),
            showsBack: OnboardingStep.allergies.allowsBack,
            showsSkip: OnboardingStep.allergies.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 10) {
                // "Aucune" on its own row for emphasis
                ChoicePill(
                    title: OnboardingAllergy.none.title,
                    systemImage: "checkmark.seal.fill",
                    isSelected: coordinator.answers.allergies.contains(.none)
                ) {
                    coordinator.toggleAllergy(.none)
                }

                // Remaining allergies in a 2-col grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(OnboardingAllergy.allCases.filter { $0 != .none }) { allergy in
                        ChoicePill(
                            title: allergy.title,
                            systemImage: systemImage(for: allergy),
                            isSelected: coordinator.answers.allergies.contains(allergy)
                        ) {
                            coordinator.toggleAllergy(allergy)
                        }
                    }
                }
            }
        }
    }

    private func systemImage(for allergy: OnboardingAllergy) -> String {
        switch allergy {
        case .none:      return "checkmark.seal.fill"
        case .peanuts:   return "circle.grid.2x2"
        case .treeNuts:  return "leaf"
        case .eggs:      return "oval"
        case .dairy:     return "drop"
        case .fish:      return "fish"
        case .shellfish: return "tortoise"
        case .soy:       return "leaf.circle"
        case .gluten:    return "exclamationmark.triangle"
        }
    }
}
