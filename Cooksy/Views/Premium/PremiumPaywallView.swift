import SwiftUI

/// Cooksy premium paywall — ReciMe-style trial flow.
///
/// Layout: hero headline → optional gift banner/strip → 3-step trial
/// timeline (only when annual+trial eligible) → social proof → testimonial
/// carousel → bottom-anchored CTA bar with "Voir tous les forfaits" sheet.
///
/// All purchase / gift-wheel / exit-intent / restore wiring is preserved
/// 1:1 from the previous version. The card-picker UI moved into a
/// presentation sheet (`PaywallPlansSheet`) so the main screen can stay
/// focused on the headline → trial → CTA conversion path.
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
    @State private var showsPlansSheet: Bool = false
    @State private var giftReminderDismissed: Bool = false
    @State private var confettiTrigger: Int = 0
    @State private var hasTriggeredExitIntent: Bool = false
    @State private var showsTermsSheet: Bool = false
    @State private var showsPrivacySheet: Bool = false

    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }
    private var trialEligible: Bool { purchaseService.isAnnualTrialEligible }
    private var trialShown: Bool { trialEligible && selectedPlan == .yearly }

    var body: some View {
        GeometryReader { geo in
            let hPad = Layout.horizontalPadding(for: geo)

            ZStack {
                CooksyTheme.background
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        Spacer().frame(height: 44)

                        PaywallHeroHeadline()
                            .padding(.horizontal, 8)

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

                        if trialShown {
                            PaywallTrialTimeline(trialDays: trialDays)
                                .padding(.top, 6)
                        }

                        PaywallSocialProofRow()
                            .padding(.top, trialShown ? 4 : 12)

                        PaywallTestimonialsScroll()
                            .padding(.horizontal, -hPad)
                            .padding(.leading, hPad)

                        Spacer().frame(height: 8)
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, hPad)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar(hPad: hPad)
                }

                if allowsFreeModeDismiss {
                    stickyCloseButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                }

                IngredientConfetti(trigger: confettiTrigger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
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
            Task { await PurchaseService.shared.fetchOfferings() }
        }
        .sheet(isPresented: $showsPlansSheet) {
            PaywallPlansSheet(
                selectedPlan: $selectedPlan,
                trialDays: trialDays,
                trialEligible: trialEligible,
                isPurchasing: isPurchasing,
                onConfirm: {
                    showsPlansSheet = false
                    handlePurchase()
                },
                onClose: { showsPlansSheet = false }
            )
            .presentationDetents([.height(440)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showsTermsSheet) {
            NavigationStack { TermsOfServiceView() }
        }
        .sheet(isPresented: $showsPrivacySheet) {
            NavigationStack { PrivacyPolicyView() }
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

    // MARK: - Bottom bar

    private func bottomBar(hPad: CGFloat) -> some View {
        VStack(spacing: 12) {
            PaywallReassuranceLine(plan: selectedPlan, trialEligible: trialEligible)

            PaywallPrimaryCTAButton(
                title: PaywallCopy.ctaTitle(plan: selectedPlan, trialEligible: trialEligible),
                isLoading: isPurchasing,
                action: handlePurchase
            )

            PaywallDisclaimerText(
                plan: selectedPlan,
                trialDays: trialDays,
                trialEligible: trialEligible
            )

            HStack(spacing: 14) {
                Button("Voir tous les forfaits") {
                    OnboardingHaptics.selection()
                    showsPlansSheet = true
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .underline()

                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)

                Button("Restaurer", action: handleRestore)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)

                Button("Conditions") { showsTermsSheet = true }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)

                Button("Confidentialité") { showsPrivacySheet = true }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, hPad)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [
                    CooksyTheme.background.opacity(0),
                    CooksyTheme.background.opacity(0.85),
                    CooksyTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Close button

    @ViewBuilder
    private var stickyCloseButton: some View {
        if allowsFreeModeDismiss {
            Button(action: handleFreeModeDismiss) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.95))
                    Circle().stroke(CooksyTheme.stroke.opacity(0.9), lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .frame(width: 38, height: 38)
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                .contentShape(Circle())
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer et rester en gratuit")
        }
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
            if PurchaseService.shared.currentOffering == nil {
                await PurchaseService.shared.fetchOfferings()
            }

            do {
                if plan == .yearly, giftActive, let percent = giftPercent {
                    try await PurchaseService.shared.purchaseAnnualWithPromo(
                        offerIdentifier: "GIFT\(percent)"
                    )
                } else {
                    try await PurchaseService.shared.purchase(plan: plan)
                }

                await PurchaseService.shared.forcePremiumAfterPurchase()
                await sessionStore.setPremium(true)
                let inTrial = PurchaseService.shared.isInTrial

                if inTrial {
                    PurchaseService.shared.recordTrialStarted()
                }

                await MainActor.run {
                    offers.recordPurchaseCompleted(plan: plan, inTrial: inTrial)
                    offers.clearFreeModeChoice()
                    isPurchasing = false
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseError = friendlyPurchaseErrorMessage(error)
                }
            }
        }
    }

    /// Translates RevenueCat/StoreKit failures into actionable copy.
    private func friendlyPurchaseErrorMessage(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("offre")
            || raw.localizedCaseInsensitiveContains("offering")
            || raw.localizedCaseInsensitiveContains("package") {
            return "Les offres n'ont pas pu être chargées. Vérifie ta connexion, puis réessaie. Si le problème persiste, déconnecte-toi de l'App Store puis reconnecte-toi avec ton compte sandbox."
        }
        return raw
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
