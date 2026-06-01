import SwiftUI
import RevenueCat

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
    /// Active −X % gift discount, when applicable. Threaded into the
    /// plans sheet and the disclaimer so the displayed price always
    /// matches what Apple will actually charge.
    private var effectiveGiftDiscount: Int? {
        guard offers.giftOfferIsActive,
              PremiumPlan.yearly.supportsPromotionalDiscount else { return nil }
        return offers.giftDiscountPercent
    }
    /// The trial timeline + "semaine GRATUITE" copy only show when the
    /// user is actually getting a trial. When a gift is active the
    /// purchase path is `purchaseAnnualWithPromo` (pay-up-front, no
    /// trial), so the whole trial mode is suppressed.
    private var trialShown: Bool {
        trialEligible
        && selectedPlan == .yearly
        && effectiveGiftDiscount == nil
    }

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
                giftDiscountPercent: effectiveGiftDiscount,
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
            PaywallReassuranceLine(
                plan: selectedPlan,
                trialEligible: trialEligible,
                giftDiscountPercent: effectiveGiftDiscount
            )

            PaywallPrimaryCTAButton(
                title: PaywallCopy.ctaTitle(
                    plan: selectedPlan,
                    trialEligible: trialEligible,
                    giftDiscountPercent: effectiveGiftDiscount
                ),
                isLoading: isPurchasing,
                action: handlePurchase
            )

            PaywallDisclaimerText(
                plan: selectedPlan,
                trialDays: trialDays,
                trialEligible: trialEligible,
                giftDiscountPercent: effectiveGiftDiscount
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
        // App Store Guideline 5.6 — Developer Code of Conduct:
        // surfacing a "last-chance" wheel immediately after the user
        // closed the paywall is treated as manipulation and gets the
        // build rejected. The gift remains discoverable through the
        // Home top-bar pill (via the standard `shouldShowGiftPill`
        // path) on the user's own initiative, which is compliant.
        //
        // We still flip `hasTriggeredExitIntent` so any callers that
        // gate copy on "user has already tried to dismiss once" keep
        // working — they just don't trigger an interstitial anymore.
        hasTriggeredExitIntent = true
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
            // Resilient offering fetch — App Review (Guideline 2.1(b))
            // expects the purchase flow to function even when the
            // storefront is slow to respond. Try up to 3 times with
            // increasing back-off before surfacing an error.
            if PurchaseService.shared.currentOffering == nil {
                for attempt in 0..<3 {
                    await PurchaseService.shared.fetchOfferings()
                    if PurchaseService.shared.currentOffering != nil { break }
                    let delay = UInt64(400_000_000) * UInt64(attempt + 1)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            do {
                let outcome: PurchaseService.PurchaseOutcome
                if plan == .yearly, giftActive, let percent = giftPercent {
                    outcome = try await PurchaseService.shared.purchaseAnnualWithPromo(
                        offerIdentifier: "GIFT\(percent)"
                    )
                } else {
                    outcome = try await PurchaseService.shared.purchase(plan: plan)
                }

                // Cancellation MUST NOT grant premium. RC silently returns
                // on `result.userCancelled = true`, so without this guard
                // the old code marked the user premium for free every time
                // they closed the StoreKit sheet.
                guard outcome == .success else {
                    await MainActor.run { isPurchasing = false }
                    return
                }

                // StoreKit accepted the transaction — Apple WILL bill the
                // user. `purchase()` has already set `PurchaseService.isPremium`
                // optimistically and kicked off a background poll for the
                // RC entitlement, so we don't gate on a second confirmation
                // here (that turned sandbox propagation lag into a fake
                // "error" alert + force-quit-to-relaunch UX). The SessionStore
                // grace window protects the optimistic flag until the
                // backend webhook lands.
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
    ///
    /// IMPORTANT (App Review): never mention "sandbox" or any internal
    /// store mode in user-facing copy — Apple's reviewers landed on
    /// that string in the previous submission and treated it as a
    /// broken purchase flow (Guideline 2.1(b) — App Completeness).
    /// Stay in plain user language and offer a retry.
    ///
    /// We dispatch on RC's `ErrorCode` enum first (most reliable signal:
    /// "card declined", "Ask to Buy pending", "purchase not allowed"
    /// each have a distinct code) and only fall back to substring
    /// matching when the error didn't come from RC.
    private func friendlyPurchaseErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let code = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch code {
            case .purchaseCancelledError:
                return "Achat annulé. Tu peux réessayer quand tu veux."
            case .paymentPendingError:
                return "Ton achat est en attente d'approbation (contrôle parental ou validation bancaire). Une fois approuvé, ton abonnement Premium s'activera automatiquement."
            case .purchaseNotAllowedError:
                return "Les achats sont désactivés sur cet appareil. Va dans Réglages > Temps d'écran > Restrictions pour les autoriser, puis réessaie."
            case .purchaseInvalidError:
                return "Ton moyen de paiement a été refusé. Vérifie ta carte dans Réglages > Apple ID > Paiement, puis réessaie."
            case .productNotAvailableForPurchaseError, .productAlreadyPurchasedError:
                return "Ce forfait n'est pas disponible pour le moment. Réessaie dans un instant."
            case .receiptAlreadyInUseError, .receiptInUseByOtherSubscriberError:
                return "Cet abonnement est déjà associé à un autre compte Apple. Connecte-toi avec l'Apple ID utilisé pour l'achat."
            case .networkError:
                return "Connexion internet instable. Vérifie ta connexion puis réessaie."
            case .storeProblemError:
                return "L'App Store rencontre un problème temporaire. Réessaie dans quelques minutes."
            case .invalidReceiptError, .missingReceiptFileError:
                return "Impossible de valider l'achat. Réessaie dans un instant — aucune somme ne sera prélevée tant que la validation n'a pas abouti."
            case .ineligibleError:
                return "Tu n'es pas éligible à cette offre. Choisis un autre forfait pour continuer."
            case .invalidCredentialsError, .invalidAppUserIdError:
                return "Ta session a expiré. Reconnecte-toi puis réessaie l'achat."
            default:
                break
            }
        }

        // Non-RC error (or a code we didn't enumerate above) — fall
        // back to substring matching on the localizedDescription so we
        // still surface something more useful than the raw debug string.
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("cancel") || lower.contains("annul") {
            return "Achat annulé. Tu peux réessayer quand tu veux."
        }
        if lower.contains("network") || lower.contains("réseau")
            || lower.contains("internet") || lower.contains("connexion") {
            return "Connexion internet instable. Vérifie ta connexion puis réessaie."
        }
        if lower.contains("offre") || lower.contains("offering")
            || lower.contains("package") || lower.contains("product") {
            return "Les abonnements ne sont pas disponibles pour le moment. Patiente quelques secondes et réessaie."
        }
        if lower.contains("payment") || lower.contains("paiement")
            || lower.contains("declined") || lower.contains("refus") {
            return "Ton moyen de paiement a été refusé. Vérifie ta carte dans Réglages > Apple ID > Paiement, puis réessaie."
        }
        return "Une erreur est survenue. Réessaie dans quelques instants."
    }

    private func handleRestore() {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            do {
                let restored = try await PurchaseService.shared.restorePurchases()
                if restored {
                    await sessionStore.setPremium(true)
                } else {
                    purchaseError = "Aucun abonnement actif trouvé sur ce compte Apple."
                }
            } catch {
                purchaseError = friendlyPurchaseErrorMessage(error)
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
