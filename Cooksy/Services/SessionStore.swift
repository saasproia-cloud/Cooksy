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

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    deinit {
        authListenerTask?.cancel()
    }

    func bootstrap() async {
        await refreshSession()
        listenToAuthChanges()
    }

    func signUp(email: String, password: String) async {
        lastErrorMessage = nil
        phase = .loading
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            await refreshSession()
        } catch {
            logger.error("signUp failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
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
            logger.error("signIn failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            await refreshSession()
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            logger.error("signOut failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
        profile = nil
        phase = .signedOut
    }

    private func refreshSession() async {
        do {
            let session = try await client.auth.session
            phase = .signedIn(session.user)
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

struct CooksyProfile: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String?
    var avatarURL: URL?
    var isPremium: Bool
    var onboardingCompletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case isPremium = "is_premium"
        case onboardingCompletedAt = "onboarding_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
