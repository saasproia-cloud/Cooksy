import SwiftUI

/// Cooksy premium paywall — round 4 single-page redesign.
///
/// The previous round still relied on a `ScrollView` that listed a hero,
/// a trust strip, a 5-question FAQ and a footer below the fold. Users
/// almost never scrolled, so half of it was wasted real estate.
///
/// This pass takes inspiration from the best-converting subscription
/// paywalls (Calm, Cal AI, Blinkist, Duolingo Super, Notion): a tight
/// editorial column that fits on a single screen — hero → benefits →
/// plans → CTA → microcopy. No FAQ, no scroll. Everything the user
/// needs to commit is visible at once; the legal microcopy pulls double
/// duty as the trust strip ("Sans engagement · Apple sécurisé · 2 taps").
///
/// The gift mini-game and the discount logic are unchanged — they
/// live in `PremiumOffersService` and surface here as the optional
/// "CADEAU ACTIF" capsule on the annual card.
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

            // Single editorial column. Phone-size variance is
            // distributed symmetrically between the top inset and the
            // gap above the CTA so the hero and picker never feel
            // isolated in a sea of empty space.
            GeometryReader { geo in
                let breathing = max((geo.size.height - 760) / 2, 0)

                VStack(spacing: 0) {
                    Color.clear.frame(height: 52 + breathing)

                    PaywallEditorialHero(
                        showGiftBadge: offers.shouldShowGiftPill
                            && offers.giftHasBeenWon
                            && offers.giftOfferIsActive,
                        giftDiscountPercent: offers.giftDiscountPercent,
                        onOpenGift: { showsExclusiveOffer = true }
                    )

                    if shouldShowGiftReminderBanner {
                        PaywallGiftReminderBanner(
                            isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                            discountPercent: offers.giftDiscountPercent ?? 25,
                            onTap: handleOpenGiftFromReminder,
                            onDismiss: { giftReminderDismissed = true }
                        )
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                    }

                    Color.clear.frame(height: 14)

                    MiniRecipeShowcase()
                        .frame(maxWidth: .infinity)

                    Color.clear.frame(height: 14)

                    PaywallBenefitsList()
                        .padding(.horizontal, 22)

                    Color.clear.frame(height: 14)

                    PaywallPlanPicker(
                        selectedPlan: $selectedPlan,
                        offerExpiresAt: activeOfferExpiresAt,
                        trialDays: trialDays,
                        trialEligible: purchaseService.isAnnualTrialEligible,
                        giftActive: offers.giftOfferIsActive,
                        confettiTrigger: $confettiTrigger
                    )
                    .padding(.horizontal, 22)

                    Color.clear.frame(height: breathing)

                    Spacer(minLength: 12)

                    PaywallStickyCTA(
                        selectedPlan: selectedPlan,
                        trialAvailable: trialAvailable,
                        trialDays: trialDays,
                        isPurchasing: isPurchasing,
                        onPurchase: handlePurchase
                    )
                }
                .frame(width: geo.size.width)
            }

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

// MARK: - Editorial hero (eyebrow + headline only)

private struct PaywallEditorialHero: View {
    let showGiftBadge: Bool
    let giftDiscountPercent: Int?
    let onOpenGift: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Text("Tes recettes,\nprêtes à cuisiner.")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }
}

// MARK: - Mini recipe showcase

/// Floating mini recipe card placed under the headline. Acts as the
/// visual hero of the paywall — communicates "premium = your recipes,
/// ready to cook" without any text. Uses a slow continuous float to
/// feel alive without demanding attention.
private struct MiniRecipeShowcase: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let yOffset = sin(t * 0.5) * 3.5
            let rotY = cos(t * 0.4) * 1.4

            ZStack {
                // Soft warm halo behind the card.
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccentGlow.opacity(0.55),
                                CooksyTheme.primaryAccentSoft.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 160
                        )
                    )
                    .frame(width: 280, height: 160)
                    .blur(radius: 18)

                showcaseCard
                    .offset(y: yOffset)
                    .rotation3DEffect(
                        .degrees(rotY),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.6
                    )
            }
            .frame(height: 132)
        }
    }

    private var showcaseCard: some View {
        HStack(spacing: 0) {
            // Warm accent band on the left.
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xFFD9A8),
                        Color(hex: 0xF5A056),
                        Color(hex: 0xE76F2A)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 56, height: 56)
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 46, height: 46)
                    ForEach(0..<3, id: \.self) { i in
                        let size = CGFloat(16 + i * 9)
                        Circle()
                            .stroke(
                                Color(hex: 0xFFF0D6).opacity(0.75 - Double(i) * 0.18),
                                lineWidth: 1.4
                            )
                            .frame(width: size, height: size)
                    }
                }
            }
            .frame(width: 78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Pâtes au pesto")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(Color(hex: 0x2A1B12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("15 min")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(CooksyTheme.accentGradient)
                    )
                }

                Rectangle()
                    .fill(Color(hex: 0xEFE3CE))
                    .frame(height: 0.6)

                VStack(alignment: .leading, spacing: 4) {
                    showcaseIngredient("200 g de pâtes")
                    showcaseIngredient("30 g de basilic frais")
                    showcaseIngredient("40 g de parmesan")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .frame(width: 248, height: 116)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xEFE3CE), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 12)
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.18), radius: 30, y: 0)
    }

    private func showcaseIngredient(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CooksyTheme.primaryAccent)
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x3A2A1F))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

