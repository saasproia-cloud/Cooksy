import SwiftUI

// MARK: - Hero headline
//
// "Obtenez tes recettes illimitées d'Instagram, TikTok et plus"
// with the value-prop fragment painted in Cooksy orange so the
// eye lands on the benefit before the price.

struct PaywallHeroHeadline: View {
    var body: some View {
        VStack(spacing: 6) {
            (
                Text("Débloque tes ")
                    .foregroundStyle(CooksyTheme.primaryText)
                + Text("recettes illimitées")
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            )
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            Text("d'Instagram, TikTok et plus")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trial timeline (3 steps with connecting line)

struct PaywallTrialTimeline: View {
    let trialDays: Int

    private var endDateString: String {
        let endDate = Calendar.current.date(byAdding: .day, value: trialDays, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: endDate)
    }

    private var reminderDay: Int { max(1, trialDays - 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comment fonctionne ton essai gratuit :")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            VStack(spacing: 0) {
                timelineRow(
                    icon: "lock.fill",
                    iconStyle: .accent,
                    title: "Aujourd'hui : débloque Cooksy",
                    body: "Accès instantané à toutes les fonctionnalités premium et organisation illimitée.",
                    connector: .active
                )
                timelineRow(
                    icon: "bell.fill",
                    iconStyle: .muted,
                    title: "Jour \(reminderDay) : rappel de l'essai",
                    body: "On t'envoie une notification pour te prévenir que ton essai se termine bientôt.",
                    connector: .muted
                )
                timelineRow(
                    icon: "star.fill",
                    iconStyle: .muted,
                    title: "Jour \(trialDays) : fin de l'essai",
                    body: "Ton abonnement commencera le \(endDateString). Annule à tout moment avant.",
                    connector: .none
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum IconStyle { case accent, muted }
    private enum Connector { case active, muted, none }

    @ViewBuilder
    private func timelineRow(
        icon: String,
        iconStyle: IconStyle,
        title: String,
        body: String,
        connector: Connector
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconStyle == .accent
                              ? AnyShapeStyle(CooksyTheme.accentGradient)
                              : AnyShapeStyle(CooksyTheme.warmCard))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(iconStyle == .accent
                                         ? Color.white
                                         : CooksyTheme.primaryText.opacity(0.55))
                }
                .frame(width: 38, height: 38)
                .shadow(
                    color: iconStyle == .accent ? CooksyTheme.primaryAccent.opacity(0.35) : .clear,
                    radius: 8, y: 3
                )

                switch connector {
                case .active:
                    Rectangle()
                        .fill(CooksyTheme.primaryAccent)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                case .muted:
                    Rectangle()
                        .fill(CooksyTheme.warmCard.opacity(0.85))
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                case .none:
                    EmptyView()
                }
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(body)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .padding(.bottom, connector == .none ? 0 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Social proof row (laurels + star rating)

struct PaywallSocialProofRow: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.85))
                VStack(spacing: 0) {
                    Text("+12 000")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    Text("Cuisiniers heureux")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.85))
            }

            VStack(spacing: 6) {
                Text("NOTE DE 4,9 ÉTOILES")
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(CooksyTheme.primaryText)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentGlow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Testimonials (horizontal scroll)

struct PaywallTestimonial: Identifiable {
    let id = UUID()
    let stars: Int
    let quote: String
    let name: String
    let flag: String
    let initialsTint: Color
}

struct PaywallTestimonialsScroll: View {
    let testimonials: [PaywallTestimonial]

    static let defaults: [PaywallTestimonial] = [
        PaywallTestimonial(
            stars: 5,
            quote: "A changé ma cuisine — je colle un lien Reel et j'ai la recette en clair en quelques secondes. Plus jamais à mettre pause pour noter.",
            name: "Léa, 32",
            flag: "🇫🇷",
            initialsTint: CooksyTheme.primaryAccent
        ),
        PaywallTestimonial(
            stars: 5,
            quote: "Cooksy enregistre toutes mes recettes TikTok sans que je les perde jamais — enfin ce qu'il me fallait pour cuisiner sans téléphone en main.",
            name: "Michael, 38",
            flag: "🇬🇧",
            initialsTint: CooksyTheme.secondaryAccentStrong
        ),
        PaywallTestimonial(
            stars: 5,
            quote: "L'extraction est bluffante : ingrédients, étapes, portions, tout est propre. Mon réflexe quand je vois une vidéo qui m'inspire.",
            name: "Sofia, 27",
            flag: "🇪🇸",
            initialsTint: CooksyTheme.primaryAccentStrong
        )
    ]

    init(testimonials: [PaywallTestimonial] = PaywallTestimonialsScroll.defaults) {
        self.testimonials = testimonials
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(testimonials) { item in
                    TestimonialCard(item: item)
                        .frame(width: 280)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private struct TestimonialCard: View {
        let item: PaywallTestimonial

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(0..<item.stars, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(CooksyTheme.primaryAccentGlow)
                    }
                }

                Text(item.quote)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(item.initialsTint.opacity(0.18))
                        Text(String(item.name.prefix(1)))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(item.initialsTint)
                    }
                    .frame(width: 28, height: 28)

                    Text("\(item.name) \(item.flag)")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.softShadow, radius: 8, y: 3)
            )
        }
    }
}

// MARK: - Plans sheet ("Choisissez un forfait")

struct PaywallPlansSheet: View {
    @Binding var selectedPlan: PremiumPlan
    let trialDays: Int
    let trialEligible: Bool
    let isPurchasing: Bool
    /// Active gift discount (e.g. 25) when the user has won a cadeau.
    /// `nil` when no gift is active. Drives the discounted price display.
    var giftDiscountPercent: Int? = nil
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CooksyTheme.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Choisissez un forfait")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.top, 22)

