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
    }

    // MARK: - Bottom bar

    private func bottomBar(hPad: CGFloat) -> some View {
        VStack(spacing: 12) {
            PaywallReassuranceLine(plan: selectedPlan, trialEligible: trialEligible)

            PaywallPrimaryCTAButton(
                title: PaywallCopy.ctaTitle(plan: selectedPlan, trialEligible: trialEligible),
                isLoading: isActivating,
                action: activate
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

                Button("Restaurer") {
                    Task {
                        try? await PurchaseService.shared.restorePurchases()
                        if PurchaseService.shared.isPremium {
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
        isActivating = true
        OnboardingHaptics.success()
        Task {
            do {
                try await PurchaseService.shared.purchase(plan: selectedPlan)
                await PurchaseService.shared.forcePremiumAfterPurchase()
                await sessionStore.setPremium(true)
                if PurchaseService.shared.isInTrial {
                    PurchaseService.shared.recordTrialStarted()
                }
            } catch {
                // User cancelled → silently ignore.
            }
            await MainActor.run { isActivating = false }
        }
    }
}
