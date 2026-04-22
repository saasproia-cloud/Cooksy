import SwiftUI

/// B5 — Cooking frequency per week. Dot stepper 1…7 with a contextual line
/// underneath that crossfades as the user moves up and down.
struct FrequencyView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Tu cuisines combien\nde fois par semaine ?",
            subtitle: "On cale la quantité de recettes qu'on te propose dessus.",
            canAdvance: true,
            progress: progress(for: .frequency),
            showsBack: OnboardingStep.frequency.allowsBack,
            showsSkip: OnboardingStep.frequency.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            VStack(spacing: 26) {
                // Big number recap
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(coordinator.answers.cookingFrequencyPerWeek)")
                            .font(.system(size: 68, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.75),
                                       value: coordinator.answers.cookingFrequencyPerWeek)
                            .monospacedDigit()

                        Text("/ 7")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Text("repas par semaine")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .tracking(1.3)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Dot stepper
                SegmentedDots(
                    value: Binding(
                        get: { coordinator.answers.cookingFrequencyPerWeek },
                        set: { coordinator.setFrequency($0) }
                    ),
                    range: 1...7
                )
                .frame(maxWidth: .infinity)

                // Contextual caption
                Text(caption)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.ctaOrange.opacity(0.3), lineWidth: 1)
                    )
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: caption)
            }
        }
    }

    private var caption: String {
        switch coordinator.answers.cookingFrequencyPerWeek {
        case ...2:  return "Le weekend warrior — tu assures sur les gros rendez-vous."
        case 3...4: return "Un bon rythme régulier — on va te faciliter la semaine."
        case 5...6: return "La cuisine, c'est clairement ton truc."
        default:    return "Tu cuisines plus que tu respires — respect."
        }
    }
}
