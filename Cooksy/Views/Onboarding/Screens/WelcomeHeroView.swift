import SwiftUI

/// A1 — Welcome hero.
///
/// Direction artistique
/// --------------------
/// Premium éditorial, pas de gadget, pas d'emoji. Le hero raconte
/// littéralement la magie produit : une carte vidéo (façon TikTok/Reel)
/// se transforme en carte recette propre, reliées par un bridge animé.
/// L'utilisateur voit, en un coup d'œil, ce que l'app fait — sans
/// avoir à lire un seul mot.
///
///   • Fond ambiant chaleureux (deux blobs qui respirent)
///   • Carte vidéo 9:16 floutée à gauche (avatar, handle, durée, play)
///   • Bridge central : capsule orange avec icône wand.and.stars qui
///     pulse, particules lumineuses traversant gauche → droite
///   • Carte recette propre à droite : titre, time chip, ingrédients
///   • Les deux cartes flottent indépendamment (parallaxe), tilt 3D
///     très léger
///   • Wordmark serif fin en haut, headline confiante en bas, un seul
///     CTA capsule + bouton inline "Déjà un compte ?"
///
/// Aucune image bitmap : tout est dessiné en SwiftUI, donc parfaitement
/// net sur tous les écrans Retina, et adaptatif sur tous les iPhone.
struct WelcomeHeroView: View {
    let onContinue: () -> Void
    let onExistingAccount: () -> Void

    @State private var heroAppeared = false

    var body: some View {
        ZStack {
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                let availableWidth = geo.size.width - 48
                let bridgeWidth: CGFloat = 50
                let cardWidth = min((availableWidth - bridgeWidth) / 2, 142)
                let cardHeight = cardWidth * 1.42

                VStack(spacing: 0) {
                    Spacer(minLength: 18)

                    Text("Cooksy")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .tracking(0.5)
                        .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
                        .opacity(heroAppeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.45), value: heroAppeared)

                    Spacer(minLength: 28)

                    TransformationHero(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        bridgeWidth: bridgeWidth,
                        appeared: heroAppeared
                    )
                    .frame(height: cardHeight + 30)

                    Spacer(minLength: 26)

                    VStack(spacing: 6) {
                        Text("Une vidéo.\nUne recette.")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(-2)
                            .minimumScaleFactor(0.8)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(heroAppeared ? 1 : 0)
                    .offset(y: heroAppeared ? 0 : 14)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.85).delay(0.35),
                        value: heroAppeared
                    )

                    Spacer(minLength: 22)

                    VStack(spacing: 12) {
                        Button(action: {
                            OnboardingHaptics.medium()
                            onContinue()
                        }) {
                            HStack(spacing: 8) {
                                Text("Commencer")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.accentGradient)
                            )
                            .shadow(color: CooksyTheme.primaryAccent.opacity(0.40), radius: 18, y: 10)
                        }
                        .buttonStyle(CooksyTheme.pressScale())

                        Button(action: {
                            OnboardingHaptics.selection()
                            onExistingAccount()
                        }) {
                            HStack(spacing: 4) {
                                Text("Déjà un compte ?")
                                    .foregroundStyle(CooksyTheme.secondaryText)
                                Text("Se connecter")
                                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .opacity(heroAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.55), value: heroAppeared)
                }
                .frame(width: geo.size.width)
                .padding(.horizontal, 24)
            }
        }
        .onAppear { heroAppeared = true }
    }
}

// MARK: - Animated background

/// Subtle gradient "breathing" background via TimelineView.
struct AnimatedAmbientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = CGFloat((sin(t * 0.4) + 1) * 0.5)

            ZStack {
                CooksyTheme.ambientGradient

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccentSoft.opacity(0.75),
                                CooksyTheme.primaryAccentSoft.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 280
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: -120 + drift * 60, y: -260 + drift * 40)
                    .blur(radius: 20)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.warmCard.opacity(0.65),
                                CooksyTheme.warmCard.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 300
                        )
                    )
                    .frame(width: 540, height: 540)
                    .offset(x: 140 - drift * 40, y: 320 - drift * 60)
                    .blur(radius: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}

// MARK: - Transformation hero (centerpiece)

/// Two floating cards (video → recipe) connected by an animated bridge.
/// Each card oscillates with its own sin/cos so the parallax feels
/// organic. Three "magic dust" particles travel from the video card to
/// the recipe card on a continuous loop, anchoring the bridge metaphor.
private struct TransformationHero: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let bridgeWidth: CGFloat
    let appeared: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let videoY = sin(t * 0.55) * 4.0
            let recipeY = sin(t * 0.55 + 1.2) * 4.0
            let videoTilt = cos(t * 0.42) * 1.6
            let recipeTilt = cos(t * 0.42 + 0.8) * 1.6
            let bridgePulse = (sin(t * 1.4) + 1) * 0.5
            let dustPhase = (t * 0.7).truncatingRemainder(dividingBy: 1.0)

            HStack(spacing: 0) {
                VideoPreviewCardArt()
                    .frame(width: cardWidth, height: cardHeight)
                    .offset(x: appeared ? 0 : -30, y: videoY)
                    .rotation3DEffect(
                        .degrees(videoTilt),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.6
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.7, dampingFraction: 0.78).delay(0.1),
                        value: appeared
                    )

                Spacer(minLength: 0)
                    .frame(width: bridgeWidth)
                    .overlay(
                        TransformationBridge(
                            pulse: bridgePulse,
                            dustPhase: CGFloat(dustPhase),
                            width: bridgeWidth
                        )
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.75).delay(0.25),
                            value: appeared
                        )
                    )

                MiniRecipeCardArt(width: cardWidth, height: cardHeight)
                    .offset(x: appeared ? 0 : 30, y: recipeY)
                    .rotation3DEffect(
                        .degrees(recipeTilt),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.6
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.7, dampingFraction: 0.78).delay(0.18),
                        value: appeared
                    )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Video preview card (left)

