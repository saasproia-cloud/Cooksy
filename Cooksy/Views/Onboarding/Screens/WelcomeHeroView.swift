import SwiftUI

/// A1 — Welcome hero.
/// Central "phone" rendered entirely in SwiftUI mocks a looping vertical
/// feed to make the product promise (TikTok/Reel → recipe) tangible before
/// the user even taps anything.
struct WelcomeHeroView: View {
    let onContinue: () -> Void
    let onExistingAccount: () -> Void

    @State private var heroAppeared = false

    var body: some View {
        ZStack {
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                PhoneMockup()
                    .frame(maxWidth: 200)
                    .scaleEffect(heroAppeared ? 1 : 0.9)
                    .opacity(heroAppeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.1), value: heroAppeared)

                Spacer(minLength: 24)

                // Width is pinned to UIScreen.main.bounds.width minus the desired
                // 22pt padding on each side. SwiftUI's layout was repeatedly
                // ignoring `.padding(.horizontal)` on this particular VStack
                // (we confirmed with a debug Rectangle that even an explicit
                // padded shape was rendering edge-to-edge), so we bypass the
                // padding chain entirely with an absolute frame width.
                let textWidth = max(UIScreen.main.bounds.width - 44, 0)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Transforme n'importe quelle vidéo en recette parfaite.")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)

                    Text("Colle un lien TikTok, Instagram ou YouTube — on extrait la recette en 15 secondes. Tu n'as plus qu'à cuisiner.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: textWidth, alignment: .leading)
                .padding(.bottom, 24)
                .opacity(heroAppeared ? 1 : 0)
                .offset(y: heroAppeared ? 0 : 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.25), value: heroAppeared)

                VStack(spacing: 14) {
                    Button(action: {
                        OnboardingHaptics.medium()
                        onContinue()
                    }) {
                        Text("Commencer")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.accentGradient)
                            )
                            .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 10)
                    }
                    .buttonStyle(CooksyTheme.pressScale())

                    Button(action: {
                        OnboardingHaptics.selection()
                        onExistingAccount()
                    }) {
                        HStack(spacing: 4) {
                            Text("Tu as déjà un compte ?")
                                .foregroundStyle(CooksyTheme.secondaryText)
                            Text("Se connecter")
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
                .opacity(heroAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.55), value: heroAppeared)
            }
            // Lock the outer VStack to the ZStack's full width. Without this
            // the VStack can size to its tightest child and ZStack's default
            // centre alignment causes children with `.frame(maxWidth:.infinity)`
            // to bleed past both screen edges on iPhone 17 Pro.
            .frame(maxWidth: .infinity)
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
            let drift = CGFloat((sin(t * 0.4) + 1) * 0.5) // 0…1

            ZStack {
                CooksyTheme.ambientGradient

                // Warm orange blob that drifts
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

                // Second warm blob bottom-right
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
            // Without this, the ZStack reports the natural size of the
            // 540×540 blob circles to its parent. Any consumer placing
            // this background inside another ZStack alongside a VStack
            // with `.frame(maxWidth: .infinity)` ends up with the VStack
            // bleeding past both screen edges. Pinning the background
            // to its container fixes that at the source.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}

// MARK: - Phone mockup

/// Phone mockup that visualises the "video → clean recipe" promise: a small
/// TikTok-style video preview at the top, an orange "magic" arrow, and a
/// crisp recipe card filling the rest of the screen with a title, hero
/// gradient, ingredients, and steps. Pure SwiftUI — no image assets.
private struct PhoneMockup: View {
    @State private var sparklePulse = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = w * 2.05

            ZStack {
                // Outer phone frame
                RoundedRectangle(cornerRadius: w * 0.18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x1A1418), Color(hex: 0x070506)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color.black.opacity(0.28), radius: 30, y: 18)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.18), radius: 26, y: 0)

                // Inner bezel
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(Color.black)
                    .padding(w * 0.022)

                // Screen content
                PhoneScreen(sparklePulse: sparklePulse)
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous))
                    .padding(w * 0.05)

                // Dynamic island
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: w * 0.34, height: h * 0.034)
                    .offset(y: -h * 0.455)

                // Subtle glass highlight on the frame
                RoundedRectangle(cornerRadius: w * 0.18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1 / 2.05, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                sparklePulse = true
            }
        }
    }
}

private struct PhoneScreen: View {
    let sparklePulse: Bool

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let w = proxy.size.width

            ZStack {
                Color(hex: 0xFFF9F1)

                VStack(spacing: 0) {
                    Spacer().frame(height: h * 0.07) // top notch padding

                    // Source video chip
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.black.opacity(0.85)))
                        Text("tiktok.com/@chef")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x4A3F36))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(hex: 0xE9DCC8), lineWidth: 0.5)
                    )

                    // Magic arrow
                    VStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccent)
                            .scaleEffect(sparklePulse ? 1.15 : 0.95)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryAccent.opacity(0.7))
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                    // Recipe card
                    RecipeCardMock()
                        .padding(.horizontal, w * 0.06)

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct RecipeCardMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xF7B26A), Color(hex: 0xE76F2A)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Plated dish silhouette
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 44, height: 44)
                    ForEach(0..<6, id: \.self) { i in
                        let angle = Double(i) / 6 * 2 * .pi
                        Circle()
                            .fill(Color(hex: 0x6B8E3A).opacity(0.85))
                            .frame(width: 6, height: 6)
                            .offset(
                                x: CGFloat(cos(angle)) * 16,
                                y: CGFloat(sin(angle)) * 16
                            )
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text("15 min")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Title
            Text("Pasta au pesto")
                .font(.system(size: 12, weight: .bold, design: .serif))
                .foregroundStyle(Color(hex: 0x2A211B))
                .padding(.top, 8)

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 6, weight: .bold))
                Text("2 pers.")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                Circle()
                    .fill(Color(hex: 0xC8B89D))
                    .frame(width: 2, height: 2)
                Text("Facile")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color(hex: 0x8A7A65))
            .padding(.top, 2)

            // Ingredients section
            HStack(spacing: 4) {
                Rectangle()
                    .fill(CooksyTheme.primaryAccent)
                    .frame(width: 2, height: 8)
                    .clipShape(Capsule())
                Text("Ingrédients")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x2A211B))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 3) {
                IngredientLine(emoji: "🍝", text: "200g de pâtes")
                IngredientLine(emoji: "🌿", text: "30g de basilic frais")
                IngredientLine(emoji: "🧀", text: "40g de parmesan")
            }
            .padding(.top, 4)

            // Steps section
            HStack(spacing: 4) {
                Rectangle()
                    .fill(CooksyTheme.primaryAccent)
                    .frame(width: 2, height: 8)
                    .clipShape(Capsule())
                Text("Étapes")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x2A211B))
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                StepLine(number: 1, text: "Cuire les pâtes")
                StepLine(number: 2, text: "Mixer le pesto")
            }
            .padding(.top, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xEFE3CE), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct IngredientLine: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Text(emoji)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x4A3F36))
                .lineLimit(1)
        }
    }
}

private struct StepLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(Circle().fill(CooksyTheme.primaryAccent))
            Text(text)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x4A3F36))
                .lineLimit(1)
        }
    }
}
