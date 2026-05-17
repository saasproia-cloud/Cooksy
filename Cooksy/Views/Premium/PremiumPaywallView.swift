import SwiftUI

/// Cooksy premium paywall — round 6, redesigned to mirror the
/// RevenueCat "modern subscription" template the user picked as
/// reference.
///
///   X close
///                       [ Cooksy logo ]
///                        Cooksy Premium
///                  Toutes tes vidéos → recettes.
///   ┌────────────────────────────────────────────────────────┐
///   │  Title                              ★★★★★              │
///   │  « avis utilisateur signé »                            │
///   │  L  Léa · Paris                              App Store │
///   └────────────────────────────────────────────────────────┘
///                          • • • •
///                      [ MEILLEUR CHOIX ]
///   ┌────────────────────────────────────────────────────────┐
///   │  Annuel  (−58 %)                              39,99€ /an │
///   │  soit 3,33€ /mois · 7 j gratuits                       │
///   └────────────────────────────────────────────────────────┘
///   ┌────────────────────────────────────────────────────────┐
///   │  Mensuel                                       7,99€ /mois │
///   │  Sans engagement                                       │
///   └────────────────────────────────────────────────────────┘
///                   [    Continuer    ]
///        Restaurer  ·  Conditions  ·  Confidentialité
///
/// The screen is tuned to fit on a single iPhone (no scroll on
/// standard devices). A vertical ScrollView is kept as a safety
/// net for XL Dynamic Type or compact phones.
///
/// All purchase / gift-wheel / exit-intent / restore wiring is
/// preserved 1:1 from the previous version — only the visual
/// layout changes.
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
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            paywallHalo
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPad = Layout.horizontalPadding(for: geo)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        // Top clearance for the sticky close button.
                        Color.clear.frame(height: 46)

                        PaywallLogoMark()

                        PaywallHeadline()

                        // Optional gift banner / strip — keep the
                        // gift-wheel mechanic intact when triggered.
                        if shouldShowGiftReminderBanner {
                            PaywallGiftReminderBanner(
                                isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                                discountPercent: offers.giftDiscountPercent ?? 25,
                                onTap: handleOpenGiftFromReminder,
                                onDismiss: { giftReminderDismissed = true }
                            )
                        }

                        if offers.giftOfferIsActive {
                            PaywallGiftStrip(
                                discountPercent: activeGiftDiscountPercent,
                                expiresAt: activeOfferExpiresAt
                            )
                        }

                        PaywallReviewCard()

                        PaywallPlanColumn(
                            selectedPlan: $selectedPlan,
                            trialDays: trialDays,
                            trialEligible: purchaseService.isAnnualTrialEligible,
                            giftActive: offers.giftOfferIsActive,
                            giftDiscountPercent: activeGiftDiscountPercent,
                            confettiTrigger: $confettiTrigger
                        )

                        PaywallContinueCTA(
                            selectedPlan: selectedPlan,
                            trialAvailable: trialAvailable,
                            trialDays: trialDays,
                            giftDiscountPercent: activeGiftDiscountPercent,
                            isPurchasing: isPurchasing,
                            onPurchase: handlePurchase
                        )

                        PaywallFooterLinks(onRestore: handleRestore)
                            .padding(.top, 2)

                        Color.clear.frame(height: 18)
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, hPad)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }

            IngredientConfetti(trigger: confettiTrigger)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) { stickyCloseButton }
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

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.warmCard.opacity(0.5),
                            CooksyTheme.warmCard.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 540, height: 540)
                .offset(x: 80, y: 340)
                .blur(radius: 22)
        }
    }

    // MARK: - Sticky chrome

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
            .padding(.leading, 16)
            .padding(.top, 8)
            .zIndex(99)
            .accessibilityLabel("Fermer et rester en gratuit")
        }
    }

    // MARK: - Derived state

    private var activeOfferExpiresAt: Date? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftOfferExpiresAt
    }

    /// Discount percentage to apply to the annual price right now —
    /// only non-nil when the user actually has an active gift in their
    /// 24 h window. Drives every price string on the paywall so the
    /// headline stays in sync with what `purchaseAnnualWithPromo` will
    /// charge via the `GIFTxx` Promotional Offer.
    private var activeGiftDiscountPercent: Int? {
        guard offers.giftOfferIsActive else { return nil }
        return offers.giftDiscountPercent
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

// MARK: - Logo mark

/// Clean Cooksy logo lockup — same recipe as the welcome screen so
/// the brand reads identically on both surfaces. Just the `HeaderLogo`
/// asset on a soft white disc; no orange square, no template tinting,
/// no weird artefact behind the toque.
private struct PaywallLogoMark: View {
    var body: some View {
        ZStack {
            // Outer warm glow.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentGlow.opacity(0.55),
                            CooksyTheme.primaryAccentGlow.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 70
                    )
                )
                .frame(width: 132, height: 132)
                .blur(radius: 8)

            // White glass disc — same as Welcome.
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 88, height: 88)
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 16, y: 9)
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.16), radius: 20, y: 0)

            // The toque — natural orange render, no template tint.
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
        }
        .frame(width: 132, height: 132)
    }
}

