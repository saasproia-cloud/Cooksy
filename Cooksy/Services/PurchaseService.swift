import Foundation
import RevenueCat
import OSLog

/// Wraps RevenueCat and exposes a simple async API for purchasing,
/// restoring, and observing subscription status.
///
/// Call `configure()` once at app launch, then `login(userID:)` each time
/// a Supabase session is established so purchases are tied to the right user.
///
/// Live storefront prices and trial info are exposed as `@Published`
/// strings so the paywall always renders exactly what Apple is going to
/// bill. Never compute a discount on top of these strings — Apple only
/// honours promotional offers configured in App Store Connect.
@MainActor
final class PurchaseService: NSObject, ObservableObject {

    static let shared = PurchaseService()

    // MARK: - Published state

    /// The live RevenueCat offering (monthly + annual packages).
    @Published private(set) var currentOffering: Offering?

    /// Whether a purchase or restore operation is in flight.
    @Published private(set) var isLoading: Bool = false

    /// Premium status straight from RevenueCat's "premium" entitlement.
    @Published private(set) var isPremium: Bool = false

    /// True when the active premium entitlement is in a free-trial period.
    @Published private(set) var isInTrial: Bool = false

    /// Localized monthly price string from the StoreKit storefront,
    /// e.g. "7,99 €" or "$9.99". Mirrors what Apple will actually charge.
    @Published private(set) var monthlyPriceString: String?

    /// Localized annual price string from the StoreKit storefront.
    @Published private(set) var annualPriceString: String?

    /// Annual price divided by 12, formatted in the same currency
    /// (used for the "soit X/mois" reassurance line).
    @Published private(set) var annualMonthlyEquivalentString: String?

    /// Real trial duration in days extracted from the annual product's
    /// introductory offer. `nil` if no free-trial intro offer exists.
    @Published private(set) var annualTrialDays: Int?

    /// Whether the current Apple ID is eligible for the annual trial.
    /// Apple grants the trial only once per Apple ID — when this is
    /// false, the paywall must NOT promise a trial.
    @Published private(set) var isAnnualTrialEligible: Bool = false

    // MARK: - Private

    /// Sandbox-only fallback used when Info.plist has no `RevenueCatAPIKey`.
    /// In production builds the value MUST come from Info.plist (set in the
    /// build config or replaced before App Store submission). Find the live
    /// key in RevenueCat Dashboard → Project Settings → API Keys → Public
    /// app SDK key (starts with `appl_`).
    private static let sandboxFallbackKey = "appl_XyhiKYHcCHxYVpnLlnoqOokWWEu"

