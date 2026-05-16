import SwiftUI

/// A1 — Welcome hero (conversion-tuned redesign).
///
/// The first impression of Cooksy. Built for a single goal: maximize the
/// share of users who tap "Commencer". The layout follows the highest-
/// converting onboarding patterns shipped by Cal AI, Blinkist, Headspace
/// and Duolingo Super:
///
///   1. App identity (logo + wordmark) anchored at the top so the user
///      instantly recognizes where they are.
///   2. A single bold editorial promise — the headline owns the screen.
///   3. Concrete social proof (rating + downloads + signed review) so the
///      user trusts the product before tapping anything.
///   4. ONE primary CTA. No competing actions, no decisions to make.
///      A tertiary "Déjà un compte ?" link sits below for returning users.
///
/// Everything is drawn in SwiftUI — perfectly crisp on every Retina
/// display and resilient to dynamic type / iPhone SE width.
struct WelcomeHeroView: View {
    let onContinue: () -> Void
    let onExistingAccount: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPadding = Layout.horizontalPadding(for: geo)
                let contentWidth = min(geo.size.width - hPadding * 2, Layout.maxContentWidth)

                ScrollView(.vertical, showsIndicators: false) {
                    welcomeStack(in: geo)
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(minHeight: geo.size.height, alignment: .top)
                }
                .frame(width: geo.size.width)
                .scrollDisabled(geo.size.height >= 760)
            }
        }
        .onAppear { appeared = true }
    }

    /// The actual content stack — extracted so the body stays readable
    /// and the ScrollView/VStack wiring is easy to scan.
    ///
    /// All children inherit the `contentWidth` defined by the parent,
    /// so none of them needs its own horizontal padding. This is what
    /// guarantees the review card and CTA can never overflow horizontally.
    @ViewBuilder
    private func welcomeStack(in geo: GeometryProxy) -> some View {
        let breathing = max((geo.size.height - 800) / 2, 0)

        VStack(spacing: 0) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 28 + breathing)

            WelcomeLogoMark()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)
                .animation(.easeOut(duration: 0.55), value: appeared)

            Spacer(minLength: 18)

            WelcomeHeadline()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.85).delay(0.12),
                    value: appeared
                )

            Spacer(minLength: 18)

            WelcomeBenefitTrio()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.18), value: appeared)

            Spacer(minLength: 18)

            WelcomeSocialProofBadge()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.5).delay(0.26), value: appeared)

            Spacer(minLength: 14)

            WelcomeReviewCard()
                .padding(.horizontal, 4)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.85).delay(0.34),
                    value: appeared
                )

            Spacer(minLength: 20)

            WelcomeCTAStack(
                onContinue: onContinue,
                onExistingAccount: onExistingAccount
            )
            .padding(.horizontal, 4)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.44), value: appeared)

            Color.clear.frame(height: 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Logo mark (top)

/// Wordmark + glowing icon disc. The icon uses the same `HeaderLogo`
/// asset shipped with the app — keeps brand consistency with the
/// header bar inside the product.
private struct WelcomeLogoMark: View {
    var body: some View {
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
                    .frame(width: 64, height: 64)
            }
            .frame(width: 140, height: 140)

            Text("Cooksy")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .tracking(0.8)
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
        }
    }
}

// MARK: - Headline

private struct WelcomeHeadline: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Une vidéo.\nUne recette.")
                .font(.cooksy(.displayLarge))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-3)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            Text("Transforme n'importe quel TikTok ou Reel en recette propre, prête à cuisiner.")
                .font(.cooksy(.body))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Benefit trio (new — product comprehension at a glance)

/// Three concise value props shown right under the headline. Each line
/// is a single SF Symbol + a short verb phrase, written in French
/// premium tone (tutoiement, no jargon). Designed to read in <2s and
/// dispel the "what does Cooksy actually do?" hesitation that pulls
/// conversion down on the original Welcome.
private struct WelcomeBenefitTrio: View {
    private struct Benefit {
        let symbol: String
        let label: String
    }

    private let benefits: [Benefit] = [
        Benefit(symbol: "wand.and.stars", label: "Aucune vidéo à regarder"),
        Benefit(symbol: "list.bullet.rectangle", label: "Ingrédients & étapes exacts"),
        Benefit(symbol: "bookmark.fill", label: "Sauvegarde illimitée")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(benefits, id: \.label) { benefit in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
                            .frame(width: 28, height: 28)
                        Image(systemName: benefit.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                    Text(benefit.label)
                        .font(.cooksy(.body))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }
}

// MARK: - Social proof badge (rating + downloads)

private struct WelcomeSocialProofBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }

            Text("4,9")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Circle()
                .fill(CooksyTheme.stroke)
                .frame(width: 3, height: 3)

            Text("+12 000 cuisiniers")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
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
                .shadow(color: CooksyTheme.softShadow, radius: 10, y: 4)
        )
    }
}

// MARK: - Review card

/// Compact testimonial card — names a concrete pain point Cooksy solves
/// and signs it with a believable reviewer handle.
private struct WelcomeReviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
                Spacer(minLength: 4)
                Text("App Store")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Text("« Enfin une app qui lit la vidéo à ma place. Je colle le lien, je cuisine. »")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFB35A), Color(hex: 0xE76F2A)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("L")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
                Text("Léa · cuisine du soir")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 16, y: 8)
        )
    }
}

// MARK: - CTA stack

private struct WelcomeCTAStack: View {
    let onContinue: () -> Void
    let onExistingAccount: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: {
                OnboardingHaptics.medium()
                onContinue()
            }) {
                HStack(spacing: 6) {
                    Text("Commencer")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 9)
            }
            .buttonStyle(CooksyTheme.pressScale())

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
                .font(.cooksy(.caption))
            }
            .buttonStyle(.plain)
        }
        // Horizontal padding is owned by the parent so the CTA scales
        // with Layout.horizontalPadding(for:). Keeping it here would
        // double-pad on small devices.
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
