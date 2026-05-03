import SwiftUI

/// D2 — Returning users. Apple + Google only. Accessible from the Welcome
/// hero ("J'ai déjà un compte") and from the SignUp footer ("Déjà un compte ?").
struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let onBack: () -> Void
    let onGoToSignUp: () -> Void

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        providers
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
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
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bon retour 👋")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("Retrouve ton carnet de recettes et tes plans repas en un clin d'œil.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Providers

    private var providers: some View {
        VStack(spacing: 12) {
            SignInWithAppleButtonView()
            GoogleSignInButtonView()
        }
    }

    private var footerLink: some View {
        Button(action: {
            OnboardingHaptics.selection()
            onGoToSignUp()
        }) {
            HStack(spacing: 4) {
                Text("Nouveau sur Cooksy ?")
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("Créer un compte")
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .fontWeight(.bold)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .buttonStyle(.plain)
    }
}
