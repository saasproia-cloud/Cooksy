import SwiftUI

/// Balloon-pop mini-game — sixth gift variant.
///
/// Three balloons drift gently. The user taps one; it inflates for a
/// beat then bursts in a shower of confetti, and the −25 % prize chip
/// springs out of the pop. The two unpicked balloons deflate and sink.
/// Rigged like every gift game: the popped balloon always hides the
/// jackpot.
///
/// Same `(onClose, onClaim)` contract as the other games so it slots
/// straight into `GiftMiniGameHost` with no plumbing changes.
struct GiftBalloonPopView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    @State private var phase: Phase = .idle
    @State private var pickedIndex: Int?
    @State private var popped: Bool = false
    @State private var prizeOut: Bool = false
    @State private var bob: Bool = false
    @State private var showsConfetti: Bool = false

    private let winningDiscount: Int = 25

    private let balloonColors: [Color] = [
        Color(hex: 0xF5736A),
        Color(hex: 0x6AA9F5),
        Color(hex: 0x4D8B47)
    ]

    enum Phase {
        case idle      // balloons drifting, awaiting a pick
        case popping   // chosen balloon inflating / bursting
        case revealed  // prize chip out, CTA flips to "Recevoir"
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

                balloonRow
                    .padding(.vertical, 8)

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
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                bob = true
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
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .lineSpacing(1)
        }
    }

    private var headerEyebrow: String {
        switch phase {
        case .idle:      return "ÉCLATE UN BALLON"
        case .popping:   return "ÇA GONFLE…"
        case .revealed:  return "TU AS GAGNÉ"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .idle:      return "Choisis un ballon\net fais-le éclater"
        case .popping:   return "Boum !"
        case .revealed:  return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .idle:
            return "Un seul cache la remise maximale."
        case .popping:
            return "On regarde ce qui en tombe…"
        case .revealed:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Balloons

    private var balloonRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 16
            let balloonWidth = min((geo.size.width - 2 * spacing) / 3, 94)
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    balloon(at: index, width: balloonWidth)
                }
            }
            .frame(width: geo.size.width, alignment: .center)
        }
        .frame(height: 250)
    }

    private func balloon(at index: Int, width: CGFloat) -> some View {
        let isPicked = pickedIndex == index
        let isOther = pickedIndex != nil && !isPicked
        let color = balloonColors[index % balloonColors.count]
        let balloonHeight = width * 1.25

        return ZStack {
            // Prize chip emerging from the popped balloon.
            if isPicked && phase == .revealed {
                prizeChip(width: width)
                    .scaleEffect(prizeOut ? 1 : 0.4)
                    .opacity(prizeOut ? 1 : 0)
                    .offset(y: prizeOut ? -balloonHeight * 0.14 : balloonHeight * 0.2)
            }

            // Expanding burst ring on pop.
            if isPicked && popped {
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 3)
                    .frame(width: width, height: width)
                    .scaleEffect(popped ? 2.3 : 0.4)
                    .opacity(popped ? 0 : 0.9)
            }

            // Radiating pop shards.
            if isPicked && popped {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) / 8.0 * 2.0 * Double.pi
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .offset(
                            x: popped ? CGFloat(cos(angle)) * width * 0.95 : 0,
                            y: popped ? CGFloat(sin(angle)) * width * 0.95 : 0
                        )
                        .opacity(popped ? 0 : 1)
                        .scaleEffect(popped ? 0.3 : 1)
                }
            }

            // The balloon itself.
            balloonShape(color: color, width: width, height: balloonHeight)
                .scaleEffect(balloonScale(isPicked: isPicked, isOther: isOther))
                .opacity(balloonOpacity(isPicked: isPicked, isOther: isOther))
                .offset(y: balloonYOffset(isPicked: isPicked, isOther: isOther))
        }
        .frame(width: width, height: balloonHeight + width * 0.7)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(index) }
        .animation(.easeOut(duration: 0.5), value: popped)
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: prizeOut)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: pickedIndex)
        .animation(.easeInOut(duration: 2.0), value: bob)
    }

    private func balloonScale(isPicked: Bool, isOther: Bool) -> CGFloat {
        if isPicked {
            if popped { return 1.5 }
            if phase == .popping { return 1.22 }
            return 1.0
        }
        return isOther ? 0.82 : 1.0
    }

    private func balloonOpacity(isPicked: Bool, isOther: Bool) -> Double {
        if isPicked && popped { return 0 }
        return isOther ? 0.5 : 1.0
    }

    private func balloonYOffset(isPicked: Bool, isOther: Bool) -> CGFloat {
        if isOther { return 40 }
        if isPicked { return 0 }
        return bob ? -8 : 8
    }

    private func balloonShape(color: Color, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.95), color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: width, height: height)
                    .overlay(
                        Ellipse()
                            .fill(.white.opacity(0.35))
                            .frame(width: width * 0.24, height: height * 0.3)
                            .offset(x: -width * 0.16, y: -height * 0.18)
                    )
                    .shadow(color: color.opacity(0.4), radius: 10, y: 8)

                // Knot at the bottom of the balloon.
                BalloonKnot()
                    .fill(color)
                    .frame(width: width * 0.16, height: width * 0.12)
                    .offset(y: height * 0.5)
            }

            // Curly string.
            BalloonString()
                .stroke(
                    color.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: width * 0.4, height: width * 0.55)
                .offset(y: width * 0.06)
        }
    }

    private func prizeChip(width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text("JACKPOT")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.9))
            Text("−\(winningDiscount)%")
                .font(.system(size: width * 0.3, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(CooksyTheme.accentGradient)
        )
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.5), radius: 14, y: 6)
        .fixedSize()
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

    private var ctaLabel: String {
        switch phase {
        case .idle:      return "Choisis un ballon"
        case .popping:   return "Boum !"
        case .revealed:  return "Recevoir mon cadeau"
        }
    }

    // MARK: - Interaction

    private func handleTap(_ index: Int) {
        guard phase == .idle else { return }
        OnboardingHaptics.selection()
        pickedIndex = index
        withAnimation(.easeOut(duration: 0.22)) {
            phase = .popping
        }

        // Inflate, then burst.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            OnboardingHaptics.success()
            popped = true
            showsConfetti = true

            // Prize springs out of the pop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                    phase = .revealed
                }
                prizeOut = true
            }
        }
    }

    private func handlePrimaryAction() {
        guard phase == .revealed else { return }
        OnboardingHaptics.medium()
        onClaim(winningDiscount)
    }
}

// MARK: - Balloon shapes

/// Small downward triangle drawn at the base of a balloon.
private struct BalloonKnot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Gently curling balloon string drawn with two quadratic curves.
private struct BalloonString: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control: CGPoint(x: rect.minX, y: rect.height * 0.28)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.72)
        )
        return path
    }
}
