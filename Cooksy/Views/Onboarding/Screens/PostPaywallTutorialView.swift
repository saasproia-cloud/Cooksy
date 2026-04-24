import SwiftUI

/// Mini onboarding tour that plays once after the paywall converts.
/// Teaches the user the 3 core loops: paste link, structured recipe, save.
/// Skippable at any time. Persisted via `@AppStorage("cooksy.hasSeenTutorial")`.
struct PostPaywallTutorialView: View {
    @AppStorage("cooksy.hasSeenTutorial") private var hasSeenTutorial: Bool = false

    @State private var index: Int = 0

    private let slides: [TutorialSlide] = [
        TutorialSlide(
            illustration: .pasteLink,
            title: "Colle un lien, on fait le reste.",
            body: "TikTok, Instagram Reels, YouTube Shorts — appuie sur le bouton + et colle n'importe quelle vidéo cuisine."
        ),
        TutorialSlide(
            illustration: .structuredRecipe,
            title: "Ta recette structurée en 15 secondes.",
            body: "Ingrédients précis, étapes numérotées, sections claires. Plus jamais besoin de re-scroller la vidéo."
        ),
        TutorialSlide(
            illustration: .savedForever,
            title: "Tout est sauvegardé.",
            body: "On range tes recettes dans ton carnet perso. Tu peux les organiser, faire ta liste de courses, cuisiner."
        )
    ]

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: skip button
                HStack {
                    Spacer()
                    Button(action: finish) {
                        Text("Passer")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Pager
                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { pair in
                        TutorialSlideView(slide: pair.element)
                            .tag(pair.offset)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Dots
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? CooksyTheme.ctaOrangeDark : CooksyTheme.stroke)
                            .frame(width: i == index ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: index)
                    }
                }
                .padding(.bottom, 16)

                // CTA
                Button(action: advance) {
                    Text(isLastSlide ? "Commencer à cuisiner" : "Suivant")
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
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private var isLastSlide: Bool { index == slides.count - 1 }

    private func advance() {
        OnboardingHaptics.light()
        if isLastSlide {
            finish()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                index += 1
            }
        }
    }

    private func finish() {
        OnboardingHaptics.selection()
        withAnimation(.easeInOut(duration: 0.3)) {
            hasSeenTutorial = true
        }
    }
}

// MARK: - Slide model

private struct TutorialSlide {
    enum Illustration {
        case pasteLink
        case structuredRecipe
        case savedForever
    }

    let illustration: Illustration
    let title: String
    let body: String
}

// MARK: - Slide view

private struct TutorialSlideView: View {
    let slide: TutorialSlide

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            illustration
                .frame(height: 280)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.85)

                Text(slide.body)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch slide.illustration {
        case .pasteLink:    PasteLinkIllustration()
        case .structuredRecipe: StructuredRecipeIllustration()
        case .savedForever: SavedForeverIllustration()
        }
    }
}

// MARK: - Illustrations (100% SwiftUI, no assets)

/// Slide 1: a "paste URL" mock bar with a link icon + TikTok URL.
private struct PasteLinkIllustration: View {
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Big rounded card with a mock URL bar inside
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)

                VStack(spacing: 14) {
                    // URL pill
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        Text("tiktok.com/@pastaqueen/8723…")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CooksyTheme.ctaOrange.opacity(0.35), lineWidth: 1)
                    )

                    // Big "+" action button
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.accentGradient)
                            .frame(width: 72, height: 72)
                            .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 16, y: 8)
                            .scaleEffect(pulse ? 1.05 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: pulse
                            )

                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(22)
            }
            .frame(height: 220)
            .padding(.horizontal, 20)
        }
        .onAppear { pulse = true }
    }
}

/// Slide 2: a mini recipe card with title + 3 ingredient rows + 2 step rows.
private struct StructuredRecipeIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bowl saumon teriyaki")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("2 portions · 25 min")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                Spacer()
            }

            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1)

            Text("INGRÉDIENTS")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(CooksyTheme.secondaryText)

            ingredientRow("200 g", "saumon frais")
            ingredientRow("3 c. à s.", "sauce soja")
            ingredientRow("1 tasse", "riz jasmin")

            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1)

            Text("ÉTAPES")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(CooksyTheme.secondaryText)

            stepRow("1", "Cuire le riz, réserver au chaud.")
            stepRow("2", "Saisir le saumon 2 min de chaque côté.")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
        .padding(.horizontal, 12)
    }

    private func ingredientRow(_ qty: String, _ name: String) -> some View {
        HStack(spacing: 10) {
            Text(qty)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .frame(width: 64, alignment: .leading)
            Text(name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Spacer()
        }
    }

    private func stepRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft)
                    .frame(width: 20, height: 20)
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

/// Slide 3: a cookbook-style list of saved recipes with a bookmark badge.
private struct SavedForeverIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mes recettes")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("12 recettes · 3 livres")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                Spacer()
            }

            savedRow(icon: "flame.fill", tint: Color(hex: 0xE86A33), title: "Pasta au pesto", sub: "2 portions · 15 min")
            savedRow(icon: "leaf.fill", tint: Color(hex: 0x8FB93A), title: "Salade César", sub: "1 portion · 10 min")
            savedRow(icon: "fish.fill", tint: Color(hex: 0x4A90E2), title: "Bowl saumon teriyaki", sub: "2 portions · 25 min")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
        .padding(.horizontal, 12)
    }

    private func savedRow(icon: String, tint: Color, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(sub)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.background)
        )
    }
}
