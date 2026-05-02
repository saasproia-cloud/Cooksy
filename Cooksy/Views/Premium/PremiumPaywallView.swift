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

    @State private var selectedPlan: PremiumPlan = .defaultPlan
    @State private var trialEnabled: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var showsGiftWheel: Bool = false
    @State private var showsExclusiveOffer: Bool = false
    @State private var giftReminderDismissed: Bool = false
    @State private var confettiTrigger: Int = 0
    /// Set to `true` after the user has tried to leave once. Drives
    /// the X-button behaviour (1st tap = open the wheel, 2nd tap =
    /// actually leave to free mode).
    @State private var hasTriggeredExitIntent: Bool = false

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
                        offerDiscount: activeDiscountPercent,
                        offerExpiresAt: activeOfferExpiresAt,
                        confettiTrigger: $confettiTrigger
                    )
                    .padding(.horizontal, 22)

                    PaywallTrialComparator(
                        plan: selectedPlan,
                        trialEnabled: $trialEnabled,
                        discountPercent: effectiveDiscount(for: selectedPlan)
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
                trialEnabled: trialEnabled,
                discountPercent: activeDiscountPercent,
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
        .onAppear {
            offers.paywallWasReached()
        }
        .fullScreenCover(isPresented: $showsGiftWheel) {
            GiftWheelView(
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
                onClose: { showsExclusiveOffer = false },
                onSubscribe: { trialOn in
                    showsExclusiveOffer = false
                    selectedPlan = .yearly
                    trialEnabled = trialOn
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        handlePurchase()
                    }
                }
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
        Button(action: { /* restore */ }) {
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

    private var activeDiscountPercent: Int? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftDiscountPercent
    }

    private var activeOfferExpiresAt: Date? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftOfferExpiresAt
    }

    private func effectiveDiscount(for plan: PremiumPlan) -> Int? {
        guard plan.supportsPromotionalDiscount else { return nil }
        return activeDiscountPercent
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

        // Wire the purchase intent into the gift state machine BEFORE
        // flipping the premium flag — so the post-trial conversion / cancel
        // bookkeeping is correctly seeded.
        offers.recordPurchaseStarted(
            plan: selectedPlan,
            usingFreeTrial: selectedPlan.hasFreeTrial && trialEnabled
        )

        isPurchasing = true
        Task {
            await sessionStore.setPremiumMock(true)
            await MainActor.run {
                isPurchasing = false
                offers.clearFreeModeChoice()
                // Mock-flow only: when the user picks the annual plan
                // without trial, treat the purchase as the trial having
                // converted instantly. Real StoreKit will replace this
                // hook with a server webhook.
                if selectedPlan == .yearly && !trialEnabled {
                    offers.recordTrialConverted()
                }
            }
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
                            Text("−\(giftDiscountPercent ?? 25) %")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(CooksyTheme.heroDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(CooksyTheme.goldShimmer))
                    }
                    .buttonStyle(CooksyTheme.pressScale())
                }
            }

            Text("Tes recettes\npréférées, prêtes\nà cuisiner.")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Importe n'importe quelle vidéo TikTok, Instagram ou YouTube. Cooksy en fait une recette propre, structurée, à ton rythme.")
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
    let offerDiscount: Int?
    let offerExpiresAt: Date?
    @Binding var confettiTrigger: Int

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("Choisis ton plan")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Spacer(minLength: 4)
                if let discount = offerDiscount {
                    Text("OFFRE −\(discount) %")
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
        let discount = plan.supportsPromotionalDiscount ? offerDiscount : nil
        let priceText = plan.formattedPrice(discountPercent: discount)
        let originalPriceText = (discount != nil) ? plan.formattedPrice() : nil

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
                if let badge = plan.badge {
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
                if let originalPriceText {
                    Text(originalPriceText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .strikethrough()
                }
                Text(priceText)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(plan.unitLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
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

// MARK: - Trial comparator

/// Compact "trial on/off" toggle that always shows the monthly
/// breakdown (e.g. *2,49 €/mois facturés 29,99 €/an*) and reveals the
/// "0 € maintenant, puis X €/an dans 7 jours" sub-line when the trial
/// is on. Single-card layout — no more confusing two-column comparator.
/// Hidden for the monthly plan since there's no trial there.
private struct PaywallTrialComparator: View {
    let plan: PremiumPlan
    @Binding var trialEnabled: Bool
    let discountPercent: Int?

    var body: some View {
        if plan.hasFreeTrial {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $trialEnabled.animation(.spring(response: 0.35))) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(CooksyTheme.primaryAccent)
                        Text("Essai gratuit 7 jours")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                }
                .tint(CooksyTheme.primaryAccent)

                Divider().background(CooksyTheme.stroke)

                // Single headline price line: monthly equivalent in
                // hero size + the full annual price as strikethrough
                // comparison. No more sub-text — the toggle alone
                // tells the user what flow they're in.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(monthlyPrice)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("au lieu de \(yearlyFullPrice)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .strikethrough()
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                trialEnabled
                                ? CooksyTheme.primaryAccent.opacity(0.4)
                                : CooksyTheme.stroke,
                                lineWidth: trialEnabled ? 1.5 : 1
                            )
                    )
            )
        }
    }

    /// "2,49 €/mois" — the per-month equivalent of the annual price,
    /// possibly with the gift discount applied. This is the number
    /// that makes the deal feel small.
    private var monthlyPrice: String {
        plan.monthlyEquivalentString(discountPercent: discountPercent)
            ?? plan.formattedPrice(discountPercent: discountPercent)
    }

    /// "39,99 €/an" — the full undiscounted annual price, used as the
    /// strikethrough so the user sees how much they save by picking
    /// the annual plan vs paying full price.
    private var yearlyFullPrice: String {
        PremiumPlan.yearly.formattedPrice() + PremiumPlan.yearly.unitLabel
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
    let trialEnabled: Bool
    let discountPercent: Int?
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 8) {
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

            if let priceLine = priceHighlightLine {
                priceLine
                    .multilineTextAlignment(.center)
            }

            Text(legalCopy)
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

    private var effectiveDiscount: Int? {
        selectedPlan.supportsPromotionalDiscount ? discountPercent : nil
    }

    private var ctaCopy: String {
        if selectedPlan.hasFreeTrial && trialEnabled {
            return "Démarrer mes 7 jours gratuits"
        }
        let priceText = selectedPlan.formattedPrice(discountPercent: effectiveDiscount)
        return "Continuer · \(priceText)\(selectedPlan.unitLabel)"
    }

    private var priceHighlightLine: Text? {
        let strike = (effectiveDiscount != nil) ? selectedPlan.formattedPrice() : nil
        let perMonth = selectedPlan.monthlyEquivalentString(discountPercent: effectiveDiscount)
        guard strike != nil || perMonth != nil else { return nil }

        var combined = Text("")
        if let strike {
            combined = combined
                + Text(strike)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .strikethrough()
                    .foregroundColor(CooksyTheme.secondaryText)
        }
        if strike != nil, perMonth != nil {
            combined = combined
                + Text("  ·  ")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(CooksyTheme.secondaryText)
        }
        if let perMonth {
            combined = combined
                + Text("soit \(perMonth)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(CooksyTheme.primaryAccentStrong)
        }
        return combined
    }

    private var legalCopy: String {
        var pieces: [String] = []
        if selectedPlan.hasFreeTrial && trialEnabled {
            let priceText = selectedPlan.formattedPrice(discountPercent: effectiveDiscount)
            pieces.append("Puis \(priceText)\(selectedPlan.unitLabel) à J+7")
        }
        if effectiveDiscount != nil, !selectedPlan.firstPeriodDisclaimer.isEmpty {
            pieces.append(selectedPlan.firstPeriodDisclaimer)
        }
        pieces.append("Résiliable en 2 taps")
        return pieces.joined(separator: " · ")
    }
}

// MARK: - Offer timer capsule

/// Live countdown rendered next to "OFFRE −25 %". Reads from the same
/// 24 h gift-offer expiry that drives `activeDiscountPercent`, so the
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
