import SwiftUI

/// Cooksy premium paywall — round 7 (complete redesign).
///
/// CRO-focused, single-screen, premium feel. Hierarchy is engineered
/// so the annual plan reads as the obvious choice the moment the
/// screen opens:
///
///   • Hero headline — "Cuisine sans limite"
///   • 5 concrete value props (checkmarks)
///   • Monthly card  → compact, secondary
///   • Annual card   → 2× taller, gradient, populaire badge, savings shouted
///   • CTA + reassurance line
///   • Restaurer · Conditions · Confidentialité footer
///
/// Layout uses the AppReviewView pattern that's proven on iPhone 17 Pro:
/// GeometryReader → VStack → `.frame(maxWidth: 420)` →
/// `.frame(maxWidth: .infinity)` → `.padding(.horizontal, hPad)` —
/// no ScrollView, no TabView, no hidden width negotiations that bleed.
///
/// All purchase / gift-wheel / exit-intent / restore wiring is
/// preserved 1:1 from the previous version.
struct PremiumPaywallView: View {
    /// Set to `false` when the paywall is presented modally from the home
    /// tab (where dismissing should NOT route to free mode — the user is
    /// already free).
    var allowsFreeModeDismiss: Bool = true
    /// When `true`, an inline reminder banner is rendered telling the
    /// user there's still a –25 % gift to unlock via the mini-game.
    var showsGiftReminder: Bool = false
    var onDismissToFreeMode: (() -> Void)? = nil
    /// Called when the user taps the gift reminder banner.
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
    /// Set to `true` after the user has tried to leave once. Drives
    /// the X-button behaviour (1st tap = open the wheel, 2nd tap =
    /// actually leave to free mode).
    @State private var hasTriggeredExitIntent: Bool = false

    /// Trial is automatically included with the annual plan and only
    /// when Apple says the current Apple ID is still eligible.
    private var trialAvailable: Bool {
        selectedPlan.hasFreeTrial && purchaseService.isAnnualTrialEligible
    }
    /// Real trial duration (days) read from the StoreKit storefront.
    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }

    private var annualTrialEligible: Bool { purchaseService.isAnnualTrialEligible }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            paywallHalo
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPad = Layout.horizontalPadding(for: geo)

                VStack(spacing: 0) {
                    Spacer(minLength: 56)

                    headline
                    Spacer(minLength: 14)
                    subtitle
                    Spacer(minLength: 22)

                    if shouldShowGiftReminderBanner {
                        PaywallGiftReminderBanner(
                            isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                            discountPercent: offers.giftDiscountPercent ?? 25,
                            onTap: handleOpenGiftFromReminder,
                            onDismiss: { giftReminderDismissed = true }
                        )
                        Spacer(minLength: 14)
                    }

                    if offers.giftOfferIsActive {
                        PaywallGiftStrip(
                            discountPercent: activeGiftDiscountPercent,
                            expiresAt: activeOfferExpiresAt
                        )
                        Spacer(minLength: 14)
                    }

                    valueProps
                    Spacer(minLength: 22)

                    planCards
                    Spacer(minLength: 18)

                    ctaButton
                    Spacer(minLength: 10)
                    reassuranceLine
                    Spacer(minLength: 14)
                    footerLinks
                    Spacer(minLength: 14)
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

    // MARK: - Backdrop

    private var paywallHalo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentGlow.opacity(0.42),
                            CooksyTheme.primaryAccentGlow.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 320
                    )
                )
                .frame(width: 600, height: 600)
                .offset(y: -260)
                .blur(radius: 14)
        }
    }

    // MARK: - Sticky close button

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

    // MARK: - Headline / subtitle

    private var headline: some View {
        Text("Cuisine sans limite")
            .font(.system(size: 30, weight: .bold, design: .serif))
            .foregroundStyle(CooksyTheme.primaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitle: some View {
        Text("Transforme toutes tes vidéos en recettes complètes.")
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
        ValueProp(icon: "bookmark.fill", label: "Recettes enregistrées"),
        ValueProp(icon: "sparkles", label: "Accès premium futur")
    ]

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(valuePropsList, id: \.label) { prop in
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                    Text(prop.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    // MARK: - Plans

    private var planCards: some View {
        VStack(spacing: 12) {
            monthlyCard
            annualCard
        }
    }

    private var monthlyCard: some View {
        let isSelected = selectedPlan == .monthly
        let priceText = PremiumPlan.monthly.liveOrFallbackPriceString

        return Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedPlan = .monthly
            }
            confettiTrigger += 1
        }) {
            HStack(spacing: 12) {
                selectionDot(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mensuel")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("Sans engagement")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 4)

                Text("\(priceText)/mois")
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
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
        let badgeText = effectiveDiscount.map { "🎁 CADEAU −\($0) %" } ?? "🔥 LE PLUS POPULAIRE"
        let savingsText: String = {
            if let percent = effectiveDiscount {
                return "Économise −\(percent)% + \(monthlyVsAnnualSavingsText())"
            }
            return monthlyVsAnnualSavingsText()
        }()

        return Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedPlan = .yearly
            }
            confettiTrigger += 1
        }) {
            VStack(spacing: 0) {
                // Floating popular badge
                Text(badgeText)
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(CooksyTheme.accentGradient)
                            .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 8, y: 3)
                    )
                    .padding(.bottom, -10)
                    .zIndex(2)

                HStack(alignment: .center, spacing: 12) {
                    selectionDot(isSelected: isSelected, onAccent: isSelected)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Annuel")
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                            Text("(12 mois)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : CooksyTheme.secondaryText)
                        }

                        Text(annualTrialEligible
                             ? "\(trialDays) jours gratuits"
                             : savingsText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : CooksyTheme.primaryAccentStrong)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(perMonth)/mois")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("soit \(priceText)/an")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : CooksyTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isSelected
                            ? AnyShapeStyle(CooksyTheme.accentGradient)
                            : AnyShapeStyle(Color.white)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.3) : CooksyTheme.primaryAccent.opacity(0.5),
                            lineWidth: isSelected ? 1.5 : 1.5
                        )
                )
                .shadow(
                    color: isSelected
                        ? CooksyTheme.primaryAccent.opacity(0.32)
                        : Color.black.opacity(0.06),
                    radius: isSelected ? 16 : 8,
                    y: isSelected ? 9 : 3
                )
            }
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// Selection radio dot. `onAccent` paints the dot for the gradient card.
    private func selectionDot(isSelected: Bool, onAccent: Bool = false) -> some View {
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

    /// "Économise 56 € vs mensuel" — computed from base prices so the
    /// line stays accurate even after the discounted price flows in.
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
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.38), radius: 14, y: 7)
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

    // MARK: - Reassurance line

    private var reassuranceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText)
            Text("Annulable à tout moment · Paiement sécurisé Apple")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: 14) {
            Button(action: handleRestore) {
                Text("Restaurer")
                    .underline()
            }
            Circle().fill(CooksyTheme.stroke).frame(width: 3, height: 3)
            Button("Conditions") {}
                .foregroundStyle(CooksyTheme.secondaryText)
            Circle().fill(CooksyTheme.stroke).frame(width: 3, height: 3)
            Button("Confidentialité") {}
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText)
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

        // Exit-intent: the FIRST time the user taps the X (and only
        // when they're eligible — never won, no cooldown), surprise
        // them with the wheel. They can still close from inside the
        // wheel if they don't want to play. Subsequent taps on the X
        // bypass the wheel and dismiss to free mode as before.
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
