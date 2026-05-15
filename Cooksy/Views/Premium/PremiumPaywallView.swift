import SwiftUI

/// Cooksy premium paywall — round 5, conversion-tuned redesign.
///
/// The previous round still leaned on a stacked editorial column with a
/// floating recipe showcase, an ambient hero and a sticky CTA. The new
/// layout mirrors the patterns that consistently win paywall A/Bs in
/// 2024-2026 (Calm, Cal AI, Blinkist Premium, RC Templates):
///
///   X close                                            Restore
///                       [Cooksy app icon]
///                          Cooksy Premium
///                Toutes tes recettes, prêtes à cuisiner.
///                   [App de l'année 2025 — laurier]
///   ┌────────────────────────────────────────────────────────┐
///   │  ★★★★★   « avis utilisateur signé »                     │
///   └────────────────────────────────────────────────────────┘
///   ┌───────────┐    ┌────────────────────┐
///   │   1 MOIS  │    │    12 MOIS  ✓      │
///   │   7,99€   │    │   3,33€ / mois     │
///   │   /mois   │    │   économise 58 %   │
///   └───────────┘    └────────────────────┘
///                   [    Continuer    ]
///       Restore · Conditions · Confidentialité
///
/// Two plans only — the lifetime SKU was dropped to keep the choice
/// visceral. The annual card is always pre-selected because that's the
/// plan that funds the product. The gift mini-game, the cadeau timer
/// and the discounted price (`GIFTxx` Promotional Offer) are unchanged
/// — they slot into the same scaffolding.
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

            // Soft warm halo behind the editorial column so the screen
            // doesn't read as a flat cream sheet.
            paywallHalo
                .ignoresSafeArea()

            GeometryReader { geo in
                let hPad = Layout.horizontalPadding(for: geo)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Top clearance for the sticky close button.
                        Color.clear.frame(height: 60)

                        // ── HERO ───────────────────────────────────────────
                        PaywallLogoMark()
                        Color.clear.frame(height: 12)
                        PaywallHeadline(
                            showGiftBadge: offers.shouldShowGiftPill
                                && offers.giftHasBeenWon
                                && offers.giftOfferIsActive,
                            giftDiscountPercent: offers.giftDiscountPercent,
                            onOpenGift: { showsExclusiveOffer = true }
                        )
                        .padding(.horizontal, hPad)
                        Color.clear.frame(height: 10)
                        PaywallAwardBadge()
                        Color.clear.frame(height: 20)

                        // ── CONTEXTUAL GIFT BLOCKS ─────────────────────────
                        if shouldShowGiftReminderBanner {
                            PaywallGiftReminderBanner(
                                isAlreadyWon: offers.giftHasBeenWon && offers.giftOfferIsActive,
                                discountPercent: offers.giftDiscountPercent ?? 25,
                                onTap: handleOpenGiftFromReminder,
                                onDismiss: { giftReminderDismissed = true }
                            )
                            .padding(.horizontal, hPad)
                            .padding(.bottom, 12)
                        }

                        if offers.giftOfferIsActive {
                            PaywallGiftStrip(
                                discountPercent: activeGiftDiscountPercent,
                                expiresAt: activeOfferExpiresAt
                            )
                            .padding(.horizontal, hPad)
                            .padding(.bottom, 10)
                        }

                        // ── PLAN CARDS ─────────────────────────────────────
                        PaywallPlanRow(
                            selectedPlan: $selectedPlan,
                            trialDays: trialDays,
                            trialEligible: purchaseService.isAnnualTrialEligible,
                            giftActive: offers.giftOfferIsActive,
                            giftDiscountPercent: activeGiftDiscountPercent,
                            confettiTrigger: $confettiTrigger
                        )
                        .padding(.horizontal, hPad)

                        Color.clear.frame(height: 16)

                        // ── PRIMARY CTA ────────────────────────────────────
                        PaywallContinueCTA(
                            selectedPlan: selectedPlan,
                            trialAvailable: trialAvailable,
                            trialDays: trialDays,
                            giftDiscountPercent: activeGiftDiscountPercent,
                            isPurchasing: isPurchasing,
                            onPurchase: handlePurchase
                        )
                        .padding(.horizontal, hPad)

                        Color.clear.frame(height: 28)

                        // ── FEATURE COMPARISON ─────────────────────────────
                        PaywallFeatureComparisonView()
                            .padding(.horizontal, hPad)

                        Color.clear.frame(height: 20)

                        // ── TRUST STRIP ────────────────────────────────────
                        PaywallTrustStripView()
                            .padding(.horizontal, hPad)

                        Color.clear.frame(height: 28)

                        // ── TESTIMONIALS ───────────────────────────────────
                        PaywallReviewCard()
                            .padding(.horizontal, hPad)

                        Color.clear.frame(height: 16)

                        // ── FOOTER ─────────────────────────────────────────
                        PaywallFooterLinks(onRestore: handleRestore)

                        Color.clear.frame(height: 32)
                    }
                    .frame(width: geo.size.width)
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

    // MARK: - Backdrop

    private var paywallHalo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentGlow.opacity(0.45),
                            CooksyTheme.primaryAccentGlow.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 320
                    )
                )
                .frame(width: 600, height: 600)
                .offset(y: -260)
                .blur(radius: 12)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.warmCard.opacity(0.55),
                            CooksyTheme.warmCard.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 540, height: 540)
                .offset(x: 80, y: 340)
                .blur(radius: 20)
        }
    }

    // MARK: - Sticky chrome

    @ViewBuilder
    private var stickyCloseButton: some View {
        if allowsFreeModeDismiss {
            Button(action: handleFreeModeDismiss) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(.black.opacity(0.05))
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

// MARK: - Logo mark

private struct PaywallLogoMark: View {
    var body: some View {
        ZStack {
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
                .frame(width: 140, height: 140)
                .blur(radius: 8)

            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 92, height: 92)
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 18, y: 10)
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.18), radius: 22, y: 0)

            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)
        }
    }
}

