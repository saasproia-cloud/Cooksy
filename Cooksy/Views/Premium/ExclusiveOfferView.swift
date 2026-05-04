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

    @State private var trialEnabled: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var giftFloat: Bool = false
    @State private var sparkle: Bool = false
    @State private var sealWiggle: Bool = false
    @State private var shimmer: Bool = false

    private let yearlyPlan: PremiumPlan = .yearly

    private var monthlyEquivalent: String {
        yearlyPlan.monthlyEquivalentString(
            discountPercent: discountPercent,
            withTrialDays: trialEnabled ? 7 : 0
        ) ?? "\(yearlyPlan.formattedPrice(discountPercent: discountPercent))/mois"
    }

    private var monthlyOfMonthlyPlan: String {
        PremiumPlan.monthly.formattedPrice() + PremiumPlan.monthly.unitLabel
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
                    giftIllustration
                        .frame(height: 260)

                    subtitleBlock

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
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
        }
    }

    // MARK: - Background aura

    private var backgroundAura: some View {
        ZStack {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(size: 34, weight: .black, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
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
                        endRadius: 200
                    )
                )
                .frame(width: 360, height: 360)
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
                .offset(x: 80, y: -82)
                .rotationEffect(.degrees(sealWiggle ? 10 : -6))
                .animation(
                    .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: sealWiggle
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var medallion: some View {
        ZStack {
            // Dropped soft shadow ring (sits below the disc).
            Circle()
                .fill(CooksyTheme.ctaOrangeDark.opacity(0.18))
                .frame(width: 220, height: 220)
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
                .frame(width: 200, height: 200)
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
                .frame(width: 170, height: 170)

            // Top sheen.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 200, height: 200)

            // Diagonal shimmer that sweeps the disc.
            shimmerStripe
                .frame(width: 200, height: 200)
                .clipShape(Circle())

            // Centered gift glyph.
            Image(systemName: "gift.fill")
                .font(.system(size: 86, weight: .bold))
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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(monthlyOfMonthlyPlan)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .strikethrough()
                Text(monthlyEquivalent)
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            Text("Une fois cette offre fermée, elle est perdue.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var headerLabel: String {
        trialEnabled
            ? "7 jours gratuits, puis −\(discountPercent) % à vie"
            : "−\(discountPercent) % à vie sur l'annuel"
    }

    // MARK: - Sticky stack (toggle + plan card + CTA + footer)

    private var stickyStack: some View {
        VStack(spacing: 12) {
            trialToggleRow
            planCard
            cta
            footer
        }
        .padding(.horizontal, 22)
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

    private var trialToggleRow: some View {
        Toggle(isOn: $trialEnabled.animation(.spring(response: 0.35))) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trialEnabled ? "Essai gratuit 7 jours activé" : "Activer 7 jours d'essai gratuit")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("En plus du −\(discountPercent) % — les deux se cumulent.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
        .tint(CooksyTheme.primaryAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
        )
        .disabled(isPurchasing)
        .opacity(isPurchasing ? 0.55 : 1)
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("\(yearlyPlan.formattedPrice(discountPercent: discountPercent))/an")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                Spacer(minLength: 4)
                Text(monthlyEquivalent)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            }
            .padding(.horizontal, 14)
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

    private var planChip: String {
        trialEnabled
            ? "7 J GRATUITS · −\(discountPercent) % À VIE"
            : "−\(discountPercent) % DE RÉDUCTION"
    }

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
        return trialEnabled
            ? "Commencer mes 7 jours gratuits"
            : "S'abonner à \(yearlyPlan.formattedPrice(discountPercent: discountPercent))/an"
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
        trialEnabled
            ? "Pas de paiement maintenant"
            : "Aucun engagement, annulez à tout moment"
    }

    // MARK: - Purchase

    /// Run the full purchase locally — record the start, flip the
    /// premium flag, then dismiss. The host paywall used to do this
    /// after dismissing the cover; doing it inline avoids the brief
    /// "back to paywall" flash and lets us show a real loading state
    /// on the CTA itself.
    private func handlePurchase() {
        guard !isPurchasing else { return }
        OnboardingHaptics.medium()

        offers.recordPurchaseStarted(plan: yearlyPlan, usingFreeTrial: trialEnabled)
        isPurchasing = true

        Task {
            await sessionStore.setPremiumMock(true)
            await MainActor.run {
                offers.clearFreeModeChoice()
                if !trialEnabled {
                    offers.recordTrialConverted()
                }
                isPurchasing = false
                onClose()
            }
        }
    }
}
