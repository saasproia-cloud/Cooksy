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
            // Subtle ambient background with slow gradient drift
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                PhoneMockup()
                    .frame(maxWidth: 220)
                    .scaleEffect(heroAppeared ? 1 : 0.9)
                    .opacity(heroAppeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.1), value: heroAppeared)

                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 14) {
                    // Title is rendered as 3 separate Text views inside a
                    // VStack instead of a single multi-line Text. This is the
                    // bulletproof approach: each line is short enough to fit
                    // on every iPhone width (even SE @ 320pt usable), so the
                    // SwiftUI text engine has zero opportunity to overflow.
                    // Earlier attempts with `\n` + fixedSize(.vertical) still
                    // produced horizontal clipping on iPhone 17 Pro, so we
                    // stop relying on the wrap engine entirely.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transforme")
                        Text("n'importe quelle vidéo")
                        Text("en recette parfaite.")
                    }
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Colle un lien TikTok, Instagram ou YouTube — on extrait la recette en 15 secondes. Tu n'as plus qu'à cuisiner.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
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
        }
    }
}

// MARK: - Phone mockup

/// Minimalist iPhone shape with a vertical feed of fake recipe "posts"
/// scrolling gently. The whole thing is pure SwiftUI — no assets.
private struct PhoneMockup: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = w * 1.95  // rough iPhone aspect ratio

            ZStack {
                RoundedRectangle(cornerRadius: w * 0.18, style: .continuous)
                    .fill(CooksyTheme.primaryText)
                    .shadow(color: Color.black.opacity(0.24), radius: 24, y: 14)

                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(Color.black)
                    .padding(w * 0.025)

                // Dynamic island
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: w * 0.32, height: h * 0.035)
                    .offset(y: -h * 0.46)

                // Screen content
                PhoneFeed()
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous))
                    .padding(w * 0.05)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1 / 1.95, contentMode: .fit)
    }
}

private struct PhoneFeed: View {
    @State private var offset: CGFloat = 0

    private let posts: [FakePost] = [
        FakePost(title: "PASTA AU PESTO 🌿", gradient: FakePost.warmGradient),
        FakePost(title: "BOWL SAUMON TERIYAKI", gradient: FakePost.oceanGradient),
        FakePost(title: "TACOS POULET LIME", gradient: FakePost.sunsetGradient)
    ]

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let itemHeight = h + 40 // full-screen posts

            VStack(spacing: 0) {
                ForEach(posts.indices, id: \.self) { idx in
                    FakePostView(post: posts[idx])
                        .frame(height: itemHeight)
                }
            }
            .offset(y: -offset)
            .onAppear {
                withAnimation(.linear(duration: Double(posts.count) * 4).repeatForever(autoreverses: false)) {
                    offset = itemHeight * CGFloat(posts.count - 1)
                }
            }
        }
    }
}

private struct FakePost {
    let title: String
    let gradient: LinearGradient

    static let warmGradient = LinearGradient(colors: [Color(hex: 0xF29434), Color(hex: 0xC8481E)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let oceanGradient = LinearGradient(colors: [Color(hex: 0x5F8636), Color(hex: 0x9AC95B)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sunsetGradient = LinearGradient(colors: [Color(hex: 0xF28E26), Color(hex: 0xF7D15B)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct FakePostView: View {
    let post: FakePost

    var body: some View {
        ZStack {
            post.gradient

            // Circular plate silhouette (no blur — cheaper on GPU)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 160, height: 160)

            VStack(alignment: .leading) {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@chef.co")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(post.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill").foregroundStyle(.white).font(.system(size: 12))
                        Image(systemName: "bubble.right.fill").foregroundStyle(.white).font(.system(size: 12))
                        Image(systemName: "square.and.arrow.up.fill").foregroundStyle(.white).font(.system(size: 12))
                    }
                }
                .padding(10)
            }
        }
    }
}
