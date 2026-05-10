import StoreKit
import SwiftUI

/// A1.5 — Soft request for an App Store rating, sandwiched between the welcome
/// hero and the demo. The screen is engineered to maximise the chance of an
/// honest 5-star tap without ever blocking the flow:
///   • social proof pill at the top primes the user
///   • a real-looking testimonial card builds trust
///   • the stars surface a live "mood" caption that reacts to the tap
///   • the primary CTA invites a rating before the user has touched a star
///   • a soft "Plus tard" always lets them skip
struct AppReviewView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.requestReview) private var requestReview
    @State private var hoveredStar: Int = 0
    @State private var lockedStar: Int = 0
    @State private var appeared = false
    @State private var sparkle = false
    @State private var promptShown = false
    @AppStorage("cooksy.onboarding.didAskReview") private var didAskReview: Bool = false

    private let moodLabels: [String] = [
        "Tape une étoile pour nous noter",
        "Aïe… on peut faire mieux.",
        "Pas mal — merci pour ton retour",
        "Sympa, ça nous touche.",
        "Génial — on adore !",
        "Wow, on adore tellement."
    ]

    private var currentMood: String {
        let idx = max(0, min(5, max(hoveredStar, lockedStar)))
        return moodLabels[idx]
    }

    private var hasInteracted: Bool { lockedStar > 0 || promptShown }

    var body: some View {
        ZStack {
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                let heroDiameter = min(geo.size.width * 0.68, 240)

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            OnboardingHaptics.selection()
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .frame(width: 38, height: 38)
                                .background(
                                    Circle()
                                        .fill(CooksyTheme.elevatedSurface)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 4)

                    socialProofPill
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.05), value: appeared)

                    Spacer(minLength: 12)

                    heroBlock(diameter: heroDiameter)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.15), value: appeared)

                    Spacer(minLength: 12)

                    copyBlock
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.28), value: appeared)

                    testimonialCard
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.4), value: appeared)

                    starsBlock
                        .padding(.bottom, 12)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.45).delay(0.52), value: appeared)

                    Spacer(minLength: 6)

                    ctas
                        .padding(.bottom, 26)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.65), value: appeared)
                }
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
            }
        }
        .onAppear {
            appeared = true
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
    }

    // MARK: - Social proof pill

    private var socialProofPill: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryAccentGlow)
                }
            }
            Text("4.9 sur l'App Store")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Circle()
                .fill(CooksyTheme.stroke)
                .frame(width: 3, height: 3)
            Text("12 000+ cuisiniers")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 8, y: 4)
    }

    // MARK: - Hero block

    private func heroBlock(diameter: CGFloat) -> some View {
        let scale = diameter / 280
        let centerSize = 104 * scale
        let positions: [(CGFloat, CGFloat)] = [
            (-110, -70), (96, -86), (-86, 52),
            (100, 60), (-70, -8), (84, 4)
        ]

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CooksyTheme.primaryAccentSoft.opacity(sparkle ? 0.95 : 0.7),
                            CooksyTheme.primaryAccentSoft.opacity(0)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 160
                    )
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: 6)

            ForEach(0..<6, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentGlow.opacity(0.85))
                    .offset(x: positions[i].0 * scale, y: positions[i].1 * scale)
                    .opacity(sparkle ? 1 : 0.35)
                    .scaleEffect(sparkle ? 1 : 0.7)
            }

            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: centerSize, height: centerSize)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 22, y: 12)
                Image(systemName: "heart.fill")
                    .font(.system(size: 44 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(sparkle ? 1.06 : 1)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Copy

    private var copyBlock: some View {
        VStack(spacing: 8) {
            Text("Tu nous fais\ngrandir.")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            Text("Une note honnête nous aide énormément à faire connaître Cooksy. Ça prend deux secondes — promis.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Testimonial

    private var testimonialCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [CooksyTheme.primaryAccent, CooksyTheme.primaryAccentGlow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                Text("L")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Léa M.")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryAccentGlow)
                        }
                    }
                }
                Text("« Plus besoin de revoir 10 fois la vidéo — la recette est là, prête à cuisiner. Un vrai bijou. »")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }

    // MARK: - Stars

    private var starsBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { idx in
                    let isFilled = idx <= max(hoveredStar, lockedStar)
                    Button {
                        OnboardingHaptics.medium()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            lockedStar = idx
                        }
                        didAskReview = true
                        promptShown = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            requestReview()
                        }
                    } label: {
                        Image(systemName: isFilled ? "star.fill" : "star")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(
                                isFilled
                                    ? AnyShapeStyle(CooksyTheme.accentGradient)
                                    : AnyShapeStyle(CooksyTheme.secondaryText.opacity(0.45))
                            )
                            .scaleEffect(idx == lockedStar ? 1.18 : 1)
                            .shadow(
                                color: isFilled ? CooksyTheme.primaryAccent.opacity(0.35) : .clear,
                                radius: 10, y: 4
                            )
                            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isFilled)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(currentMood)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .id(currentMood)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(.easeInOut(duration: 0.2), value: currentMood)
    }

    // MARK: - CTAs

    private var ctas: some View {
        VStack(spacing: 12) {
            Button(action: {
                OnboardingHaptics.medium()
                if hasInteracted {
                    onContinue()
                } else {
                    didAskReview = true
                    promptShown = true
                    requestReview()
                }
            }) {
                HStack(spacing: 8) {
                    if !hasInteracted {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(hasInteracted ? "Continuer" : "Noter Cooksy")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
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
                onContinue()
            }) {
                Text(hasInteracted ? "Passer" : "Plus tard")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}
