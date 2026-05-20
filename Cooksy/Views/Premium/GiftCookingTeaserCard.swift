import SwiftUI

/// Home-screen anticipation card shown while a declined gift is in its
/// reissue cooldown.
///
/// A pot quietly simmers a "surprise": a live countdown ticks down, the
/// lid lifts a little more each day, steam thickens and a golden glow
/// grows inside. The user can tap the pot to stir — a burst of bubbles,
/// a wiggle and a rotating teaser line — which builds the habit of
/// coming back. When the cooldown elapses the card flips to a glowing
/// "ready" state that launches the gift mini-game.
struct GiftCookingTeaserCard: View {
    @ObservedObject var offers: PremiumOffersService
    /// Called when the user opens the now-ready surprise.
    let onPlay: () -> Void
    /// Called when the user dismisses the ready card without playing.
    let onDismissReady: () -> Void

    @State private var appeared = false
    @State private var potWiggle: Double = 0
    @State private var burstID: Int = 0
    @State private var teaseIndex: Int = 0
    @State private var glowPulse = false

    private let teaseLines: [String] = [
        "Le chef peaufine ta surprise…",
        "Ça mijote, ça sent déjà bon…",
        "Encore un peu de patience…",
        "Quelque chose de bon se prépare…",
        "Reviens vite, ça avance bien…"
    ]