// MARK: - Headline

private struct PaywallHeadline: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Débloque l'accès complet")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)

            Text("Toutes tes vidéos transformées en recettes claires, sans limite.")
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Review card carousel

/// One signed testimonial in the rotating carousel.
private struct PaywallReview: Identifiable {
    let id = UUID()
    let title: String
    let quote: String
    let authorInitial: String
    let authorName: String
    let avatarColors: [Color]
}

/// Auto-rotating testimonial carousel — visually mirrors the model:
/// a single card with title, stars, quote, signed author and an
/// "App Store" tag, plus a row of page dots underneath. Reviews are
/// written for Cooksy (not the cat-photo demo from the reference).
private struct PaywallReviewCard: View {
    private static let reviews: [PaywallReview] = [
        PaywallReview(
            title: "La meilleure app cuisine",
            quote: "« Je colle un lien TikTok, j'obtiens la recette propre en 10 s. Plus jamais besoin de revoir la vidéo en cuisine. »",
            authorInitial: "L",
            authorName: "Léa · Paris",
            avatarColors: [Color(hex: 0xFFB35A), Color(hex: 0xE76F2A)]
        ),
        PaywallReview(
            title: "Structure préservée à 100 %",
            quote: "« Les sections marinade, sauce et assemblage restent bien séparées. C'est exactement la recette qu'il y avait dans la vidéo. »",
            authorInitial: "M",
            authorName: "Marc · Lyon",
            avatarColors: [Color(hex: 0xF7C77A), Color(hex: 0xC9471D)]
        ),
        PaywallReview(
            title: "Un vrai gain de temps",
            quote: "« Plus d'allers-retours entre l'app et la cuisine. Je gagne 15 minutes par recette, et tout est précis au gramme. »",
            authorInitial: "S",
            authorName: "Sophie · Bordeaux",
            avatarColors: [Color(hex: 0xF8B26A), Color(hex: 0xD94B20)]
        ),
        PaywallReview(
            title: "Précision au top",
            quote: "« Les quantités sont justes, les ingrédients pas génériques. Du vrai cooking. Cooksy a remplacé mes captures d'écran. »",
            authorInitial: "T",
            authorName: "Thomas · Marseille",
            avatarColors: [Color(hex: 0xFFB35A), Color(hex: 0xB3441C)]
        )
    ]

    @State private var index: Int = 0
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            // Crossfade carousel — replaces TabView(.page) which
            // bleeds past its SwiftUI frame because UIPageViewController
            // hardcodes page width to UIScreen.main.bounds. Pure SwiftUI
            // ZStack with opacity transitions stays inside the parent.
            ZStack {
                ForEach(Array(Self.reviews.enumerated()), id: \.element.id) { i, review in
                    reviewCard(review)
                        .opacity(i == index ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.45)) {
                    index = (index + 1) % Self.reviews.count
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<Self.reviews.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index
                              ? AnyShapeStyle(CooksyTheme.accentGradient)
                              : AnyShapeStyle(CooksyTheme.stroke))
                        .frame(width: i == index ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
                        .onTapGesture {
                            OnboardingHaptics.selection()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                index = i
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewCard(_ review: PaywallReview) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(review.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 1.5) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentGlow)
                    }
                }
            }

            Text(review.quote)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.88))
                .lineSpacing(1)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: review.avatarColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(
                        Text(review.authorInitial)
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
                Text(review.authorName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text("App Store")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 16, y: 6)
        )
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

