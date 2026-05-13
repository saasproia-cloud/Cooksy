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
                let breathing = max((geo.size.height - 760) / 2, 0)

                VStack(spacing: 0) {
                    Color.clear.frame(height: 28 + breathing)

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

                    Spacer(minLength: 14)

                    WelcomeSocialProofBadge()
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.5).delay(0.22), value: appeared)

                    Spacer(minLength: 18)

                    WelcomeReviewCard()
                        .padding(.horizontal, 22)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.85).delay(0.32),
                            value: appeared
                        )

                    Spacer(minLength: 20)

                    WelcomeCTAStack(
                        onContinue: onContinue,
                        onExistingAccount: onExistingAccount
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.5).delay(0.42), value: appeared)

                    Color.clear.frame(height: 24)
                }
                .frame(width: geo.size.width)
            }
        }
        .onAppear { appeared = true }
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
                // Outer warm glow.
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

                // Glass disc.
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
                    .frame(width: 70, height: 70)
            }

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
        VStack(spacing: 8) {
            Text("Une vidéo.\nUne recette.")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-3)
                .minimumScaleFactor(0.8)
                .lineLimit(3)
                .padding(.horizontal, 22)

            Text("Transforme n'importe quel TikTok ou Reel en recette propre, prête à cuisiner.")
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
                Spacer(minLength: 4)
                Text("App Store")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Text("« Enfin une app qui lit la vidéo à ma place. Je colle le lien, je cuisine. »")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFB35A), Color(hex: 0xE76F2A)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("L")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
                Text("Léa · cuisine du soir")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
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
                HStack(spacing: 8) {
                    Text("Commencer")
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.42), radius: 18, y: 10)
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
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
