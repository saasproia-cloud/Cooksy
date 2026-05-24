import SwiftUI

/// Full-screen "shock & awe" takeover that fires when a fresh gift cycle
/// becomes available after a 7-day cooldown — i.e. the user lost their
/// previous claim window, came back later, and a new mini-game is now
/// queued up. The teaser card on Home already telegraphs this, but a
/// returning user deserves a bigger moment than a scroll-into-view card:
/// the goal is for the gift to literally explode onto the screen the
/// moment they re-open the app.
///
/// Visually: dark gradient, radial light beams, continuous confetti
/// shower, a large opening gift box, the upcoming game's name + glyph,
/// and a single high-contrast CTA. The user can:
///   • Tap the CTA → `onPlay` (host opens the mini-game).
///   • Tap the X    → `onDismiss` (acknowledged so it doesn't re-fire).
/// Both routes acknowledge the celebration in the offers service so the
/// user doesn't get hit with the takeover every cold start.
struct GiftNewCycleHypeView: View {
    @ObservedObject var offers: PremiumOffersService
    let onPlay: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var lidLift = false
    @State private var glow = false
    @State private var ringPulse = false
    @State private var beamSpin = false
    @State private var confettiSeed: Date = Date()

    var body: some View {
        ZStack {
            background
            beams
            confetti
            content
            closeButton
        }
        .onAppear {
            // Heavy haptic so the user feels something happen even
            // before the eye registers the confetti.
            OnboardingHaptics.success()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glow = true
                ringPulse = true
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.18)) {
                lidLift = true
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                beamSpin = true
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A0E2E),
                    Color(hex: 0x2A1352),
                    Color(hex: 0x0F0820)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft halo behind the centerpiece — anchors the eye.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xC084FC).opacity(glow ? 0.55 : 0.35),
                            Color(hex: 0xC084FC).opacity(0)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 320
                    )
                )
                .frame(width: 600, height: 600)
                .blur(radius: 40)
                .offset(y: -40)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Beams

    /// Radial light beams behind the gift — slowly rotating so the scene
    /// breathes. Pure decoration, no hit testing.
    private var beams: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10.0 * 360.0
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFFD8A8).opacity(0.0),
                                Color(hex: 0xFFD8A8).opacity(0.32),
                                Color(hex: 0xFFD8A8).opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 38, height: 480)
                    .rotationEffect(.degrees(angle))
                    .blur(radius: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rotationEffect(.degrees(beamSpin ? 360 : 0))
        .offset(y: -30)
        .allowsHitTesting(false)
    }

    // MARK: - Confetti shower

    private var confetti: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawConfetti(context: &context,
                                 size: size,
                                 t: timeline.date.timeIntervalSince(confettiSeed))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawConfetti(
        context: inout GraphicsContext,
        size: CGSize,
        t: TimeInterval
    ) {
        let pieces = 36
        for i in 0..<pieces {
            // Deterministic per-piece pseudo-random so the shower is
            // stable across frames but feels chaotic.
            let seed = Double(i) * 12.9898
            let r1 = fract(sin(seed) * 43758.5453)
            let r2 = fract(sin(seed + 1.3) * 43758.5453)
            let r3 = fract(sin(seed + 2.7) * 43758.5453)

            let fallDuration = 2.6 + r1 * 2.0     // 2.6–4.6 s per cycle
            let phase = ((t * 1.0 / fallDuration) + r2).truncatingRemainder(dividingBy: 1.0)

            let x = CGFloat(r2) * size.width
            let y = CGFloat(phase) * (size.height + 80) - 40
            let sway = CGFloat(sin(phase * .pi * 2 + r3 * 6)) * 22
            let rotation = phase * 2 * .pi * (r3 > 0.5 ? 1 : -1) * 3
            let s: CGFloat = 6 + CGFloat(r1) * 6

            let color: Color
            switch i % 5 {
            case 0: color = Color(hex: 0xC084FC)
            case 1: color = Color(hex: 0xFFB347)
            case 2: color = Color(hex: 0xFFE066)
            case 3: color = Color(hex: 0xF472B6)
            default: color = .white
            }

            var transform = CGAffineTransform(translationX: x + sway, y: y)
            transform = transform.rotated(by: rotation)

            let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s * 0.45)
            let path = Path(roundedRect: rect, cornerRadius: 1)
            context.drawLayer { layerContext in
                layerContext.transform = transform
                layerContext.fill(path, with: .color(color.opacity(0.95)))
            }
        }
    }

    private func fract(_ x: Double) -> Double {
        x - floor(x)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            tagline

            giftBox
                .frame(height: 240)
                .scaleEffect(appeared ? 1 : 0.55)
                .opacity(appeared ? 1 : 0)

            headline

            gameBadge

            Spacer(minLength: 16)

            cta

            Text("Cette offre est limitée. Sa fenêtre se referme bientôt.")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tagline: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .black))
            Text("NOUVEAU CADEAU DÉBLOQUÉ")
                .font(.system(size: 11.5, weight: .black, design: .rounded))
                .tracking(2.2)
        }
        .foregroundStyle(Color(hex: 0xFFD8A8))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(hex: 0xFFD8A8).opacity(0.45), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("Un nouveau jeu t'attend !")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            Text("Tente ta chance et débloque ta remise exclusive sur l'abonnement annuel.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 8)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var gameBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: offers.currentGiftGameKind.pillIconSystemName)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xC084FC), Color(hex: 0x8B5CF6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color(hex: 0xC084FC).opacity(0.6), radius: 10, y: 4)

            Text(offers.currentGiftGameKind.displayName.capitalized)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
    }

    private var cta: some View {
        Button(action: {
            OnboardingHaptics.medium()
            onPlay()
        }) {
            HStack(spacing: 10) {
                Text("Ouvre ton cadeau")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC084FC), Color(hex: 0x8B5CF6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x8B5CF6).opacity(0.55),
                    radius: ringPulse ? 28 : 18, y: 10)
            .scaleEffect(ringPulse ? 1.02 : 0.98)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Gift box

    /// A simplified gift box centerpiece: open lid (lifted on appear),
    /// vertical light shaft escaping from inside, ribbon cross and a
    /// pulsing percent badge.
    private var giftBox: some View {
        ZStack {
            // Halo / glow behind the box.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFE0A6).opacity(glow ? 0.75 : 0.45),
                            Color(hex: 0xFFE0A6).opacity(0)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 18)

            // Vertical light shaft escaping the open box.
            LightShaftShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xFFE2A6).opacity(0.0),
                            Color(hex: 0xFFE2A6).opacity(0.65),
                            Color(hex: 0xFFE2A6).opacity(0.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 220, height: 260)
                .blur(radius: 6)
                .offset(y: -90)
                .opacity(lidLift ? 1 : 0)

            // Box body.
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xA864F2),
                                    Color(hex: 0x7E3CE0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 200, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )

                    // Vertical ribbon
                    Rectangle()
                        .fill(Color(hex: 0xFFCA64))
                        .frame(width: 26, height: 140)
                        .overlay(
                            Rectangle()
                                .fill(.white.opacity(0.22))
                                .frame(height: 1)
                                .offset(y: -10)
                        )
                }
            }
            .frame(width: 220, height: 240)

            // Lid — lifts on appear, tilts slightly for life.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xB877F7),
                                Color(hex: 0x9554EE)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 216, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

                // Bow on top of the lid.
                bow
                    .offset(y: -22)
            }
            .frame(width: 216, height: 60)
            .offset(y: lidLift ? -110 : -32)
            .rotationEffect(.degrees(lidLift ? -8 : 0), anchor: .bottomTrailing)

            // Percent badge anchored top-right of the lid.
            percentBadge
                .offset(x: 100, y: lidLift ? -150 : -70)
                .rotationEffect(.degrees(ringPulse ? -10 : -4))
                .scaleEffect(ringPulse ? 1.06 : 0.96)
                .opacity(lidLift ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var bow: some View {
        ZStack {
            Capsule()
                .fill(Color(hex: 0xFFCA64))
                .frame(width: 36, height: 22)
                .offset(x: -18)
            Capsule()
                .fill(Color(hex: 0xFFCA64))
                .frame(width: 36, height: 22)
                .offset(x: 18)
            Circle()
                .fill(Color(hex: 0xFFB23F))
                .frame(width: 18, height: 18)
        }
    }

    private var percentBadge: some View {
        ZStack {
            // Scalloped white edge.
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(y: -26)
                    .rotationEffect(.degrees(Double(i) * (360.0 / 12.0)))
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [CooksyTheme.ctaOrange, CooksyTheme.ctaOrangeDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle().stroke(.white.opacity(0.7), lineWidth: 1)
                )
            VStack(spacing: -1) {
                Text("−\(offers.giftDiscountPercent ?? PremiumOffersService.defaultGiftDiscount)%")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("À VIE")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .opacity(0.95)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        }
        .shadow(color: CooksyTheme.ctaOrangeDark.opacity(0.5), radius: 8, y: 4)
    }

    // MARK: - Close

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    OnboardingHaptics.selection()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(.white.opacity(0.14))
                        )
                        .overlay(
                            Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
            Spacer()
        }
    }
}

/// Vertical "spotlight escaping the gift box" silhouette: wider at top,
/// narrow at the seam, soft-edged via blur on the fill.
private struct LightShaftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topInset: CGFloat = 0
        let midInset = rect.width * 0.25
        let bottomInset = rect.width * 0.40
        p.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - midInset, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + midInset, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
