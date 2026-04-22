import SwiftUI

/// Shared chrome for every onboarding screen:
/// top bar (optional back + progress + optional skip) and bottom CTA container.
/// Content is injected via the `content` closure.
struct OnboardingChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let ctaTitle: String
    let canAdvance: Bool
    let progress: Double?   // 0…1 — nil hides the bar
    let showsBack: Bool
    let showsSkip: Bool
    let onBack: () -> Void
    let onSkip: (() -> Void)?
    let onAdvance: () -> Void
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        ctaTitle: String = "Continuer",
        canAdvance: Bool,
        progress: Double? = nil,
        showsBack: Bool = true,
        showsSkip: Bool = false,
        onBack: @escaping () -> Void,
        onSkip: (() -> Void)? = nil,
        onAdvance: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.ctaTitle = ctaTitle
        self.canAdvance = canAdvance
        self.progress = progress
        self.showsBack = showsBack
        self.showsSkip = showsSkip
        self.onBack = onBack
        self.onSkip = onSkip
        self.onAdvance = onAdvance
        self.content = content
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                header
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }

                Spacer(minLength: 0)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                OnboardingHaptics.selection()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(CooksyTheme.elevatedSurface)
                    )
                    .overlay(
                        Circle().stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .opacity(showsBack ? 1 : 0)
            .disabled(!showsBack)

            if let progress {
                OnboardingProgressBar(progress: progress)
                    .animation(.spring(response: 0.55, dampingFraction: 0.85), value: progress)
            } else {
                Color.clear
                    .frame(height: 4)
            }

            if showsSkip, let onSkip {
                Button(action: {
                    OnboardingHaptics.selection()
                    onSkip()
                }) {
                    Text("Passer")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 36)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        Button(action: {
            guard canAdvance else {
                OnboardingHaptics.warning()
                return
            }
            OnboardingHaptics.light()
            onAdvance()
        }) {
            Text(ctaTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                        .opacity(canAdvance ? 1 : 0.4)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: canAdvance ? 1 : 0)
                )
                .shadow(
                    color: canAdvance ? CooksyTheme.primaryAccent.opacity(0.35) : .clear,
                    radius: 16, y: 8
                )
                .scaleEffect(canAdvance ? 1 : 0.98)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: canAdvance)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }
}

// MARK: - Press scale button style

extension CooksyTheme {
    /// Applies a subtle scale-down on press, used throughout onboarding CTAs.
    static func pressScale() -> PressScaleButtonStyle {
        PressScaleButtonStyle()
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
