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

    /// Sandbox key — replace with the live key before App Store submission.
    /// Find it in RevenueCat Dashboard → Project Settings → API Keys → Public app SDK key.
    private static let apiKey = "test_jIGGNTvSGURxfCizpICebehLAgt"

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "PurchaseService")

    private override init() { super.init() }

    // MARK: - Setup

    /// Call once from `CooksyApp.init()` before any other RC call.
    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        Purchases.shared.delegate = self
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
    func refreshTrialEligibility() async {
        guard let id = currentOffering?.annual?.storeProduct.productIdentifier else {
            isAnnualTrialEligible = false
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: [id])
        let status = result[id]?.status
        isAnnualTrialEligible = (status == .eligible || status == .unknown)
    }

    private func refreshDerivedFromOffering() {
        let monthlyProduct = currentOffering?.monthly?.storeProduct
        let annualProduct = currentOffering?.annual?.storeProduct

        monthlyPriceString = monthlyProduct?.localizedPriceString
        annualPriceString = annualProduct?.localizedPriceString
        annualMonthlyEquivalentString = computeMonthlyEquivalent(annualProduct: annualProduct)
        annualTrialDays = extractTrialDays(annualProduct: annualProduct)
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
        if let formatter = product.priceFormatter {
            return formatter.string(from: rounded as NSDecimalNumber)
        }
        let fallback = NumberFormatter()
        fallback.numberStyle = .currency
        fallback.currencyCode = product.currencyCode
        return fallback.string(from: rounded as NSDecimalNumber)
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
    func purchaseAnnualWithPromo(offerIdentifier: String) async throws {
        guard let offering = currentOffering,
              let pkg = offering.annual else { throw PurchaseError.packageNotFound }

        let product = pkg.storeProduct
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
