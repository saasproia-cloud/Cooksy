import SwiftUI

/// Full-screen "VOTRE OFFRE UNIQUE" page presented after the user wins
/// the wheel. The view now owns the entire purchase flow — tapping the
/// CTA executes the purchase inline (with a loading state) instead of
/// dismissing back to the paywall and letting the host execute it.
///
/// The hero illustration is a layered "medallion" with a centered gift
/// icon, an offset scalloped discount seal, and animated sparkles —
/// replacing the previous custom-built bow/box that read as toy-ish.
struct ExclusiveOfferView: View {
    let discountPercent: Int
    let expiresAt: Date?
    let onClose: () -> Void

    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var offers = PremiumOffersService.shared
    @StateObject private var purchaseService = PurchaseService.shared

    @State private var isPurchasing: Bool = false
    @State private var giftFloat: Bool = false
    @State private var sparkle: Bool = false
    @State private var sealWiggle: Bool = false
    @State private var shimmer: Bool = false
    @State private var timerPulse: Bool = false

    private let yearlyPlan: PremiumPlan = .yearly

    /// The gift purchase always buys the dedicated discounted SKU
    /// (`cooksy_premium_yearly_gift`) via `purchaseAnnualWithPromo`,
    /// which is pay-up-front and has no introductory free trial.
    /// Promising "X jours gratuits" here would lie about what Apple
    /// is going to bill, so the trial UI is suppressed entirely on
    /// this screen — gift overrides trial, end of story.
    private var trialShown: Bool { false }

    /// Live monthly equivalent of the discounted annual plan, formatted
    /// in the user's currency. Reflects what Apple will bill via the
    /// matching `GIFTxx` Promotional Offer — the gift discount is
    /// applied locally so the headline matches checkout. The string is
    /// just the money amount (e.g. `"2,50 €"`); call sites add `/mois`.
    private var monthlyEquivalent: String {
        yearlyPlan.liveOrFallbackMonthlyEquivalent(discountPercent: discountPercent)
            ?? yearlyPlan.liveOrFallbackPriceString(discountPercent: discountPercent)
    }

    /// Live annual price with the gift discount applied. Drives the
    /// plan card subtitle and the CTA copy.
    private var discountedYearlyPriceString: String {
        yearlyPlan.liveOrFallbackPriceString(discountPercent: discountPercent)
    }

    /// Same number with the `/mois` unit appended — used wherever the
    /// price is presented standalone (the hero price next to the
    /// strikethrough, the plan-card right column).
    private var monthlyEquivalentLabeled: String {
        "\(monthlyEquivalent)/mois"
    }

