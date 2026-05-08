import SwiftUI

/// Cooksy premium paywall — round 3 redesign.
///
/// The previous layout tried to fit a dark cinematic hero, a testimonial
/// carousel, a bento grid, a draggable before/after slider, a recipe
/// card stack, a trust strip, a 5-question FAQ and a sticky CTA into a
/// single screen. Users complained it was unreadable.
///
/// The new shape is a single editorial column on a warm cream background:
///   1. Sticky close X (top-leading) + sticky restore (top-trailing)
///   2. Soft-coloured hero with a serif headline and a single supporting line
///   3. Three crisp value propositions (icon + label only, no body copy)
///   4. Two-card plan picker (Mensuel / Annuel — lifetime removed)
///   5. Free-trial toggle with a side-by-side price comparison so the
///      user *sees* the difference between trialling and paying upfront
///   6. Sticky CTA bar at the bottom with strikethrough + monthly equivalent
///   7. Compact 3-question FAQ + footer links
///
/// The gift mini-game and the −25 % discount logic are unchanged — they
/// live in `PremiumOffersService` and surface here as the optional pill
/// next to "Choisis ton plan" plus the strikethrough on the annual card.
struct PremiumPaywallView: View {
    /// Set to `false` when the paywall is presented modally from the home
    /// tab (where dismissing should NOT route to free mode — the user is
    /// already free).
    var allowsFreeModeDismiss: Bool = true
    /// When `true`, an inline reminder banner is rendered at the top of
    /// the scroll content telling the user there's still a –25 % gift
    /// to unlock via the mini-game.
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
    /// when Apple says the current Apple ID is still eligible (it grants
    /// the trial only once per Apple ID). When ineligible, the paywall
    /// must NOT promise a trial.
    private var trialAvailable: Bool {
        selectedPlan.hasFreeTrial && purchaseService.isAnnualTrialEligible
    }
    /// Real trial duration (days) read from the StoreKit storefront.
    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    PaywallEditorialHero(
                        // Gift badge is intentionally suppressed at
                        // the very start of the paywall — the wheel
                        // is the surprise reward for an exit-intent
                        // (tapping the X). It only appears here once
                        // the user has actually won the discount and
                        // it's still active.
                        showGiftBadge: offers.shouldShowGiftPill
                            && offers.giftHasBeenWon
                            && offers.giftOfferIsActive,
                        giftDiscountPercent: offers.giftDiscountPercent,
                        onOpenGift: { showsExclusiveOffer = true }
                    )
                    .padding(.top, 64) // breathing room for sticky chrome

                    if shouldShowGiftReminderBanner {
                        PaywallGiftReminderBanner(
                            isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                            discountPercent: offers.giftDiscountPercent ?? 25,
                            onTap: handleOpenGiftFromReminder,
                            onDismiss: { giftReminderDismissed = true }
                        )
                        .padding(.horizontal, 22)
                    }

                    PaywallValueProps()
                        .padding(.horizontal, 22)

                    PaywallPlanPicker(
                        selectedPlan: $selectedPlan,
                        offerExpiresAt: activeOfferExpiresAt,
                        trialDays: trialDays,
                        trialEligible: purchaseService.isAnnualTrialEligible,
                        giftActive: offers.giftOfferIsActive,
                        confettiTrigger: $confettiTrigger
                    )
                    .padding(.horizontal, 22)

                    PaywallTrustStrip()
                        .padding(.horizontal, 22)

                    PaywallCompactFAQ()
                        .padding(.horizontal, 22)

