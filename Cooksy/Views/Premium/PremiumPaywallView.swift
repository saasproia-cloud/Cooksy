import SwiftUI

/// Cooksy premium paywall — round 8 (premium redesign).
///
/// Designed to feel like Headspace / Calm / Speak — minimal, generous
/// whitespace, dominant annual card, single bold CTA, the trial as a
/// floating chip rather than buried copy, and the orange accent used
/// only where it earns conversion.
///
/// Layout pattern is the proven AppReviewView shape:
/// GeometryReader → VStack → `.frame(maxWidth: 420)` →
/// `.frame(maxWidth: .infinity)` → `.padding(.horizontal, hPad)`.
/// No ScrollView, no TabView — both have known width-negotiation
/// quirks on iPhone 17 Pro that cause edge bleed.
///
/// All purchase / gift-wheel / exit-intent / restore wiring is
/// preserved 1:1 from the previous version.
struct PremiumPaywallView: View {
    var allowsFreeModeDismiss: Bool = true
    var showsGiftReminder: Bool = false
    var onDismissToFreeMode: (() -> Void)? = nil
    var onOpenGiftFromReminder: (() -> Void)? = nil

    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var offers = PremiumOffersService.shared
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var selectedPlan: PremiumPlan = .defaultPlan
    @State private var isPurchasing: Bool = false
    @State private var purchaseError: String? = nil
    @State private var showsGiftWheel: Bool = false
    @State private var showsExclusiveOffer: Bool = false
    @State private var giftReminderDismissed: Bool = false
    @State private var confettiTrigger: Int = 0
    @State private var hasTriggeredExitIntent: Bool = false
    /// Drives the subtle breathing animation on the annual card.
    @State private var pulse: Bool = false