/// Simulated TikTok/Reel preview: dark gradient background, abstract
/// blurred "kitchen" blobs, play icon, social handle and a duration
/// chip. Communicates "vertical short-form video" without any emoji.
private struct VideoPreviewCardArt: View {
    var body: some View {
        ZStack {
            // Dark moody backdrop (kitchen vibe).
            LinearGradient(
                colors: [
                    Color(hex: 0x2A1810),
                    Color(hex: 0x4A2818),
                    Color(hex: 0x6B3220)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Abstract blurred color blobs — read as out-of-focus food.
            Circle()
                .fill(Color(hex: 0xF59E2B).opacity(0.55))
                .frame(width: 80, height: 80)
                .offset(x: -28, y: -32)
                .blur(radius: 18)

            Circle()
                .fill(Color(hex: 0xC1452A).opacity(0.5))
                .frame(width: 70, height: 70)
                .offset(x: 32, y: 28)
                .blur(radius: 16)

            Circle()
                .fill(Color(hex: 0x6BA13A).opacity(0.35))
                .frame(width: 50, height: 50)
                .offset(x: -20, y: 40)
                .blur(radius: 14)

            // Play glyph at center.
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .offset(x: 1.5)
            }

            // Top chrome: source dot + duration.
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.white)
                            .frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 7.5, weight: .black, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.black.opacity(0.45))
                    )

                    Spacer()

                    Text("0:32")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.black.opacity(0.45))
                        )
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()
            }

            // Bottom chrome: avatar + handle.
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xFFB35A), Color(hex: 0xE76F2A)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle().stroke(.white, lineWidth: 1)
                        )
                        .frame(width: 18, height: 18)

                    Text("@chef.luna")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
    }
}

// MARK: - Recipe card (right)

/// Compact recipe card with an orange header bar (no full pasta art —
/// kept minimal to keep the right card visually paired with the video
/// card on the left). Title + time chip + 3 ingredient rows.
private struct MiniRecipeCardArt: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top warm band — communicates "cooking".
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xFFD9A8),
                        Color(hex: 0xF5A056),
                        Color(hex: 0xE76F2A)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [Color.white.opacity(0.20), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )

                // Tiny stylised plate — nest of pasta evoked by 3 thin arcs.
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 50, height: 50)
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 42, height: 42)
                    ForEach(0..<3, id: \.self) { i in
                        let size = CGFloat(14 + i * 8)
                        Circle()
                            .stroke(
                                Color(hex: 0xFFF0D6).opacity(0.75 - Double(i) * 0.18),
                                lineWidth: 1.4
                            )
                            .frame(width: size, height: size)
                    }
                }

                // Time chip top-right.
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("15 min")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.30))
                        )
                    }
                    Spacer()
                }
                .padding(7)
            }
            .frame(height: height * 0.42)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pâtes au pesto")
                    .font(.system(size: 13.5, weight: .bold, design: .serif))
                    .foregroundStyle(Color(hex: 0x2A1B12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Rectangle()
                    .fill(Color(hex: 0xEFE3CE))
                    .frame(height: 0.6)
                    .padding(.vertical, 1)

                VStack(alignment: .leading, spacing: 4) {
                    miniIngredient("200 g de pâtes")
                    miniIngredient("30 g de basilic frais")
                    miniIngredient("40 g de parmesan")
                }

                HStack(spacing: 3) {
                    Text("+ 4 ingrédients")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(CooksyTheme.primaryAccent)
                .padding(.top, 1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xEFE3CE), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 14)
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.18), radius: 28, y: 0)
    }

    private func miniIngredient(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CooksyTheme.primaryAccent)
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x3A2A1F))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

// MARK: - Bridge between the two cards

/// Pulsing orange capsule with a wand glyph, plus 3 magic-dust
/// particles travelling left → right on a continuous loop. The bridge
/// is the visual metaphor for the AI transformation.
private struct TransformationBridge: View {
    let pulse: Double
    let dustPhase: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack {
            // Magic dust particles travelling across.
            ForEach(0..<3, id: \.self) { i in
                let phase = (dustPhase + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                let progress = phase
                let x = -width / 2 + width * progress
                let y = sin(Double(progress) * .pi * 2) * 6
                let opacity = sin(Double(progress) * .pi)

                Circle()
                    .fill(CooksyTheme.primaryAccentGlow)
                    .frame(width: 4, height: 4)
                    .offset(x: x, y: y)
                    .opacity(opacity * 0.9)
                    .blur(radius: 0.5)
            }

            // Soft halo behind the badge.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentGlow.opacity(0.5 + pulse * 0.3),
                            CooksyTheme.primaryAccentGlow.opacity(0)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .blur(radius: 6)

            // Badge.
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 36, height: 36)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 10, y: 4)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(1.0 + CGFloat(pulse) * 0.06)
        }
    }
}
