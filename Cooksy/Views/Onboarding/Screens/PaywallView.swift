import SwiftUI

/// E1 — Hard paywall gate. Shown once the user is authenticated and their
/// onboarding answers are stored, if `profile.isPremium == false`.
/// No close button, no "skip" path — the only way out is to tap the CTA.
/// StoreKit is NOT wired in this version: the CTA just flips `isPremium`
/// locally + in Supabase via `SessionStore.setPremiumMock`.
struct PaywallView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var trialEnabled: Bool = true
    @State private var appeared: Bool = false
    @State private var isActivating: Bool = false

    /// Real trial duration from the storefront (default 7 if not loaded).
    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }
    /// Whether Apple still allows the trial for this Apple ID.
    private var trialEligible: Bool { purchaseService.isAnnualTrialEligible }
    /// Resolved trial state shown in the UI.
    private var trialShown: Bool { trialEnabled && trialEligible && selectedPlan == .annual }

    var body: some View {
        ZStack {
            // Layered background: glow gradient + drifting sparkles.
            CooksyTheme.heroGlowGradient
                .ignoresSafeArea()

            SparkleCanvas(count: 34, baseColor: CooksyTheme.sparkleYellow)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                            .padding(.top, 20)

                        featureList

                        planStack
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }
        }
        .onAppear {
            appeared = false
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                await MainActor.run { appeared = true }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 72, height: 72)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: appeared)

            VStack(spacing: 8) {
                Text("Débloque tout Cooksy")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(trialEligible
                     ? "\(trialDays) jours d'essai gratuit, puis le plan qui te convient. Annulable à tout moment."
                     : "Choisis ton plan. Annulable à tout moment.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.1), value: appeared)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(Array(PaywallFeature.all.enumerated()), id: \.offset) { index, feature in
                FeatureRow(feature: feature, index: index, appeared: appeared)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.heroRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.heroRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
    }

    // MARK: - Plans

    private var planStack: some View {
        VStack(spacing: 10) {
            ForEach(PaywallPlan.allCases) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: selectedPlan == plan
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedPlan = plan
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.4), value: appeared)
    }

    // MARK: - Bottom CTA

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if trialEligible && selectedPlan == .annual {
                Toggle(isOn: $trialEnabled) {
                    Text(trialEnabled
                         ? "Essai gratuit \(trialDays) jours activé"
                         : "Essai gratuit désactivé")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .tint(CooksyTheme.ctaOrange)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.elevatedSurface.opacity(0.85))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
            }

            Button(action: activate) {
                HStack(spacing: 8) {
                    if isActivating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isActivating ? "Activation…" : ctaTitle)
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
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 8)
                .shimmer(period: 3)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(isActivating)

            Text(trialShown
                 ? "Pas de paiement aujourd'hui. \(selectedPlan.livePrice)\(selectedPlan.cadence) après l'essai. Annulable depuis Réglages > Apple ID."
                 : "Facturation immédiate de \(selectedPlan.livePrice)\(selectedPlan.cadence). Annulable à tout moment.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 16) {
                PaywallFooterLink(title: "Restaurer") {
                    Task {
                        try? await PurchaseService.shared.restorePurchases()
                        if PurchaseService.shared.isPremium {
                            await sessionStore.setPremium(true)
                        }
                    }
                }
                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)
                PaywallFooterLink(title: "Conditions") { }
                Circle().fill(CooksyTheme.dividerSubtle).frame(width: 3, height: 3)
                PaywallFooterLink(title: "Confidentialité") { }
            }
            .padding(.top, 2)
        }
    }

    private var ctaTitle: String {
        trialShown
            ? "Commencer mes \(trialDays) jours gratuits"
            : "Continuer avec \(selectedPlan.shortName)"
    }

    private func activate() {
        isActivating = true
        OnboardingHaptics.success()
        Task {
            do {
                let rcPlan: PremiumPlan = selectedPlan == .annual ? .yearly : .monthly
                try await PurchaseService.shared.purchase(plan: rcPlan)
                if PurchaseService.shared.isPremium {
                    await sessionStore.setPremium(true)
                }
            } catch {
                // User cancelled → silently ignore.
            }
            await MainActor.run { isActivating = false }
        }
    }
}