                VStack(spacing: 12) {
                    annualCard
                    monthlyCard
                }

                Spacer(minLength: 0)

                PaywallReassuranceLine(
                    plan: selectedPlan,
                    trialEligible: trialEligible,
                    giftDiscountPercent: giftDiscountPercent
                )

                PaywallPrimaryCTAButton(
                    title: PaywallCopy.ctaTitle(
                        plan: selectedPlan,
                        trialEligible: trialEligible,
                        giftDiscountPercent: giftDiscountPercent
                    ),
                    isLoading: isPurchasing,
                    action: onConfirm
                )

                PaywallDisclaimerText(
                    plan: selectedPlan,
                    trialDays: trialDays,
                    trialEligible: trialEligible,
                    giftDiscountPercent: giftDiscountPercent
                )
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)

            closeButton
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }

    // MARK: Annual

    private var annualCard: some View {
        let isSelected = selectedPlan == .yearly
        // When a gift discount is active we surface the discounted price
        // — otherwise StoreKit ends up debiting less than what the UI
        // promised and the user feels deceived.
        let hasGift = (giftDiscountPercent ?? 0) > 0
        let priceText = PremiumPlan.yearly.liveOrFallbackPriceString(discountPercent: giftDiscountPercent)
        let monthlyEquivalent = PremiumPlan.yearly
            .liveOrFallbackMonthlyEquivalent(discountPercent: giftDiscountPercent) ?? "3,33 €"
        // Strikethrough swaps role depending on context:
        //   • gift active    → original annual price (so the −X % saving is visible)
        //   • no gift        → monthly × 12 (so the annual saving over monthly is visible)
        let strikethrough = hasGift
            ? PremiumPlan.yearly.liveOrFallbackPriceString
            : formattedStrikethroughForYearly()

        return Button {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedPlan = .yearly
            }
        } label: {
            VStack(spacing: 0) {
                // Banner: gift overrides trial (the gift purchase is
                // pay-up-front so promising "Essai gratuit" would lie).
                if hasGift, let percent = giftDiscountPercent {
                    Text("Cadeau −\(percent) % actif")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(CooksyTheme.accentGradient)
                } else if trialEligible {
                    Text("Essai gratuit de \(trialDays) jours")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(CooksyTheme.accentGradient)
                }

                // Pricing hierarchy required by App Store Guideline 3.1.2(c):
                // the actually-billed amount (here, the annual price)
                // MUST be the most clear and conspicuous pricing element.
                //
                // We keep `39,99 €/an` as the visually dominant element
                // (24pt heavy, primary text color) and place the
                // calculated `soit X €/mois` in a subordinate slot —
                // smaller (13pt) and lighter weight (semibold) than the
                // billed amount, but still rendered in the primary text
                // color (not gray) so it stays clearly legible without
                // overtaking the headline price.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Annuel")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                        if let strikethrough {
                            Text(strikethrough)
                                .strikethrough()
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        // ── Primary, billed amount (Apple-mandated headline) ──
                        Text("\(priceText)/an")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        // ── Subordinate, calculated per-month ──
                        // Smaller and lighter than the billed amount,
                        // but in primary text color so it stays readable
                        // at a glance.
                        Text("soit \(monthlyEquivalent)/mois")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke.opacity(0.8),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.18) : .clear,
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private var monthlyCard: some View {
        let isSelected = selectedPlan == .monthly
        let priceText = PremiumPlan.monthly.liveOrFallbackPriceString

        return Button {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedPlan = .monthly
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mensuel")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("Pas d'essai gratuit")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Text("\(priceText)/mois")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? CooksyTheme.primaryAccent : CooksyTheme.stroke.opacity(0.8),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? CooksyTheme.primaryAccent.opacity(0.18) : .clear,
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                Circle().stroke(CooksyTheme.stroke.opacity(0.9), lineWidth: 1)
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .frame(width: 34, height: 34)
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
            .contentShape(Circle())
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fermer")
    }

    /// "monthly × 12" formatted, used as the strikethrough next to the
    /// actual annual price so the saving feels visceral.
    private func formattedStrikethroughForYearly() -> String? {
        let total = PremiumPlan.monthly.basePrice * 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: total as NSDecimalNumber)
    }
}