                    Color.clear.frame(height: 200) // sticky CTA breathing room
                }
            }

            PaywallStickyCTA(
                selectedPlan: selectedPlan,
                trialAvailable: trialAvailable,
                trialDays: trialDays,
                isPurchasing: isPurchasing,
                onPurchase: handlePurchase
            )

            IngredientConfetti(trigger: confettiTrigger)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) { stickyCloseButton }
        .overlay(alignment: .topTrailing) { stickyRestoreButton }
        .ignoresSafeArea(edges: .bottom)
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
            // ExclusiveOfferView now executes its own purchase inline
            // (with a loading state on its CTA) — the cover dismisses
            // itself once premium is granted, so the paywall never has
            // to flash back into view between "j'achète" and "premium".
            ExclusiveOfferView(
                discountPercent: offers.giftDiscountPercent ?? PremiumOffersService.defaultGiftDiscount,
                expiresAt: offers.giftOfferExpiresAt,
                onClose: { showsExclusiveOffer = false }
            )
        }
    }

    // MARK: - Sticky chrome

    @ViewBuilder
    private var stickyCloseButton: some View {
        if allowsFreeModeDismiss {
            Button(action: handleFreeModeDismiss) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(.black.opacity(0.06))
                    Circle().stroke(CooksyTheme.stroke, lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 8)
            .zIndex(99)
            .accessibilityLabel("Fermer et rester en gratuit")
        }
    }

    private var stickyRestoreButton: some View {
        Button(action: handleRestore) {
            Text("Restaurer")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().stroke(CooksyTheme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .zIndex(99)
    }

    // MARK: - Derived state

    private var activeOfferExpiresAt: Date? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftOfferExpiresAt
    }

    private var shouldShowGiftReminderBanner: Bool {
        showsGiftReminder && !giftReminderDismissed
    }

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
        // Snapshot whether a gift is active right now — the purchase
        // closure runs concurrently and the state machine could roll
        // over while the StoreKit sheet is up.
        let giftActive = offers.giftOfferIsActive
        let giftPercent = offers.giftDiscountPercent

        Task {
            do {
                if plan == .yearly, giftActive, let percent = giftPercent {
                    // Try the matching Promotional Offer first
                    // (e.g. "GIFT25"). If App Store Connect doesn't
                    // have it configured, RC silently falls back to
                    // the regular price — the user still gets premium,
                    // just at the standard tariff.
                    try await PurchaseService.shared.purchaseAnnualWithPromo(
                        offerIdentifier: "GIFT\(percent)"
                    )
                } else {
                    try await PurchaseService.shared.purchase(plan: plan)
                }

                // Only mark premium / record the gift if RevenueCat
                // actually confirmed the entitlement. A user who
                // dismissed the StoreKit sheet returns here without
                // `isPremium`, so nothing must mutate.
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

// MARK: - Editorial hero

private struct PaywallEditorialHero: View {
    let showGiftBadge: Bool
    let giftDiscountPercent: Int?
    let onOpenGift: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("COOKSY PREMIUM")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                Spacer()
                if showGiftBadge {
                    Button(action: onOpenGift) {
                        HStack(spacing: 4) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("CADEAU")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(0.6)
                        }
                        .foregroundStyle(CooksyTheme.heroDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(CooksyTheme.goldShimmer))
                    }
                    .buttonStyle(CooksyTheme.pressScale())
                }
            }

            Text("7 jours gratuits,\npuis tes recettes\nprêtes à cuisiner.")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Essai gratuit sans paiement immédiat. Importe n'importe quelle vidéo TikTok, Instagram ou YouTube — Cooksy en fait une recette propre, structurée, à ton rythme.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
    }
}

// MARK: - Value props

private struct PaywallValueProps: View {
    private let items: [(icon: String, title: String)] = [
        ("infinity", "Imports illimités"),
        ("wand.and.stars", "IA culinaire avancée"),
        ("calendar.badge.clock", "Plan repas + courses")
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items, id: \.title) { item in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft)
                            .frame(width: 36, height: 36)
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryAccent)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Plan picker