// MARK: - Benefits list

/// Four checked rows that articulate what premium unlocks. Replaces
/// the previous 3-line inline benefits — denser, clearer, more
/// concrete value propositions.
private struct PaywallBenefitsList: View {
    private static let items: [(icon: String, title: String)] = [
        ("infinity", "Imports illimités — TikTok, Reels, YouTube"),
        ("wand.and.stars", "IA culinaire ultra-fidèle à la vidéo"),
        ("calendar.badge.clock", "Plan repas + liste de courses auto"),
        ("hand.raised.fill", "Sans pub, sans limite — pour toujours")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Self.items, id: \.title) { item in
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 8) {
            // Header is shown only when a gift is active — when there's
            // no offer to communicate, the title would be wasted space
            // since the two cards already speak for themselves.
            if giftActive {
                HStack(spacing: 8) {
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
                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 8) {
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

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke,
                        lineWidth: 2
                    )
                    .frame(width: 20, height: 20)
                if isSelected {
                    Circle()
                        .fill(CooksyTheme.primaryAccent)
                        .frame(width: 10, height: 10)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if showsTrial {
                    HStack(spacing: 4) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(trialDays) JOURS GRATUITS")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CooksyTheme.accentGradient))
                } else if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(CooksyTheme.accentGradient))
                }
                Text(plan.title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(plan.subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(priceText)
                    .font(.system(size: 17, weight: .bold, design: .serif))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Selected card sits on a soft warm gradient with a tinted
            // surface — this is what gives the middle of the paywall a
            // visual anchor so the page no longer reads as "three loose
            // blocks floating on cream".
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? CooksyTheme.elevatedSurface : CooksyTheme.surface)
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    CooksyTheme.primaryAccentSoft.opacity(0.55),
                                    CooksyTheme.primaryAccentSoft.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.22) : .clear,
                radius: 16, y: 8
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

// MARK: - Sticky CTA

private struct PaywallStickyCTA: View {
    let selectedPlan: PremiumPlan
    let trialAvailable: Bool
    let trialDays: Int
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 8)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(isPurchasing)

            // ONE clear billing lockup — exactly what Apple will charge
            // and when. No fragmentation across multiple lines.
            billingLockup
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)

            // Compact trust strip — two items only (the third was
            // duplicated by the benefits list above).
            HStack(spacing: 12) {
                trustItem(icon: "lock.shield.fill", label: "Sécurisé Apple")
                Circle().fill(CooksyTheme.stroke).frame(width: 2, height: 2)
                trustItem(icon: "xmark.circle.fill", label: "Annulable 2 taps")
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)

            HStack(spacing: 16) {
                Button("Conditions") {}
                Button("Confidentialité") {}
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func trustItem(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
            Text(label)
        }
    }

    private var ctaCopy: String {
        // For the yearly plan we ALWAYS show the per-month equivalent
        // on the button — it's the most decision-friendly figure
        // (€/mois feels small and concrete next to a €/an total). The
        // trial promise stays on the button when applicable so the
        // user doesn't have to read the sub-line to find it.
        if selectedPlan == .yearly,
           let perMonth = selectedPlan.liveOrFallbackMonthlyEquivalent {
            if trialAvailable {
                return "Commencer · \(trialDays) j gratuit, puis \(perMonth)/mois"
            }
            return "Continuer · \(perMonth)/mois"
        }
        // Monthly plan (or yearly without a derivable monthly figure).
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
