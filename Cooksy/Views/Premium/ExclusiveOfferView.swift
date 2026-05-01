import SwiftUI

/// Full-screen "VOTRE OFFRE UNIQUE" page presented after the user wins
/// the wheel. Adapted from the reference screenshot the user sent —
/// same skeleton (oversized title, illustrated gift box with diagonal
/// banner, strikethrough + per-month price, trial toggle, single plan
/// card, big CTA, footer reassurance) but in Cooksy's warm orange/cream
/// palette instead of the reference's purple.
///
/// Two states driven by a single `trialEnabled` toggle:
///
///   ┌──────────────────────────┬──────────────────────────┐
///   │  Trial ON (default)      │  Trial OFF               │
///   ├──────────────────────────┼──────────────────────────┤
///   │  "7 jours d'essai…"      │  "−25 % aujourd'hui"     │
///   │  ~~7,99 €/mois~~ 2,49 €  │  ~~7,99 €/mois~~ 2,49 €  │
///   │  Card chip:              │  Card chip:              │
///   │    "7 JOURS D'ESSAI"     │    "−25 % DE RÉDUCTION"  │
///   │  CTA:                    │  CTA:                    │
///   │    "Commencer mes 7 j…"  │    "S'abonner −25 %"     │
///   │  Footer:                 │  Footer:                 │
///   │    "Pas de paiement…"    │    "Aucun engagement…"   │
///   └──────────────────────────┴──────────────────────────┘
struct ExclusiveOfferView: View {
    let discountPercent: Int
    let expiresAt: Date?
    let onClose: () -> Void
    /// Called when the user taps the main CTA. Receives the trial
    /// toggle state so the host can wire it into `handlePurchase`.
    let onSubscribe: (Bool) -> Void

    @State private var trialEnabled: Bool = true

    private let yearlyPlan: PremiumPlan = .yearly

    private var monthlyEquivalent: String {
        yearlyPlan.monthlyEquivalentString(discountPercent: discountPercent)
            ?? "\(yearlyPlan.formattedPrice(discountPercent: discountPercent))/mois"
    }

    private var monthlyOfMonthlyPlan: String {
        PremiumPlan.monthly.formattedPrice() + PremiumPlan.monthly.unitLabel
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Color.clear.frame(height: 56) // top chrome breathing room

                    title
                    giftIllustration
                        .frame(height: 230)

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
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Title

    private var title: some View {
        Text("VOTRE OFFRE UNIQUE")
            .font(.system(size: 32, weight: .black, design: .serif))
            .foregroundStyle(CooksyTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Gift illustration

    private var giftIllustration: some View {
        ZStack {
            // Soft glow behind the box.
            Circle()
                .fill(CooksyTheme.primaryAccentSoft)
                .frame(width: 260, height: 260)
                .blur(radius: 30)

            // The box itself — drawn with primitives so it matches the
            // brand without bundling an SVG asset.
            VStack(spacing: 0) {
                // Bow
                ZStack {
                    HStack(spacing: -8) {
                        Ellipse()
                            .fill(CooksyTheme.ctaOrange)
                            .frame(width: 64, height: 38)
                            .rotationEffect(.degrees(-22))
                        Ellipse()
                            .fill(CooksyTheme.ctaOrange)
                            .frame(width: 64, height: 38)
                            .rotationEffect(.degrees(22))
                    }
                    Circle()
                        .fill(CooksyTheme.ctaOrangeDark)
                        .frame(width: 22, height: 22)
                }
                .offset(y: 14)
                .zIndex(2)

                // Body of the box (warm cream with cross-ribbon)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.heroGlowGradient)
                        .frame(width: 200, height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(CooksyTheme.ctaOrange.opacity(0.3), lineWidth: 1.5)
                        )

                    // Vertical ribbon
                    Rectangle()
                        .fill(CooksyTheme.ctaOrange)
                        .frame(width: 22, height: 150)
                }
                .zIndex(1)
            }
            .shadow(color: CooksyTheme.ctaOrange.opacity(0.3), radius: 24, y: 12)

            // Diagonal banner across the box.
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 280, height: 70)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                VStack(spacing: 0) {
                    Text("−\(discountPercent) % DE RÉDUCTION")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .tracking(0.5)
                    Text("PENDANT 24 H")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .opacity(0.92)
                }
                .foregroundStyle(.white)
            }
            .rotationEffect(.degrees(-12))
            .offset(y: 10)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Subtitle / strikethrough price

    private var subtitleBlock: some View {
        VStack(spacing: 10) {
            Text(headerLabel)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

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
        trialEnabled ? "7 jours d'essai gratuit" : "−\(discountPercent) % à vie sur l'annuel"
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
            Text(trialEnabled ? "Essai gratuit activé" : "Offre spéciale activée")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
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
            ? "7 JOURS D'ESSAI GRATUIT"
            : "−\(discountPercent) % DE RÉDUCTION"
    }

    private var cta: some View {
        Button(action: {
            OnboardingHaptics.medium()
            onSubscribe(trialEnabled)
        }) {
            Text(ctaLabel)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 8)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var ctaLabel: String {
        trialEnabled
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
}