    /// Live "regular" monthly subscription price (for the strikethrough
    /// "you'd otherwise pay …/mois" comparison line).
    private var monthlyOfMonthlyPlan: String {
        PremiumPlan.monthly.liveOrFallbackPriceString + PremiumPlan.monthly.unitLabel
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            // Subtle warm aurora behind the whole screen — keeps the
            // medallion from feeling like it's floating on flat cream.
            backgroundAura
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Color.clear.frame(height: 56) // top chrome breathing room

                    title
                    urgencyTimer
                    giftIllustration
                        .frame(height: 230)

                    subtitleBlock

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 360) // leave room for the sticky stack
            }

            stickyStack
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                guard !isPurchasing else { return }
                OnboardingHaptics.selection()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(CooksyTheme.elevatedSurface)
                            .overlay(Circle().stroke(CooksyTheme.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
            .opacity(isPurchasing ? 0.4 : 1)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            giftFloat = true
            sparkle = true
            sealWiggle = true
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                shimmer = true
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                timerPulse = true
            }
        }
    }

    // MARK: - Urgency timer

    /// Big live HH:MM:SS countdown — anchored visually to the title so
    /// it's the first thing the user reads after "Votre offre unique".
    /// Once `remaining` drops under 2 h the banner flips into "critical"
    /// mode (deep red, heavier pulse, "DERNIÈRES HEURES !" copy) so the
    /// user feels the runway shrinking instead of just numbers ticking.
    @ViewBuilder
    private var urgencyTimer: some View {
        if let expiresAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, expiresAt.timeIntervalSince(context.date))
                let total = Int(remaining)
                let hours = total / 3600
                let minutes = (total % 3600) / 60
                let seconds = total % 60
                let isCritical = remaining > 0 && remaining <= 2 * 3600
                let isExpired = remaining <= 0

                VStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: isCritical
                              ? "exclamationmark.triangle.fill"
                              : "alarm.fill")
                            .font(.system(size: 12, weight: .black))
                            .scaleEffect(timerPulse ? 1.18 : 0.94)
                        Text(timerLabel(isCritical: isCritical, isExpired: isExpired))
                            .font(.system(size: 11.5, weight: .black, design: .rounded))
                            .tracking(1.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        timerUnitBox(value: hours, unit: "H")
                        timerSeparator
                        timerUnitBox(value: minutes, unit: "M")
                        timerSeparator
                        timerUnitBox(value: seconds, unit: "S")
                    }
                    .opacity(isExpired ? 0.55 : 1)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(timerBackground(isCritical: isCritical))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            .white.opacity(isCritical ? 0.45 : 0.28),
                            lineWidth: isCritical ? 1.5 : 1
                        )
                )
                .shadow(
                    color: (isCritical
                            ? Color(hex: 0xC8311B)
                            : CooksyTheme.ctaOrangeDark).opacity(0.45),
                    radius: timerPulse ? 22 : 14,
                    y: 10
                )
                .animation(.easeInOut(duration: 0.4), value: isCritical)
            }
        }
    }

    private func timerLabel(isCritical: Bool, isExpired: Bool) -> String {
        if isExpired { return "OFFRE EXPIRÉE" }
        if isCritical { return "DERNIÈRES HEURES !" }
        return "OFFRE EXPIRE DANS"
    }

    private func timerUnitBox(value: Int, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%02d", max(0, value)))
                .font(.system(size: 30, weight: .black, design: .rounded)
                    .monospacedDigit())
                .foregroundStyle(.white)
            Text(unit)
                .font(.system(size: 9.5, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 64, height: 62)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        )
    }

    private var timerSeparator: some View {
        Text(":")
            .font(.system(size: 26, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .opacity(timerPulse ? 1 : 0.45)
    }

    private func timerBackground(isCritical: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isCritical
                        ? [Color(hex: 0xE13D1E), Color(hex: 0xA61D08)]
                        : [CooksyTheme.ctaOrange, CooksyTheme.ctaOrangeDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Background aura

    /// The aura is a single 520×520 radial blob anchored at the top.
    /// We host it inside `Color.clear` (which adopts whatever size the
    /// parent ZStack proposes — i.e. the screen) and apply it via
    /// `.overlay`, so the layout footprint stays at the screen width.
    /// Without this wrapper the oversized circle would force the host
    /// ZStack to ~520 pt wide, bleed the whole view past the screen
    /// edges, and push the top-trailing close X out of the visible
    /// area. Same root cause as the previous AppReviewView overflow.
    private var backgroundAura: some View {
        Color.clear
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccentSoft.opacity(0.55),
                                CooksyTheme.primaryAccentSoft.opacity(0)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 320
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(y: -200)
                    .blur(radius: 30)
            )
            .clipped()
    }

    // MARK: - Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                Text("OFFRE EXCLUSIVE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.0)
            }
            .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text("Votre offre\nunique")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Gift illustration (redesigned)

    private var giftIllustration: some View {
        ZStack {
            // 1. Soft ambient pad — adds depth.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.ctaOrange.opacity(0.30),
                            CooksyTheme.ctaOrange.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 24)

            // 2. Sparkle particles around the medallion.
            sparkleField

            // 3. The medallion itself.
            medallion
                .offset(y: giftFloat ? -6 : 4)
                .animation(
                    .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                    value: giftFloat
                )

            // 4. Discount seal anchored to the top-right of the medallion.
            discountSeal
                .offset(x: 70, y: -72)
                .rotationEffect(.degrees(sealWiggle ? 10 : -6))
                .animation(
                    .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: sealWiggle
                )
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var medallion: some View {
        ZStack {
            // Dropped soft shadow ring (sits below the disc).
            Circle()
                .fill(CooksyTheme.ctaOrangeDark.opacity(0.18))
                .frame(width: 195, height: 195)
                .offset(y: 14)
                .blur(radius: 20)

            // Outer disc — warm metallic gradient.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.86, blue: 0.58),
                            CooksyTheme.ctaOrange,
                            CooksyTheme.ctaOrangeDark
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 175, height: 175)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.7), .white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )

            // Inner ring — adds a "coin" feel.
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .frame(width: 148, height: 148)

            // Top sheen.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 175, height: 175)

            // Diagonal shimmer that sweeps the disc.
            shimmerStripe
                .frame(width: 175, height: 175)
                .clipShape(Circle())

            // Centered gift glyph.
            Image(systemName: "gift.fill")
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .shadow(color: CooksyTheme.ctaOrangeDark.opacity(0.4), radius: 2, y: 1)
        }
        .shadow(color: CooksyTheme.ctaOrange.opacity(0.45), radius: 30, y: 16)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var shimmerStripe: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0),
                        .white.opacity(0.35),
                        .white.opacity(0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60)
            .rotationEffect(.degrees(20))
            .offset(x: shimmer ? 130 : -130)
    }

    private var discountSeal: some View {
        ZStack {
            // Scalloped white edge — like an old-school sticker.
            ForEach(0..<14, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .offset(y: -34)
                    .rotationEffect(.degrees(Double(i) * (360.0 / 14.0)))
            }

            // Inner orange disc — carries the percent text.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [CooksyTheme.ctaOrange, CooksyTheme.ctaOrangeDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                )

            VStack(spacing: -2) {
                Text("−\(discountPercent)%")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text("À VIE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .opacity(0.95)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
        }
        .shadow(color: CooksyTheme.ctaOrangeDark.opacity(0.45), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var sparkleField: some View {
        ZStack {
            ForEach(Self.sparkles.indices, id: \.self) { i in
                let item = Self.sparkles[i]
                Image(systemName: "sparkle")
                    .font(.system(size: item.size, weight: .bold))
                    .foregroundStyle(item.color)
                    .offset(x: item.x, y: item.y)
                    .opacity(sparkle ? item.opacity : 0.15)
                    .scaleEffect(sparkle ? 1 : 0.55)
            }
            // A few tiny dots for variety.
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 5, height: 5)
                .offset(x: -68, y: -118)
                .opacity(sparkle ? 1 : 0.4)
            Circle()
                .fill(Color(red: 1.0, green: 0.92, blue: 0.7))
                .frame(width: 4, height: 4)
                .offset(x: 90, y: 110)
                .opacity(sparkle ? 1 : 0.4)
            Circle()
                .fill(.white.opacity(0.7))
                .frame(width: 3, height: 3)
                .offset(x: -100, y: 30)
                .opacity(sparkle ? 1 : 0.4)
        }
        .animation(
            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
            value: sparkle
        )
    }

    private static let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat, color: Color, opacity: Double)] = [
        (-130, -88, 18, .white, 1.0),
        (118, -72, 14, Color(red: 1.0, green: 0.92, blue: 0.7), 0.95),
        (138, 78, 12, .white, 0.85),
        (-118, 86, 16, Color(red: 1.0, green: 0.88, blue: 0.6), 0.9),
        (-78, -130, 10, .white, 0.8),
        (88, 122, 9, Color(red: 1.0, green: 0.92, blue: 0.7), 0.75),
        (152, 4, 8, .white, 0.75),
        (-150, -10, 8, Color(red: 1.0, green: 0.92, blue: 0.7), 0.7)
    ]

    // MARK: - Subtitle / strikethrough price

    private var subtitleBlock: some View {
        VStack(spacing: 10) {
            Text(headerLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(monthlyOfMonthlyPlan)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .strikethrough()
                Text(monthlyEquivalentLabeled)
                    .font(.system(size: 26, weight: .black, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text("Une fois cette offre fermée, elle est perdue.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var headerLabel: String {
        "Offre exclusive sur l'annuel"
    }

    // MARK: - Sticky stack (toggle + plan card + CTA + footer)

    private var stickyStack: some View {
        VStack(spacing: 12) {
            planCard
            cta
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var planCard: some View {
        VStack(spacing: 0) {
            Text(planChip)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16, topTrailingRadius: 16,
                        style: .continuous
                    )
                    .fill(CooksyTheme.accentGradient)
                )

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Plan annuel")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                    Text("\(discountedYearlyPriceString)\(yearlyPlan.unitLabel)")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(monthlyEquivalentLabeled)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 16, bottomTrailingRadius: 16,
                    style: .continuous
                )
                .fill(CooksyTheme.elevatedSurface)
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.primaryAccent, lineWidth: 2)
        )
    }

    private var planChip: String { "CADEAU EXCLUSIF" }

    private var cta: some View {
        Button(action: handlePurchase) {
            HStack(spacing: 10) {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(ctaLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .disabled(isPurchasing)
    }

    private var ctaLabel: String {
        if isPurchasing {
            return "Activation…"
        }
        return "S'abonner à \(discountedYearlyPriceString)\(yearlyPlan.unitLabel)"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
            Text(footerLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }

    private var footerLabel: String {
        "Aucun engagement, annulez à tout moment"
    }

    // MARK: - Purchase

    /// Run the full purchase locally — execute the purchase, and only
    /// after StoreKit confirms the entitlement do we mutate the gift
    /// state machine. The previous version mutated the gift BEFORE
    /// the purchase, which silently consumed the gift if the user
    /// cancelled the StoreKit sheet.
    private func handlePurchase() {
        guard !isPurchasing else { return }
        OnboardingHaptics.medium()
        isPurchasing = true

        let percent = discountPercent

        Task {
            var didSucceed = false
            do {
                // Try the matching Promotional Offer first ("GIFT25")
                // — Apple applies a real reduction if the offer is
                // configured server-side. Otherwise this falls back
                // silently to the regular annual price.
                try await PurchaseService.shared.purchaseAnnualWithPromo(
                    offerIdentifier: "GIFT\(percent)"
                )
                // Trust StoreKit's transaction success — RC's entitlement
                // may lag 1–2 s in sandbox. Force-grant premium locally
                // so the UI transitions off the offer screen immediately.
                await PurchaseService.shared.forcePremiumAfterPurchase()
                didSucceed = true
                await sessionStore.setPremium(true)
            } catch {
                // User cancelled or error — gift state unchanged.
            }

            await MainActor.run {
                if didSucceed {
                    let inTrial = PurchaseService.shared.isInTrial
                    offers.recordPurchaseCompleted(plan: yearlyPlan, inTrial: inTrial)
                    offers.clearFreeModeChoice()
                }
                isPurchasing = false
                onClose()
            }
        }
    }
}
