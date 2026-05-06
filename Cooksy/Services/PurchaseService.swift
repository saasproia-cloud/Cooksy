import Foundation
import RevenueCat
import OSLog

/// Wraps RevenueCat and exposes a simple async API for purchasing,
/// restoring, and observing subscription status.
///
/// Call `configure()` once at app launch, then `login(userID:)` each time
/// a Supabase session is established so purchases are tied to the right user.
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
        } catch {
            logger.error("RC login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the RC identity on sign-out so purchases aren't shared across accounts.
    func logout() async {
        do {
            _ = try await Purchases.shared.logOut()
            isPremium = false
        } catch {
            logger.error("RC logout failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Offerings

    func fetchOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            logger.error("RC fetchOfferings failed: \(error.localizedDescription, privacy: .public)")
        }
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
        isPremium = info.entitlements["premium"]?.isActive == true
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