    /// Cooking is done — the countdown elapsed / a fresh celebration is
    /// queued. Drives the flip from "simmering" to "ready".
    private var isReady: Bool {
        offers.hasFreshGiftCelebrationPending || offers.giftCooldownRemaining <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            marmiteScene
            if isReady { readyFooter } else { cookingFooter }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color(hex: 0xF2C083).opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color(hex: 0xC9772A).opacity(0.18), radius: 20, y: 12)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xFFF4E3), Color(hex: 0xFCE7C9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: isReady ? "sparkles" : "flame.fill")
                        .font(.system(size: 10, weight: .black))
                    Text(isReady ? "TA SURPRISE EST PRÊTE" : "SURPRISE EN PRÉPARATION")
                        .font(.system(size: 10.5, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(hex: 0xC9772A))

                Spacer(minLength: 0)

                if isReady {
                    Button(action: {
                        OnboardingHaptics.selection()
                        onDismissReady()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(isReady ? "C'est prêt — découvre\nton cadeau" : "Quelque chose mijote\npour toi")
                .font(.system(size: 21, weight: .heavy, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Marmite scene

    private var marmiteScene: some View {
        let progress = offers.giftTeaserProgress
        let lidLift: CGFloat = isReady ? 32 : 8 + 22 * CGFloat(progress)
        let lidTilt: Double = isReady ? 7 : 5 * progress

        return ZStack {
            ambientGlow
            flames
            innerGlow

            // Handles sit behind the body so only the outer loop shows.
            HStack {
                potHandle
                Spacer()
                potHandle
            }
            .frame(width: 150)
            .offset(y: 14)

            potBody
                .offset(y: 26)

            liveLayer
                .offset(y: -10)

            lid
                .offset(y: -12 - lidLift)
                .rotationEffect(.degrees(lidTilt))

            if burstID > 0 {
                StirBurstView(tint: Color(hex: 0xFFD27A))
                    .id(burstID)
                    .offset(y: -10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .rotationEffect(.degrees(potWiggle), anchor: .bottom)
        .onTapGesture { handleTap() }
    }

    private var ambientGlow: some View {
        let strength: Double = isReady ? 1 : 0.3 + 0.6 * offers.giftTeaserProgress
        return Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0xFFB23F).opacity(0.42 * strength), .clear],
                    center: .center, startRadius: 6, endRadius: 100
                )
            )
            .frame(width: 200, height: 200)
            .scaleEffect(glowPulse ? 1.06 : 0.94)
    }

    private var innerGlow: some View {
        let strength: Double = isReady ? 1 : 0.28 + 0.65 * offers.giftTeaserProgress
        return Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0xFFE39A).opacity(strength), .clear],
                    center: .center, startRadius: 2, endRadius: 56
                )
            )
            .frame(width: 108, height: 108)
            .offset(y: -14)
            .scaleEffect(glowPulse ? 1.08 : 0.92)
    }

    private var flames: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "flame.fill")
                    .font(.system(size: i == 1 ? 26 : 20, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xFFC24B), Color(hex: 0xFF7A2E)],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .scaleEffect(x: 1, y: glowPulse ? 1.12 : 0.9, anchor: .bottom)
                    .opacity(0.9)
            }
        }
        .offset(y: 60)
    }

    private var potHandle: some View {
        Capsule()
            .stroke(Color(hex: 0x2E2722), lineWidth: 7)
            .frame(width: 26, height: 30)
    }

    private var potBody: some View {
        PotBodyShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x4C4039), Color(hex: 0x2B2521)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 122, height: 74)
            .overlay(
                Ellipse()
                    .fill(Color(hex: 0x6A5B50))
                    .frame(width: 116, height: 13)
                    .offset(y: -30)
            )
            .overlay(
                PotBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 122, height: 74)
            )
    }

    private var lid: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x5A4D44), Color(hex: 0x352D28)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 138, height: 30)
                .overlay(
                    Ellipse()
                        .fill(.white.opacity(0.18))
                        .frame(width: 94, height: 11)
                        .offset(y: -6)
                )
                .shadow(color: .black.opacity(0.2), radius: 5, y: 4)

            Capsule()
                .fill(Color(hex: 0x6A5B50))
                .frame(width: 30, height: 13)
                .offset(y: -16)
        }
    }

    // MARK: - Steam + bubbles

    private var liveLayer: some View {
        let intensity: Double = isReady ? 1.0 : 0.4 + 0.55 * offers.giftTeaserProgress
        return TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    bubble(t: t, seed: Double(i), intensity: intensity)
                }
                ForEach(0..<3, id: \.self) { i in
                    steamPuff(t: t, seed: Double(i), intensity: intensity)
                }
            }
        }
    }

    private func bubble(t: Double, seed: Double, intensity: Double) -> some View {
        let speed = 0.85
        let raw = (t * speed + seed * 0.37).truncatingRemainder(dividingBy: 1)
        let p = raw < 0 ? raw + 1 : raw
        let size: CGFloat = 7 + CGFloat(seed.truncatingRemainder(dividingBy: 2)) * 3
        return Circle()
            .fill(Color(hex: 0xFFE6B0))
            .frame(width: size, height: size)
            .offset(x: CGFloat(seed - 2) * 17, y: 6 - CGFloat(p) * 20)
            .opacity(sin(p * .pi) * 0.75 * intensity)
    }

    private func steamPuff(t: Double, seed: Double, intensity: Double) -> some View {
        let speed = 0.4
        let raw = (t * speed + seed / 3.0).truncatingRemainder(dividingBy: 1)
        let p = raw < 0 ? raw + 1 : raw
        let drift = CGFloat(sin(p * 5 + seed * 2)) * 9
        let size = 18 + CGFloat(p) * 18
        return Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .blur(radius: 6)
            .opacity(sin(p * .pi) * 0.4 * intensity)
            .offset(x: CGFloat(seed - 1) * 13 + drift, y: -6 - CGFloat(p) * 42)
    }

    // MARK: - Cooking footer

    private var cookingFooter: some View {
        VStack(spacing: 11) {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                countdownAndGauge
            }

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC9772A))
                Text(burstID == 0 ? "Touche la marmite pour remuer" : teaseLines[teaseIndex])
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var countdownAndGauge: some View {
        let remaining = offers.giftCooldownRemaining
        let progress = offers.giftTeaserProgress
        return VStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC9772A))
                (
                    Text("Surprise prête dans ")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(CooksyTheme.secondaryText)
                    + Text(countdownText(remaining))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(CooksyTheme.primaryText)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEAD7BC))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xFFB23F), Color(hex: 0xF2802B)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Ready footer

    private var readyFooter: some View {
        VStack(spacing: 9) {
            Button(action: {
                OnboardingHaptics.medium()
                onPlay()
            }) {
                HStack(spacing: 7) {
                    Text("Ouvre ta surprise")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(CooksyTheme.accentGradient))
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 14, y: 8)
            }
            .buttonStyle(CooksyTheme.pressScale())

            Text("Un mini-jeu t'attend — −25 % à la clé.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }

    // MARK: - Helpers

    private func countdownText(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "très bientôt" }
        let totalMinutes = max(1, Int(remaining / 60))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days >= 1 { return "\(days) j \(hours) h" }
        if hours >= 1 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    private func handleTap() {
        if isReady {
            OnboardingHaptics.medium()
            onPlay()
            return
        }
        OnboardingHaptics.selection()
        burstID += 1
        withAnimation(.easeInOut(duration: 0.25)) {
            teaseIndex = (teaseIndex + 1) % teaseLines.count
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.32)) {
            potWiggle = 3.5
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.5).delay(0.09)) {
            potWiggle = 0
        }
    }
}

// MARK: - Stir burst

/// One-shot bubble burst, re-created on every stir via `.id(burstID)`
/// so its `onAppear` animation fires fresh each tap.
private struct StirBurstView: View {
    let tint: Color
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7.0 * 2.0 * Double.pi - Double.pi / 2
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .offset(
                        x: go ? CGFloat(cos(angle)) * 48 : 0,
                        y: go ? CGFloat(sin(angle)) * 36 - 14 : 0
                    )
                    .opacity(go ? 0 : 0.95)
                    .scaleEffect(go ? 0.3 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.62)) {
                go = true
            }
        }
    }
}

// MARK: - Pot shape

/// A cooking-pot silhouette: straight mouth, very slightly tapered
/// sides and softly rounded bottom corners.
private struct PotBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let taper = rect.width * 0.055
        let radius = rect.width * 0.17
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - taper, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - taper - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX - taper, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + taper + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + taper, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX + taper, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
