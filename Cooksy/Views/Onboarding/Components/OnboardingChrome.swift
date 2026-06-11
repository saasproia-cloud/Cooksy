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
        GeometryReader { proxy in
            let width = proxy.size.width
            let cls = Layout.DeviceClass.from(width: width)
            let hPadOuter = Layout.horizontalPadding(for: width)
            let hPadContent = hPadOuter + (cls.isPhone ? 4 : 8)
            // Compact (SE/8, mini) gets tighter vertical rhythm so the
            // CTA never gets pushed off-screen. Bigger devices get more
            // breathing room.
            let topGap: CGFloat   = cls == .compact ? 6 : 12
            let headerBottom: CGFloat = cls == .compact ? 14 : 24
            let contentBottom: CGFloat = cls == .compact ? 12 : 24
            let topBarBottom: CGFloat = cls == .compact ? 10 : 18
            ZStack {
                CooksyTheme.ambientGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(width: width)
                        .padding(.horizontal, hPadOuter)
                        .padding(.top, topGap)
                        .padding(.bottom, topBarBottom)

                    header(width: width)
                        .padding(.horizontal, hPadContent)
                        .padding(.bottom, headerBottom)

                    ScrollView(showsIndicators: false) {
                        content()
                            .padding(.horizontal, hPadContent)
                            .padding(.bottom, contentBottom)
                            .frame(maxWidth: Layout.maxContentWidth)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 0)

                    bottomBar(width: width)
                        .padding(.horizontal, hPadContent)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 12))
                        .frame(maxWidth: Layout.maxContentWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func topBar(width: CGFloat) -> some View {
        let cls = Layout.DeviceClass.from(width: width)
        let chipSize: CGFloat = cls == .compact ? 32 : 36
        return HStack(spacing: 12) {
            Button(action: {
                OnboardingHaptics.selection()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: chipSize, height: chipSize)
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
                        .frame(height: chipSize)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: chipSize)
            }
        }
    }

    /// Title size scaled per device class. Compact devices (SE/8/mini)
    /// can't fit 30pt serif comfortably on two lines — we drop to 24pt
    /// and let `minimumScaleFactor` handle very long strings.
    private func titleFontSize(for width: CGFloat) -> CGFloat {
        switch Layout.DeviceClass.from(width: width) {
        case .compact:        return 24
        case .regular:        return 28
        case .large:          return 30
        case .tabletCompact:  return 34
        case .tablet:         return 38
        }
    }

    private func subtitleFontSize(for width: CGFloat) -> CGFloat {
        switch Layout.DeviceClass.from(width: width) {
        case .compact:        return 14
        case .regular:        return 15
        case .large:          return 16
        case .tabletCompact:  return 17
        case .tablet:         return 18
        }
    }

    private func header(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: titleFontSize(for: width), weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleFontSize(for: width), weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bottomBar(width: CGFloat) -> some View {
        let cls = Layout.DeviceClass.from(width: width)
        let ctaHeight: CGFloat = cls == .compact ? 48 : (cls.isTablet ? 56 : 52)
        let ctaFont: CGFloat = cls == .compact ? 15 : 16
        return Button(action: {
            guard canAdvance else {
                OnboardingHaptics.warning()
                return
            }
            OnboardingHaptics.light()
            onAdvance()
        }) {
            Text(ctaTitle)
                .font(.system(size: ctaFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: ctaHeight)
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
