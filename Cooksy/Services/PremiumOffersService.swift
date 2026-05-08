import Foundation
import Combine
import OSLog

/// Single source of truth for Cooksy's promotional offers.
///
/// Lifecycle of a gift offer (annual plan only):
///
/// ```
/// notWon ──[plays + wins mini-game]──▶ won (24 h window)
///   ▲                                    │
///   │                                    ├─[buys annual w/o trial]──▶ consumed (TERMINAL — never returns)
///   │                                    │
///   │                                    ├─[starts annual w/ trial]──▶ pendingFromTrial
///   │                                    │                                  │
///   │                                    │                                  ├─[trial converts]──▶ consumed (TERMINAL)
///   │                                    │                                  │
///   │                                    │                                  └─[trial cancelled]──▶ forfeited
///   │                                    │                                                          │
///   │                                    └─[24 h elapses without purchase]──────────▶ forfeited ──┤
///   │                                                                                              │
///   └──────────[forfeited cooldown elapses ─ 6 d]────── + fresh-gift celebration ◀─────────────────┘
/// ```
///
/// Two important UX guarantees:
///   • **Once paid, the gift is gone forever.** A user who consumed
///     the gift via a real purchase doesn't get another chance — even
///     after a downgrade. (`.consumed` is terminal.)
///   • **Free users get a second chance.** If a user ignored the
///     24 h window or cancelled their trial, the pill comes back
///     after the reissue cooldown with a celebration animation on
///     Home so they know it's a fresh shot.
///
/// All state is persisted in UserDefaults so countdowns survive both
/// app relaunches and quick device reboots.
@MainActor
final class PremiumOffersService: ObservableObject {
    static let shared = PremiumOffersService()

    // MARK: - Tunables

    static let giftOfferDuration: TimeInterval = 24 * 3600     // 24 h to claim
    /// How long the gift pill stays hidden when the user didn't bite —
    /// either because the 24 h window expired or the trial was
    /// cancelled before billing. After this delay the pill comes back
    /// with a "fresh chance" celebration animation on Home.
    static let reissueCooldown: TimeInterval = 6 * 86_400      // 6 days
    static let defaultGiftDiscount: Int = 25

    // MARK: - State

    /// Coarse machine state. The fine-grained timestamps live in
    /// `giftWonAt`, `giftConsumedAt`, `giftForfeitedAt`, etc.
    enum GiftPhase: String {
        case notWon            // never played, or cooldown just ended
        case won               // mini-game played, discount usable in next 24 h
        case pendingFromTrial  // started the annual trial with the gift; waiting on conversion
        case consumed          // gift was effectively used (annual paid). 7 d cooldown.
        case forfeited         // user cancelled the trial before billing. 3 d cooldown.
    }

    // MARK: - Storage keys

    private let firstSeenKey = "cooksy.paywall.firstSeenAt"
    private let giftWonAtKey = "cooksy.gift.wonAt"
    private let giftDiscountKey = "cooksy.gift.discountPercent"
    private let giftPhaseKey = "cooksy.gift.phase"
    private let giftPendingTrialAtKey = "cooksy.gift.pendingTrialAt"
    private let giftConsumedAtKey = "cooksy.gift.consumedAt"
    private let giftForfeitedAtKey = "cooksy.gift.forfeitedAt"
    private let freshGiftCelebrationKey = "cooksy.gift.freshCelebrationPending"
    private let giftCycleIndexKey = "cooksy.gift.cycleIndex"
    private let freeModeKey = "cooksy.userChoseFreeMode"

    // MARK: - Published state

    @Published private(set) var giftPhase: GiftPhase = .notWon
    @Published private(set) var giftDiscountPercent: Int?
    @Published private(set) var giftOfferExpiresAt: Date?
    @Published private(set) var giftCooldownEndsAt: Date?
    @Published private(set) var userChoseFreeMode: Bool = false
    /// Set to `true` the first time the gift pill rolls over from a
    /// cooldown back to `.notWon` — the Home screen reads this to fire a
    /// "you've got a new chance!" celebration. Cleared by
    /// `acknowledgeFreshGiftCelebration()` once the user has seen it.
    @Published private(set) var hasFreshGiftCelebrationPending: Bool = false

