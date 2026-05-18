import SwiftUI

/// A1 — Welcome hero (final version).
///
/// Mirrors the exact layout pattern used by AppReviewView, which is the
/// only onboarding screen that has historically rendered correctly on
/// iPhone 17 Pro: no ScrollView, GeometryReader → VStack → `.frame(maxWidth: 380)`
/// → `.frame(maxWidth: .infinity)` → `.padding(.horizontal, X)`. The
/// ScrollView wrapper was the actual source of the asymmetric layout —
/// `.frame(maxWidth: .infinity, alignment: .center)` does not propagate
/// the expected width inside a ScrollView, and content drifts off-centre.
struct WelcomeHeroView: View {
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPad = Layout.horizontalPadding(for: geo)

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    logoMark
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -8)

                    Spacer(minLength: 18)

                    titleBlock
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)

                    Spacer(minLength: 22)

                    benefitsList
                        .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 18)

                    ratingPill
                        .opacity(appeared ? 1 : 0)

                    Spacer(minLength: 24)

                    ctaButton
                        .opacity(appeared ? 1 : 0)

                    secureFooter
                        .padding(.top, 14)
                        .padding(.bottom, 22)
                        .opacity(appeared ? 1 : 0)
                }
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, hPad)
                .animation(.easeOut(duration: 0.55), value: appeared)
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

    private var titleBlock: some View {
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

    private var benefitsList: some View {
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

    private var ctaButton: some View {
        Button(action: {
            OnboardingHaptics.medium()
            onContinue()
        }) {
            HStack(spacing: 7) {
                Text("Commencer")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.32), radius: 10, y: 5)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Secure footer (replaces former "Se connecter" link)

    /// Sober reassurance line. Mirrors the visual weight of the previous
    /// "Déjà un compte ?" link so the layout stays balanced now that account
    /// access only happens at the end of onboarding (via Apple Sign In).
    private var secureFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
            Text("Aucun compte requis pour commencer")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
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
