import SwiftUI

/// Interlude 1 — Suspense / chiffres. Shown after the first block of questions
/// (~7) to break the rhythm and tease how much value the user is unlocking.
///
/// v2 design: stacked 3D recipe cards as the hero, a giant gradient number
/// that ticks up, a glowing profile completion meter, sparkle particles
/// drifting up the background, and a "locked next reveal" teaser to hint at
/// what the next block will unlock. The whole screen should feel like
/// something is being _built_ for the user.
struct InterludeNumbersView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var appeared: Bool = false
    @State private var recipeCount: Int = 0
    @State private var profileProgress: CGFloat = 0
    @State private var heroPulse: Bool = false
    @State private var cardsRevealed: Bool = false
    @State private var ctaShimmer: Bool = false

    private let targetRecipes: Int = 1247
    private let targetProgress: CGFloat = 0.34

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            backgroundGlow
                .allowsHitTesting(false)

            SparkleCanvas(count: 14)
                .opacity(appeared ? 0.55 : 0)
                .animation(.easeOut(duration: 0.8).delay(0.2), value: appeared)
                .allowsHitTesting(false)

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
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1), value: appeared)

                        recipeStack
                            .padding(.top, 4)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.22), value: appeared)

                        bigNumberBlock
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.4), value: appeared)

                        profileMeter
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.55), value: appeared)

                        miniStatsRow
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.7), value: appeared)

                        nextRevealTease
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.85), value: appeared)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
                }

                Spacer(minLength: 0)

                continueButton
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.45).delay(1.0), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            heroPulse = true
            cardsRevealed = true
            runCountUp()
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
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == 0 ? AnyShapeStyle(CooksyTheme.accentGradient) : AnyShapeStyle(CooksyTheme.stroke.opacity(0.7)))
                    .frame(width: i == 0 ? 22 : 6, height: 6)
                    .shadow(color: i == 0 ? CooksyTheme.primaryAccent.opacity(0.35) : .clear, radius: 5, y: 2)
            }
            Text("Étape 1 / 3")
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

    private var backgroundGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentGlow.opacity(0.45),
                            CooksyTheme.primaryAccentGlow.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: -80, y: -260)
                .blur(radius: 24)
                .scaleEffect(heroPulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: heroPulse)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.warmCard.opacity(0.5),
                            CooksyTheme.warmCard.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: 130, y: 200)
                .blur(radius: 28)
        }
        .ignoresSafeArea()
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Text("On a déjà commencé")
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

            Text("Voilà ce qu'on\nconstruit pour toi.")
                .font(.system(size: 30, weight: .heavy, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recipe stack hero

    /// Three peek-style recipe cards stacked behind one another. Animates
    /// in with a small spring + offset so it feels like the cards are
    /// landing in place. The whole stack tilts subtly for depth.
    private var recipeStack: some View {
        ZStack {
            RecipePreviewCard(
                title: "Bowl miso · saumon",
                tag: "Healthy",
                accent: CooksyTheme.primaryAccent,
                glyph: "leaf.fill"
            )
            .frame(width: 220, height: 64)
            .rotationEffect(.degrees(cardsRevealed ? -8 : -20))
            .offset(x: cardsRevealed ? -78 : -40, y: cardsRevealed ? 18 : 60)
            .opacity(cardsRevealed ? 0.85 : 0)
            .scaleEffect(0.88)

            RecipePreviewCard(
                title: "Carbonara, vraie recette",
                tag: "Comfort",
                accent: CooksyTheme.secondaryAccent,
                glyph: "flame.fill"
            )
            .frame(width: 230, height: 66)
            .rotationEffect(.degrees(cardsRevealed ? 6 : 18))
            .offset(x: cardsRevealed ? 70 : 40, y: cardsRevealed ? 14 : 50)
            .opacity(cardsRevealed ? 0.92 : 0)
            .scaleEffect(0.92)

            RecipePreviewCard(
                title: "Poulet teriyaki express",
                tag: "12 min",
                accent: CooksyTheme.primaryAccentStrong,
                glyph: "bolt.fill",
                featured: true
            )
            .frame(width: 250, height: 76)
            .rotationEffect(.degrees(cardsRevealed ? -2 : 6))
            .offset(y: cardsRevealed ? -10 : 30)
            .opacity(cardsRevealed ? 1 : 0)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.spring(response: 0.75, dampingFraction: 0.78).delay(0.25), value: cardsRevealed)
    }

    // MARK: - Big number block

    private var bigNumberBlock: some View {
        VStack(spacing: 6) {
            Text("\(recipeCount)")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundStyle(CooksyTheme.accentGradient)
                .contentTransition(.numericText(value: Double(recipeCount)))
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.25), radius: 14, y: 6)
                .monospacedDigit()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Text("recettes déjà compatibles avec ton profil")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Profile meter

    private var profileMeter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 8, y: 3)
                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Ton profil culinaire")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("Il devient unique à chaque réponse.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer()

                Text("\(Int(profileProgress * 100)) %")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.accentGradient)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CooksyTheme.stroke.opacity(0.45))
                        .frame(height: 12)

                    Capsule()
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: max(16, geo.size.width * profileProgress), height: 12)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 8, y: 3)
                        .animation(.spring(response: 1.1, dampingFraction: 0.85), value: profileProgress)

                    // Glow puck at the end of the fill
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(CooksyTheme.primaryAccent, lineWidth: 2)
                        )
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.5), radius: 6, y: 0)
                        .offset(x: max(0, geo.size.width * profileProgress - 5), y: 0)
                        .animation(.spring(response: 1.1, dampingFraction: 0.85), value: profileProgress)
                }
            }
            .frame(height: 12)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 6)
    }

    // MARK: - Mini stats row

    private var miniStatsRow: some View {
        HStack(spacing: 10) {
            MiniStatTile(icon: "leaf.fill", value: "384", label: "ingrédients\nfiltrés")
            MiniStatTile(icon: "graduationcap.fill", value: "56", label: "techniques\nadaptées")
            MiniStatTile(icon: "shield.lefthalf.filled", value: "12", label: "allergènes\nbloqués")
        }
    }

    // MARK: - Next reveal tease

    private var nextRevealTease: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
                    .frame(width: 40, height: 40)
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Prochain bloc → goûts & cuisines")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("On va calibrer ce que tu adores vraiment.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                )
                .foregroundStyle(CooksyTheme.primaryAccent.opacity(0.45))
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

                // Shimmer sweep
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
                    Text("Continuer")
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

    // MARK: - Count-up + shimmer loops

    private func runCountUp() {
        let steps = 36
        let duration = 1.8
        let interval = duration / Double(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                let t = Double(i) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                recipeCount = Int(Double(targetRecipes) * eased)
            }
        }

        withAnimation(.spring(response: 1.2, dampingFraction: 0.85).delay(0.3)) {
            profileProgress = targetProgress
        }
    }

    private func startShimmerLoop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            ctaShimmer = true
        }
    }
}

// MARK: - Recipe preview card (mock)

private struct RecipePreviewCard: View {
    let title: String
    let tag: String
    let accent: Color
    let glyph: String
    var featured: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: accent.opacity(0.35), radius: 8, y: 4)

                Image(systemName: glyph)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(accent.opacity(0.16))
                        )
                    if featured {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Compatible")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(featured ? accent.opacity(0.45) : CooksyTheme.stroke, lineWidth: featured ? 1.5 : 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 8)
    }
}

// MARK: - Mini stat tile

private struct MiniStatTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            }

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
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
