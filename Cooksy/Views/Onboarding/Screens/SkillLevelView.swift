import SwiftUI

/// B3 — Skill level. Three full-width cards with animated dot indicators.
struct SkillLevelView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Tu es à quel niveau\nen cuisine ?",
            subtitle: "Sois honnête — on adapte la difficulté des recettes qu'on te propose.",
            canAdvance: coordinator.canAdvance(from: .skillLevel),
            progress: progress(for: .skillLevel),
            showsBack: OnboardingStep.skillLevel.allowsBack,
            showsSkip: OnboardingStep.skillLevel.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingSkillLevel.allCases) { level in
                    LevelCard(
                        title: level.title,
                        subtitle: level.subtitle,
                        filledDots: level.filledDots,
                        isSelected: coordinator.answers.skillLevel == level
                    ) {
                        coordinator.selectSkill(level)
                    }
                }
            }
        }
    }
}
