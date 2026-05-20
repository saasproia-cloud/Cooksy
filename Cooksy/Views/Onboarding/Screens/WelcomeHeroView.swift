import SwiftUI

/// A1 — Welcome hero ("La Transformation" redesign).
///
/// This is the very first screen a fresh install sees, so the layout
/// is engineered around one job: communicate the product promise
/// (TikTok/Reel video → clean recipe) in under a second, without
/// asking the user to read.
///
/// The hero visual is the message: two phone-card mockups separated by
/// a glowing gold arrow. Left card = the messy source (video frame +
/// play icon + caption blur). Right card = the result (recipe with
/// title, ingredients, step). The arrow shimmers once on entry. The
/// whole composition tilts in 3D for depth.
///
/// Layout note: mirrors the historical AppReviewView pattern that has
/// always centred correctly on iPhone 17 Pro — no ScrollView,
/// GeometryReader → VStack → `.frame(maxWidth: 380)` →
/// `.frame(maxWidth: .infinity)` → `.padding(.horizontal, X)`. The
/// ScrollView wrapper was the actual source of historical asymmetric
/// layout — `.frame(maxWidth: .infinity, alignment: .center)` does not
/// propagate the expected width inside a ScrollView and content drifts
/// off-centre.
struct WelcomeHeroView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        // No background here — `OnboardingFlow` provides a single shared
        // `AnimatedAmbientBackground()` for the whole flow, so we stay
        // transparent and let it bleed through. Avoids running two
        // 30fps TimelineViews during the screen-to-screen crossfade.
        GeometryReader { geo in
            let hPad = Layout.horizontalPadding(for: geo)

            VStack(spacing: 0) {
                Spacer(minLength: 18)

                wordmark
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -6)

                Spacer(minLength: 18)

                TransformationHero(appeared: appeared, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 22)

                titleBlock
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)

                Spacer(minLength: 14)

                ratingPill
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                Spacer(minLength: 22)

                ctaButton
                    .opacity(appeared ? 1 : 0)

                secureFooter
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, hPad)
            // Single, gentle one-shot cascade. Reduce Motion users get
            // instant content (handled in `.onAppear` below).
            .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.55), value: appeared)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                // Slight delay so the entrance reads as deliberate, not
                // as a "missed frame" right after the launch screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.18), radius: 8, y: 3)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }

            Text("Cooksy")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .tracking(0.5)
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.78))
        }
    }

    // MARK: - Title

    /// Editorial title with one word coloured in the brand accent.
    /// Built from three concatenated `Text` views so we get rich
    /// styling without losing native text rendering (no SwiftUI
    /// HStack hacks that break line-breaks on narrow widths).
    private var titleBlock: some View {
        VStack(spacing: 12) {
            (
                Text("Scrolle la vidéo.\n")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                +
                Text("Cuisine")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryAccent)
                +
                Text(" la recette.")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
            )
            .multilineTextAlignment(.center)
            .lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true)

            Text("La seule app qui transforme tes TikToks food\nen recettes nettes, prêtes à cuisiner.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Rating pill

    private var ratingPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }

            Text("4,9")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Circle()
                .fill(CooksyTheme.stroke)
                .frame(width: 3, height: 3)

            Text("+12 000 cuisiniers")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.85))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.softShadow, radius: 8, y: 3)
        )
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button(action: {
            OnboardingHaptics.medium()
            onContinue()
        }) {
            HStack(spacing: 8) {
                Text("Démarrer la magie")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.34), radius: 12, y: 6)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Secure footer

    /// Sober reassurance line. Account creation only happens at the end
    /// of onboarding (via Apple Sign In), so we make that explicit here
    /// to lower the perceived commitment of tapping "Démarrer".
    private var secureFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
            Text("Aucun compte requis pour commencer")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }
}

// MARK: - Transformation hero

/// The signature visual of the welcome screen: a "video card" on the
/// left morphs into a "recipe card" on the right, separated by an
/// animated gold arrow. Tells the entire product story in one frame.
///
/// All animations are **one-shot** (no `.repeatForever`) — they fire
/// once on appear via the `appeared` flag and then settle. Live
/// breathing is delegated to the shared `AnimatedAmbientBackground`
/// behind the whole flow, so this view costs nothing while idle.
private struct TransformationHero: View {
    let appeared: Bool
    let reduceMotion: Bool

    private let cardWidth: CGFloat = 118
    private let cardHeight: CGFloat = 178

    var body: some View {
        ZStack {
            // Soft warm glow behind the composition — static, no
            // timeline. Adds depth without GPU cost.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentSoft.opacity(0.75),
                            CooksyTheme.primaryAccentSoft.opacity(0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 320, height: 220)
                .blur(radius: 18)
                .opacity(appeared ? 1 : 0.4)

            HStack(spacing: 0) {
                videoCard
                    .offset(x: appeared ? 0 : -40)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(0.05),
                               value: appeared)

                arrow
                    .frame(width: 56)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72).delay(0.28),
                               value: appeared)