    private static var resolvedAPIKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? sandboxFallbackKey : trimmed
    }

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "PurchaseService")

    private override init() { super.init() }

    // MARK: - Setup

    /// Call once from `CooksyApp.init()` before any other RC call.
    func configure() {
        Purchases.logLevel = .warn
        let key = Self.resolvedAPIKey
        Purchases.configure(withAPIKey: key)
        Purchases.shared.delegate = self
        if key == Self.sandboxFallbackKey {
            logger.warning("[RC] Using sandbox fallback API key — set RevenueCatAPIKey in Info.plist with the live key before App Store submission.")
        }
    }

    // MARK: - User identity

    /// Associates the RevenueCat subscriber with the signed-in Supabase user.
    /// Must be called every time a new session is established.
    func login(userID: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userID)
            syncStatus(from: info)
            await refreshTrialEligibility()
        } catch {
            logger.error("RC login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the RC identity on sign-out so purchases aren't shared across accounts.
    func logout() async {
        do {
            _ = try await Purchases.shared.logOut()
            isPremium = false
            isInTrial = false
        } catch {
            logger.error("RC logout failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Offerings

    func fetchOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
            refreshDerivedFromOffering()
            await refreshTrialEligibility()
        } catch {
            logger.error("RC fetchOfferings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-checks whether the current Apple ID can still claim the annual
    /// free trial. Treats `.eligible` and `.unknown` as eligible (Apple
    /// gates at billing time), and `.ineligible` / `.noIntroOfferExists`
    /// as not eligible — when this returns false the paywall hides the
    /// trial promise instead of disappointing the user at checkout.
    ///
    /// We layer our own anti-abuse cooldown on top of Apple's eligibility:
    /// if the user already started a trial and let it lapse (no payment),
    /// we block free-trial UI for `Self.trialCooldownDuration` even though
    /// Apple itself technically still considers them eligible for a
    /// promo intro offer on a separate product. Prevents the
    /// "create new Apple ID every 7 days" exploit.
    func refreshTrialEligibility() async {
        guard let id = currentOffering?.annual?.storeProduct.productIdentifier else {
            isAnnualTrialEligible = false
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: [id])
        let status = result[id]?.status
        let appleEligible = (status == .eligible || status == .unknown)

        // Detect "abandoned trial": we recorded a trial start in the
        // past, the recorded window has elapsed, and the user is no
        // longer premium → they didn't convert. Burn the cooldown.
        promoteAbandonedTrialToCooldownIfNeeded()

        isAnnualTrialEligible = appleEligible && !isInTrialAbuseCooldown
    }

    // MARK: - Trial abuse cooldown

    /// Length of our local cooldown after a user starts a free trial
    /// and lets it expire without paying. Apple's eligibility check
    /// alone allows re-trial via different product/account, so we add
    /// this local gate to discourage abuse.
    static let trialCooldownDuration: TimeInterval = 60 * 86_400 // 60 d

    /// Maximum plausible duration of a single trial. Used to decide
    /// whether a recorded `trialStartedAt` should be treated as
    /// "still in flight" or "abandoned". 30 d covers Apple's typical
    /// 7-d/14-d/30-d trial windows comfortably.
    private static let trialMaxWindow: TimeInterval = 30 * 86_400

    private let trialStartedAtKey = "cooksy.trial.startedAt"
    private let trialCooldownUntilKey = "cooksy.trial.cooldownUntil"

    /// True when the user is in our local anti-abuse cooldown after
    /// having started a free trial that didn't convert to a paid sub.
    /// The paywall reads this in tandem with `isAnnualTrialEligible`
    /// and falls back to "no trial, regular price" copy.
    var isInTrialAbuseCooldown: Bool {
        guard let until = UserDefaults.standard.object(forKey: trialCooldownUntilKey) as? Date else {
            return false
        }
        return until > Date()
    }

    /// Stamp "trial just started". Called from the paywall's purchase
    /// completion handler when `isInTrial == true` so we have a baseline
    /// for the abuse detection on subsequent app launches.
    func recordTrialStarted() {
        UserDefaults.standard.set(Date(), forKey: trialStartedAtKey)
        // Clear any stale cooldown — the user has clearly re-engaged
        // with a new trial (Apple let them through).
        UserDefaults.standard.removeObject(forKey: trialCooldownUntilKey)
        logger.info("Trial started — recorded baseline at \(Date(), privacy: .public)")
    }

    /// Heuristic: if we previously recorded a trial start, more time
    /// has passed than a single trial window can plausibly run, AND
    /// the user is currently NOT premium, the trial must have been
    /// cancelled / expired without conversion. Stamp the cooldown
    /// window and clear the start anchor.
    ///
    /// Called from `refreshTrialEligibility()` so the check happens
    /// at every cold start without needing a webhook listener.
    private func promoteAbandonedTrialToCooldownIfNeeded() {
        guard let startedAt = UserDefaults.standard.object(forKey: trialStartedAtKey) as? Date else {
            return
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > Self.trialMaxWindow, !isPremium else {
            return
        }
        let cooldownUntil = Date().addingTimeInterval(Self.trialCooldownDuration)
        UserDefaults.standard.set(cooldownUntil, forKey: trialCooldownUntilKey)
        UserDefaults.standard.removeObject(forKey: trialStartedAtKey)
        logger.info("Abandoned trial detected — trial UI blocked until \(cooldownUntil, privacy: .public)")
    }

    private func refreshDerivedFromOffering() {
        let monthlyProduct = currentOffering?.monthly?.storeProduct
        let annualProduct = currentOffering?.annual?.storeProduct

        monthlyPriceString = monthlyProduct?.localizedPriceString
        annualPriceString = annualProduct?.localizedPriceString
        annualMonthlyEquivalentString = computeMonthlyEquivalent(annualProduct: annualProduct)

        annualTrialDays = extractTrialDays(annualProduct: annualProduct)

        // Loud diagnostic — surfaces in Xcode console at every offering
        // refresh so we can confirm whether RevenueCat is wiring the
        // *regular* annual (cooksy_premium_yearly) or the discounted
        // gift product (cooksy_premium_yearly_gift) into the annual
        // package. If the latter sneaks in, the paywall would show
        // 29.99 € on first view even before the gift wheel runs.
        logger.info("[paywall-diag] annual=\(annualProduct?.productIdentifier ?? "nil", privacy: .public) price=\(self.annualPriceString ?? "nil", privacy: .public) monthly=\(monthlyProduct?.productIdentifier ?? "nil", privacy: .public)")
    }

    private func extractTrialDays(annualProduct: StoreProduct?) -> Int? {
        guard let intro = annualProduct?.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        return totalDays(period: intro.subscriptionPeriod, count: intro.numberOfPeriods)
    }

    private func totalDays(period: SubscriptionPeriod, count: Int) -> Int {
        let value = period.value * count
        switch period.unit {
        case .day:   return value
        case .week:  return value * 7
        case .month: return value * 30
        case .year:  return value * 365
        @unknown default: return value
        }
    }

    private func computeMonthlyEquivalent(annualProduct: StoreProduct?) -> String? {
        guard let product = annualProduct else { return nil }
        let perMonth = product.price / Decimal(12)
        var rounded = Decimal()
        var raw = perMonth
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return formatPrice(amount: rounded, product: product)
    }

    /// Annual storefront price with a local promotional discount applied,
    /// formatted in the user's currency. Returns `nil` when no offering
    /// is loaded yet — the caller falls back to the hardcoded EUR maths.
    func discountedAnnualPriceString(percent: Int) -> String? {
        guard percent > 0,
              let product = currentOffering?.annual?.storeProduct else { return nil }
        let multiplier = Decimal(100 - percent) / 100
        var rounded = Decimal()
        var raw = product.price * multiplier
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return formatPrice(amount: rounded, product: product)
    }

    /// Per-month equivalent of the discounted annual price, in the user's
    /// currency. Returns `nil` if the offering is not loaded yet.
    func discountedAnnualMonthlyEquivalentString(percent: Int) -> String? {
        guard percent > 0,
              let product = currentOffering?.annual?.storeProduct else { return nil }
        let multiplier = Decimal(100 - percent) / 100
        let perMonth = (product.price * multiplier) / Decimal(12)
        var rounded = Decimal()
        var raw = perMonth
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return formatPrice(amount: rounded, product: product)
    }

    private func formatPrice(amount: Decimal, product: StoreProduct) -> String? {
        if let formatter = product.priceFormatter {
            return formatter.string(from: amount as NSDecimalNumber)
        }
        let fallback = NumberFormatter()
        fallback.numberStyle = .currency
        fallback.currencyCode = product.currencyCode
        return fallback.string(from: amount as NSDecimalNumber)
    }

    // MARK: - Purchase

    /// Presents the native StoreKit payment sheet for the given plan.
    /// Throws `PurchaseError` on failure; silently returns if the user cancels.
    func purchase(plan: PremiumPlan) async throws {
        guard let offering = currentOffering else { throw PurchaseError.noOffering }

        let package: Package? = plan == .monthly ? offering.monthly : offering.annual
        guard let pkg = package else { throw PurchaseError.packageNotFound }

        isLoading = true
        defer { isLoading = false }

        let result = try await Purchases.shared.purchase(package: pkg)
        guard !result.userCancelled else { return }
        syncStatus(from: result.customerInfo)
    }

    /// Annual purchase that tries to apply a Promotional Offer matching
    /// `offerIdentifier` (e.g. `"GIFT25"`). If the offer is configured
    /// in App Store Connect for the annual product, Apple will bill the
    /// reduced amount; otherwise we silently fall back to the regular
    /// price so the user still gets premium even without a real promo
    /// configured server-side.
    /// Product ID of the discounted annual subscription that's surfaced
    /// when the user wins the gift wheel. Priced at 29,99 € (vs 39,99 €
    /// for the regular annual), it bypasses Apple's Promotional Offer
    /// API entirely — so the discount applies to *every* user, not just
    /// returning subscribers.
    static let giftYearlyProductID = "cooksy_premium_yearly_gift"

    func purchaseAnnualWithPromo(offerIdentifier: String) async throws {
        // Strategy: purchase the dedicated 29,99 € product
        // `cooksy_premium_yearly_gift`. This sidesteps Apple's rule
        // that Promotional Offers only apply to existing/expired
        // subscribers — new users on the wheel get the discount too.
        //
        // We still keep the Promotional Offer path below as a fallback
        // in case the gift product isn't yet provisioned in RevenueCat
        // (e.g. fresh sandbox builds before the user has rebuilt the
        // .storekit file).
        let giftProducts = await Purchases.shared.products([Self.giftYearlyProductID])
        if let giftProduct = giftProducts.first {
            isLoading = true
            defer { isLoading = false }
            let result = try await Purchases.shared.purchase(product: giftProduct)
            guard !result.userCancelled else { return }
            syncStatus(from: result.customerInfo)
            return
        }

        logger.warning("Gift product \(Self.giftYearlyProductID, privacy: .public) not found — attempting Promotional Offer fallback")

        guard let offering = currentOffering,
              let pkg = offering.annual else { throw PurchaseError.packageNotFound }

        let product = pkg.storeProduct

        // Promotional Offer path — only works for users who have had a
        // prior subscription (Apple's restriction). For brand-new users
        // Apple returns AMS 3903; we then fall back to the regular price
        // after a small delay so StoreKit can release the UI anchor.
        if let discount = product.discounts.first(where: { $0.offerIdentifier == offerIdentifier }) {
            do {
                let promoOffer = try await Purchases.shared.promotionalOffer(
                    forProductDiscount: discount,
                    product: product
                )
                isLoading = true
                defer { isLoading = false }
                let result = try await Purchases.shared.purchase(package: pkg, promotionalOffer: promoOffer)
                guard !result.userCancelled else { return }
                syncStatus(from: result.customerInfo)
                return
            } catch {
                logger.warning("Promo offer \(offerIdentifier, privacy: .public) failed (\(error.localizedDescription, privacy: .public)) — falling back to regular annual price")
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        } else {
            logger.info("No promo offer \(offerIdentifier, privacy: .public) configured on annual product — using regular price")
        }
        try await purchase(plan: .yearly)
    }

    /// Convenience overload that defaults to the annual plan (used by the
    /// onboarding paywall which has its own plan enum).
    func purchaseAnnual() async throws {
        try await purchase(plan: .yearly)
    }

    /// Force `isPremium` to `true` and persist a server-side refresh in
    /// the background. Use this immediately after a StoreKit purchase
    /// has *succeeded* (no `userCancelled`, no error) so the UI can
    /// react instantly — without waiting for RevenueCat's webhook /
    /// CustomerInfo poll to confirm.
    ///
    /// Two practical reasons this exists:
    ///   • RevenueCat's `Purchases.shared.purchase(...)` returns a
    ///     `CustomerInfo` that *should* reflect the new entitlement,
    ///     but in sandbox/test environments the entitlement is
    ///     sometimes still empty for ~1–2 s while RC's backend catches
    ///     up. Without this method the paywall would stay open until
    ///     the next CustomerInfo refresh, and the user has to background
    ///     the app to unstick it.
    ///   • Even in production, network jitter between StoreKit success
    ///     and RC's server can produce the same race. Trusting the
    ///     transaction success is correct UX — the worst case is that
    ///     we grant premium for a few seconds before the server-side
    ///     entitlement lands (which it always does, otherwise StoreKit
    ///     would have reported failure).
    func forcePremiumAfterPurchase() async {
        isPremium = true
        // Best-effort: pull the latest CustomerInfo so any other
        // downstream consumers (sessionStore, RootView) see the
        // server-confirmed value as soon as it's available.
        do {
            let info = try await Purchases.shared.customerInfo()
            syncStatus(from: info)
            // syncStatus may have flipped isPremium back to false if RC
            // is still catching up — reinforce the optimistic value so
            // the UI doesn't flicker. The next CustomerInfo refresh will
            // confirm it for real.
            if !isPremium {
                isPremium = true
                logger.info("RC entitlement not yet active after purchase — keeping optimistic isPremium=true")
            }
        } catch {
            logger.warning("RC customerInfo refresh after purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }
        let info = try await Purchases.shared.restorePurchases()
        syncStatus(from: info)
    }

    // MARK: - Refresh

    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            syncStatus(from: info)
        } catch {
            logger.error("RC refreshStatus failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internal

    private func syncStatus(from info: CustomerInfo) {
        let entitlement = info.entitlements["premium"]
        isPremium = entitlement?.isActive == true
        isInTrial = entitlement?.periodType == .trial
    }

    // MARK: - Errors

    enum PurchaseError: LocalizedError {
        case noOffering
        case packageNotFound

        var errorDescription: String? {
            switch self {
            case .noOffering:      return "Offres indisponibles. Réessaie dans un instant."
            case .packageNotFound: return "Plan introuvable. Réessaie dans un instant."
            }
        }
    }
}

// MARK: - PurchasesDelegate

extension PurchaseService: PurchasesDelegate {
    /// Called by RevenueCat when a subscription renews, expires, or changes
    /// while the app is in the foreground.
    nonisolated func purchases(
        _ purchases: Purchases,
        receivedUpdated customerInfo: CustomerInfo
    ) {
        Task { @MainActor in self.syncStatus(from: customerInfo) }
    }
}
