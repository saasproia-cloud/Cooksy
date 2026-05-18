import Foundation
import OSLog
import Security

/// Enforces the "uninstall ⇒ Welcome" policy.
///
/// iOS Keychain entries persist across uninstalls by default, so the Supabase
/// session token also survives a reinstall — meaning the user would silently
/// skip Welcome and land deep in the app. We neutralise that by tracking a
/// `hasLaunched` flag in **UserDefaults** (which IS wiped on uninstall). On
/// every cold start, if the flag is missing, we treat the install as fresh
/// and purge the cached Supabase session + local onboarding progress, so the
/// user always restarts from Welcome with the onboarding questions.
///
/// We still keep a Keychain `lastActiveAt` timestamp via `markActive(_:)` for
/// future analytics / lifecycle work, but it no longer gates the purge — every
/// fresh install resets the user.
///
/// Thread-safety: the guard only reads/writes during `bootstrap()` and on
/// auth events — all on `@MainActor` via SessionStore, which is sufficient
/// for our needs.
@MainActor
final class SessionFreshnessGuard {
    static let shared = SessionFreshnessGuard()

    // MARK: - Storage keys

    private let hasLaunchedKey = "cooksy.hasLaunched"
    private let tutorialKey = "cooksy.hasSeenTutorial"
    private let keychainService = "com.cooksy.ios.session"
    private let keychainAccount = "lastActiveAt"

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "SessionFreshnessGuard")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Call this once at launch, BEFORE reading the Supabase session.
    ///
    /// Returns `true` when we decided the stored session is stale and the
    /// caller should sign out + purge local state. Returns `false` when the
    /// session can be preserved as-is.
    ///
    /// Policy: ANY fresh install (UserDefaults `hasLaunched` flag missing)
    /// purges the cached Supabase session and resets onboarding progress.
    /// The previous 7-day grace window has been removed so uninstall ⇒
    /// reinstall always lands on Welcome with the onboarding questions,
    /// regardless of how recently the user was active.
    func shouldPurgeStaleSession() -> Bool {
        let isFreshInstall = !defaults.bool(forKey: hasLaunchedKey)

        if !isFreshInstall {
            // Not a fresh install — the user already launched this install at
            // least once. The normal Supabase refresh flow handles everything.
            return false
        }

        // Flip the launched flag immediately so subsequent cold starts of
        // this install don't re-enter this branch.
        defaults.set(true, forKey: hasLaunchedKey)

        logger.info("Fresh install detected — purging any cached Supabase session and onboarding state")
        return true
    }

    /// Called after the session has been purged so the router falls back to
    /// the very first screen (Welcome) rather than an intermediate step like
    /// the post-paywall tutorial.
    ///
    /// Also nukes the promotional-offer state so a fresh install never
    /// inherits a gift the previous user/session won — preventing the
    /// −25 % from showing on the very first paywall view.
    func resetLocalProgress() {
        defaults.removeObject(forKey: tutorialKey)
        deleteLastActive()
        PremiumOffersService.shared.resetAllGiftStateForNewSession()
    }

    /// Stamp "now" as the last time the user was active. Call on successful
    /// auth and on significant lifecycle events (app foreground, etc.).
    func markActive(_ date: Date = Date()) {
        writeLastActive(date)
    }

    // MARK: - Keychain helpers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private func readLastActive() -> Date? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                logger.debug("Keychain read returned status \(status, privacy: .public)")
            }
            return nil
        }
        guard let interval = TimeInterval(String(data: data, encoding: .utf8) ?? "") else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    private func writeLastActive(_ date: Date) {
        let payload = Data("\(date.timeIntervalSince1970)".utf8)

        // Try update first; fall back to add.
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: payload] as CFDictionary
        )
        if status == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = payload
            // `kSecAttrAccessibleAfterFirstUnlock` lets the timestamp survive
            // reboots and be read before the user unlocks the device — which
            // matches Supabase's default token accessibility.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed: \(addStatus, privacy: .public)")
            }
        } else if status != errSecSuccess {
            logger.error("Keychain update failed: \(status, privacy: .public)")
        }
    }

    private func deleteLastActive() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logger.debug("Keychain delete returned status \(status, privacy: .public)")
        }
    }
}
