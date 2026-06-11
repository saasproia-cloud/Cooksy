import SwiftUI

/// Cup-shuffle mini-game — fifth gift variant.
///
/// A golden −25 % token is shown under one of three "cloches"; the
/// cloches drop, swap positions several times, then the user picks
/// one. The chosen cloche lifts to reveal the token underneath.
/// Rigged like every gift game: wherever the user picks, the token is
/// there.
///
/// Same `(onClose, onClaim)` contract as the other games so it slots
/// straight into `GiftMiniGameHost` with no plumbing changes.
struct GiftCupShuffleView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    @State private var phase: Phase = .intro
    /// `cupSlots[cupID]` = the slot (0, 1, 2) the cup currently sits in.
    /// Shuffling swaps entries; the cups animate to their new slot X.
    @State private var cupSlots: [Int] = [0, 1, 2]
    @State private var pickedCup: Int?
    @State private var introTokenVisible: Bool = false
    @State private var showsConfetti: Bool = false

    private let winningDiscount: Int = 25
    private let totalSwaps: Int = 6

    private let cupColors: [(base: Color, accent: Color)] = [
        (Color(hex: 0xF59E0B), Color(hex: 0xFCD9A6)),
        (Color(hex: 0xC084FC), Color(hex: 0xE9D5FF)),
        (Color(hex: 0x4D8B47), Color(hex: 0xC8DDC0))
    ]

    enum Phase {
        case intro      // cloches raised, token teased
        case shuffling  // cloches swapping positions
        case ready      // cloches settled, awaiting a pick
        case revealed   // chosen cloche lifted, prize shown
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

                cupRow
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
        .onAppear { runIntro() }
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(headerTitle)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .lineSpacing(1)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var headerEyebrow: String {
        switch phase {
        case .intro:     return "MÉMORISE BIEN"
        case .shuffling: return "ÇA MÉLANGE…"
        case .ready:     return "À TOI DE JOUER"
        case .revealed:  return "TU AS GAGNÉ"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .intro:     return "Le cadeau se cache\nsous une cloche"
        case .shuffling: return "Suis bien la cloche…"
        case .ready:     return "Choisis ta cloche"
        case .revealed:  return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .intro:
            return "Regarde où se cache la remise."
        case .shuffling:
            return "Garde l'œil sur le bon couvercle."
        case .ready:
            return "Touche la cloche qui cache le cadeau."
        case .revealed:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Cups

    private var cupRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            let cupWidth = min((geo.size.width - 2 * spacing) / 3, 96)
            let step = cupWidth + spacing
            let centerY = geo.size.height * 0.5

            ZStack {
                // Token revealed under the chosen cloche.
                if phase == .revealed, let picked = pickedCup {
                    token(size: cupWidth * 0.66)
                        .position(
                            x: geo.size.width / 2 + CGFloat(cupSlots[picked] - 1) * step,
                            y: centerY + cupWidth * 0.18
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                // Token teased under the middle cloche during the intro.
                if introTokenVisible {
                    token(size: cupWidth * 0.66)
                        .position(x: geo.size.width / 2, y: centerY + cupWidth * 0.18)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                ForEach(0..<3, id: \.self) { id in
                    cloche(id: id, cupWidth: cupWidth)
                        .position(
                            x: geo.size.width / 2 + CGFloat(cupSlots[id] - 1) * step,
                            y: centerY + clocheYOffset(id)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 210)
    }

    private func clocheYOffset(_ id: Int) -> CGFloat {
        switch phase {
        case .intro:
            return -64
        case .revealed:
            return pickedCup == id ? -66 : 0
        case .shuffling, .ready:
            return 0
        }
    }

    private func cloche(id: Int, cupWidth: CGFloat) -> some View {
        let domeHeight = cupWidth * 0.62
        let pair = cupColors[id % cupColors.count]

        return ZStack(alignment: .top) {
            DomeShape()
                .fill(
                    LinearGradient(
                        colors: [pair.accent, pair.base],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    DomeShape().stroke(.white.opacity(0.55), lineWidth: 1.5)
                )
                .frame(width: cupWidth, height: domeHeight)
                .shadow(color: pair.base.opacity(0.45), radius: 9, y: 7)

            // Knob on top of the cloche.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.95), pair.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .frame(width: cupWidth * 0.18, height: cupWidth * 0.18)
                .offset(y: -cupWidth * 0.09)
                .shadow(color: pair.base.opacity(0.4), radius: 3, y: 2)
        }
        .frame(width: cupWidth, height: domeHeight + cupWidth * 0.12, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { handlePick(id) }
    }

    private func token(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFEFC2), Color(hex: 0xF5B739)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                .shadow(color: Color(hex: 0xF5B739).opacity(0.6), radius: 10, y: 4)

            Text("−\(winningDiscount)%")
                .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                .foregroundStyle(CooksyTheme.heroDark)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
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
        case .intro:     return "Observe bien…"
        case .shuffling: return "Ça mélange…"
        case .ready:     return "Choisis une cloche"
        case .revealed:  return "Recevoir mon cadeau"
        }
    }

    // MARK: - Interaction

    /// Tease the token under the middle cloche, drop the cloches, then
    /// kick off the shuffle.
    private func runIntro() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            introTokenVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeIn(duration: 0.3)) {
                introTokenVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.74)) {
                    phase = .shuffling
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    performShuffle(remaining: totalSwaps)
                }
            }
        }
    }

    /// Swaps two random slots, then schedules the next swap. When no
    /// swaps remain the round opens up for the user's pick.
    private func performShuffle(remaining: Int) {
        guard remaining > 0 else {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .ready
            }
            return
        }

        let slotA = Int.random(in: 0..<3)
        var slotB = Int.random(in: 0..<3)
        while slotB == slotA {
            slotB = Int.random(in: 0..<3)
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            for cup in cupSlots.indices {
                if cupSlots[cup] == slotA {
                    cupSlots[cup] = slotB
                } else if cupSlots[cup] == slotB {
                    cupSlots[cup] = slotA
                }
            }
        }
        OnboardingHaptics.selection()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            performShuffle(remaining: remaining - 1)
        }
    }

    private func handlePick(_ id: Int) {
        guard phase == .ready else { return }
        OnboardingHaptics.selection()
        pickedCup = id
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            phase = .revealed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            OnboardingHaptics.success()
            showsConfetti = true
        }
    }

    private func handlePrimaryAction() {
        guard phase == .revealed else { return }
        OnboardingHaptics.medium()
        onClaim(winningDiscount)
    }
}

// MARK: - Dome shape

/// A clean half-circle dome used to draw the cloche lids — no asset
/// dependency, just an arc closed across a flat bottom edge.
private struct DomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