// MARK: - Shared CTA / disclaimer / reassurance

struct PaywallReassuranceLine: View {
    let plan: PremiumPlan
    let trialEligible: Bool
    /// When set, the user has an active gift discount — purchase pays
    /// up front, so the "Aucun paiement maintenant" copy would lie.
    var giftDiscountPercent: Int? = nil

    private var copy: String {
        // Gift overrides trial — purchaseAnnualWithPromo is pay-up-front.
        if plan == .yearly, (giftDiscountPercent ?? 0) > 0 {
            return "Sans engagement, annule à tout moment"
        }
        if plan == .yearly, trialEligible {
            return "Aucun paiement maintenant"
        }
        return "Sans engagement, annule à tout moment"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CooksyTheme.primaryText)
            Text(copy)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PaywallPrimaryCTAButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isLoading ? "Activation…" : title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 9)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .disabled(isLoading)
    }
}

struct PaywallDisclaimerText: View {
    let plan: PremiumPlan
    let trialDays: Int
    let trialEligible: Bool
    /// Active gift discount (e.g. 25) — applied to the yearly price so
    /// the small-print never lies about what Apple will charge.
    var giftDiscountPercent: Int? = nil

    var body: some View {
        Text(copy)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
    }

    private var copy: String {
        // Gift mode: the GIFT25 adHocOffer is pay-up-front, no trial.
        // Short-circuit BEFORE the trial branch so we never promise
        // "Gratuit pendant 7 jours" while Apple is actually charging.
        if plan == .yearly, (giftDiscountPercent ?? 0) > 0 {
            let annual = PremiumPlan.yearly.liveOrFallbackPriceString(discountPercent: giftDiscountPercent)
            return "\(annual)/an. Annulable à tout moment."
        }
        if plan == .yearly, trialEligible {
            let annual = PremiumPlan.yearly.liveOrFallbackPriceString
            let monthly = PremiumPlan.yearly.liveOrFallbackMonthlyEquivalent ?? "3,33 €"
            return "Gratuit pendant \(trialDays) jours, puis \(annual)/an (\(monthly)/mois)."
        }
        if plan == .yearly {
            let annual = PremiumPlan.yearly.liveOrFallbackPriceString
            return "\(annual)/an. Annulable à tout moment."
        }
        let monthly = PremiumPlan.monthly.liveOrFallbackPriceString
        return "\(monthly)/mois. Annulable à tout moment."
    }
}

// MARK: - Copy helpers

enum PaywallCopy {
    static func ctaTitle(
        plan: PremiumPlan,
        trialEligible: Bool,
        giftDiscountPercent: Int? = nil
    ) -> String {
        if plan == .yearly, let percent = giftDiscountPercent, percent > 0 {
            return "Active ton cadeau −\(percent) %"
        }
        if plan == .yearly, trialEligible {
            return "Commence ta semaine GRATUITE"
        }
        return "Abonne-toi maintenant"
    }
}