// MARK: - Headline

private struct PaywallHeadline: View {
    let showGiftBadge: Bool
    let giftDiscountPercent: Int?
    let onOpenGift: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if showGiftBadge {
                Button(action: onOpenGift) {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(giftDiscountPercent.map { "CADEAU −\($0) %" } ?? "CADEAU ACTIF")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                    }
                    .foregroundStyle(CooksyTheme.heroDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CooksyTheme.goldShimmer))
                }
                .buttonStyle(CooksyTheme.pressScale())
            }

            Text("Cooksy Premium")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)

            Text("Toutes tes vidéos transformées en recettes,\nprêtes à cuisiner — sans limite.")
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Award badge

/// "App de l'année 2025" laurel — replicates the visual cue from the
/// RevenueCat template. Drawn entirely in SwiftUI (no bitmaps).
private struct PaywallAwardBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            LaurelBranch(flipped: false)

            VStack(spacing: 1) {
                Text("THE COOKSY")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("App de l'année")
                    .font(.system(size: 13.5, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("FOOD · 2025")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            LaurelBranch(flipped: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct LaurelBranch: View {
    let flipped: Bool

    var body: some View {
        ZStack {
            // Main stem.
            Path { p in
                p.move(to: CGPoint(x: 4, y: 38))
                p.addCurve(
                    to: CGPoint(x: 22, y: 4),
                    control1: CGPoint(x: 0, y: 26),
                    control2: CGPoint(x: 10, y: 10)
                )
            }
            .stroke(
                CooksyTheme.primaryAccentStrong.opacity(0.75),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )

            // Leaves — 5 ellipses staggered along the stem.
            ForEach(0..<5, id: \.self) { i in
                let t = CGFloat(i) / 4
                let x: CGFloat = 4 + (1 - t) * 4 + t * 20
                let y: CGFloat = 38 - t * 30
                Ellipse()
                    .fill(CooksyTheme.primaryAccentStrong.opacity(0.78))
                    .frame(width: 9, height: 4)
                    .rotationEffect(.degrees(Double(-60 + i * 12)))
                    .offset(x: x - 10, y: y - 20)

                Ellipse()
                    .fill(CooksyTheme.primaryAccentStrong.opacity(0.78))
                    .frame(width: 9, height: 4)
                    .rotationEffect(.degrees(Double(60 - i * 12)))
                    .offset(x: x - 2, y: y - 20)
            }
        }
        .frame(width: 30, height: 42)
        .scaleEffect(x: flipped ? -1 : 1)
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

/// Auto-rotating testimonial carousel. Reviews advance every 4 s on
/// their own, and the user can swipe left/right to jump manually — the
/// auto-rotation timer pauses briefly after each interaction so the
/// carousel doesn't fight against the user's intent.
private struct PaywallReviewCard: View {
    private static let reviews: [PaywallReview] = [
        PaywallReview(
            title: "Recette parfaite à chaque fois",
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
            quote: "« Les quantités sont justes, les ingrédients pas génériques. Du vrai cooking, pas du blabla. Cooksy a remplacé mes captures d'écran. »",
            authorInitial: "T",
            authorName: "Thomas · Marseille",
            avatarColors: [Color(hex: 0xFFB35A), Color(hex: 0xB3441C)]
        )
    ]

    @State private var index: Int = 0
    /// Bumped on every user swipe so the auto-rotation pauses briefly
    /// before resuming — feels less like a fight against the user.
    @State private var pauseToken: Int = 0
    private let rotationInterval: TimeInterval = 4.0
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(Self.reviews.enumerated()), id: \.element.id) { i, review in
                    reviewCard(review)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 4)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 158)
            .onChange(of: index) { _, _ in
                // User (or timer) advanced the carousel. Reset the pause
                // window — the next auto-tick will respect it.
                pauseToken &+= 1
            }
            .onReceive(timer) { _ in
                // Drop ticks that arrive within ~1 s of a user swipe so
                // the carousel never feels jumpy right after an
                // interaction.
                let token = pauseToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard token == pauseToken else { return }
                    advance()
                }
            }

            // Page dots — tap to jump to a specific review.
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
    }

    private func advance() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            index = (index + 1) % Self.reviews.count
        }
    }

    private func reviewCard(_ review: PaywallReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentGlow)
                    }
                }
                Text(review.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }

            Text(review.quote)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.88))
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: review.avatarColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(review.authorInitial)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
                Text(review.authorName)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Spacer(minLength: 0)
                Text("App Store")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 18, y: 8)
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

