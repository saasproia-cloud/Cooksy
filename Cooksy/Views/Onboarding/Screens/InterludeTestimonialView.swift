import SwiftUI

/// Interlude 2 — Témoignage / social proof.
///
/// v2 design: a deck of three testimonial cards rendered as a peek-stack —
/// front card fully visible, two behind tilted and slightly smaller — so the
/// user feels "there's a whole crowd here, not just one quote." A live
/// counter at the top ticks past 12 000 users, an animated five-star burst
/// rates the front quote, and a "featured" strip mimics App Store / Product
/// Hunt placements to add credibility. The CTA repeats the gradient +
/// shimmer language from interlude 1 so the two screens feel like a series.
struct InterludeTestimonialView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var appeared: Bool = false
    @State private var starsLit: Int = 0
    @State private var quoteVisible: Bool = false
    @State private var deckRevealed: Bool = false
    @State private var liveCount: Int = 0
    @State private var ctaShimmer: Bool = false
    @State private var heroPulse: Bool = false

    private let targetLiveCount: Int = 12_047

    var body: some View {
        // The content VStack is the single layout root. Decorative
        // glow + gradient live in `.background()` so their fixed 500-520pt
        // circle sizes are out of the layout flow and can never push the
        // page wider than the screen.
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headline
                        .padding(.top, 8)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1), value: appeared)

                    liveCounter
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.92)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.2), value: appeared)

                    testimonialDeck
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.35), value: appeared)

                    featuredStrip
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.55), value: appeared)

                    microStatsRow
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.7), value: appeared)

                    hookLine
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.85), value: appeared)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            continueButton
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.45).delay(1.0), value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(decorativeBackdrop)
        .onAppear {
            appeared = true
            heroPulse = true
            deckRevealed = true
            runSequencedReveals()
            startShimmerLoop()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                OnboardingHaptics.selection()
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(CooksyTheme.elevatedSurface))
                    .overlay(Circle().stroke(CooksyTheme.stroke, lineWidth: 1))
                    .shadow(color: CooksyTheme.softShadow, radius: 6, y: 3)
            }
            .buttonStyle(.plain)

            Spacer()

            stepProgressDots

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
    }

    private var stepProgressDots: some View {
        HStack(spacing: 6) {
            // Step 1 — done
            Capsule()
                .fill(CooksyTheme.accentGradient.opacity(0.4))
                .frame(width: 14, height: 6)
            // Step 2 — current
            Capsule()
                .fill(CooksyTheme.accentGradient)
                .frame(width: 22, height: 6)
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 5, y: 2)
            // Step 3 — to come
            Capsule()
                .fill(CooksyTheme.stroke.opacity(0.7))
                .frame(width: 6, height: 6)

            Text("Étape 2 / 3")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(CooksyTheme.elevatedSurface.opacity(0.95))
        )
        .overlay(
            Capsule()
                .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 8, y: 3)
    }

    // MARK: - Background

    /// Decorative chrome (gradient + glow blobs) consolidated into one
    /// view consumed via `.background()` on the body. Out of layout flow
    /// + hard-clipped so the 500–520pt blobs cannot bleed past the screen
    /// edge or inflate the page width.
    private var decorativeBackdrop: some View {
        ZStack {
            CooksyTheme.ambientGradient

            backgroundGlow
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .clipped()
    }

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.warmCard.opacity(0.55),
                            CooksyTheme.warmCard.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: 140, y: -240)
                .blur(radius: 22)
                .scaleEffect(heroPulse ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: heroPulse)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentSoft.opacity(0.5),
                            CooksyTheme.primaryAccentSoft.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -150, y: 240)
                .blur(radius: 26)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Text("La famille Cooksy")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    .tracking(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .stroke(CooksyTheme.primaryAccent.opacity(0.25), lineWidth: 1)
            )

            Text("Tu rejoins une\nvraie communauté.")
                .font(.system(size: 28, weight: .heavy, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Live counter

    /// Big gradient counter pretending to tick the user count in real time.
    /// Adds a tiny pulsing dot to suggest "live."
    private var liveCounter: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .scaleEffect(heroPulse ? 1.25 : 0.85)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: heroPulse)
            }

            Text("\(liveCount.formatted(.number.grouping(.automatic)))")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.accentGradient)
                .contentTransition(.numericText(value: Double(liveCount)))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            Text("actifs")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            Capsule()
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }

    // MARK: - Testimonial deck

    /// Three cards stacked: back-left, back-right, and a featured front
    /// card on top. The two back cards are dimmed + tilted so the eye
    /// goes straight to the front quote.
    private var testimonialDeck: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frontW = min(280, w)
            let backW = min(240, w * 0.85)
            let sideOffset = min(28, w * 0.08)

            ZStack {
                TestimonialCard(
                    initial: "M",
                    name: "Marc, 34 ans",
                    meta: "Famille · sans gluten",
                    quote: "Mes recettes TikTok sont enfin propres.",
                    gradient: [CooksyTheme.secondaryAccent, CooksyTheme.secondaryAccentStrong],
                    stars: 5,
                    isFeatured: false,
                    animatedStars: 5
                )
                .frame(width: backW, height: 150)
                .rotationEffect(.degrees(deckRevealed ? -7 : -16))
                .offset(x: deckRevealed ? -sideOffset : -sideOffset * 0.3, y: deckRevealed ? 22 : 50)
                .scaleEffect(0.9)
                .opacity(deckRevealed ? 0.8 : 0)

                TestimonialCard(
                    initial: "T",
                    name: "Tom, 22 ans",
                    meta: "Solo · débutant",
                    quote: "Je cuisine vraiment, plus juste scroller.",
                    gradient: [CooksyTheme.primaryAccentStrong, CooksyTheme.primaryAccent],
                    stars: 5,
                    isFeatured: false,
                    animatedStars: 5
                )
                .frame(width: backW, height: 150)
                .rotationEffect(.degrees(deckRevealed ? 6 : 14))
                .offset(x: deckRevealed ? sideOffset : sideOffset * 0.3, y: deckRevealed ? 18 : 44)
                .scaleEffect(0.92)
                .opacity(deckRevealed ? 0.85 : 0)

                TestimonialCard(
                    initial: "L",
                    name: "Léa, 28 ans",
                    meta: "Couple · intermédiaire",
                    quote: "J'ai arrêté de scroller pour rien. Je gagne 2 soirées par semaine.",
                    gradient: [CooksyTheme.primaryAccent, CooksyTheme.primaryAccentGlow],
                    stars: 5,
                    isFeatured: true,
                    animatedStars: starsLit,
                    quoteVisible: quoteVisible
                )
                .frame(width: frontW, height: 172)
                .rotationEffect(.degrees(deckRevealed ? -1 : 4))
                .offset(y: deckRevealed ? -8 : 24)
                .opacity(deckRevealed ? 1 : 0)
            }
            .frame(width: w, height: 220)
            .animation(.spring(response: 0.8, dampingFraction: 0.78).delay(0.35), value: deckRevealed)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Featured strip

    /// Faux "as featured in" credibility row — App Store badges + ratings.
    private var featuredStrip: some View {
        HStack(spacing: 10) {
            FeaturedBadge(
                icon: "app.badge.fill",
                title: "App Store",
                subtitle: "Top 10 cuisine"
            )
            FeaturedBadge(
                icon: "star.circle.fill",
                title: "4.9 / 5",
                subtitle: "2 300 avis"
            )
            FeaturedBadge(
                icon: "sparkles",
                title: "Coup de ♥",
                subtitle: "Apple Éditeurs"
            )
        }
    }

    // MARK: - Micro stats

    private var microStatsRow: some View {
        HStack(spacing: 10) {
            MicroResultTile(value: "94 %", label: "cuisinent\nplus souvent")
            MicroResultTile(value: "2 h", label: "gagnées\npar semaine")
            MicroResultTile(value: "0", label: "vidéos\nà re-regarder")
        }
    }

    // MARK: - Hook

    private var hookLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)

            Text("Plus que quelques questions avant ton profil.")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.primaryAccentSoft.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                )
                .foregroundStyle(CooksyTheme.primaryAccent.opacity(0.4))
        )
    }

    // MARK: - Continue CTA

    private var continueButton: some View {
        Button(action: {
            OnboardingHaptics.medium()
            onContinue()
        }) {
            ZStack {
                Capsule()
                    .fill(CooksyTheme.accentGradient)

                GeometryReader { geo in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 110)
                        .offset(x: ctaShimmer ? geo.size.width + 50 : -120)
                        .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: ctaShimmer)
                }
                .mask(Capsule())

                HStack(spacing: 8) {
                    Text("Dernière ligne droite")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 10)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Sequenced reveals

    private func runSequencedReveals() {
        // Live counter ticks up.
        let steps = 32
        let duration = 1.8
        let interval = duration / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + interval * Double(i)) {
                let t = Double(i) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                liveCount = Int(Double(targetLiveCount) * eased)
            }
        }

        // Stars light up.
        for i in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + Double(i) * 0.09) {
                OnboardingHaptics.selection()
                starsLit = i
            }
        }

        // Quote fades in after stars finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                quoteVisible = true
            }
        }
    }

    private func startShimmerLoop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            ctaShimmer = true
        }
    }
}

