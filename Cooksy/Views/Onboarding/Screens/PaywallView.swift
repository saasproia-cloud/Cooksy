import SwiftUI

/// E1 — Hard paywall gate shown once after sign-up.
///
/// Design copied from the ReciMe-style trial paywall:
/// hero headline with orange accent, 3-step "Comment fonctionne ton
/// essai gratuit" timeline, social-proof row, horizontally scrolling
/// testimonials, single dominant CTA, and a "Voir tous les forfaits"
/// sheet for users who want the monthly option.
struct PaywallView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var selectedPlan: PremiumPlan = .yearly
    @State private var isActivating: Bool = false
    @State private var showsPlansSheet: Bool = false
    @State private var showsTermsSheet: Bool = false
    @State private var showsPrivacySheet: Bool = false

    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }
    private var trialEligible: Bool { purchaseService.isAnnualTrialEligible }
    private var trialShown: Bool { trialEligible && selectedPlan == .yearly }
    /// `true` once RC's storefront has been fetched. Gates the CTA so
    /// Apple's reviewer can never tap an "Abonne-toi" button that
    /// errors with "Les abonnements ne sont pas disponibles".
    private var offeringsReady: Bool { purchaseService.currentOffering != nil }

    var body: some View {
        GeometryReader { geo in
            let hPad = Layout.horizontalPadding(for: geo)

            ZStack {
                CooksyTheme.background
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        Spacer().frame(height: 32)

                        PaywallHeroHeadline()
                            .padding(.horizontal, 8)

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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(hPad: hPad)
            }
        }
        .sheet(isPresented: $showsPlansSheet) {
            PaywallPlansSheet(
                selectedPlan: $selectedPlan,
                trialDays: trialDays,
                trialEligible: trialEligible,
                isPurchasing: isActivating,
                onConfirm: {
                    showsPlansSheet = false
                    activate()
                },
                onClose: { showsPlansSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showsTermsSheet) {
            NavigationStack { TermsOfServiceView() }
        }
        .sheet(isPresented: $showsPrivacySheet) {
            NavigationStack { PrivacyPolicyView() }
        }
        .onAppear {
            // Apple Review (Guideline 2.1(b)): the storefront MUST be
            // ready by the time the reviewer taps the CTA. Hammer the
            // fetch on appear with retries so a slow first response
            // doesn't produce a user-facing error.
            Task {
                for attempt in 0..<6 {
                    if PurchaseService.shared.currentOffering != nil { break }
                    await PurchaseService.shared.fetchOfferings()
                    if PurchaseService.shared.currentOffering != nil { break }
                    let delay = UInt64(500_000_000) * UInt64(attempt + 1)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    // MARK: - Bottom bar

    private func bottomBar(hPad: CGFloat) -> some View {
        VStack(spacing: 12) {
            PaywallReassuranceLine(plan: selectedPlan, trialEligible: trialEligible)

            PaywallPrimaryCTAButton(
                title: offeringsReady
                    ? PaywallCopy.ctaTitle(plan: selectedPlan, trialEligible: trialEligible)
                    : "Chargement…",
                isLoading: isActivating || !offeringsReady,
                action: activate
            )
            .disabled(!offeringsReady)

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

                Button("Restaurer") {
                    Task {
                        // Restore is read-only — it can never grant
                        // premium unless RC reports an actually-active
                        // entitlement on the restored CustomerInfo.
                        let restored = (try? await PurchaseService.shared.restorePurchases()) ?? false
                        if restored {
                            await sessionStore.setPremium(true)
                        }
                    }
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)

                Button("Conditions") { showsTermsSheet = true }
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

    // MARK: - Purchase

    private func activate() {
        guard !isActivating else { return }
        // CRITICAL: never proceed without offerings — the CTA is
        // disabled while loading but this is a defensive backstop.
        guard offeringsReady else { return }
        isActivating = true
        OnboardingHaptics.success()
        Task {
            do {
                let outcome = try await PurchaseService.shared.purchase(plan: selectedPlan)
                // Cancellation is a no-op (user stays on the onboarding
                // paywall). On `.success` we trust StoreKit — Apple has
                // accepted the transaction, PurchaseService has flipped
                // the optimistic flag, and SessionStore's grace window
                // covers the RC propagation lag.
                if outcome == .success {
                    await sessionStore.setPremium(true)
                    if PurchaseService.shared.isInTrial {
                        PurchaseService.shared.recordTrialStarted()
                    }
                }
            } catch {
                // Network / package errors → leave the user on the
                // paywall, no premium granted. The StoreKit sheet
                // surfaces the failure to the user already.
            }
            await MainActor.run { isActivating = false }
        }
    }
}
