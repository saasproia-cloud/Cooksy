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

    // MARK: - OpenID Connect (Apple / Google)

    /// Sign in using an Apple identity token obtained from `ASAuthorizationAppleIDCredential`.
    /// The `nonce` must be the *raw* nonce used to generate the hashed nonce passed to Apple.
    /// `fullName` is provided by Apple **only on the very first sign-in** for a given Apple ID;
    /// when present and the profile row has no display name yet, we persist it so the user
    /// sees their actual name everywhere instead of a generic placeholder.
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents? = nil) async {
        await signInWithIdToken(provider: .apple, idToken: idToken, nonce: nonce)
        await persistAppleFullNameIfNeeded(fullName)
    }

    /// First-sign-in only: Apple hands us the user's name once. If we already
    /// have a non-empty display name on the profile row, we leave it untouched
    /// (the user may have customised it). Otherwise we format the components
    /// with `PersonNameComponentsFormatter` and write it to Supabase.
    private func persistAppleFullNameIfNeeded(_ fullName: PersonNameComponents?) async {
        guard let fullName, let user = currentUser else { return }
        let existing = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return }

        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: fullName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatted.isEmpty else { return }

        do {
            _ = try await client
                .from("profiles")
                .update(DisplayNameUpdatePayload(displayName: formatted))
                .eq("id", value: user.id)
                .execute()
        } catch {
            logger.debug("persistAppleFullName failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
        await loadProfile(for: user.id)
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

    // MARK: - Account deletion

    /// Permanently deletes the signed-in user's account.
    ///
    /// Calls the `delete_my_account` Postgres RPC which drops the row
    /// from `auth.users`; cascading FKs wipe the user's profile,
    /// recipes, recipe books, meal plan, shopping list and quota row.
    /// Storage objects (avatars, recipe images) become orphaned but
    /// harmless — a server-side janitor will sweep them later.
    /// On success the local session is signed out so the app routes
    /// back to the welcome screen.
    ///
    /// Required by Apple Guideline 5.1.1(v) and RGPD.
    func deleteAccount() async throws {
        guard currentUser != nil else {
            throw NSError(
                domain: "Cooksy.SessionStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Aucune session active."]
            )
        }

        do {
            _ = try await client.rpc("delete_my_account").execute()
        } catch {
            logger.error("deleteAccount RPC failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // The RPC removes the auth row; the access token is now invalid.
        // signOut() locally clears keychain + state and resets the
        // freshness anchor, mirroring the standard sign-out path.
        await signOut()
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
        // Drop the "returning user" hint so a NEW account signing up on
        // this device doesn't skip the onboarding welcome screen. Same
        // user signing back in will re-latch it on first authenticated
        // route resolution.
        UserDefaults.standard.removeObject(forKey: "cooksy.session.hasReachedAuthenticated")
        // Reset the onboarding "answers saved" latch so the next signup
        // / login from the OnboardingFlow can push its draft answers.
        UserDefaults.standard.removeObject(forKey: "cooksy.onboarding.didSaveAnswers")
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

            // Right after onboarding completes is the moment to ask for
            // notification permission. We show the *explicit* iOS prompt
            // (not a silent provisional grant) so the user makes a clear
            // choice — the trial-ending and quota reminders only have
            // value if they're actually visible banners.
            _ = await NotificationsCenter.shared.requestExplicitAuthorization()

            // Schedule the A1 welcome nudge (~1 h out, daytime-clamped).
            // Cancelled automatically the moment the user makes their
            // first import — see NotificationScheduler / RecipeStore.
            NotificationScheduler.scheduleWelcome()
        } catch {
            logger.error("saveOnboardingAnswers failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Updates the user's display name and/or avatar URL in one round-trip.
    /// Pass `nil` for a field to leave it untouched. Refreshes `self.profile`
    /// on success so the UI reflects the change immediately.
    func updateProfile(displayName: String? = nil, avatarURL: URL? = nil) async throws {
        guard let user = currentUser else {
            throw NSError(
                domain: "Cooksy.SessionStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Session utilisateur introuvable."]
            )
        }

        let payload = ProfileUpdatePayload(
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURL: avatarURL?.absoluteString
        )

        do {
            _ = try await client
                .from("profiles")
                .update(payload)
                .eq("id", value: user.id)
                .execute()
            await loadProfile(for: user.id)
        } catch {
            logger.error("updateProfile failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Uploads JPEG data to the `avatars` Supabase Storage bucket and returns
    /// a long-lived signed URL.
    ///
    /// The bucket was switched to private in the 20260518 migration so
    /// the user UUID embedded in the object path no longer leaks via a
    /// public URL. We mint a 10-year signed URL at upload time — long
    /// enough that we don't need to re-sign on every render, short
    /// enough to be revocable by rotating the storage JWT.
    ///
    /// Path convention `<uid>/avatar-<ms-timestamp>.jpg` matches the
    /// `recipe-images` RLS pattern (folder = uid).
    func uploadAvatar(_ data: Data) async throws -> URL {
        guard let user = currentUser else {
            throw NSError(
                domain: "Cooksy.SessionStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Session utilisateur introuvable."]
            )
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(user.id.uuidString.lowercased())/avatar-\(timestamp).jpg"

        do {
            _ = try await client.storage
                .from("avatars")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            // 10 years in seconds — effectively permanent for the
            // lifespan of an account, while still being a signed URL
            // (which the private bucket policy requires for reads).
            let tenYears = 60 * 60 * 24 * 365 * 10
            let signedURL = try await client.storage
                .from("avatars")
                .createSignedURL(path: path, expiresIn: tenYears)
            return signedURL
        } catch {
            logger.error("uploadAvatar failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Updates premium status locally (optimistic UI) and re-fetches the
    /// canonical row from Supabase.
    ///
    /// The DB column `profiles.is_premium` is **read-only for clients** —
    /// the RLS policy blocks self-writes. The single trusted writer is
    /// the backend's RevenueCat webhook, which receives the purchase
    /// event from Apple via RevenueCat and flips the flag through a
    /// `security definer` RPC. After a purchase completes locally we
    /// just refresh our copy of the profile; the webhook usually wins
    /// the race, but if it hasn't fired yet `loadProfile` will pick up
    /// the new value on the next call.
    func setPremium(_ premium: Bool) async {
        guard let user = currentUser else { return }

        // Optimistic local update so the router can react immediately.
        profile?.isPremium = premium
        ImportQuotaService.shared.isPremium = premium

        // Re-sync from server-of-truth. If the webhook has landed by
        // now, the profile reflects it; otherwise we'll catch it the
        // next time `loadProfile` runs (e.g. on auth state change or
        // explicit refresh).
        await loadProfile(for: user.id)
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
        // Right after a fresh sign-up the `handle_new_user` Postgres trigger
        // races with this SELECT. Retry a few times with a short exponential
        // backoff so the router doesn't get stuck on `.bootstrap` waiting for
        // the row to materialise.
        let attemptDelaysMs: [UInt64] = [0, 300, 600, 1_200]
        for (index, delay) in attemptDelaysMs.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
            }
            do {
                let loaded: CooksyProfile = try await client
                    .from("profiles")
                    .select()
                    .eq("id", value: userID)
                    .single()
                    .execute()
                    .value
                profile = loaded
                // Mirror premium state into the import quota service so the
                // free-tier gate uses the live value without polling.
                ImportQuotaService.shared.isPremium = loaded.isPremium
                return
            } catch {
                if index == attemptDelaysMs.count - 1 {
                    logger.debug("Profile still unavailable after \(attemptDelaysMs.count, privacy: .public) attempts for \(userID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    profile = nil
                }
            }
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

/// Partial profile update — fields left as `nil` are omitted from the payload
/// (`encodeIfPresent`) so the existing Supabase row keeps its current value.
private struct ProfileUpdatePayload: Encodable {
    let displayName: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
    }
}
