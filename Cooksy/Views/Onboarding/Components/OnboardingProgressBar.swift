import SwiftUI

/// Thin progress bar used at the top of every question screen.
/// `progress` is clamped to 0…1 and animates via spring on parent changes.
struct OnboardingProgressBar: View {
    var progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(CooksyTheme.stroke.opacity(0.55))

                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: proxy.size.width * clamped)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 6, y: 2)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progression de l'onboarding")
        .accessibilityValue("\(Int(max(0, min(1, progress)) * 100)) pour cent")
    }
}
