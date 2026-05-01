import Foundation
import Combine
import OSLog

/// Single source of truth for Cooksy's promotional offers.
///
/// Lifecycle of a gift offer (–25 % on the **annual** plan only):
///
/// ```
/// notWon ──[plays + wins mini-game]──▶ won (24 h window)
///   ▲                                    │
///   │                                    ├─[buys annual w/o trial]──▶ consumed (7 d cooldown) ──▶ notWon
///   │                                    ├─[starts annual w/ trial]──▶ pendingFromTrial ──┐
///   │                                    │                                                 │
///   │                                    └─[24 h elapses, no purchase]──▶ notWon          │
///   │                                                                                      │
///   ├──────────[trial converts (J+7)]──────────────────────────────────▶ consumed (7 d cooldown)
///   │                                                                                      │
///   └──────────[trial cancelled before billing]────────────────────────▶ forfeited (3 d cooldown)
/// ```
///
/// Cooldowns drive the visibility of the gift pill on Home (and the
/// "OFFRE −25 %" tag on the paywall). During cooldown the user sees
/// nothing at all so they don't perceive the discount as "always there".
///
/// All state is persisted in UserDefaults so countdowns survive both
/// app relaunches and quick device reboots.
@MainActor
final class PremiumOffersService: ObservableObject {
    static let shared = PremiumOffersService()

    // MARK: - Tunables

    static let giftOfferDuration: TimeInterval = 24 * 3600     // 24 h to claim
    static let consumedCooldown: TimeInterval = 7 * 86_400     // 7 days after a real conversion
    static let forfeitedCooldown: TimeInterval = 3 * 86_400    // 3 days after cancelling a trial
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
    private let freeModeKey = "cooksy.userChoseFreeMode"

    // MARK: - Published state

    @Published private(set) var giftPhase: GiftPhase = .notWon
    @Published private(set) var giftDiscountPercent: Int?
    @Published private(set) var giftOfferExpiresAt: Date?
    @Published private(set) var giftCooldownEndsAt: Date?
    @Published private(set) var userChoseFreeMode: Bool = false

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

    /// Wire this from the paywall's CTA right BEFORE flipping
    /// `setPremiumMock(true)`. The service decides whether the gift is
    /// being consumed instantly (annual w/o trial), held in escrow until
    /// conversion (annual w/ trial), or simply ignored (monthly purchase).
    ///
    /// Pass:
    ///   • `plan` — the plan the user is purchasing
    ///   • `usingFreeTrial` — whether the trial toggle was on
    func recordPurchaseStarted(plan: PremiumPlan, usingFreeTrial: Bool) {
        rollOverIfNeeded()

        guard plan == .yearly, giftPhase == .won, giftOfferIsActive else {
            // Monthly plan, or no active gift — leave the gift state
            // untouched. If the gift was won but the user picked
            // monthly, the gift remains valid for its 24 h window so
            // they can come back and use it on the annual plan.
            logger.info("Purchase started (\(plan.rawValue, privacy: .public), trial=\(usingFreeTrial, privacy: .public)) — gift state unchanged (\(self.giftPhase.rawValue, privacy: .public))")
            return
        }

        if usingFreeTrial {
            // Hold the gift in escrow until the trial converts. If the
            // user cancels first, `recordTrialCancelled` will move us to
            // .forfeited.
            defaults.set(Date(), forKey: giftPendingTrialAtKey)
            setPhase(.pendingFromTrial)
            logger.info("Annual trial started w/ gift — phase=pendingFromTrial")
        } else {
            // Direct purchase with the discount = the gift is consumed
            // immediately. 7 d cooldown.
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
        let now = Date()
        defaults.set(now, forKey: giftForfeitedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        giftCooldownEndsAt = now.addingTimeInterval(Self.forfeitedCooldown)
        setPhase(.forfeited)
        logger.info("Annual trial cancelled before billing — 3 d cooldown started")
    }

    private func consumeGiftNow() {
        let now = Date()
        defaults.set(now, forKey: giftConsumedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        giftCooldownEndsAt = now.addingTimeInterval(Self.consumedCooldown)
        setPhase(.consumed)
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
            freeModeKey
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
    /// states back to `.notWon` so the user can replay. Called from
    /// every public read so we never serve stale state.
    private func rollOverIfNeeded() {
        let now = Date()

        switch giftPhase {
        case .won:
            // 24 h window expired without a purchase → re-enable the
            // mini-game without any cooldown (the user simply didn't
            // claim).
            if let expiry = giftOfferExpiresAt, expiry <= now {
                resetToNotWon()
            }

        case .consumed:
            if let consumedAt = defaults.object(forKey: giftConsumedAtKey) as? Date,
               now.timeIntervalSince(consumedAt) >= Self.consumedCooldown {
                resetToNotWon()
            }

        case .forfeited:
            if let forfeitedAt = defaults.object(forKey: giftForfeitedAtKey) as? Date,
               now.timeIntervalSince(forfeitedAt) >= Self.forfeitedCooldown {
                resetToNotWon()
            }

        case .notWon, .pendingFromTrial:
            break
        }
    }

    private func resetToNotWon() {
        defaults.removeObject(forKey: giftWonAtKey)
        defaults.removeObject(forKey: giftConsumedAtKey)
        defaults.removeObject(forKey: giftForfeitedAtKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        giftDiscountPercent = nil
        giftOfferExpiresAt = nil
        giftCooldownEndsAt = nil
        setPhase(.notWon)
    }

    private func rehydrate() {
        userChoseFreeMode = defaults.bool(forKey: freeModeKey)

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

        if let consumedAt = defaults.object(forKey: giftConsumedAtKey) as? Date {
            giftCooldownEndsAt = consumedAt.addingTimeInterval(Self.consumedCooldown)
        } else if let forfeitedAt = defaults.object(forKey: giftForfeitedAtKey) as? Date {
            giftCooldownEndsAt = forfeitedAt.addingTimeInterval(Self.forfeitedCooldown)
        }

        rollOverIfNeeded()
    }
}