// MARK: - Plan model

enum PaywallPlan: String, CaseIterable, Identifiable {
    case weekly
    case annual
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:   return "Hebdo"
        case .annual:   return "Annuel"
        case .lifetime: return "À vie"
        }
    }

    var shortName: String {
        switch self {
        case .weekly:   return "l'abo hebdo"
        case .annual:   return "l'abo annuel"
        case .lifetime: return "l'accès à vie"
        }
    }

    var price: String {
        switch self {
        case .weekly:   return "4,99 €"
        case .annual:   return "39,99 €"
        case .lifetime: return "89,99 €"
        }
    }

    /// Price string sourced from RevenueCat when available so what we
    /// show always matches what Apple is going to bill. Falls back to
    /// the hardcoded marketing price only during a cold start (no
    /// network, offering not yet fetched).
    @MainActor
    var livePrice: String {
        switch self {
        case .weekly:   return PurchaseService.shared.monthlyPriceString ?? price
        case .annual:   return PurchaseService.shared.annualPriceString ?? price
        case .lifetime: return price
        }
    }

    var cadence: String {
        switch self {
        case .weekly:   return "/ semaine"
        case .annual:   return "/ an"
        case .lifetime: return "une fois"
        }
    }

    var bottomLine: String {
        switch self {
        case .weekly:   return "Flexible, tu stoppes quand tu veux"
        case .annual:   return "Le meilleur rapport qualité / prix"
        case .lifetime: return "Un paiement, pour toujours"
        }
    }

    var badge: String? {
        switch self {
        case .annual: return "POPULAIRE · -85%"
        default:      return nil
        }
    }
}

// MARK: - Plan card

private struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            OnboardingHaptics.selection()
            action()
        }) {
            HStack(alignment: .center, spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(CooksyTheme.accentGradient)
                            .frame(width: 12, height: 12)
                            .transition(.scale)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .tracking(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CooksyTheme.accentGradient)
                                )
                        }
                    }
                    Text(plan.bottomLine)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.livePrice)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(plan.cadence)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.55) : CooksyTheme.elevatedSurface.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.28) : CooksyTheme.softShadow,
                radius: isSelected ? 14 : 6, y: 4
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }
}

// MARK: - Features

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String

    static let all: [PaywallFeature] = [
        .init(systemImage: "infinity", title: "Imports illimités depuis TikTok, Insta, YouTube"),
        .init(systemImage: "wand.and.stars", title: "IA avancée : structure, sections, nutrition"),
        .init(systemImage: "calendar", title: "Plan de repas hebdo + liste de courses auto"),
        .init(systemImage: "flame", title: "Recettes tendance en avant-première"),
        .init(systemImage: "hand.raised", title: "Sans publicité, pour toujours"),
        .init(systemImage: "bolt.heart", title: "Support prioritaire")
    ]
}

private struct FeatureRow: View {
    let feature: PaywallFeature
    let index: Int
    let appeared: Bool

    @State private var checkProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 26, height: 26)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.3), radius: 4, y: 2)

                AnimatedCheckmark(progress: checkProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 10)
            }

            HStack(spacing: 8) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .frame(width: 20)

                Text(feature.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -10)
        .animation(
            .spring(response: 0.55, dampingFraction: 0.85).delay(0.2 + Double(index) * 0.08),
            value: appeared
        )
        .onChange(of: appeared) { _, newValue in
            guard newValue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.08) {
                withAnimation(.easeOut(duration: 0.35)) {
                    checkProgress = 1
                }
            }
        }
    }
}

// MARK: - Footer links

private struct PaywallFooterLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }
}
