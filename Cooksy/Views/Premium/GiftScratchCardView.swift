import SwiftUI

/// Scratch-card mini-game — alternative to the wheel.
///
/// The user is shown a sealed foil card with a "Gratte ici" call to
/// action; dragging a finger across erases the foil and reveals the
/// −25 % prize underneath. Like the wheel, the outcome is rigged: the
/// hidden prize is always the jackpot. The interaction simply makes
/// the win feel earned.
///
/// Same `(onClose, onClaim)` contract as `GiftWheelView` so it plugs
/// straight into `GiftMiniGameHost` without any plumbing changes.
struct GiftScratchCardView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    @State private var phase: Phase = .idle
    /// Accumulated drag path used as the foil mask. As the user
    /// scratches, segments are appended and the mask "punches" them
    /// out via `.destinationOut`, exposing the prize layer beneath.
    @State private var scratchPath: Path = Path()
    /// Approximate fraction of the foil the user has cleared.
    /// Crosses `revealThreshold` → the rest is auto-revealed.
    @State private var scratchProgress: Double = 0
    @State private var lastPoint: CGPoint?
    @State private var showsConfetti: Bool = false
    @State private var sparkle: Bool = false
    @State private var teaseGlow: Bool = false

    private let winningDiscount: Int = 25
    private let cardSize: CGSize = CGSize(width: 280, height: 380)
    /// User-facing target: scratch ~45 % of the card and we auto-reveal
    /// the rest. Keeps the interaction snappy without being a chore.
    private let revealThreshold: Double = 0.45
    /// Stroke width used both visually (in the mask) and as the rate
    /// at which `scratchProgress` accumulates per drag-distance unit.
    private let strokeWidth: CGFloat = 48

    enum Phase {
        case idle      // foil intact (or partially scratched)
        case revealed  // prize fully visible, CTA flips to "Recevoir"
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [CooksyTheme.primaryAccentSoft, CooksyTheme.background],
                center: .center,
                startRadius: 40,
                endRadius: 380
            )
            .opacity(0.6)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                topBar

                Spacer(minLength: 0)

                header

                scratchCard
                    .padding(.vertical, 12)

                Spacer(minLength: 0)

                cta
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)

            if showsConfetti {
                IngredientConfetti(trigger: showsConfetti ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                sparkle = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                teaseGlow = true
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: {
                OnboardingHaptics.selection()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(CooksyTheme.elevatedSurface)
                            .overlay(Circle().stroke(CooksyTheme.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text(headerEyebrow)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2.0)
                .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text(headerTitle)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)

            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .lineSpacing(1)
        }
    }

    private var headerEyebrow: String {
        phase == .revealed ? "TU AS GAGNÉ" : "TICKET À GRATTER"
    }

    private var headerTitle: String {
        switch phase {
        case .idle:     return "Gratte la carte\npour révéler ton lot"
        case .revealed: return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .idle:
            return "Glisse ton doigt sur le revêtement argenté."
        case .revealed:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Scratch card

    private var scratchCard: some View {
        ZStack {
            prizeLayer
            foilLayer
                .mask(scratchMask)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 22, y: 14)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleScratch(at: value.location)
                }
                .onEnded { _ in
                    lastPoint = nil
                }
        )
    }

    /// Behind-the-foil layer: cream/gold background with sparkles and
    /// the discount text. Visible through the holes the user scratches
    /// into the foil layer above it.
    private var prizeLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xFFF6E0),
                    Color(hex: 0xFFE2A8),
                    Color(hex: 0xF5BE5C)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Animated sparkle field
            ForEach(Self.sparkles.indices, id: \.self) { i in
                let s = Self.sparkles[i]
                Image(systemName: "sparkle")
                    .font(.system(size: s.size, weight: .bold))
                    .foregroundStyle(.white.opacity(s.opacity))
                    .offset(x: s.x, y: s.y)
                    .scaleEffect(sparkle ? 1 : 0.7)
                    .opacity(sparkle ? s.opacity : s.opacity * 0.45)
            }

            VStack(spacing: 6) {
                Text("JACKPOT")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                Text("−\(winningDiscount) %")
                    .font(.system(size: 70, weight: .black, design: .serif))
                    .foregroundStyle(CooksyTheme.heroDark)
                    .shadow(color: .white.opacity(0.6), radius: 6, y: 2)
                Text("sur l'annuel")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.75))
                    .padding(.top, 4)
            }
            // A soft glow that pulses to tease the prize through any
            // partially scratched areas.
            .shadow(color: CooksyTheme.ctaOrange.opacity(teaseGlow ? 0.5 : 0.2), radius: 18)
        }
    }

    /// Foil layer painted on top of the prize. The diagonal hatching
    /// + holographic gradient makes the surface feel like a real
    /// scratch ticket. The mask lets the user erase it stroke by
    /// stroke.
    private var foilLayer: some View {
        ZStack {
            // Holographic silver gradient base
            LinearGradient(
                colors: [
                    Color(hex: 0xCFD2D8),
                    Color(hex: 0xE8EBEF),
                    Color(hex: 0xB7BEC8),
                    Color(hex: 0xE3E6EB),
                    Color(hex: 0xA9B0BB)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle diagonal stripes for texture
            Canvas { context, size in
                let stripeSpacing: CGFloat = 12
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.10)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    x += stripeSpacing
                }
            }

            VStack(spacing: 10) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.65))
                Text("GRATTE-MOI")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(3.0)
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.7))
                Text("Ton lot est en dessous")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.heroDark.opacity(0.55))
                    .padding(.top, 4)
            }
        }
    }

    /// Mask for the foil. Initially fully white (foil opaque); the
    /// user's drag path is stroked with `.destinationOut` to punch
    /// transparent holes through it so the prize behind shows through.
    private var scratchMask: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white)
            )
            context.blendMode = .destinationOut
            context.stroke(
                scratchPath,
                with: .color(.black),
                style: StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    // MARK: - Sparkle layout (constant)

    private static let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (-100,  -150, 14, 0.85),
        ( 100,  -130, 12, 0.70),
        (-110,    20, 10, 0.65),
        ( 115,    50, 16, 0.80),
        ( -50,   140,  8, 0.55),
        (  90,   150, 13, 0.75),
        (   0,   -90,  9, 0.55)
    ]

    // MARK: - Scratch handling

    private func handleScratch(at point: CGPoint) {
        guard phase == .idle else { return }

        if let last = lastPoint {
            scratchPath.move(to: last)
            scratchPath.addLine(to: point)
            let dx = point.x - last.x
            let dy = point.y - last.y
            let length = Double(sqrt(dx * dx + dy * dy))
            // Scale: scratching the equivalent of ~3 full diagonals
            // worth of strokes maxes out the bar. Calibrated so
            // `revealThreshold` (45 %) is hit after ~3-4 sweeps.
            scratchProgress = min(1, scratchProgress + length / 1400.0)
        } else {
            // First touch: paint a tiny segment so a tap registers.
            scratchPath.move(to: point)
            scratchPath.addLine(to: CGPoint(x: point.x + 0.5, y: point.y + 0.5))
            scratchProgress = min(1, scratchProgress + 0.005)
        }
        lastPoint = point

        // Light haptic tick on every meaningful drag step.
        if Int(scratchProgress * 20) % 2 == 0 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
        }

        if scratchProgress >= revealThreshold {
            triggerReveal()
        }
    }

    private func triggerReveal() {
        guard phase == .idle else { return }
        OnboardingHaptics.success()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            phase = .revealed
            scratchProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showsConfetti = true
        }
    }

    // MARK: - CTA

    private var cta: some View {
        VStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                Text(ctaLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule(style: .continuous)
                            .fill(phase == .revealed
                                  ? AnyShapeStyle(CooksyTheme.accentGradient)
                                  : AnyShapeStyle(CooksyTheme.primaryAccent.opacity(0.45)))
                    )
                    .shadow(color: CooksyTheme.primaryAccent.opacity(phase == .revealed ? 0.4 : 0.0),
                            radius: 18, y: 10)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(phase != .revealed)

            if phase == .revealed {
                Text("Cadeau valable 24 h. Cumulable avec l'essai 7 jours.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            } else {
                // Progress bar so the user feels their progress while scratching.
                progressBar
                Button(action: {
                    OnboardingHaptics.selection()
                    onClose()
                }) {
                    Text("Plus tard")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CooksyTheme.stroke.opacity(0.6))
                Capsule()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: proxy.size.width * CGFloat(min(1, scratchProgress / revealThreshold)))
                    .animation(.easeOut(duration: 0.2), value: scratchProgress)
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 220)
    }

    private var ctaLabel: String {
        phase == .revealed ? "Recevoir mon cadeau" : "Continue à gratter…"
    }

    private func handlePrimaryAction() {
        guard phase == .revealed else { return }
        OnboardingHaptics.medium()
        onClaim(winningDiscount)
    }
}
