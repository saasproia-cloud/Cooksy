import SwiftUI

/// E1 — Hard paywall gate. Shown once the user is authenticated and their
/// onboarding answers are stored, if `profile.isPremium == false`.
/// Design mirrors the RevenueCat "modern app" paywall template: a large
/// rounded app icon, bold serif title, short subtitle, award badge,
/// testimonial card, three horizontal price tiles with the recommended
/// one visually highlighted, full-width CTA, and a discreet legal footer.
struct PaywallView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var appeared: Bool = false
    @State private var isActivating: Bool = false

    private var trialDays: Int { purchaseService.annualTrialDays ?? 7 }
    private var trialEligible: Bool { purchaseService.isAnnualTrialEligible }
    private var trialShown: Bool { trialEligible && selectedPlan == .annual }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CooksyTheme.ambientGradient
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        headerBlock
                            .padding(.top, 14)

                        awardBadge

                        reviewCard

                        planRow
                            .padding(.top, 4)

                        ctaBlock
                            .padding(.top, 2)

                        legalFooter
                            .padding(.bottom, 18)
                    }
                    .frame(maxWidth: Layout.maxContentWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Layout.horizontalPadding(for: geo))
                    .padding(.top, 8)
                }
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

    private var headerBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 104, height: 104)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 22, y: 12)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75), value: appeared)

            VStack(spacing: 8) {
                Text("Débloque Cooksy Premium")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)

                Text(trialEligible
                     ? "Transforme chaque vidéo en recette claire. \(trialDays) jours gratuits, sans engagement."
                     : "Transforme chaque vidéo en recette claire. Annulable à tout moment.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.1), value: appeared)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Award badge (replaces "App of the Year")

    private var awardBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(CooksyTheme.primaryAccentStrong.opacity(0.85))

            VStack(spacing: 1) {
                Text("Sélection App Store")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Cuisine · 2026")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Image(systemName: "laurel.trailing")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(CooksyTheme.primaryAccentStrong.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
    }

    // MARK: - Review card

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Mon nouveau réflexe en cuisine")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }

            Text("« Je colle le lien d'un Reel, j'ai la recette en clair en 5 secondes. Plus jamais à mettre pause pour noter. »")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("— Léa · cuisine du soir")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.softShadow, radius: 14, y: 6)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.28), value: appeared)
    }

    // MARK: - Plan row (3 horizontal tiles, middle highlighted)

    private var planRow: some View {
        HStack(spacing: 10) {
            ForEach(PaywallPlan.allCases) { plan in
                PaywallPlanTile(
                    plan: plan,
                    isSelected: selectedPlan == plan,
                    showTrialChip: plan == .annual && trialShown,
                    trialDays: trialDays
                ) {
                    OnboardingHaptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedPlan = plan
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.38), value: appeared)
    }

    // MARK: - CTA + disclaimer

    private var ctaBlock: some View {
        VStack(spacing: 10) {
            Button(action: activate) {
                HStack(spacing: 8) {
                    if isActivating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isActivating ? "Activation…" : ctaTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.42), radius: 18, y: 10)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(isActivating)

            Text(disclaimer)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.46), value: appeared)
    }

    private var disclaimer: String {
        if trialShown {
            return "Aucun paiement aujourd'hui. \(selectedPlan.livePrice)\(selectedPlan.cadence) après l'essai. Annulable depuis Réglages."
        }
        return "\(selectedPlan.livePrice)\(selectedPlan.cadence). Annulable à tout moment."
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        HStack(spacing: 18) {
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
        .frame(maxWidth: .infinity)
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

    /// Big number shown on the tile (no currency).
    var headlineAmount: String {
        switch self {
        case .weekly:   return "7"
        case .annual:   return "12"
        case .lifetime: return "∞"
        }
    }

    /// Unit shown under the big amount.
    var headlineUnit: String {
        switch self {
        case .weekly:   return "JOURS"
        case .annual:   return "MOIS"
        case .lifetime: return "À VIE"
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
        case .weekly:   return " / semaine"
        case .annual:   return " / an"
        case .lifetime: return " une fois"
        }
    }
}

// MARK: - Plan tile

private struct PaywallPlanTile: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let showTrialChip: Bool
    let trialDays: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        Text(plan.headlineAmount)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text(plan.headlineUnit)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(isSelected ? .white.opacity(0.95) : CooksyTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .background(
                                Circle()
                                    .fill(CooksyTheme.primaryAccentStrong)
                                    .frame(width: 22, height: 22)
                            )
                            .frame(width: 22, height: 22)
                            .offset(x: -8, y: 8)
                    }
                }

                priceFooter
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                        ? AnyShapeStyle(CooksyTheme.accentGradient)
                        : AnyShapeStyle(CooksyTheme.elevatedSurface.opacity(0.96))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.0) : CooksyTheme.stroke.opacity(0.85),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.35) : CooksyTheme.softShadow,
                radius: isSelected ? 14 : 4,
                y: isSelected ? 8 : 2
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var priceFooter: some View {
        VStack(spacing: 1) {
            Text(plan.livePrice)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(footerSubtitle)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white.opacity(0.9) : CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var footerSubtitle: String {
        if showTrialChip {
            return "Essai \(trialDays) j"
        }
        switch plan {
        case .weekly:   return "/ semaine"
        case .annual:   return "/ an"
        case .lifetime: return "paiement unique"
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
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .buttonStyle(.plain)
    }
}
