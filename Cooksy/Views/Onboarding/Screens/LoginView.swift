import SwiftUI

/// D2 — Returning users. Same 3 providers as SignUp, different copy and the
/// email CTA triggers a sign-in rather than a sign-up.
/// Accessible from the Welcome hero ("J'ai déjà un compte") and from the
/// SignUp footer ("Déjà un compte ?").
struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let onBack: () -> Void
    let onGoToSignUp: () -> Void

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        providers
                        separator
                        emailForm
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
        VStack(spacing: 10) {
            SignInWithAppleButtonView()
            GoogleSignInButtonView()
        }
    }

    private var separator: some View {
        HStack(spacing: 12) {
            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1)
            Text("ou")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .tracking(1)
                .textCase(.uppercase)
            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1)
        }
    }

    // MARK: - Email form

    private var emailForm: some View {
        VStack(spacing: 12) {
            field(
                placeholder: "Adresse e-mail",
                systemImage: "envelope.fill",
                text: $email,
                isSecure: false,
                keyboard: .emailAddress,
                textContent: .emailAddress,
                autocap: .never,
                field: .email,
                submitLabel: .next
            )

            field(
                placeholder: "Mot de passe",
                systemImage: "lock.fill",
                text: $password,
                isSecure: true,
                keyboard: .default,
                textContent: .password,
                autocap: .never,
                field: .password,
                submitLabel: .go
            )

            if let error = sessionStore.lastErrorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }

            emailCTA
                .padding(.top, 4)
        }
    }

    private func field(
        placeholder: String,
        systemImage: String,
        text: Binding<String>,
        isSecure: Bool,
        keyboard: UIKeyboardType,
        textContent: UITextContentType?,
        autocap: TextInputAutocapitalization,
        field: Field,
        submitLabel: SubmitLabel
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: 22)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
            .keyboardType(keyboard)
            .textContentType(textContent)
            .textInputAutocapitalization(autocap)
            .submitLabel(submitLabel)
            .focused($focusedField, equals: field)
            .onSubmit {
                switch field {
                case .email: focusedField = .password
                case .password: submit()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    focusedField == field ? CooksyTheme.ctaOrange : CooksyTheme.stroke,
                    lineWidth: focusedField == field ? 1.5 : 1
                )
        )
    }

    private var emailCTA: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isSubmitting ? "Connexion…" : "Se connecter")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .opacity(canSubmit ? 1 : 0.4)
            )
            .shadow(
                color: canSubmit ? CooksyTheme.primaryAccent.opacity(0.3) : .clear,
                radius: 14, y: 6
            )
        }
        .buttonStyle(CooksyTheme.pressScale())
        .disabled(!canSubmit || isSubmitting)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: canSubmit)
    }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty
    }

    private func submit() {
        focusedField = nil
        guard canSubmit else { return }
        isSubmitting = true
        sessionStore.lastErrorMessage = nil
        Task {
            await sessionStore.signIn(email: email, password: password)
            await MainActor.run { isSubmitting = false }
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
