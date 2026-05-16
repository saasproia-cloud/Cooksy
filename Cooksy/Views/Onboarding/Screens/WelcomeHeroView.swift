import SwiftUI

/// A1 — Welcome hero (rewritten from scratch).
///
/// Layout rule: ALL children use a HARD width computed from the
/// GeometryReader (`.frame(width:)`). Nothing uses
/// `.frame(maxWidth: .infinity)` — it's the source of the bleed bug
/// on iPhone 17 Pro where the parent VStack shrinks to its tightest
/// child and infinity-width siblings escape both screen edges.
struct WelcomeHeroView: View {
    let onContinue: () -> Void
    let onExistingAccount: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let hPad: CGFloat = geo.size.width < 380 ? 20 : 26
            let contentWidth = min(geo.size.width - hPad * 2, 440)

            ZStack {
                AnimatedAmbientBackground()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 28)

                        logoMark
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : -8)

                        Spacer().frame(height: 22)

                        titleBlock(width: contentWidth)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)

                        Spacer().frame(height: 26)

                        benefitsList(width: contentWidth)
                            .opacity(appeared ? 1 : 0)

                        Spacer(minLength: 20)

                        ratingPill
                            .opacity(appeared ? 1 : 0)

                        Spacer(minLength: 22)

                        ctaButton(width: contentWidth)
                            .opacity(appeared ? 1 : 0)

                        Spacer().frame(height: 12)

                        loginLink
                            .opacity(appeared ? 1 : 0)

                        Spacer().frame(height: 24)
                    }
                    .frame(width: contentWidth)
                    .frame(maxWidth: geo.size.width, alignment: .center)
                    .frame(minHeight: geo.size.height, alignment: .top)
                    .animation(.easeOut(duration: 0.55), value: appeared)
                }
                .scrollDisabled(geo.size.height >= 760)
            }
        }
        .onAppear { appeared = true }
    }

    // MARK: - Logo

    private var logoMark: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccentGlow.opacity(0.55),
                                CooksyTheme.primaryAccentGlow.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 8)

                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 92, height: 92)
                    .overlay(
                        Circle()
                            .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.shadow, radius: 18, y: 10)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.16), radius: 22, y: 0)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
            }

            Text("Cooksy")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .tracking(0.6)
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
        }
    }

    // MARK: - Title

    private func titleBlock(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text("Une vidéo.\nUne recette.")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Transforme n'importe quel TikTok ou Reel\nen recette propre, prête à cuisiner.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width)
    }

    // MARK: - Benefits

    private struct Benefit {
        let symbol: String
        let label: String
    }

    private let benefits: [Benefit] = [
        Benefit(symbol: "wand.and.stars", label: "Aucune vidéo à regarder"),
        Benefit(symbol: "list.bullet.rectangle", label: "Ingrédients & étapes exacts"),
        Benefit(symbol: "bookmark.fill", label: "Sauvegarde illimitée")
    ]

    private func benefitsList(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(benefits, id: \.label) { benefit in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
                            .frame(width: 30, height: 30)
                        Image(systemName: benefit.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                    Text(benefit.label)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(width: min(width, 280), alignment: .leading)
    }

    // MARK: - Rating pill

    private var ratingPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }

            Text("4,9")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Circle()
                .fill(CooksyTheme.stroke)
                .frame(width: 3, height: 3)

            Text("+12 000 cuisiniers")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.85))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.softShadow, radius: 8, y: 3)
        )
    }

    // MARK: - CTA

    private func ctaButton(width: CGFloat) -> some View {
        Button(action: {
            OnboardingHaptics.medium()
            onContinue()
        }) {
            HStack(spacing: 7) {
                Text("Commencer")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: width, height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.42), radius: 18, y: 10)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Login link

    private var loginLink: some View {
        Button(action: {
            OnboardingHaptics.selection()
            onExistingAccount()
        }) {
            HStack(spacing: 4) {
                Text("Déjà un compte ?")
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("Se connecter")
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated background (shared)

/// Subtle gradient "breathing" background via TimelineView. Re-exported
/// so other onboarding screens (AppReviewView, etc.) can reuse it.
struct AnimatedAmbientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = CGFloat((sin(t * 0.4) + 1) * 0.5)

            ZStack {
                CooksyTheme.ambientGradient

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccentSoft.opacity(0.75),
                                CooksyTheme.primaryAccentSoft.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: -120 + drift * 60, y: -260 + drift * 40)
                    .blur(radius: 20)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.warmCard.opacity(0.65),
                                CooksyTheme.warmCard.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 300
                        )
                    )
                    .frame(width: 540, height: 540)
                    .offset(x: 140 - drift * 40, y: 320 - drift * 60)
                    .blur(radius: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}