private struct PaywallPlanPicker: View {
    @Binding var selectedPlan: PremiumPlan
    let offerExpiresAt: Date?
    let trialDays: Int
    let trialEligible: Bool
    let giftActive: Bool
    @Binding var confettiTrigger: Int

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("Choisis ton plan")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Spacer(minLength: 4)
                if giftActive {
                    Text("CADEAU ACTIF")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(CooksyTheme.accentGradient))
                    if let expiresAt = offerExpiresAt {
                        PaywallOfferTimerCapsule(expiresAt: expiresAt)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(PremiumPlan.allCases) { plan in
                    planCard(plan)
                        .onTapGesture {
                            OnboardingHaptics.selection()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                selectedPlan = plan
                            }
                            confettiTrigger += 1
                        }
                }
            }
        }
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let isSelected = plan == selectedPlan
        // Always show the live storefront price — never apply a local
        // discount on top of it (Apple only honours promo offers
        // configured server-side in App Store Connect).
        let priceText = plan.liveOrFallbackPriceString
        let showsTrial = plan.hasFreeTrial && trialEligible
        let monthlyEquivalent = plan.liveOrFallbackMonthlyEquivalent

        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke,
                        lineWidth: 2
                    )
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(CooksyTheme.primaryAccent)
                        .frame(width: 12, height: 12)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if showsTrial {
                    HStack(spacing: 4) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(trialDays) JOURS GRATUITS")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(CooksyTheme.accentGradient))
                } else if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(CooksyTheme.accentGradient))
                }
                Text(plan.title)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(plan.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(priceText)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(plan.unitLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                if plan == .yearly, let monthlyEquivalent {
                    Text("soit \(monthlyEquivalent)/mois")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? CooksyTheme.elevatedSurface : CooksyTheme.surface)
                .shadow(
                    color: isSelected ? CooksyTheme.primaryAccent.opacity(0.18) : .clear,
                    radius: 14, y: 6
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected
                    ? AnyShapeStyle(CooksyTheme.accentGradient)
                    : AnyShapeStyle(CooksyTheme.stroke),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .scaleEffect(isSelected ? 1.01 : 1.0)
    }
}

// MARK: - Trust strip

private struct PaywallTrustStrip: View {
    private let items: [(String, String)] = [
        ("lock.shield.fill", "Sécurisé Apple"),
        ("xmark.circle.fill", "Annulable 2 taps"),
        ("hand.raised.fill", "Sans pub")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.0) { icon, label in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.surface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - Compact FAQ

private struct PaywallCompactFAQ: View {
    private let items: [(q: String, a: String)] = [
        ("Comment fonctionne l'essai gratuit ?",
         "7 jours offerts sur l'annuel. Rappel 24 h avant le 1ʳᵉ prélèvement. Annulation libre depuis Réglages > Apple ID."),
        ("Puis-je résilier facilement ?",
         "Oui, en 2 taps depuis Réglages > Apple ID > Abonnements. Sans aucune justification."),
        ("Quelles plateformes vidéo sont compatibles ?",
         "TikTok, Instagram Reels, YouTube et Shorts en français, anglais, espagnol et italien.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions fréquentes")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
            VStack(spacing: 8) {
                ForEach(items, id: \.q) { item in
                    DisclosureGroup {
                        Text(item.a)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(item.q)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .tint(CooksyTheme.primaryAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CooksyTheme.elevatedSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(CooksyTheme.stroke, lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
}

// MARK: - Sticky CTA

private struct PaywallStickyCTA: View {
    let selectedPlan: PremiumPlan
    let trialAvailable: Bool
    let trialDays: Int
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onPurchase) {
                HStack(spacing: 10) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(ctaCopy)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 10)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(isPurchasing)

            // ONE clear billing lockup — no fragmentation. The user
            // reads exactly what Apple is going to charge in their own
            // currency, and when (after the trial or immediately).
            billingLockup
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 4)

            Text("Sans engagement · Annulable en 2 taps depuis Réglages")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Conditions") {}
                Button("Confidentialité") {}
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var ctaCopy: String {
        if selectedPlan == .yearly && trialAvailable {
            return "Commencer mes \(trialDays) jours gratuits"
        }
        return "Continuer · \(selectedPlan.liveOrFallbackPriceString)\(selectedPlan.unitLabel)"
    }

    /// Single source of truth for the small line under the CTA. It
    /// always reads "[trial preface] then [LIVE PRICE] / [unit]" so the
    /// user never has any doubt about what's being charged.
    private var billingLockup: Text {
        let billed = selectedPlan.liveOrFallbackPriceString
        let unit = selectedPlan.unitLabel

        if selectedPlan == .yearly && trialAvailable {
            let trialPart = Text("Essai \(trialDays) jours gratuit")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(CooksyTheme.primaryAccentStrong)
            let billedPart = Text("  ·  puis \(billed)\(unit)")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(CooksyTheme.secondaryText)
            return trialPart + billedPart
        }
        return Text("Facturé \(billed)\(unit) · aujourd'hui")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(CooksyTheme.secondaryText)
    }
}

// MARK: - Offer timer capsule

/// Live countdown rendered next to "OFFRE −25 %". Reads from the same
/// 24 h gift-offer expiry that drives the gift state machine, so the
/// UI never drifts from discount eligibility.
private struct PaywallOfferTimerCapsule: View {
    let expiresAt: Date

    @State private var now: Date = Date()
    @State private var pulse: Bool = false
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval { max(expiresAt.timeIntervalSince(now), 0) }
    private var isUrgent: Bool { remaining < 3600 }
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
        .background(
            Capsule().fill(isUrgent ? Color(hex: 0xE11D48) : Color(hex: 0x111827))
        )
        .scaleEffect(isUrgent && pulse ? 1.05 : 1.0)
        .animation(
            isUrgent
            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
            : .default,
            value: pulse
        )
        .onReceive(timer) { date in
            now = date
            if isUrgent { pulse.toggle() }
        }
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