                recipeCard
                    .offset(x: appeared ? 0 : 40)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(0.18),
                               value: appeared)
            }
        }
        .frame(height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Une vidéo TikTok transformée en recette propre")
    }

    // MARK: Left card — the "before" (video)

    private var videoCard: some View {
        ZStack {
            // Food-toned gradient background — a fake video frame.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xC8481E),
                            Color(hex: 0xF29434),
                            Color(hex: 0xF7D15B)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Diagonal sheen — pure decoration, suggests video light.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )

            VStack(spacing: 0) {
                // Top chrome: tiny "TikTok-style" handle row.
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 12, height: 12)
                    Text("@chef")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer()
                    Text("0:42")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer()

                // Center play icon.
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color(hex: 0xC8481E))
                        .offset(x: 1)
                }

                Spacer()

                // Bottom: blurred caption strip to suggest text we
                // can't decipher — the very problem Cooksy solves.
                VStack(alignment: .leading, spacing: 3) {
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 60, height: 4)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color(hex: 0xC8481E, opacity: 0.28), radius: 18, y: 12)
        // Tilt left into the page for depth.
        .rotation3DEffect(
            .degrees(appeared ? -8 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6
        )
        .rotationEffect(.degrees(appeared ? -3 : 0))
    }

    // MARK: Center — the magic

    private var arrow: some View {
        ZStack {
            // Two sparkles flanking the arrow — static positions,
            // animated only on appear.
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentGlow)
                .offset(x: -2, y: -22)
                .opacity(appeared ? 1 : 0)

            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentGlow.opacity(0.85))
                .offset(x: 14, y: 18)
                .opacity(appeared ? 1 : 0)

            // The arrow itself: thin line + chevron. We draw it with
            // an SF Symbol stacked on a gold capsule for the shimmer.
            ZStack {
                Capsule()
                    .fill(CooksyTheme.goldShimmer)
                    .frame(width: 36, height: 5)
                    .shadow(color: CooksyTheme.primaryAccentGlow.opacity(0.5), radius: 8, y: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    .offset(x: 20)
            }
        }
    }

    // MARK: Right card — the "after" (recipe)

    private var recipeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header line: tiny dish icon + meta.
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.primaryAccentSoft)
                        .frame(width: 14, height: 14)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(CooksyTheme.primaryAccentStrong)
                }
                Text("Pad Thai")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            // Ingredient bullets.
            VStack(alignment: .leading, spacing: 5) {
                ingredientRow("200 g de nouilles")
                ingredientRow("2 c. à s. de sauce")
                ingredientRow("1 œuf, crevettes")
            }

            // A faint divider for the step preview.
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(height: 1)
                .padding(.vertical, 2)

            // One step preview, truncated.
            HStack(alignment: .top, spacing: 5) {
                Text("1")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(CooksyTheme.primaryAccent))
                Text("Faire revenir l'ail puis…")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: CooksyTheme.shadow, radius: 18, y: 12)
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.10), radius: 22, y: 0)
        // Tilt right into the page — mirror of the video card so the
        // pair reads as a symmetric "before / after" pair.
        .rotation3DEffect(
            .degrees(appeared ? 8 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6
        )
        .rotationEffect(.degrees(appeared ? 3 : 0))
    }

    private func ingredientRow(_ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(CooksyTheme.primaryAccentGlow)
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.82))
                .lineLimit(1)
        }
    }
}

// MARK: - Animated background (shared)

/// Subtle gradient "breathing" background via TimelineView. Mounted
/// **once** at the `OnboardingFlow` level so it persists across screen
/// transitions (we used to remount one per screen, which doubled the
/// GPU cost during the cross-fade — measurable hitch on the
/// welcome → appReview → demo path).
///
/// Tuning (May 2026): refresh rate dropped from 30fps → 20fps, blur
/// radii halved (20/24 → 12/14), circle sizes shrunk (520/540 → 420/440).
/// The drift is sinusoidal so 20fps reads identically to 30fps in
/// motion, and shrinking the blur kernel is the single biggest GPU win
/// available on this view.
struct AnimatedAmbientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
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
                            endRadius: 230
                        )
                    )
                    .frame(width: 420, height: 420)
                    .offset(x: -100 + drift * 60, y: -240 + drift * 40)
                    .blur(radius: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.warmCard.opacity(0.65),
                                CooksyTheme.warmCard.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 250
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: 120 - drift * 40, y: 300 - drift * 60)
                    .blur(radius: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}
