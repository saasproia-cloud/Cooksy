import Foundation
import OSLog
import Security

/// Enforces the "reinstall within one week keeps you signed in" policy.
///
/// iOS Keychain entries persist across uninstalls by default, so the Supabase
/// session token also survives a reinstall — meaning the user would silently
/// skip Welcome and land deep in the app. We neutralise that by:
///
///   1. Writing a `lastActiveAt` timestamp into the **Keychain** on every
///      successful auth event / foreground. The Keychain value also survives
///      uninstalls — it's our only reliable "last time the user opened this
///      install" anchor.
///   2. Tracking a `hasLaunched` flag in **UserDefaults**. UserDefaults IS
///      wiped on uninstall, so the absence of this flag tells us "the app was
///      freshly installed on this device".
///
/// At bootstrap, if `hasLaunched` is missing AND the keychain timestamp is
/// older than `staleAfter` (default: 7 days), we purge the Supabase session
/// and any local onboarding progress so the user lands on the Welcome screen.
/// If the timestamp is younger than 7 days, we preserve the session — a user
/// who reinstalls quickly shouldn't lose their context.
///
/// Thread-safety: the guard only reads/writes during `bootstrap()` and on
/// auth events — all on `@MainActor` via SessionStore, which is sufficient
/// for our needs.
@MainActor
final class SessionFreshnessGuard {
    static let shared = SessionFreshnessGuard()

    // MARK: - Tunables

    /// After this much inactivity, a fresh install signs the user out.
    static let staleAfter: TimeInterval = 7 * 24 * 60 * 60  // 7 days

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
    func shouldPurgeStaleSession() -> Bool {
        let isFreshInstall = !defaults.bool(forKey: hasLaunchedKey)

        if !isFreshInstall {
            // Not a fresh install — the user already launched this install at
            // least once. The normal Supabase refresh flow handles everything.
            return false
        }

        // Fresh install. The Keychain may still hold a session token from a
        // previous install of this app on this device. Decide based on how
        // old the last activity is.
        let lastActive = readLastActive()

        // Flip the launched flag immediately so subsequent calls during this
        // process (and future cold starts) don't re-enter this branch.
        defaults.set(true, forKey: hasLaunchedKey)

        guard let lastActive else {
            // No prior timestamp. Either this is the very first install ever
            // on this device, or the previous install never authenticated.
            // Purge conservatively — we want Welcome, not a silent session.
            logger.info("Fresh install with no prior activity timestamp — purging stale session")
            return true
        }

        let age = Date().timeIntervalSince(lastActive)
        if age > Self.staleAfter {
            logger.info("Fresh install, last activity \(Int(age), privacy: .public)s ago (> 7d) — purging stale session")
            return true
        }

        logger.info("Fresh install within 7d grace (last activity \(Int(age), privacy: .public)s ago) — keeping session")
        return false
    }

    /// Called after the session has been purged so the router falls back to
    /// the very first screen (Welcome) rather than an intermediate step like
    /// the post-paywall tutorial.
    func resetLocalProgress() {
        defaults.removeObject(forKey: tutorialKey)
        deleteLastActive()
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
