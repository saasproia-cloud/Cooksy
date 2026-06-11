import SwiftUI

/// B4 — Time per meal slider. The giant number in the middle is the real
/// feedback loop; the descriptor changes contextually.
struct TimeSliderView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    private let range: ClosedRange<Double> = 10...90
    private let step: Double = 5

    var body: some View {
        OnboardingChrome(
            title: "Combien de temps pour cuisiner ?",
            subtitle: "Une soirée classique en semaine. On t'enverra des recettes à ton rythme.",
            canAdvance: true,
            progress: progress(for: .timeSlider),
            showsBack: OnboardingStep.timeSlider.allowsBack,
            showsSkip: OnboardingStep.timeSlider.allowsSkip,
            onBack: onBack,
            onSkip: onContinue,
            onAdvance: onContinue
        ) {
            VStack(spacing: 28) {
                // Big number
                VStack(spacing: 4) {
                    Text("\(coordinator.answers.timeMinutesPerMeal)")
                        .font(.system(size: 88, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: coordinator.answers.timeMinutesPerMeal)
                        .monospacedDigit()

                    Text("minutes")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .tracking(1.5)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 2)

                // Slider
                CustomSlider(
                    value: Binding(
                        get: { Double(coordinator.answers.timeMinutesPerMeal) },
                        set: { coordinator.setTime(Int($0.rounded())) }
                    ),
                    range: range,
                    step: step
                )
                .padding(.horizontal, 6)

                HStack {
                    Text("10 min")
                    Spacer()
                    Text("90+ min")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .padding(.horizontal, 6)

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
        switch coordinator.answers.timeMinutesPerMeal {
        case ...15:  return "Mode rapide — un bol en 15 min max."
        case 16...30: return "Express — du goût sans perdre de temps."
        case 31...60: return "Confortable — tu prends ton temps."
        default:      return "Les grands jours — tu te fais plaisir."
        }
    }
}