    /// Monotonic counter incremented at the start of each new gift
    /// cycle (i.e. when transitioning from cooldown back to `.notWon`).
    /// Drives the rotation between mini-games so the user doesn't see
    /// the same one every cooldown.
    @Published private(set) var giftCycleIndex: Int = 0

    /// Which mini-game should be presented for the current cycle.
    /// Stable within a cycle so re-opening the gift sheet doesn't
    /// surprise the user with a different game mid-flow.
    var currentGiftGameKind: GiftGameKind {
        let count = max(GiftGameKind.allCases.count, 1)
        let index = ((giftCycleIndex % count) + count) % count
        return GiftGameKind.allCases[index]
    }

    /// One mini-game variant. Adding a new case here, plus a matching
    /// view in `GiftMiniGameHost`, is enough to slot it into the
    /// rotation — no other change required.
    enum GiftGameKind: String, CaseIterable {
        case wheel
        case scratchCard
        case mysteryBox
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "PremiumOffers")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rehydrate()
    }

    // MARK: - Paywall lifecycle

    /// Stamp "first paywall view" so we can decide whether to auto-show
    /// the gift mini-game on subsequent visits.
    func paywallWasReached() {
        if defaults.object(forKey: firstSeenKey) == nil {
            defaults.set(Date(), forKey: firstSeenKey)
        }
        rollOverIfNeeded()
    }

    /// True if the user hasn't played the mini-game yet — used to
    /// auto-present it shortly after the paywall appears the first time.
    /// Auto-show is skipped during cooldowns and during a pending trial.
    var shouldAutoShowGift: Bool {
        rollOverIfNeeded()
        return giftPhase == .notWon
            && defaults.object(forKey: giftWonAtKey) == nil
    }

    // MARK: - Public read API used by the UI

    /// True only when the gift pill should be rendered on the Home top-
    /// bar. Hidden during cooldowns, pending trials, and after a true
    /// conversion (until the 7 d cooldown ends).
    var shouldShowGiftPill: Bool {
        rollOverIfNeeded()
        switch giftPhase {
        case .notWon, .won: return true
        case .pendingFromTrial, .consumed, .forfeited: return false
        }
    }

    /// True when the −25 % can actually be applied to a purchase made
    /// right now. This is the only check the price formatter cares about.
    var giftOfferIsActive: Bool {
        rollOverIfNeeded()
        guard giftPhase == .won, let expiry = giftOfferExpiresAt else { return false }
        return expiry > Date()
    }

    /// True if the user has ever played and won the mini-game (used by
    /// the gift sheet to skip the loss/win animation on re-entry).
    var giftHasBeenWon: Bool {
        defaults.object(forKey: giftWonAtKey) != nil
    }

    // MARK: - Mini-game outcomes

    /// Records a successful gift game. Stamps the discount + the
    /// timestamp so the 24 h countdown starts now.
    func recordGiftWon(percent: Int) {
        defaults.set(Date(), forKey: giftWonAtKey)
        defaults.set(percent, forKey: giftDiscountKey)
        giftDiscountPercent = percent
        giftOfferExpiresAt = Date().addingTimeInterval(Self.giftOfferDuration)
        setPhase(.won)
        logger.info("Gift offer won: -\(percent, privacy: .public) % for 24 h")
    }

    // MARK: - Purchase / cancellation hooks

    /// Wire this AFTER a purchase has actually been confirmed by
    /// StoreKit (RevenueCat returned without `userCancelled`). The
    /// service decides whether the gift is consumed instantly (annual
    /// paid up-front), held in escrow until trial conversion (annual
    /// w/ trial), or simply ignored (monthly purchase).
    ///
    /// Pass:
    ///   • `plan` — the plan the user actually bought
    ///   • `inTrial` — whether the entitlement Apple just granted is in
    ///     a free-trial period (read from `PurchaseService.isInTrial` —
    ///     NOT the UI toggle, since Apple may refuse the trial).
    ///
    /// Critical: this MUST run only after the purchase succeeded,
    /// otherwise a cancelled checkout would silently consume the gift
    /// and the user would lose access to the home pill without ever
    /// being charged.
    func recordPurchaseCompleted(plan: PremiumPlan, inTrial: Bool) {
        rollOverIfNeeded()

        guard plan == .yearly, giftPhase == .won, giftOfferIsActive else {
            // Monthly plan, or no active gift — leave the gift state
            // untouched. If the gift was won but the user picked
            // monthly, the gift remains valid for its 24 h window so
            // they can come back and use it on the annual plan.
            logger.info("Purchase completed (\(plan.rawValue, privacy: .public), trial=\(inTrial, privacy: .public)) — gift state unchanged (\(self.giftPhase.rawValue, privacy: .public))")
            return
        }

        if inTrial {
            // Hold the gift in escrow until the trial converts. If the
            // user cancels first, `recordTrialCancelled` will move us to
            // .forfeited.
            defaults.set(Date(), forKey: giftPendingTrialAtKey)
            setPhase(.pendingFromTrial)
            logger.info("Annual trial started w/ gift — phase=pendingFromTrial")
        } else {
            // Direct paid purchase with the discount = the gift is
            // consumed immediately. 7 d cooldown.
            consumeGiftNow()
        }
    }

    /// Wire this when the trial converts to a paid subscription
    /// (typically driven by a StoreKit / Supabase webhook). For the
    /// mock-purchase flow we currently call this from `setPremiumMock`
    /// after the trial period elapses; in production this fires when
    /// Apple posts the first renewal receipt.
    func recordTrialConverted() {
        rollOverIfNeeded()
        guard giftPhase == .pendingFromTrial else { return }
        consumeGiftNow()
        logger.info("Annual trial converted — gift consumed, 7 d cooldown started")
    }

    /// Wire this when the user cancels their annual trial before the
    /// first billing. Without this hook, the gift would remain in
    /// `pendingFromTrial` forever and the user could never replay.
    func recordTrialCancelled() {
        rollOverIfNeeded()
        guard giftPhase == .pendingFromTrial else { return }
        startReissueCooldown(reason: "trial cancelled before billing")
    }

    /// Marks the gift as definitively used. We never roll back from
    /// `.consumed` — by design, a user who paid (directly or after a
    /// converted trial) has spent their one shot at the gift. They're
    /// already premium so the home pill is hidden anyway, but we still
    /// want the state machine to remember this forever in case they
    /// downgrade later.
    private func consumeGiftNow() {
        let now = Date()
        defaults.set(now, forKey: giftConsumedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        giftCooldownEndsAt = nil
        setPhase(.consumed)
    }

    /// Drops the won-but-unclaimed (or trial-cancelled) gift into the
    /// shared "wait & reissue" cooldown. After the cooldown elapses
    /// the gift comes back with a fresh-chance celebration.
    private func startReissueCooldown(reason: String) {
        let now = Date()
        defaults.set(now, forKey: giftForfeitedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        defaults.removeObject(forKey: giftWonAtKey)
        giftDiscountPercent = nil
        giftOfferExpiresAt = nil
        giftCooldownEndsAt = now.addingTimeInterval(Self.reissueCooldown)
        setPhase(.forfeited)
        logger.info("Gift reissue cooldown started (\(reason, privacy: .public)) — back in \(Self.reissueCooldown / 86_400, privacy: .public) d")
    }

    // MARK: - Fresh-gift celebration

    /// Called by Home once the "new chance" animation has been shown to
    /// the user, so it doesn't fire on every subsequent app launch.
    func acknowledgeFreshGiftCelebration() {
        defaults.removeObject(forKey: freshGiftCelebrationKey)
        hasFreshGiftCelebrationPending = false
    }

    // MARK: - Free mode

    /// `true` if the user explicitly closed the paywall to stay on the
    /// free plan. Persisted so a second app launch doesn't trap them
    /// back into the paywall.
    func chooseFreeMode() {
        defaults.set(true, forKey: freeModeKey)
        userChoseFreeMode = true
    }

    /// Clears the free-mode flag — call when the user goes premium so a
    /// future downgrade leads back to the paywall.
    func clearFreeModeChoice() {
        defaults.set(false, forKey: freeModeKey)
        userChoseFreeMode = false
    }

    // MARK: - Debug

    func resetAllOffers() {
        for key in [
            firstSeenKey, giftWonAtKey, giftDiscountKey, giftPhaseKey,
            giftPendingTrialAtKey, giftConsumedAtKey, giftForfeitedAtKey,
            freshGiftCelebrationKey, giftCycleIndexKey, freeModeKey
        ] {
            defaults.removeObject(forKey: key)
        }
        rehydrate()
    }

    // MARK: - Internals

    private func setPhase(_ phase: GiftPhase) {
        defaults.set(phase.rawValue, forKey: giftPhaseKey)
        giftPhase = phase
    }

    /// Idempotent self-heal: walks the cooldowns and rolls expired
    /// states forward so the user gets a fresh chance after the right
    /// delay. Called from every public read so we never serve stale
    /// state.
    ///
    /// Transitions:
    ///   • `.won` whose 24 h claim window has lapsed → `.forfeited`
    ///     with a 6-day reissue cooldown.
    ///   • `.forfeited` whose cooldown has elapsed → `.notWon` AND a
    ///     fresh-chance celebration is queued for the Home screen.
    ///   • `.consumed` → terminal, never rolls back. A user who has
    ///     already paid with the gift has spent their one shot — even
    ///     if they downgrade later, the gift never returns.
    private func rollOverIfNeeded() {
        let now = Date()

        switch giftPhase {
        case .won:
            if let expiry = giftOfferExpiresAt, expiry <= now {
                startReissueCooldown(reason: "24 h window expired without claim")
            }

        case .forfeited:
            if let forfeitedAt = defaults.object(forKey: giftForfeitedAtKey) as? Date,
               now.timeIntervalSince(forfeitedAt) >= Self.reissueCooldown {
                resetToNotWon(scheduleCelebration: true)
            }

        case .consumed, .notWon, .pendingFromTrial:
            break
        }
    }

    private func resetToNotWon(scheduleCelebration: Bool) {
        defaults.removeObject(forKey: giftWonAtKey)
        defaults.removeObject(forKey: giftConsumedAtKey)
        defaults.removeObject(forKey: giftForfeitedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        giftDiscountPercent = nil
        giftOfferExpiresAt = nil
        giftCooldownEndsAt = nil
        setPhase(.notWon)

        if scheduleCelebration {
            defaults.set(true, forKey: freshGiftCelebrationKey)
            hasFreshGiftCelebrationPending = true
            // New cycle = next mini-game in the rotation, so the user
            // doesn't replay the same one twice in a row.
            advanceGiftCycle()
        }
    }

    private func advanceGiftCycle() {
        giftCycleIndex &+= 1
        defaults.set(giftCycleIndex, forKey: giftCycleIndexKey)
    }

    private func rehydrate() {
        userChoseFreeMode = defaults.bool(forKey: freeModeKey)
        hasFreshGiftCelebrationPending = defaults.bool(forKey: freshGiftCelebrationKey)
        giftCycleIndex = defaults.integer(forKey: giftCycleIndexKey)

        if let raw = defaults.string(forKey: giftPhaseKey),
           let stored = GiftPhase(rawValue: raw) {
            giftPhase = stored
        } else {
            giftPhase = .notWon
        }

        if let wonAt = defaults.object(forKey: giftWonAtKey) as? Date {
            giftOfferExpiresAt = wonAt.addingTimeInterval(Self.giftOfferDuration)
            giftDiscountPercent = defaults.object(forKey: giftDiscountKey) as? Int ?? Self.defaultGiftDiscount
        }

        // Cooldown end-time is only meaningful for the .forfeited
        // (waiting-to-reissue) state. .consumed is now terminal.
        if let forfeitedAt = defaults.object(forKey: giftForfeitedAtKey) as? Date {
            giftCooldownEndsAt = forfeitedAt.addingTimeInterval(Self.reissueCooldown)
        }

        rollOverIfNeeded()
    }
}
