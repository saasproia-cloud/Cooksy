import Foundation
import OSLog
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn(User)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var profile: CooksyProfile?
    @Published var lastErrorMessage: String?

    private let client: SupabaseClient
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "SessionStore")
    private var authListenerTask: Task<Void, Never>?

    var currentUser: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    var isSignedIn: Bool { currentUser != nil }

    /// `true` once the server-side profile row has been loaded with onboarding flag set.
    /// Used by the root router to gate onboarding vs paywall vs home.
    var hasCompletedOnboarding: Bool {
        profile?.onboardingCompletedAt != nil
    }

    var isPremium: Bool {
        profile?.isPremium ?? false
    }

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    deinit {
        authListenerTask?.cancel()
    }

    func bootstrap() async {
        // Keychain (where Supabase stores the session token) survives an app
        // uninstall, which means a clean reinstall would silently skip the
        // Welcome screen. Enforce the "signed out after 7 days of no
        // activity" policy here, before reading the session. A quick
        // reinstall within a week preserves the session untouched.
        if SessionFreshnessGuard.shared.shouldPurgeStaleSession() {
            logger.info("Purging stale Supabase session after uninstall/reinstall > 7d")
            do {
                try await client.auth.signOut()
            } catch {
                logger.error("signOut during freshness purge failed: \(error.localizedDescription, privacy: .public)")
            }
            SessionFreshnessGuard.shared.resetLocalProgress()
        }

        await refreshSession()

        if isSignedIn {
            SessionFreshnessGuard.shared.markActive()
        }

        listenToAuthChanges()
    }

    // MARK: - Email / password

    func signUp(email: String, password: String, firstName: String, lastName: String?) async {
        lastErrorMessage = nil
        phase = .loading
        do {
            // Pass the human-readable name(s) as auth metadata so the
            // `handle_new_user` trigger / our own profile update can pick them
            // up. Supabase stores these in `auth.users.raw_user_meta_data`.
            let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLast = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String = {
                if let trimmedLast, !trimmedLast.isEmpty {
                    return "\(trimmedFirst) \(trimmedLast)"
                }
                return trimmedFirst
            }()

            let metadata: [String: AnyJSON] = [
                "first_name": .string(trimmedFirst),
                "last_name": .string(trimmedLast ?? ""),
                "display_name": .string(displayName)
            ]

            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: metadata
            )

            if response.session != nil {
                // Got a session immediately — email confirmation is OFF on
                // Supabase, the user is fully signed in. Persist the display
                // name on the profile row so it shows up in the app.
                await persistDisplayName(displayName)
                await refreshSession()
                return
            }

            // No session in the response → either email confirmation is ON
            // (Supabase sent a magic-link mail), or Supabase silently created
            // the user but didn't return a session. Try a sign-in with the
            // same credentials — if email confirmation is OFF this completes
            // the sign-up flow seamlessly. If it's ON, the sign-in will fail
            // with `email_not_confirmed` and we surface a clear message.
            do {
                _ = try await client.auth.signIn(email: email, password: password)
                await persistDisplayName(displayName)
                await refreshSession()
            } catch {
                logger.info("Auto sign-in after sign-up failed (likely email confirmation required): \(String(describing: error), privacy: .public)")
                lastErrorMessage = "Compte créé. Vérifie tes emails pour activer ton compte, puis connecte-toi."
                await refreshSession()
            }
        } catch {
            let friendly = Self.friendlyAuthError(error)
            logger.error("signUp failed: \(String(describing: error), privacy: .public)")
            lastErrorMessage = friendly
            await refreshSession()
        }
    }

    func signIn(email: String, password: String) async {
        lastErrorMessage = nil
        phase = .loading
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            await refreshSession()
        } catch {
            let friendly = Self.friendlyAuthError(error)
            logger.error("signIn failed: \(String(describing: error), privacy: .public)")
            lastErrorMessage = friendly
            await refreshSession()
        }
    }

    /// After a successful sign-up we patch the freshly-created profile row
    /// with the display name the user typed. The `handle_new_user` Postgres
    /// trigger creates the row with default fields, but does not see our
    /// auth metadata, so we update it here.
    private func persistDisplayName(_ name: String) async {
        guard !name.isEmpty else { return }
        do {
            let session = try await client.auth.session
            _ = try await client
                .from("profiles")
                .update(DisplayNameUpdatePayload(displayName: name))
                .eq("id", value: session.user.id)
                .execute()
        } catch {
            logger.debug("persistDisplayName failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Translates the Supabase auth `errorCode` (when present) into a
    /// French message the user can act on, instead of dumping a 60-line
    /// HTTP response into the alert.
    private static func friendlyAuthError(_ error: Error) -> String {
        let raw = String(describing: error)
        // The `errorCode: Auth.ErrorCode(rawValue: "user_already_exists")`
        // bit in the dump is the most reliable signal. Match it textually.
        if raw.contains("user_already_exists") {
            return "Un compte existe déjà avec cette adresse e-mail. Connecte-toi."
        }
        if raw.contains("invalid_credentials") || raw.contains("Invalid login") {
            return "E-mail ou mot de passe incorrect."
        }
        if raw.contains("email_not_confirmed") {
            return "Ton e-mail n'a pas encore été confirmé. Vérifie ta boîte de réception."
        }
        if raw.contains("weak_password") {
            return "Mot de passe trop faible. Utilise au moins 6 caractères avec un mélange de lettres et chiffres."
        }
        if raw.contains("over_email_send_rate_limit") || raw.contains("rate limit") {
            return "Trop de tentatives. Patiente quelques minutes avant de réessayer."
        }
        if raw.contains("validation_failed") || raw.contains("invalid_email") {
            return "Adresse e-mail invalide."
        }
        if raw.contains("signup_disabled") {
            return "Les inscriptions sont temporairement désactivées."
        }
        if raw.contains("network") || raw.contains("offline") {
            return "Pas de connexion internet. Vérifie ton réseau."
        }
        // Fallback — show the localizedDescription which is usually short
        // enough for an alert.
        return error.localizedDescription
    }

    // MARK: - OpenID Connect (Apple / Google)

    /// Sign in using an Apple identity token obtained from `ASAuthorizationAppleIDCredential`.
    /// The `nonce` must be the *raw* nonce used to generate the hashed nonce passed to Apple.
    func signInWithApple(idToken: String, nonce: String) async {
        await signInWithIdToken(provider: .apple, idToken: idToken, nonce: nonce)
    }

    /// Sign in using a Google ID token (from GoogleSignIn-iOS).
    /// `accessToken` is optional but recommended (Supabase uses it to validate `at_hash`).
    func signInWithGoogle(idToken: String, accessToken: String? = nil, nonce: String? = nil) async {
        await signInWithIdToken(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nonce)
    }

    private func signInWithIdToken(
        provider: OpenIDConnectCredentials.Provider,
        idToken: String,
        accessToken: String? = nil,
        nonce: String? = nil
    ) async {
        lastErrorMessage = nil
        phase = .loading
        do {
            let credentials = OpenIDConnectCredentials(
                provider: provider,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nonce
            )
            _ = try await client.auth.signInWithIdToken(credentials: credentials)
            await refreshSession()
        } catch {
            let detail = String(describing: error)
            logger.error("\(String(describing: provider), privacy: .public) sign-in failed: \(detail, privacy: .public)")
            lastErrorMessage = "Connexion \(provider) échouée — \(detail)"
            await refreshSession()
        }
    }

    // MARK: - Sign out

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            logger.error("signOut failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
        // Explicit sign-out clears the freshness anchor too, so an uninstall
        // afterwards doesn't leave a valid timestamp behind for the next
        // fresh install to honour.
        SessionFreshnessGuard.shared.resetLocalProgress()
        profile = nil
        phase = .signedOut
    }

    // MARK: - Profile updates

    /// Writes the captured onboarding answers to Supabase and stamps `onboarding_completed_at`.
    /// Keeps `self.profile` hydrated so the root router switches out of onboarding.
    func saveOnboardingAnswers(_ answers: OnboardingAnswers) async {
        guard let user = currentUser else {
            logger.fault("saveOnboardingAnswers called without a signed-in user")
            lastErrorMessage = "Session utilisateur introuvable."
            return
        }

        do {
            let payload = OnboardingCompletionPayload(
                onboardingAnswers: answers,
                onboardingCompletedAt: Date()
            )
            _ = try await client
                .from("profiles")
                .update(payload)
                .eq("id", value: user.id)
                .execute()
            await loadProfile(for: user.id)
        } catch {
            logger.error("saveOnboardingAnswers failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Mock premium flip — called from the paywall CTA until StoreKit/RevenueCat is wired.
    /// Updates both the local optimistic copy and the Supabase row.
    func setPremiumMock(_ premium: Bool) async {
        guard let user = currentUser else { return }

        // Optimistic local update so the router can react immediately.
        profile?.isPremium = premium

        do {
            _ = try await client
                .from("profiles")
                .update(PremiumUpdatePayload(isPremium: premium))
                .eq("id", value: user.id)
                .execute()
            await loadProfile(for: user.id)
        } catch {
            logger.error("setPremiumMock failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            // Revert optimistic update on failure.
            await loadProfile(for: user.id)
        }
    }

    // MARK: - Session / listener

    private func refreshSession() async {
        do {
            let session = try await client.auth.session
            phase = .signedIn(session.user)
            // Any path that leaves us signed-in should slide the freshness
            // window forward — not just the auth listener, which may fire
            // asynchronously after the router has already reacted.
            SessionFreshnessGuard.shared.markActive()
            await loadProfile(for: session.user.id)
        } catch {
            phase = .signedOut
            profile = nil
        }
    }

    private func listenToAuthChanges() {
        authListenerTask?.cancel()
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                await self.handleAuthChange(event: event, session: session)
            }
        }
    }

    private func handleAuthChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
            if let user = session?.user {
                phase = .signedIn(user)
                // Stamp the freshness timestamp on every successful auth event
                // so the "last active" window keeps sliding forward while the
                // user is actually using the app.
                SessionFreshnessGuard.shared.markActive()
                await loadProfile(for: user.id)
            } else {
                phase = .signedOut
                profile = nil
            }
        case .signedOut:
            phase = .signedOut
            profile = nil
        default:
            break
        }
    }

    private func loadProfile(for userID: UUID) async {
        do {
            let loaded: CooksyProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            profile = loaded
        } catch {
            logger.debug("Profile not yet available for user \(userID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            profile = nil
        }
    }
}

// MARK: - Profile model

struct CooksyProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String?
    var avatarURL: URL?
    var isPremium: Bool
    var onboardingCompletedAt: Date?
    var onboardingAnswers: OnboardingAnswers?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case isPremium = "is_premium"
        case onboardingCompletedAt = "onboarding_completed_at"
        case onboardingAnswers = "onboarding_answers"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        isPremium = (try? container.decode(Bool.self, forKey: .isPremium)) ?? false
        onboardingCompletedAt = try container.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        // Supabase returns `{}` when unset — treat decode failure as nil to keep the app robust.
        onboardingAnswers = try? container.decodeIfPresent(OnboardingAnswers.self, forKey: .onboardingAnswers)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Synthesized encoder to keep `Codable` conformance once we added a manual `init(from:)`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encodeIfPresent(onboardingCompletedAt, forKey: .onboardingCompletedAt)
        try container.encodeIfPresent(onboardingAnswers, forKey: .onboardingAnswers)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Update payloads

private struct OnboardingCompletionPayload: Encodable {
    let onboardingAnswers: OnboardingAnswers
    let onboardingCompletedAt: Date

    enum CodingKeys: String, CodingKey {
        case onboardingAnswers = "onboarding_answers"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

private struct PremiumUpdatePayload: Encodable {
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case isPremium = "is_premium"
    }
}

private struct DisplayNameUpdatePayload: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