// MARK: - Plan column (vertical stack — yearly on top, monthly below)

/// Stacked plan cards. Each card is a horizontal row: plan name +
/// subtitle on the left, price + cadence on the right, with a
/// floating "MEILLEUR CHOIX" pill above the annual card when it's
/// the selected option (matches the reference template).
private struct PaywallPlanColumn: View {
    @Binding var selectedPlan: PremiumPlan
    let trialDays: Int
    let trialEligible: Bool
    let giftActive: Bool
    let giftDiscountPercent: Int?
    @Binding var confettiTrigger: Int

    /// Stable order: yearly first (with badge), monthly second.
    private var orderedPlans: [PremiumPlan] {
        [.yearly, .monthly]
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(orderedPlans) { plan in
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
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func planCard(_ plan: PremiumPlan) -> some View {
        let isSelected = plan == selectedPlan
        let effectiveDiscount: Int? = (giftActive && plan.supportsPromotionalDiscount)
            ? giftDiscountPercent
            : nil
        let priceText = plan.liveOrFallbackPriceString(discountPercent: effectiveDiscount)
        let originalPriceText: String? = effectiveDiscount != nil
            ? plan.liveOrFallbackPriceString
            : nil
        let perMonth = plan.liveOrFallbackMonthlyEquivalent(discountPercent: effectiveDiscount)
        let showsTrial = plan.hasFreeTrial && trialEligible

        VStack(spacing: 0) {
            // "MEILLEUR CHOIX" floating badge — only on yearly.
            if plan == .yearly {
                bestValueBadge(isSelected: isSelected)
                    .padding(.bottom, -8)
                    .zIndex(2)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(plan.title)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if plan == .yearly, effectiveDiscount == nil {
                            Text("(−58 %)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    isSelected
                                    ? Color.white.opacity(0.92)
                                    : CooksyTheme.primaryAccentStrong
                                )
                                .lineLimit(1)
                        } else if let percent = effectiveDiscount {
                            Text("(−\(percent) %)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    isSelected
                                    ? Color.white.opacity(0.92)
                                    : CooksyTheme.primaryAccentStrong
                                )
                                .lineLimit(1)
                        }
                    }

                    Text(subtitle(for: plan, perMonth: perMonth, showsTrial: showsTrial))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            isSelected
                            ? Color.white.opacity(0.88)
                            : CooksyTheme.secondaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                priceColumn(
                    plan: plan,
                    isSelected: isSelected,
                    priceText: priceText,
                    originalPriceText: originalPriceText,
                    perMonth: perMonth
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, plan == .yearly ? 10 : 9)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isSelected
                            ? AnyShapeStyle(CooksyTheme.accentGradient)
                            : AnyShapeStyle(Color.white)
                        )

                    if !isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        CooksyTheme.primaryAccentSoft.opacity(0.18),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? AnyShapeStyle(Color.white.opacity(0.35))
                        : AnyShapeStyle(CooksyTheme.stroke),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? CooksyTheme.primaryAccent.opacity(0.28)
                    : Color.black.opacity(0.05),
                radius: isSelected ? 18 : 8,
                y: isSelected ? 10 : 3
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(priceText)\(plan.unitLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Right-side price column. On the annual card we surface the
    /// **per-month equivalent** as the headline number (cheaper-looking,
    /// what users compare against the monthly plan) and push the yearly
    /// total to a small caption underneath. When a gift discount is
    /// active, the caption shows the strikethrough original yearly price
    /// next to the discounted one, so the −25 % savings stay visible
    /// after spinning the wheel.
    @ViewBuilder
    private func priceColumn(
        plan: PremiumPlan,
        isSelected: Bool,
        priceText: String,
        originalPriceText: String?,
        perMonth: String?
    ) -> some View {
        let headlinePrice: String = {
            if plan == .yearly, let perMonth { return "\(perMonth)/mois" }
            return "\(priceText)\(plan.unitLabel)"
        }()

        VStack(alignment: .trailing, spacing: 1) {
            Text(headlinePrice)
                .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if plan == .yearly {
                HStack(spacing: 4) {
                    if let originalPriceText {
                        Text("\(originalPriceText)/an")
                            .strikethrough()
                            .foregroundStyle(
                                isSelected
                                ? Color.white.opacity(0.65)
                                : CooksyTheme.secondaryText.opacity(0.8)
                            )
                    }
                    Text("\(priceText)/an")
                        .foregroundStyle(
                            isSelected
                            ? Color.white.opacity(0.92)
                            : CooksyTheme.secondaryText
                        )
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private func bestValueBadge(isSelected: Bool) -> some View {
        Text("MEILLEUR CHOIX")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(CooksyTheme.accentGradient)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 8, y: 4)
            )
    }

    private func subtitle(for plan: PremiumPlan, perMonth: String?, showsTrial: Bool) -> String {
        switch plan {
        case .yearly:
            // Per-month figure is now the headline number on the right —
            // keep this subtitle short and focused on the differentiator:
            // the free trial (when eligible) or just "Sans engagement".
            if showsTrial {
                return "\(trialDays) j gratuits · sans engagement"
            }
            return "Sans engagement"
        case .monthly:
            return plan.subtitle
        }
    }
}

// MARK: - Continue CTA

private struct PaywallContinueCTA: View {
    let selectedPlan: PremiumPlan
    let trialAvailable: Bool
    let trialDays: Int
    let giftDiscountPercent: Int?
    let isPurchasing: Bool
    let onPurchase: () -> Void

    private var effectiveDiscount: Int? {
        guard selectedPlan.supportsPromotionalDiscount else { return nil }
        return giftDiscountPercent
    }

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
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 9)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(isPurchasing)

            billingLockup
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var ctaCopy: String {
        if selectedPlan == .yearly, trialAvailable {
            return "Démarrer l'essai gratuit"
        }
        return "Continuer"
    }

    private var billingLockup: Text {
        let billed = selectedPlan.liveOrFallbackPriceString(discountPercent: effectiveDiscount)
        let unit = selectedPlan.unitLabel
        let perMonthValue = selectedPlan.liveOrFallbackMonthlyEquivalent(discountPercent: effectiveDiscount)

        // ── Annual ───────────────────────────────────────────────────
        // We want the user to compare on the per-month figure, with the
        // yearly total appearing as the small "equivalent" caption — the
        // discount from the gift wheel (−25 %, etc.) already flows
        // through both `billed` and `perMonthValue` here.
        if selectedPlan == .yearly, let perMonth = perMonthValue {
            if trialAvailable {
                let trialPart = Text("Essai \(trialDays) jours gratuit")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(CooksyTheme.primaryAccentStrong)
                let billedPart = Text("  ·  puis \(perMonth)/mois (soit \(billed)/an)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(CooksyTheme.secondaryText)
                return trialPart + billedPart
            }
            let leading = Text("\(perMonth)/mois")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(CooksyTheme.primaryText)
            let trailing = Text("  ·  soit \(billed)/an facturé annuellement")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundColor(CooksyTheme.secondaryText)
            return leading + trailing
        }

        // ── Monthly ──────────────────────────────────────────────────
        return Text("Facturé \(billed)\(unit) · sans engagement")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(CooksyTheme.secondaryText)
    }
}

// MARK: - Footer links

private struct PaywallFooterLinks: View {
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onRestore) {
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Offer timer capsule

/// Neutral countdown capsule. The red-pulse "urgency" pattern was
/// removed — it erodes trust on a premium surface. The timer is kept
/// as a factual indicator of offer expiry without any alarm coloring.
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