    private var trialAvailable: Bool {
        selectedPlan.hasFreeTrial && purchaseService.isAnnualTrialEligible
    }
    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }
    private var annualTrialEligible: Bool { purchaseService.isAnnualTrialEligible }

    var body: some View {
        ZStack {
            // Premium cream backdrop with a single soft orange halo
            // anchored top-centre. Used sparingly — the rest of the
            // canvas stays calm so the annual card can lead the eye.
            CooksyTheme.background
                .ignoresSafeArea()
            paywallHalo
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPad = Layout.horizontalPadding(for: geo)

                VStack(spacing: 0) {
                    Spacer(minLength: 52)

                    socialProofPill
                        .padding(.bottom, 16)

                    headline
                        .padding(.bottom, 12)

                    subtitle
                        .padding(.bottom, 26)

                    if shouldShowGiftReminderBanner {
                        PaywallGiftReminderBanner(
                            isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                            discountPercent: offers.giftDiscountPercent ?? 25,
                            onTap: handleOpenGiftFromReminder,
                            onDismiss: { giftReminderDismissed = true }
                        )
                        .padding(.bottom, 14)
                    }

                    if offers.giftOfferIsActive {
                        PaywallGiftStrip(
                            discountPercent: activeGiftDiscountPercent,
                            expiresAt: activeOfferExpiresAt
                        )
                        .padding(.bottom, 14)
                    }

                    valueProps
                        .padding(.bottom, 26)

                    planCards
                        .padding(.bottom, 18)

                    ctaButton
                        .padding(.bottom, 10)

                    reassuranceLine
                        .padding(.bottom, 14)

                    footerLinks

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, hPad)
            }

            IngredientConfetti(trigger: confettiTrigger)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) { stickyCloseButton }
        .alert("Erreur", isPresented: .init(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: {
            Text(purchaseError ?? "")
        }
        .onAppear {
            offers.paywallWasReached()
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .fullScreenCover(isPresented: $showsGiftWheel) {
            GiftMiniGameHost(
                onClose: { showsGiftWheel = false },
                onClaim: { discount in
                    offers.recordGiftWon(percent: discount)
                    showsGiftWheel = false
                    selectedPlan = .yearly
                    confettiTrigger += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showsExclusiveOffer = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showsExclusiveOffer) {
            ExclusiveOfferView(
                discountPercent: offers.giftDiscountPercent ?? PremiumOffersService.defaultGiftDiscount,
                expiresAt: offers.giftOfferExpiresAt,
                onClose: { showsExclusiveOffer = false }
            )
        }
    }

    // MARK: - Halo

    private var paywallHalo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        CooksyTheme.primaryAccentGlow.opacity(0.32),
                        CooksyTheme.primaryAccentGlow.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 320
                )
            )
            .frame(width: 540, height: 540)
            .offset(y: -270)
            .blur(radius: 14)
    }

    // MARK: - Close button

    @ViewBuilder
    private var stickyCloseButton: some View {
        if allowsFreeModeDismiss {
            Button(action: handleFreeModeDismiss) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(.black.opacity(0.04))
                    Circle().stroke(CooksyTheme.stroke, lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
            .padding(.top, 10)
            .accessibilityLabel("Fermer et rester en gratuit")
        }
    }

    // MARK: - Social proof pill (delicate, hero-anchored)

    private var socialProofPill: some View {
        HStack(spacing: 7) {
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }
            Text("4,9")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Circle()
                .fill(CooksyTheme.stroke)
                .frame(width: 2.5, height: 2.5)
            Text("+12 000 cuisiniers")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.7))
                .overlay(Capsule().stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 0.5))
        )
    }

    // MARK: - Headline / subtitle

    private var headline: some View {
        VStack(spacing: 0) {
            Text("Cuisine")
            Text("sans limite")
        }
        .font(.system(size: 36, weight: .bold, design: .serif))
        .tracking(-0.5)
        .foregroundStyle(CooksyTheme.primaryText)
        .multilineTextAlignment(.center)
        .lineSpacing(-6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitle: some View {
        Text("Transforme toutes tes vidéos en recettes complètes, prêtes à cuisiner.")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Value props

    private struct ValueProp {
        let icon: String
        let label: String
    }

    private let valuePropsList: [ValueProp] = [
        ValueProp(icon: "infinity", label: "Imports illimités"),
        ValueProp(icon: "leaf.fill", label: "Nutrition avancée"),
        ValueProp(icon: "fork.knife", label: "Mode guidé en cuisine"),
        ValueProp(icon: "bookmark.fill", label: "Sauvegarde illimitée"),
        ValueProp(icon: "sparkles", label: "Futures fonctionnalités premium")
    ]

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(valuePropsList, id: \.label) { prop in
                HStack(spacing: 12) {
                    Image(systemName: prop.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                        .frame(width: 22, height: 22)
                    Text(prop.label)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    // MARK: - Plans

    private var planCards: some View {
        VStack(spacing: 14) {
            monthlyCard
            annualCard
        }
    }

    private var monthlyCard: some View {
        let isSelected = selectedPlan == .monthly
        let priceText = PremiumPlan.monthly.liveOrFallbackPriceString

        return Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                selectedPlan = .monthly
            }
            confettiTrigger += 1
        }) {
            HStack(spacing: 12) {
                selectionDot(isSelected: isSelected, onAccent: false)

                Text("Mensuel")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 4)

                Text("\(priceText)/mois")
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke.opacity(0.7),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var annualCard: some View {
        let isSelected = selectedPlan == .yearly
        let effectiveDiscount: Int? = (offers.giftOfferIsActive && PremiumPlan.yearly.supportsPromotionalDiscount)
            ? offers.giftDiscountPercent
            : nil
        let priceText = PremiumPlan.yearly.liveOrFallbackPriceString(discountPercent: effectiveDiscount)
        let perMonth = PremiumPlan.yearly.liveOrFallbackMonthlyEquivalent(discountPercent: effectiveDiscount) ?? "3,33 €"

        let badgeText: String = {
            if let percent = effectiveDiscount {
                return "🎁 CADEAU −\(percent) %"
            }
            if annualTrialEligible {
                return "ESSAI \(trialDays) JOURS GRATUITS"
            }
            return "ÉCONOMIE 58 %"
        }()

        return Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                selectedPlan = .yearly
            }
            confettiTrigger += 1
        }) {
            VStack(spacing: 0) {
                // Floating premium chip — the only place where orange
                // gets to shout. Subtle pulse when not selected.
                Text(badgeText)
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(CooksyTheme.accentGradient)
                            .shadow(
                                color: CooksyTheme.primaryAccent.opacity(0.5),
                                radius: 10,
                                y: 4
                            )
                    )
                    .scaleEffect(isSelected || pulse ? 1 : 0.97)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)
                    .padding(.bottom, -12)
                    .zIndex(2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        selectionDot(isSelected: isSelected, onAccent: isSelected)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Annuel")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                                Text("· 12 mois")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : CooksyTheme.secondaryText)
                            }
                            Text(monthlyVsAnnualSavingsText())
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : CooksyTheme.primaryAccentStrong)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 4)

                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(perMonth)
                                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("/mois")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : CooksyTheme.secondaryText)
                            }
                            Text("facturé \(priceText)/an")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : CooksyTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected
                            ? AnyShapeStyle(CooksyTheme.accentGradient)
                            : AnyShapeStyle(Color.white)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            isSelected
                                ? Color.white.opacity(0.28)
                                : CooksyTheme.primaryAccent.opacity(0.55),
                            lineWidth: 1.5
                        )
                )
                .shadow(
                    color: isSelected
                        ? CooksyTheme.primaryAccent.opacity(0.32)
                        : CooksyTheme.primaryAccent.opacity(0.08),
                    radius: isSelected ? 18 : 10,
                    y: isSelected ? 10 : 5
                )
            }
            .scaleEffect(isSelected ? 1.012 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func selectionDot(isSelected: Bool, onAccent: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                    ? AnyShapeStyle(onAccent ? Color.white : CooksyTheme.primaryAccent)
                    : AnyShapeStyle(Color.clear)
                )
                .frame(width: 20, height: 20)
            Circle()
                .stroke(
                    isSelected
                    ? (onAccent ? Color.white : CooksyTheme.primaryAccent)
                    : CooksyTheme.stroke,
                    lineWidth: 1.5
                )
                .frame(width: 20, height: 20)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(onAccent ? CooksyTheme.primaryAccentStrong : .white)
            }
        }
    }

    /// "Économise 56 €/an" — computed from base prices so the
    /// callout stays accurate even when the live storefront price
    /// shifts (regional Apple ID, App Store pricing tier moves).
    private func monthlyVsAnnualSavingsText() -> String {
        let monthlyTimes12 = PremiumPlan.monthly.basePrice * 12
        let annual = PremiumPlan.yearly.basePrice
        let diff = monthlyTimes12 - annual
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: diff as NSDecimalNumber) ?? "56 €"
        return "Économise \(amount)/an"
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button(action: handlePurchase) {
            HStack(spacing: 10) {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(ctaCopy)
                    .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !isPurchasing {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.42), radius: 16, y: 8)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .disabled(isPurchasing)
    }

    private var ctaCopy: String {
        if selectedPlan == .yearly, trialAvailable {
            return "Commencer mes \(trialDays) jours gratuits"
        }
        return "Continuer"
    }

    // MARK: - Reassurance / footer

    private var reassuranceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
            Text("Annulable · Paiement sécurisé Apple · Sans engagement")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 12) {
            Button(action: handleRestore) {
                Text("Restaurer")
                    .underline()
            }
            Circle().fill(CooksyTheme.stroke).frame(width: 2.5, height: 2.5)
            Button("Conditions") {}
            Circle().fill(CooksyTheme.stroke).frame(width: 2.5, height: 2.5)
            Button("Confidentialité") {}
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
    }

    // MARK: - Derived state

    private var activeOfferExpiresAt: Date? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftOfferExpiresAt
    }

    private var activeGiftDiscountPercent: Int? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftDiscountPercent
    }

    private var shouldShowGiftReminderBanner: Bool {
        showsGiftReminder && !giftReminderDismissed
    }

    // MARK: - Handlers

    private func handleFreeModeDismiss() {
        OnboardingHaptics.selection()
        let canSurpriseWithWheel = !hasTriggeredExitIntent
            && !offers.giftHasBeenWon
            && offers.shouldShowGiftPill
        if canSurpriseWithWheel {
            hasTriggeredExitIntent = true
            showsGiftWheel = true
            return
        }

        offers.chooseFreeMode()
        onDismissToFreeMode?()
    }

    private func handleOpenGiftFromReminder() {
        OnboardingHaptics.selection()
        if let onOpenGiftFromReminder {
            onOpenGiftFromReminder()
        } else {
            showsGiftWheel = true
        }
    }

    private func handlePurchase() {
        guard !isPurchasing else { return }
        OnboardingHaptics.medium()

        isPurchasing = true
        let plan = selectedPlan
        let giftActive = offers.giftOfferIsActive
        let giftPercent = offers.giftDiscountPercent

        Task {
            do {
                if plan == .yearly, giftActive, let percent = giftPercent {
                    try await PurchaseService.shared.purchaseAnnualWithPromo(
                        offerIdentifier: "GIFT\(percent)"
                    )
                } else {
                    try await PurchaseService.shared.purchase(plan: plan)
                }

                guard PurchaseService.shared.isPremium else {
                    await MainActor.run { isPurchasing = false }
                    return
                }

                await sessionStore.setPremium(true)
                let inTrial = PurchaseService.shared.isInTrial

                await MainActor.run {
                    offers.recordPurchaseCompleted(plan: plan, inTrial: inTrial)
                    offers.clearFreeModeChoice()
                    isPurchasing = false
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseError = error.localizedDescription
                }
            }
        }
    }

    private func handleRestore() {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            do {
                try await PurchaseService.shared.restorePurchases()
                if PurchaseService.shared.isPremium {
                    await sessionStore.setPremium(true)
                } else {
                    purchaseError = "Aucun abonnement actif trouvé."
                }
            } catch {
                purchaseError = error.localizedDescription
            }
            isPurchasing = false
        }
    }
}