// MARK: - Testimonial card

private struct TestimonialCard: View {
    let initial: String
    let name: String
    let meta: String
    let quote: String
    let gradient: [Color]
    let stars: Int
    let isFeatured: Bool
    let animatedStars: Int
    var quoteVisible: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        if isFeatured {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryAccentStrong)
                        }
                    }

                    Text(meta)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                starsRow
            }

            if isFeatured {
                Text("«  \(quote)  »")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(quoteVisible ? 1 : 0)
                    .offset(y: quoteVisible ? 0 : 6)
            } else {
                Text(quote)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isFeatured {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    Text("Avis vérifié — App Store")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isFeatured ? CooksyTheme.primaryAccent.opacity(0.35) : CooksyTheme.stroke,
                    lineWidth: isFeatured ? 1.4 : 1
                )
        )
        .shadow(color: CooksyTheme.softShadow, radius: isFeatured ? 22 : 12, y: isFeatured ? 14 : 8)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
            Text(initial)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle().stroke(CooksyTheme.elevatedSurface, lineWidth: 2)
        )
        .shadow(color: gradient.first?.opacity(0.35) ?? .clear, radius: 8, y: 4)
    }

    private var starsRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<stars, id: \.self) { index in
                let isLit = index < animatedStars
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isLit ? AnyShapeStyle(CooksyTheme.primaryAccentGlow) : AnyShapeStyle(CooksyTheme.stroke.opacity(0.5)))
                    .scaleEffect(isLit ? 1.08 : 0.9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLit)
            }
        }
    }
}

// MARK: - Featured badge

private struct FeaturedBadge: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 8, y: 4)
    }
}

// MARK: - Micro result tile

private struct MicroResultTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.accentGradient)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
        )
    }
}
