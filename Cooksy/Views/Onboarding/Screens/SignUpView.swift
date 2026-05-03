import SwiftUI

/// D1 — Account creation. Apple + Google only. Once the user authenticates,
/// the parent OnboardingFlow detects the sign-in transition and pushes
/// onboarding answers to Supabase before routing toward the paywall.
///
/// Email sign-up was removed, so the layout is rebalanced around three
/// blocks — a hero badge, a short benefit list, and a social-proof bar —
/// to keep the screen feeling intentional rather than empty.
struct SignUpView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @EnvironmentObject private var sessionStore: SessionStore
    let onBack: () -> Void
    let onGoToLogin: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            backgroundGlow
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        heroBadge
                            .padding(.top, 4)
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.9)
                            .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05), value: appeared)

                        header
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.15), value: appeared)

                        benefits
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.28), value: appeared)

                        providers
                            .padding(.top, 4)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.4), value: appeared)

                        socialProof
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.55), value: appeared)

                        legalFooter
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.65), value: appeared)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }

                Spacer(minLength: 0)

                footerLink
                    .padding(.bottom, 22)
            }
        }
        .alert(
            "Erreur d'authentification",
            isPresented: Binding(
                get: { sessionStore.lastErrorMessage != nil },
                set: { if !$0 { sessionStore.lastErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    sessionStore.lastErrorMessage = nil
                }
            },
            message: {
                Text(sessionStore.lastErrorMessage ?? "")
            }
        )
        .onAppear { appeared = true }
    }

    // MARK: - Background glow

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentSoft.opacity(0.55),
                            CooksyTheme.primaryAccentSoft.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: -160, y: -260)
                .blur(radius: 18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.warmCard.opacity(0.5),
                            CooksyTheme.warmCard.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: 160, y: 220)
                .blur(radius: 22)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: {
                OnboardingHaptics.selection()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(CooksyTheme.elevatedSurface))
                    .overlay(Circle().stroke(CooksyTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            quickBadge
        }
    }

    private var quickBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccent)
            Text("Inscription en 2 sec.")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 6, y: 3)
    }

    // MARK: - Hero badge

    private var heroBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentSoft.opacity(0.7),
                            CooksyTheme.primaryAccentSoft.opacity(0)
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .blur(radius: 4)

            Circle()
                .fill(CooksyTheme.elevatedSurface)
                .frame(width: 84, height: 84)
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
                .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)

            Circle()
                .fill(CooksyTheme.accentGradient)
                .frame(width: 60, height: 60)
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 14, y: 8)

            Image(systemName: "fork.knife")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            // tiny floating sparkles
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentGlow)
                .offset(x: 48, y: -38)
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentGlow.opacity(0.8))
                .offset(x: -52, y: 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Crée ton compte\nen 2 secondes")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text("Sauvegarde ton profil et tes recettes en sécurité — synchronisés sur tous tes appareils.")
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(spacing: 10) {
            SignUpBenefitRow(
                icon: "icloud.fill",
                title: "Recettes synchronisées",
                subtitle: "Disponibles sur tous tes appareils, partout."
            )
            SignUpBenefitRow(
                icon: "lock.shield.fill",
                title: "100 % privé",
                subtitle: "Aucune publicité, tes données ne sont jamais revendues."
            )
            SignUpBenefitRow(
                icon: "arrow.uturn.backward.circle.fill",
                title: "Tu ne perds rien",
                subtitle: "Récupère tout, même en changeant de téléphone."
            )
        }
    }

    // MARK: - Providers (Apple / Google)

    private var providers: some View {
        VStack(spacing: 12) {
            SignInWithAppleButtonView()
            GoogleSignInButtonView()
        }
    }

    // MARK: - Social proof

    private var socialProof: some View {
        HStack(spacing: 12) {
            HStack(spacing: -8) {
                avatarBubble(initial: "L", colors: [CooksyTheme.primaryAccent, CooksyTheme.primaryAccentGlow])
                avatarBubble(initial: "M", colors: [CooksyTheme.secondaryAccent, CooksyTheme.secondaryAccentStrong])
                avatarBubble(initial: "T", colors: [CooksyTheme.primaryAccentStrong, CooksyTheme.primaryAccent])
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccentGlow)
                    }
                    Text("4.9")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .padding(.leading, 2)
                }
                Text("Rejoint par 12 000+ cuisiniers")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
        )
    }

    private func avatarBubble(initial: String, colors: [Color]) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
            Text(initial)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle().stroke(CooksyTheme.elevatedSurface, lineWidth: 2)
        )
    }

    // MARK: - Legal + footer link

    private var legalFooter: some View {
        Text("En continuant, tu acceptes nos Conditions d'utilisation et notre Politique de confidentialité.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var footerLink: some View {
        Button(action: {
            OnboardingHaptics.selection()
            onGoToLogin()
        }) {
            HStack(spacing: 4) {
                Text("Déjà un compte ?")
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("Se connecter")
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .fontWeight(.bold)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Benefit row

private struct SignUpBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.65))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.55), lineWidth: 1)
        )
    }
}