// MARK: - Gift strip (only when cadeau active)

private struct PaywallGiftStrip: View {
    let discountPercent: Int?
    let expiresAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(discountPercent.map { "CADEAU −\($0) %" } ?? "CADEAU ACTIF")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(CooksyTheme.accentGradient))

            if let expiresAt {
                PaywallOfferTimerCapsule(expiresAt: expiresAt)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Offer timer capsule

private struct PaywallOfferTimerCapsule: View {
    let expiresAt: Date

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval { max(expiresAt.timeIntervalSince(now), 0) }
    private var label: String {
        let secs = Int(remaining)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(hex: 0x111827)))
        .onReceive(timer) { date in now = date }
    }
}

// MARK: - Gift reminder banner

private struct PaywallGiftReminderBanner: View {
    let isAlreadyWon: Bool
    let discountPercent: Int
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.goldShimmer)
                    .frame(width: 38, height: 38)
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CooksyTheme.heroDark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isAlreadyWon
                     ? "Tu as gagné −\(discountPercent) %"
                     : "Cadeau non réclamé")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(isAlreadyWon
                     ? "Applique ta remise sur l'annuel"
                     : "Tente le mini-jeu pour débloquer −\(discountPercent) %")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onTap) {
                Text(isAlreadyWon ? "Appliquer" : "Jouer")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(CooksyTheme.accentGradient))
            }
            .buttonStyle(CooksyTheme.pressScale())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CooksyTheme.primaryAccentGlow.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccentGlow.opacity(0.18), radius: 14, y: 4)
        )
    }
}
