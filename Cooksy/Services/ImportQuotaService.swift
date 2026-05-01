import Foundation
import Combine
import OSLog

/// Tracks the free-plan recipe-import quota: 3 imports per **rolling 7-day
/// window** anchored on the user's *first* import. Premium users
/// (`SessionStore.profile.isPremium == true`) bypass the quota entirely.
///
/// The previous behaviour reset every Monday at 00:00 (ISO week). That
/// felt arbitrary — a user installing on Saturday only got 2 days of
/// imports before the reset. The window now starts ticking *when the
/// user actually does something* and resets exactly 7 days later.
///
/// State is persisted in UserDefaults so the count and window survive
/// app relaunches.
@MainActor
final class ImportQuotaService: ObservableObject {
    static let shared = ImportQuotaService()

    /// Free-plan limit per rolling window. Premium users have no limit.
    static let freeWeeklyLimit = 3
    /// Length of the rolling window, anchored on the first import.
    static let windowDuration: TimeInterval = 7 * 86_400

    /// Number of imports already consumed during the current window.
    @Published private(set) var currentCount: Int = 0

    /// `true` if the active session belongs to a premium user — set
    /// from `SessionStore.profile.isPremium` whenever it changes.
    @Published var isPremium: Bool = false

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "ImportQuota")

    private let countKey = "cooksy.importQuota.count"
    private let windowStartedAtKey = "cooksy.importQuota.windowStartedAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rolloverIfWindowExpired()
        currentCount = defaults.integer(forKey: countKey)
    }

    /// `true` if the user is allowed to start a new import. Always true
    /// for premium users; for free users this is true only while
    /// `count < limit` within the active window.
    var canImport: Bool {
        if isPremium { return true }
        rolloverIfWindowExpired()
        return currentCount < Self.freeWeeklyLimit
    }

    /// Number of imports remaining this window. Returns `Int.max` for
    /// premium so callers don't have to special-case.
    var remainingThisWeek: Int {
        if isPremium { return .max }
        rolloverIfWindowExpired()
        return max(Self.freeWeeklyLimit - currentCount, 0)
    }

    /// Number of seconds until the next reset (= window expiry).
    /// Returns 0 if the window hasn't started yet (the user is still
    /// at 3/3 — there's nothing to count down from).
    var secondsUntilReset: TimeInterval {
        guard let windowStartedAt = defaults.object(forKey: windowStartedAtKey) as? Date else {
            return 0
        }
        let resetAt = windowStartedAt.addingTimeInterval(Self.windowDuration)
        return max(resetAt.timeIntervalSince(Date()), 0)
    }

    /// Call this AFTER a successful recipe import. Increments the count
    /// and persists. No-op for premium users. Stamps the window start
    /// timestamp on the *first* import so the rolling window begins
    /// from real activity rather than from app install.
    func incrementOnSuccess() {
        guard !isPremium else { return }
        rolloverIfWindowExpired()

        // Anchor the window on the very first import in this cycle.
        if defaults.object(forKey: windowStartedAtKey) == nil {
            defaults.set(Date(), forKey: windowStartedAtKey)
        }

        currentCount += 1
        defaults.set(currentCount, forKey: countKey)
        logger.info("Import quota: \(self.currentCount, privacy: .public)/\(Self.freeWeeklyLimit, privacy: .public) (window started)")
    }

    /// Reset hook used by tests / debug menu. NOT exposed in production UI.
    func resetForDebug() {
        currentCount = 0
        defaults.set(0, forKey: countKey)
        defaults.removeObject(forKey: windowStartedAtKey)
    }

    // MARK: - Internals

    /// Walks the window clock and resets when 7 days have elapsed since
    /// the first import. Idempotent — safe to call from every read.
    private func rolloverIfWindowExpired() {
        guard let windowStartedAt = defaults.object(forKey: windowStartedAtKey) as? Date else {
            return
        }
        if Date().timeIntervalSince(windowStartedAt) >= Self.windowDuration {
            defaults.removeObject(forKey: windowStartedAtKey)
            defaults.set(0, forKey: countKey)
            currentCount = 0
            logger.info("Import quota window expired — reset to 0/\(Self.freeWeeklyLimit, privacy: .public)")
        }
    }
}