// MARK: - Plan row (2 cards, side-by-side)

private struct PaywallPlanRow: View {
    @Binding var selectedPlan: PremiumPlan
    let trialDays: Int
    let trialEligible: Bool
    let giftActive: Bool
    let giftDiscountPercent: Int?
    @Binding var confettiTrigger: Int

    var body: some View {
        HStack(spacing: 12) {
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
        let showsTrial = plan.hasFreeTrial && trialEligible
        let perMonth = plan.liveOrFallbackMonthlyEquivalent(discountPercent: effectiveDiscount)

        let bigUnit: String = plan == .monthly ? "1" : "12"
        let unitWord: String = plan == .monthly ? "MOIS" : "MOIS"
        let footnote: String = {
            if plan == .yearly {
                if let perMonth { return "soit \(perMonth)/mois" }
                return "−58 % vs mensuel"
            } else {
                return "Sans engagement"
            }
        }()

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                // Top: optional trial / best-value badge.
                if plan == .yearly {
                    HStack(spacing: 4) {
                        if showsTrial {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(trialDays) J. GRATUITS")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.6)
                        } else {
                            Text("ÉCONOMISEZ 58 %")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.6)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : CooksyTheme.primaryAccentStrong)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            isSelected
                            ? AnyShapeStyle(Color.white.opacity(0.22))
                            : AnyShapeStyle(CooksyTheme.primaryAccentSoft)
                        )
                    )
                    .padding(.top, 2)
                } else {
                    Color.clear.frame(height: 18)
                }

                // Big number.
                Text(bigUnit)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unitWord)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : CooksyTheme.secondaryText)
                    .padding(.top, -6)

                Rectangle()
                    .fill(isSelected ? Color.white.opacity(0.25) : CooksyTheme.stroke)
                    .frame(height: 0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)

                // Price block.
                VStack(spacing: 1) {
                    if let originalPriceText {
                        Text(originalPriceText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : CooksyTheme.secondaryText)
                            .strikethrough()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(priceText)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(plan.unitLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : CooksyTheme.secondaryText)
                }

                Text(footnote)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : CooksyTheme.primaryAccentStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(CooksyTheme.accentGradient) : AnyShapeStyle(Color.white))
                    if !isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        CooksyTheme.primaryAccentSoft.opacity(0.22),
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? AnyShapeStyle(Color.white.opacity(0.35))
                        : AnyShapeStyle(CooksyTheme.stroke),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.32) : Color.black.opacity(0.05),
                radius: isSelected ? 22 : 10,
                y: isSelected ? 12 : 4
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)

            // Check disc top-right (matches the RC template).
            if isSelected {
                ZStack {
                    Circle().fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                }
                .offset(x: -8, y: 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(priceText)\(plan.unitLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
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
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.42), radius: 18, y: 10)
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

        if selectedPlan == .yearly && trialAvailable {
            let trialPart = Text("Essai \(trialDays) jours gratuit")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(CooksyTheme.primaryAccentStrong)
            let billedPart = Text("  ·  puis \(billed)\(unit)")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(CooksyTheme.secondaryText)
            return trialPart + billedPart
        }
        return Text("Facturé \(billed)\(unit) · sans engagement")
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(CooksyTheme.secondaryText)
    }
}

// MARK: - Footer links

private struct PaywallFooterLinks: View {
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 18) {
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
