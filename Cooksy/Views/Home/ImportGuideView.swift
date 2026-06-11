import SwiftUI

/// 5-step swipeable guide that teaches the user how to import a recipe from
/// TikTok / Instagram via the iOS share sheet (Cooksy share extension).
///
/// Pattern mirrors `PostPaywallTutorialView`: TabView .page, animated dots,
/// "Passer" + CTA. All illustrations are 100 % SwiftUI — no static
/// screenshots — so they render crisp at any density and stay maintainable.
struct ImportGuideView: View {
    var onClose: () -> Void

    @State private var index: Int = 0

    private let slides: [ImportGuideSlide] = [
        ImportGuideSlide(
            illustration: .videoFeed,
            title: "Trouve une recette qui te plaît",
            body: "TikTok, Instagram, YouTube — n'importe quelle vidéo cuisine."
        ),
        ImportGuideSlide(
            illustration: .shareTap,
            title: "Appuie sur le bouton Partager",
            body: "L'icône avec la flèche vers le haut, généralement à droite de la vidéo."
        ),
        ImportGuideSlide(
            illustration: .shareSheetMore,
            title: "Cooksy n'apparaît pas ? Appuie sur \"Plus\"",
            body: "Active Cooksy une fois et il restera dans ta feuille de partage."
        ),
        ImportGuideSlide(
            illustration: .shareSheetCooksy,
            title: "Choisis Cooksy",
            body: "On ouvre l'app et on commence l'extraction automatiquement."
        ),
        ImportGuideSlide(
            illustration: .recipeExtracted,
            title: "Ta recette structurée arrive",
            body: "Ingrédients, étapes, durées — prêts à cuisiner."
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let hPadding = Layout.horizontalPadding(for: width)
            let topPad = max(Layout.topPadding(for: width), 12)
            ZStack {
                CooksyTheme.ambientGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar — close (X) + skip
                    HStack {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(CooksyTheme.elevatedSurface))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: close) {
                            Text("Passer")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, hPadding)
                    .padding(.top, topPad)

                    // Pager
                    TabView(selection: $index) {
                        ForEach(Array(slides.enumerated()), id: \.offset) { pair in
                            ImportGuideSlideView(
                                slide: pair.element,
                                availableSize: proxy.size
                            )
                            .tag(pair.offset)
                            .padding(.horizontal, hPadding + 4)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                    // Dots — capsule grows on selection
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
                        Text(isLastSlide ? "C'est parti" : "Suivant")
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
                    .padding(.horizontal, hPadding + 8)
                    .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 12))
                    .frame(maxWidth: Layout.maxContentWidth)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var isLastSlide: Bool { index == slides.count - 1 }

    private func advance() {
        OnboardingHaptics.light()
        if isLastSlide {
            close()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                index += 1
            }
        }
    }

    private func close() {
        OnboardingHaptics.selection()
        onClose()
    }
}

// MARK: - Slide model

private struct ImportGuideSlide {
    enum Illustration {
        case videoFeed
        case shareTap
        case shareSheetMore
        case shareSheetCooksy
        case recipeExtracted
    }

    let illustration: Illustration
    let title: String
    let body: String
}

// MARK: - Slide view

private struct ImportGuideSlideView: View {
    let slide: ImportGuideSlide
    let availableSize: CGSize

    var body: some View {
        let illustrationH = Layout.illustrationHeight(for: availableSize)
        let isTablet = Layout.DeviceClass.from(width: availableSize.width).isTablet
        let titleSize: CGFloat = isTablet ? 30 : 24
        let bodySize: CGFloat = isTablet ? 17 : 14
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            illustration
                .frame(maxHeight: illustrationH)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 4)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.system(size: titleSize, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)

                Text(slide.body)
                    .font(.system(size: bodySize, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: Layout.maxContentWidth)

            Spacer(minLength: 12)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch slide.illustration {
        case .videoFeed:        VideoFeedIllustration()
        case .shareTap:         ShareTapIllustration()
        case .shareSheetMore:   ShareSheetMoreIllustration()
        case .shareSheetCooksy: ShareSheetCooksyIllustration()
        case .recipeExtracted:  RecipeExtractedIllustration()
        }
    }
}

// MARK: - Illustration 1: video feed with share button highlighted

private struct VideoFeedIllustration: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Phone-frame "video"
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: 0x1A1A1A))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xE86A33).opacity(0.55),
                            Color(hex: 0xF7B05C).opacity(0.35),
                            Color(hex: 0x4A4035).opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .frame(width: 200, height: 300)
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 12)

            // Centered play button
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 56, height: 56)
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .offset(x: 2)
            }

            // Right-side TikTok-style action column (like / comment / share)
            VStack(spacing: 16) {
                actionIcon(systemName: "heart.fill", subtitle: "12k")
                actionIcon(systemName: "bubble.right.fill", subtitle: "381")
                ZStack {
                    actionIcon(systemName: "arrowshape.turn.up.right.fill", subtitle: "Partager", highlighted: true)

                    // Pulsing ring to draw the eye to the share button
                    Circle()
                        .stroke(CooksyTheme.ctaOrange, lineWidth: 3)
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulse
                        )
                        .offset(y: -8)
                }
            }
            .offset(x: 80, y: 50)
        }
        .onAppear { pulse = true }
        .frame(maxWidth: .infinity)
    }

    private func actionIcon(systemName: String, subtitle: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(highlighted ? CooksyTheme.accentGradient : LinearGradient(colors: [Color.white.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)

                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(subtitle)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Illustration 2: zoomed share button + finger tap

private struct ShareTapIllustration: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Big iOS-style share icon centered
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.elevatedSurface)
                        .frame(width: 180, height: 180)
                        .overlay(
                            Circle()
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                        .shadow(color: CooksyTheme.softShadow, radius: 18, y: 10)

                    // Pulsing ring
                    Circle()
                        .stroke(CooksyTheme.ctaOrange, lineWidth: 3)
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulse ? 1.18 : 1.0)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: pulse
                        )

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 80, weight: .medium))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .offset(y: -6)
                }

                Text("Bouton Partager")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(CooksyTheme.elevatedSurface)
                            .overlay(Capsule().stroke(CooksyTheme.stroke, lineWidth: 1))
                    )
            }

            // Finger tap overlay (bottom right of share icon)
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
                .offset(x: 50, y: 32)
        }
        .onAppear { pulse = true }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Illustration 3: share sheet with "Plus" highlighted

