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
///   └──────────[forfeited cooldown elapses ─ 7 d]────── + fresh-gift celebration ◀─────────────────┘
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
    ///
    /// Tuned to 7 days: a weekly rhythm keeps the gift feeling like a
    /// genuine, scarce "event" rather than ambient pricing — which
    /// preserves the urgency of the 24 h claim window. A shorter
    /// cooldown would let users simply wait it out.
    static let reissueCooldown: TimeInterval = 7 * 86_400      // 7 days
    static let defaultGiftDiscount: Int = 25
    /// How long after a forfeit the Home "something's cooking" teaser
    /// stays hidden. A short quiet period so the card lands as a
    /// pleasant discovery mid-cooldown rather than an instant
    /// consolation prize the user would tune out.
    static let giftTeaserRevealDelay: TimeInterval = 2 * 86_400   // 2 days

    // MARK: - State

    /// Coarse machine state. The fine-grained timestamps live in
    /// `giftWonAt`, `giftConsumedAt`, `giftForfeitedAt`, etc.
    enum GiftPhase: String {
        case notWon            // never played, or cooldown just ended
        case won               // mini-game played, discount usable in next 24 h
        case pendingFromTrial  // started the annual trial with the gift; waiting on conversion
        case consumed          // gift was effectively used (annual paid). Terminal — never returns.
        case forfeited         // 24 h window lapsed, or trial cancelled before billing. 7 d cooldown.
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
    private let lastAutoShownAtKey = "cooksy.gift.lastAutoShownAt"

    // MARK: - Auto-presentation throttle

    /// Minimum elapsed time between two auto-presentations of the gift,
    /// regardless of origin. Without this floor the user could see the
    /// gift on app launch, dismiss it, open Settings 10 seconds later
    /// and be slapped with it again — fastest way to make the offer
    /// feel like spam. Six hours is the smallest window that still
    /// lets the gift surface across a typical day's usage.
    static let autoShowMinInterval: TimeInterval = 6 * 3600

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
    ///
    /// The user cycles through these in declaration order: a fresh
    /// game each gift cycle so the offer never feels repetitive. Every
    /// variant is rigged to award the same −25 % jackpot.
    enum GiftGameKind: String, CaseIterable {
        case wheel
        case scratchCard
        case mysteryBox
        case cardFlip
        case cupShuffle
        case balloonPop

        /// SF Symbol that hints at this mini-game on the home gift pill,
        /// so the user gets a visual whisper of what awaits when they tap.
        /// Rotates with the cycle, never the same two cycles in a row.
        var pillIconSystemName: String {
            switch self {
            case .wheel:       return "dial.medium"
            case .scratchCard: return "rectangle.dashed"
            case .mysteryBox:  return "shippingbox.fill"
            case .cardFlip:    return "rectangle.on.rectangle.fill"
            case .cupShuffle:  return "cup.and.saucer.fill"
            case .balloonPop:  return "balloon.fill"
            }
        }

        /// Human-readable label for the mini-game — used in the HYPE
        /// takeover when announcing a fresh cycle.
        var displayName: String {
            switch self {
            case .wheel:       return "la Roue de la chance"
            case .scratchCard: return "le Ticket à gratter"
            case .mysteryBox:  return "la Boîte mystère"
            case .cardFlip:    return "les Cartes retournées"
            case .cupShuffle:  return "le Bonneteau"
            case .balloonPop:  return "les Ballons à éclater"
            }
        }
    }

    /// SF Symbol to render inside the home gift pill. While the gift is
    /// in cooldown (`.forfeited`) we keep the generic gift glyph: the
    /// tap doesn't open a game yet, so teasing the next game's shape
    /// would over-promise. In every other phase we surface the active
    /// cycle's game-specific glyph.
    var giftPillIconSystemName: String {
        giftPhase == .forfeited ? "gift.fill" : currentGiftGameKind.pillIconSystemName
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "PremiumOffers")
    /// Guards against queueing more than one deferred rollover at a time
    /// (see `rollOverIfNeeded()`).
    private var rolloverScheduled = false

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
        applyRolloverNow()
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
    /// bar.
    ///
    /// We keep the pill visible in `.forfeited` too (with a "Bientôt · Xj"
    /// countdown copy) — hiding it for a full 7 days was confusing users
    /// who wondered where the gift had gone. The cooldown is enforced at
    /// the tap level: the wheel doesn't re-open until the timer elapses.
    /// `.pendingFromTrial` and `.consumed` stay hidden — the user is
    /// either already in trial (premium) or has already paid with the
    /// gift, so the pill would be dead weight.
    var shouldShowGiftPill: Bool {
        rollOverIfNeeded()
        switch giftPhase {
        case .notWon, .won, .forfeited: return true
        case .pendingFromTrial, .consumed: return false
        }
    }

    /// Whole days remaining before a forfeited gift cycle rolls over to a
    /// fresh `.notWon`. `nil` outside `.forfeited`. Drives the "Bientôt ·
    /// Xj" label on the Home gift pill.
    var giftCooldownDaysRemaining: Int? {
        guard giftPhase == .forfeited, let endsAt = giftCooldownEndsAt else { return nil }
        let seconds = endsAt.timeIntervalSinceNow
        guard seconds > 0 else { return 0 }
        return max(1, Int(ceil(seconds / 86_400)))
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

    // MARK: - Gift teaser (Home "something's cooking" card)

    /// `true` once a forfeited gift has been cooling down long enough
    /// for the Home anticipation card to surface (see
    /// `giftTeaserRevealDelay`). False outside the `.forfeited` phase.
    var shouldShowGiftTeaser: Bool {
        rollOverIfNeeded()
        guard giftPhase == .forfeited, let started = giftForfeitedAt else { return false }
        return Date().timeIntervalSince(started) >= Self.giftTeaserRevealDelay
    }

    /// Timestamp the current cooldown started (the forfeit moment).
    /// Nil when no forfeit is on record.
    var giftForfeitedAt: Date? {
        defaults.object(forKey: giftForfeitedAtKey) as? Date
    }

    /// "Cooking" progress 0...1 across the whole reissue cooldown —
    /// drives the teaser's gauge, lid lift and glow intensity.
    var giftTeaserProgress: Double {
        guard let started = giftForfeitedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(started)
        return min(1, max(0, elapsed / Self.reissueCooldown))
    }

    /// Seconds left before the gift becomes claimable again, clamped
    /// at zero once the cooldown has elapsed.
    var giftCooldownRemaining: TimeInterval {
        guard let ends = giftCooldownEndsAt else { return 0 }
        return max(0, ends.timeIntervalSince(Date()))
    }

    // MARK: - Mini-game outcomes

    /// Records a successful gift game. Stamps the discount + the
    /// timestamp so the 24 h countdown starts now.
    func recordGiftWon(percent: Int) {
        defaults.set(Date(), forKey: giftWonAtKey)
        defaults.set(percent, forKey: giftDiscountKey)
        giftDiscountPercent = percent
        let expiresAt = Date().addingTimeInterval(Self.giftOfferDuration)
        giftOfferExpiresAt = expiresAt
        setPhase(.won)
        logger.info("Gift offer won: -\(percent, privacy: .public) % for 24 h")

        // The gift was just won — any pending cooldown anticipation
        // notifications are now obsolete.
        NotificationScheduler.cancelGiftCooldown()

        // H1 — schedule the "6 h left" local reminder so the discount
        // window doesn't quietly lapse while the app is closed.
        NotificationScheduler.scheduleGiftExpiry(
            expiresAt: expiresAt,
            discountPercent: percent
        )
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
        applyRolloverNow()

        // A confirmed purchase always retires the gift-expiry and the
        // onboarding welcome nudges — the user is past that funnel now.
        // The trial reminder series is kept when `inTrial` (the user
        // genuinely is mid-trial and J-2/J-1 still matter); a direct
        // paid purchase cancels everything.
        if inTrial {
            NotificationScheduler.cancelGiftExpiry()
            NotificationScheduler.cancelWelcome()
        } else {
            NotificationScheduler.cancelAllConversionNudges()
        }

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
        applyRolloverNow()
        guard giftPhase == .pendingFromTrial else { return }
        consumeGiftNow()
        logger.info("Annual trial converted — gift consumed, 7 d cooldown started")
    }

    /// Wire this when the user cancels their annual trial before the
    /// first billing. Without this hook, the gift would remain in
    /// `pendingFromTrial` forever and the user could never replay.
    func recordTrialCancelled() {
        applyRolloverNow()
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
        let cooldownEnd = now.addingTimeInterval(Self.reissueCooldown)
        giftCooldownEndsAt = cooldownEnd
        setPhase(.forfeited)

        // Schedule the anticipation notifications that pull the user
        // back to watch the Home "something's cooking" card simmer
        // toward its reveal.
        NotificationScheduler.scheduleGiftCooldown(
            cooldownEndsAt: cooldownEnd,
            teaserAppearsAt: now.addingTimeInterval(Self.giftTeaserRevealDelay)
        )
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

    // MARK: - Auto-presentation

    /// Where in the app the gift is being considered for auto-presentation.
    /// Each origin has its own probability so the gift surfaces more
    /// often in high-intent contexts (opening the app) than in lower-
    /// intent ones (entering settings), without turning into spam.
    enum AutoShowOrigin {
        case appLaunch      // ~1 in 4 — Home appearance
        case settingsOpen   // ~1 in 6 — Profile / settings entry
        case importSuccess  // ~1 in 5 — right after a successful import

        var probability: Double {
            switch self {
            case .appLaunch:     return 1.0 / 4.0
            case .settingsOpen:  return 1.0 / 6.0
            case .importSuccess: return 1.0 / 5.0
            }
        }
    }

    /// Decides whether the host view should auto-present the gift sheet
    /// (game OR exclusive offer, depending on phase). The host is then
    /// responsible for routing based on `giftPhase` — this method only
    /// owns the *whether*.
    ///
    /// Eligibility:
    ///   • Gift must be in `.notWon` or `.won + active` (other phases
    ///     have nothing meaningful to present).
    ///   • At least `autoShowMinInterval` must have elapsed since the
    ///     last auto-show across all origins (anti-spam floor).
    ///
    /// Returns: `true` with the origin's probability when eligible.
    /// The caller MUST invoke `recordAutoShownNow()` if it goes ahead
    /// and presents — otherwise the throttle never engages.
    func shouldAutoShow(from origin: AutoShowOrigin) -> Bool {
        rollOverIfNeeded()

        // Only meaningful in phases where there's something to present.
        // Forfeited gives the cooldown screen — distinct UX, not part
        // of the silent auto-show loop.
        switch giftPhase {
        case .notWon: break
        case .won where giftOfferIsActive: break
        default: return false
        }

        if let lastShown = defaults.object(forKey: lastAutoShownAtKey) as? Date,
           Date().timeIntervalSince(lastShown) < Self.autoShowMinInterval {
            return false
        }

        return Double.random(in: 0..<1) < origin.probability
    }

    /// Stamps "we just auto-presented the gift" so the throttle knows
    /// when to gate the next opportunity. Call this immediately after
    /// presenting (not on dismiss) so a quick-close still consumes the
    /// slot for the next 6 h window.
    func recordAutoShownNow() {
        defaults.set(Date(), forKey: lastAutoShownAtKey)
    }

    // MARK: - Debug

    func resetAllOffers() {
        for key in [
            firstSeenKey, giftWonAtKey, giftDiscountKey, giftPhaseKey,
            giftPendingTrialAtKey, giftConsumedAtKey, giftForfeitedAtKey,
            freshGiftCelebrationKey, giftCycleIndexKey, freeModeKey,
            lastAutoShownAtKey
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

    /// Idempotent self-heal — **deferred** entry point. Safe to call
    /// from inside a SwiftUI `body` (every public read does): when a
    /// phase transition is due it is applied on the next run-loop tick,
    /// never synchronously.
    ///
    /// Why deferral matters: the previous version called
    /// `startReissueCooldown` / `resetToNotWon` directly from getters
    /// like `shouldShowGiftPill`, which SwiftUI evaluates *inside* a
    /// view `body`. Mutating `@Published` state during a view update is
    /// undefined behaviour ("Modifying state during view update…") and
    /// was a plausible cause of the gift pill flickering / vanishing
    /// intermittently. Deferring the mutation guarantees it always
    /// lands outside the render pass.
    ///
    /// Transitions handled by `applyRolloverNow()`:
    ///   • `.won` whose 24 h claim window lapsed → `.forfeited` (cooldown).
    ///   • `.forfeited` whose cooldown elapsed → `.notWon` + celebration.
    ///   • `.consumed` → terminal, never rolls back.
    private func rollOverIfNeeded() {
        guard rolloverIsDue(), !rolloverScheduled else { return }
        rolloverScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rolloverScheduled = false
            self.applyRolloverNow()
        }
    }

    /// Pure predicate — is a phase transition currently due? No
    /// mutation, so it is safe to evaluate during a view update.
    private func rolloverIsDue() -> Bool {
        let now = Date()
        switch giftPhase {
        case .won:
            guard let expiry = giftOfferExpiresAt else { return false }
            return expiry <= now
        case .forfeited:
            guard let forfeitedAt = defaults.object(forKey: giftForfeitedAtKey) as? Date
            else { return false }
            return now.timeIntervalSince(forfeitedAt) >= Self.reissueCooldown
        case .consumed, .notWon, .pendingFromTrial:
            return false
        }
    }

    /// Synchronous transition application. Used only at safe call sites
    /// (init / rehydrate, purchase hooks) where mutating `@Published`
    /// state immediately is fine because we are not inside a `body`.
    private func applyRolloverNow() {
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

    /// Nuke every gift-related persisted flag and reset the in-memory
    /// state to `.notWon`. Used by `SessionFreshnessGuard` on fresh
    /// installs and by `SessionStore` when the user signs out or signs
    /// in to a different account — both contexts where any lingering
    /// discount from a previous user/session must NOT carry over.
    ///
    /// Unlike `resetToNotWon(scheduleCelebration:)`, this method also
    /// clears `firstSeenKey`, `giftCycleIndexKey`, `freeModeKey`, and
    /// the "fresh celebration pending" flag — i.e. it's a full wipe,
    /// not a phase transition.
    func resetAllGiftStateForNewSession() {
        defaults.removeObject(forKey: firstSeenKey)
        defaults.removeObject(forKey: giftWonAtKey)
        defaults.removeObject(forKey: giftDiscountKey)
        defaults.removeObject(forKey: giftPhaseKey)
        defaults.removeObject(forKey: giftPendingTrialAtKey)
        defaults.removeObject(forKey: giftConsumedAtKey)
        defaults.removeObject(forKey: giftForfeitedAtKey)
        defaults.removeObject(forKey: freshGiftCelebrationKey)
        defaults.removeObject(forKey: giftCycleIndexKey)
        defaults.removeObject(forKey: freeModeKey)
        defaults.removeObject(forKey: lastAutoShownAtKey)

        giftPhase = .notWon
        giftDiscountPercent = nil
        giftOfferExpiresAt = nil
        giftCooldownEndsAt = nil
        userChoseFreeMode = false
        hasFreshGiftCelebrationPending = false
        giftCycleIndex = 0

        // Drop any pending gift-cooldown notifications so a previous
        // user's anticipation pings never fire for the new account.
        NotificationScheduler.cancelGiftCooldown()

        logger.info("Gift state fully reset for new session")
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

        applyRolloverNow()
    }
}
