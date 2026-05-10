import Foundation
import SwiftUI

/// One subscription option offered on the premium paywall. The lifetime
/// option was dropped — keeping just two SKUs makes the choice visceral
/// and the screen far less busy.
enum PremiumPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    /// Localized French display title.
    var title: String {
        switch self {
        case .monthly:  return "Mensuel"
        case .yearly:   return "Annuel"
        }
    }

    /// Original (non-discounted) price in EUR.
    var basePrice: Decimal {
        switch self {
        case .monthly:  return 7.99
        case .yearly:   return 39.99
        }
    }

    /// Per-period unit shown in the price string.
    var unitLabel: String {
        switch self {
        case .monthly:  return "/mois"
        case .yearly:   return "/an"
        }
    }

    /// Short subtitle line under the price.
    var subtitle: String {
        switch self {
        case .monthly:  return "Sans engagement"
        case .yearly:   return "−58 % vs mensuel"
        }
    }

    /// Optional one-line badge above the title. Kept short so the pill
    /// stays on a single line on iPhone SE width (320 pt).
    var badge: String? {
        switch self {
        case .monthly:  return nil
        case .yearly:   return "CHOIX DU CHEF"
        }
    }

    /// Whether an introductory free trial applies.
    var hasFreeTrial: Bool {
        self == .yearly
    }

    /// Default plan pre-selected on the paywall.
    static let defaultPlan: PremiumPlan = .yearly
}

extension PremiumPlan {
    /// Format the price of this plan, optionally with a discount percentage.
    /// Returns e.g. "7,99 €" or "29,99 €" (after –25 %).
    func formattedPrice(discountPercent: Int? = nil) -> String {
        let price = discountedPrice(percent: discountPercent)
        return Self.priceFormatter.string(from: price as NSDecimalNumber) ?? "\(price) €"
    }

    /// Apply a discount percentage to the base price (rounded to 2 decimals).
    func discountedPrice(percent: Int?) -> Decimal {
        guard let percent, percent > 0 else { return basePrice }
        let multiplier = Decimal(100 - percent) / 100
        var raw = basePrice * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }

    /// Whether this plan is eligible for promotional discounts (welcome /
    /// scratch). Only the yearly plan: monthly stays at the entry price for
    /// simplicity.
    var supportsPromotionalDiscount: Bool {
        self == .yearly
    }

    /// Small-print disclaimer shown next to a discounted price.
    var firstPeriodDisclaimer: String {
        switch self {
        case .monthly:  return "1er mois · puis 7,99 €/mois"
        case .yearly:   return "1ère année · puis 39,99 €/an"
        }
    }

    /// Per-month equivalent of this plan, formatted with the same locale
    /// as `formattedPrice`. Returns `nil` for monthly (already monthly).
    /// Drives the "soit 2,49 €/mois" line under the CTA on the annual
    /// plan to make the savings feel concrete.
    ///
    /// Returns just the money amount (e.g. `"2,49 €"`) — call sites
    /// add the `/mois` unit themselves. This keeps the shape identical
    /// to `PurchaseService.annualMonthlyEquivalentString` so the live
    /// and fallback paths can never diverge into a `"3,33 €/mois/mois"`
    /// duplicate-suffix bug.
    ///
    /// `withTrialDays` shaves the equivalent monthly down by the share
    /// of the year covered for free, so the displayed price drops a few
    /// cents when the user activates the trial.
    func monthlyEquivalentString(discountPercent: Int? = nil, withTrialDays trialDays: Int = 0) -> String? {
        guard self == .yearly else { return nil }
        let total = discountedPrice(percent: discountPercent)
        let billedDays = max(365 - trialDays, 1)
        let perMonth = (total * Decimal(billedDays)) / Decimal(365) / 12
        var rounded = Decimal()
        var raw = perMonth
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return Self.priceFormatter.string(from: rounded as NSDecimalNumber)
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

// MARK: - Live storefront prices

@MainActor
extension PremiumPlan {
    /// Real price string from the StoreKit storefront — exactly matches
    /// what Apple will charge in the user's country / currency. Falls
    /// back to the hardcoded EUR formatting only when the offering
    /// hasn't been fetched yet (cold start, no network). Never apply a
    /// local discount on top of this string: Apple only honours the
    /// promotional offers configured in App Store Connect.
    var liveOrFallbackPriceString: String {
        switch self {
        case .monthly:
            return PurchaseService.shared.monthlyPriceString ?? formattedPrice()
        case .yearly:
            return PurchaseService.shared.annualPriceString ?? formattedPrice()
        }
    }

    /// Per-month equivalent of the annual plan, derived from the live
    /// price when available so it matches what Apple is going to bill.
    /// Returns `nil` for monthly plans.
    var liveOrFallbackMonthlyEquivalent: String? {
        guard self == .yearly else { return nil }
        if let live = PurchaseService.shared.annualMonthlyEquivalentString {
            return live
        }
        return monthlyEquivalentString()
    }

    /// Real free-trial duration extracted from the storefront's intro
    /// offer (e.g. `7`). When we can't read it (offering not loaded),
    /// we fall back to the marketing copy of 7 days for the annual plan.
    var trialDaysOrFallback: Int {
        if let live = PurchaseService.shared.annualTrialDays { return live }
        return self == .yearly ? 7 : 0
    }
}