private struct ShareSheetMoreIllustration: View {
    @State private var pulse = false

    var body: some View {
        ShareSheetMockup(highlight: .more, pulse: pulse)
            .onAppear { pulse = true }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Illustration 4: share sheet with Cooksy highlighted

private struct ShareSheetCooksyIllustration: View {
    @State private var pulse = false

    var body: some View {
        ShareSheetMockup(highlight: .cooksy, pulse: pulse)
            .onAppear { pulse = true }
            .frame(maxWidth: .infinity)
    }
}

/// Shared iOS share-sheet mockup used by slides 3 & 4. Renders the rounded
/// white sheet, a row of four "app" icons, and three action rows. The
/// `highlight` parameter draws a pulsing orange ring around either the
/// Cooksy app icon (slide 4) or the "Plus" action row (slide 3).
private struct ShareSheetMockup: View {
    enum Highlight { case more, cooksy }
    let highlight: Highlight
    let pulse: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(white: 0.86))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            // Title
            Text("Partager")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.top, 12)

            // App icons row
            HStack(spacing: 16) {
                appIcon(letter: "M", color: Color(hex: 0x34C759))
                appIcon(letter: "W", color: Color(hex: 0x25D366))
                appIcon(
                    letter: "C",
                    color: nil,
                    asset: "HeaderLogo",
                    isHighlighted: highlight == .cooksy
                )
                appIcon(letter: "T", color: Color(hex: 0x1DA1F2))
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            Rectangle().fill(CooksyTheme.dividerSubtle)
                .frame(height: 1)
                .padding(.top, 18)

            // Action rows
            actionRow(systemName: "doc.on.doc", title: "Copier le lien")
            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1).padding(.leading, 56)

            actionRow(systemName: "bookmark", title: "Ajouter aux favoris")
            Rectangle().fill(CooksyTheme.dividerSubtle).frame(height: 1).padding(.leading, 56)

            actionRow(
                systemName: "ellipsis.circle",
                title: "Plus…",
                isHighlighted: highlight == .more
            )

            // Finger tap overlay anchored to the highlighted target
            if highlight == .more {
                HStack {
                    Spacer()
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .shadow(color: Color.black.opacity(0.18), radius: 5, y: 3)
                        .padding(.trailing, 28)
                }
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)
        .padding(.horizontal, 8)
    }

    /// One app icon in the horizontal row. Either a generic letter capsule
    /// (placeholder app) or, when `asset` is provided, the real Cooksy
    /// header logo wrapped in our brand gradient ring.
    private func appIcon(
        letter: String,
        color: Color?,
        asset: String? = nil,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            ZStack {
                if let asset {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.background)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(asset)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(CooksyTheme.stroke.opacity(isHighlighted ? 0 : 1), lineWidth: 1)
                        )
                } else if let color {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(letter)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        )
                }

                if isHighlighted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.ctaOrange, lineWidth: 3)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .opacity(pulse ? 0 : 0.85)
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: pulse
                        )

                    if asset != nil {
                        // Glow halo
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CooksyTheme.accentGradient.opacity(0.45))
                            .frame(width: 56, height: 56)
                            .blur(radius: 14)
                    }
                }
            }
            Text(asset != nil ? "Cooksy" : appLabel(for: letter))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
                .lineLimit(1)
        }
    }

    private func appLabel(for letter: String) -> String {
        switch letter {
        case "M": return "Messages"
        case "W": return "WhatsApp"
        case "T": return "Twitter"
        default:  return ""
        }
    }

    private func actionRow(systemName: String, title: String, isHighlighted: Bool = false) -> some View {
        ZStack {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CooksyTheme.ctaOrange, lineWidth: 2.5)
                    .padding(.horizontal, 8)
                    .scaleEffect(pulse ? 1.02 : 1.0)
                    .opacity(pulse ? 0.55 : 1)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }

            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Illustration 5: extracted recipe card

private struct RecipeExtractedIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            // "Importé" pill on top
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Recette importée")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(0.4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(hex: 0x4A8C2F))
                )
                .shadow(color: Color(hex: 0x2D5A1B).opacity(0.4), radius: 6, y: 3)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            // Recipe card
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

#Preview {
    ImportGuideView(onClose: {})
}
