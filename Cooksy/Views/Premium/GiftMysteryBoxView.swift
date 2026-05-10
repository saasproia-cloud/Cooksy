import SwiftUI

/// Mystery-box mini-game — third variant alongside the wheel and the
/// scratch card.
///
/// Three closed gift boxes are presented; the user picks one. The
/// chosen box wiggles, the lid flies off, and the −25 % discount
/// floats up out of it on a burst of particles. The two unpicked
/// boxes ease back and reveal weaker prizes ("−5 %", "Rien") so the
/// user feels they made the right call. Like the wheel and the
/// scratch card, the outcome is rigged: every pick wins the jackpot.
///
/// Same `(onClose, onClaim)` contract as the other games so it slots
/// into `GiftMiniGameHost` with no plumbing changes.
struct GiftMysteryBoxView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    @State private var phase: Phase = .idle
    @State private var selectedIndex: Int?
    @State private var bobToggle: Bool = false
    @State private var showsConfetti: Bool = false
    @State private var prizeAppeared: Bool = false

    private let winningDiscount: Int = 25

    /// Cosmetic prizes shown on the two unpicked boxes after reveal —
    /// purely there to make the chosen box's −25 % feel like the best
    /// outcome. Never claimed; the user still wins the jackpot.
    private let consolationPrizes: [String] = ["−5 %", "Rien"]

    private let boxColors: [(base: Color, accent: Color)] = [
        (Color(hex: 0xF59E0B), Color(hex: 0xFCD9A6)),
        (Color(hex: 0xC084FC), Color(hex: 0xE9D5FF)),
        (Color(hex: 0x4D8B47), Color(hex: 0xC8DDC0))
    ]

    enum Phase {
        case idle      // boxes bob, awaiting pick
        case opening   // chosen box opening, others easing back
        case revealed  // prize visible, CTA flips to "Recevoir"
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

                boxRow
                    .padding(.vertical, 14)

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
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                bobToggle = true
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
        switch phase {
        case .idle:                 return "BOÎTE MYSTÈRE"
        case .opening:              return "OUVERTURE…"
        case .revealed:             return "TU AS GAGNÉ"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .idle:     return "Choisis une boîte\npour révéler ton lot"
        case .opening:  return "On regarde dedans…"
        case .revealed: return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .idle:
            return "Une seule chance — fais confiance à ton instinct."
        case .opening:
            return "Les autres boîtes te montrent ce que tu aurais eu…"
        case .revealed:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Boxes

    private var boxRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let boxWidth = min((geo.size.width - 2 * spacing) / 3, 110)
            let boxHeight = boxWidth * (130.0 / 110.0)
            let iconWidth = boxWidth * (92.0 / 110.0)
            let iconHeight = boxHeight * (102.0 / 130.0)
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    box(
                        at: index,
                        boxWidth: boxWidth,
                        boxHeight: boxHeight,
                        iconWidth: iconWidth,
                        iconHeight: iconHeight
                    )
                }
            }
            .frame(width: geo.size.width, alignment: .center)
        }
        .frame(height: 158)
    }

    private func box(
        at index: Int,
        boxWidth: CGFloat,
        boxHeight: CGFloat,
        iconWidth: CGFloat,
        iconHeight: CGFloat
    ) -> some View {
        let isSelected = selectedIndex == index
        let isOther = selectedIndex != nil && !isSelected
        let pair = boxColors[index % boxColors.count]
        let intrinsicScale = iconWidth / 92
        let stateScale: CGFloat = isSelected ? 1.1 : (isOther ? 0.85 : 1.0)

        return VStack(spacing: 8) {
            ZStack {
                if isSelected, phase == .revealed, prizeAppeared {
                    // Floating prize that emerges from the chosen box.
                    floatingPrize
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                GiftBoxIcon(
                    baseColor: pair.base,
                    accentColor: pair.accent,
                    state: boxState(for: index),
                    bobOffset: isSelected || isOther ? 0 : (bobToggle ? -4 : 4)
                )
                .frame(width: iconWidth, height: iconHeight)
                .scaleEffect(intrinsicScale * stateScale)
                .opacity(isOther ? 0.55 : 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: selectedIndex)
                .animation(.easeInOut(duration: 1.5), value: bobToggle)
            }
            .frame(width: boxWidth, height: boxHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap(index: index)
            }

            // Reveal label under each box once the round is over.
            if phase == .revealed {
                Text(isSelected ? "−\(winningDiscount) %" : consolationPrizes[index % consolationPrizes.count])
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected
                                     ? CooksyTheme.ctaOrangeDark
                                     : CooksyTheme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected
                                  ? CooksyTheme.ctaOrange.opacity(0.18)
                                  : CooksyTheme.surface)
                    )
                    .overlay(
                        Capsule().stroke(
                            isSelected
                            ? CooksyTheme.ctaOrange.opacity(0.4)
                            : CooksyTheme.stroke,
                            lineWidth: 1
                        )
                    )
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func boxState(for index: Int) -> GiftBoxIcon.State {
        guard selectedIndex == index else { return .closed }
        switch phase {
        case .idle:     return .closed
        case .opening:  return .opening
        case .revealed: return .open
        }
    }

    /// Prize chip that springs out of the chosen box on reveal.
    private var floatingPrize: some View {
        VStack(spacing: 0) {
            Text("−\(winningDiscount) %")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(CooksyTheme.accentGradient)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 14, y: 6)
        }
        .offset(y: prizeAppeared ? -84 : -10)
        .scaleEffect(prizeAppeared ? 1.0 : 0.5)
        .opacity(prizeAppeared ? 1 : 0)
        .animation(.spring(response: 0.55, dampingFraction: 0.7), value: prizeAppeared)
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
        case .idle:     return "Choisis une boîte"
        case .opening:  return "Ouverture…"
        case .revealed: return "Recevoir mon cadeau"
        }
    }

    // MARK: - Interaction

    private func handleTap(index: Int) {
        guard phase == .idle else { return }
        OnboardingHaptics.selection()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
            selectedIndex = index
            phase = .opening
        }

        // Sequence: lid flies off after a brief wiggle, then prize
        // emerges, then confetti fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            OnboardingHaptics.success()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                phase = .revealed
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                prizeAppeared = true
                showsConfetti = true
            }
        }
    }

    private func handlePrimaryAction() {
        guard phase == .revealed else { return }
        OnboardingHaptics.medium()
        onClaim(winningDiscount)
    }
}

// MARK: - Gift box icon

/// Stylised gift box drawn entirely with SwiftUI shapes — no asset
/// dependency. Three states: closed, opening (lid lifting + rotating),
/// open (lid gone, glow visible).
private struct GiftBoxIcon: View {
    enum State { case closed, opening, open }

    let baseColor: Color
    let accentColor: Color
    let state: State
    /// Subtle vertical bob applied to the closed boxes only — gives
    /// the row a sense of "alive, awaiting your pick".
    let bobOffset: CGFloat

    var body: some View {
        ZStack {
            // Inner glow that becomes visible once the lid is gone.
            innerGlow
                .opacity(state == .open ? 1 : 0)
                .animation(.easeIn(duration: 0.25), value: state)

            // Box base (always visible).
            base
                .offset(y: state == .closed ? bobOffset : 0)

            // Lid + bow (animate up & away when opening).
            lidGroup
                .offset(y: lidOffsetY)
                .rotationEffect(.degrees(lidRotation))
                .opacity(state == .open ? 0 : 1)
                .animation(.spring(response: 0.55, dampingFraction: 0.6), value: state)
        }
    }

    // MARK: - Pieces

    private var base: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor, baseColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: baseColor.opacity(0.45), radius: 12, y: 8)
                .frame(width: 84, height: 70)
                .offset(y: 14)

            // Vertical ribbon down the middle of the base.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 70)
                .offset(y: 14)
        }
    }

    private var lidGroup: some View {
        ZStack {
            // Lid rectangle.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor, baseColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                )
                .frame(width: 92, height: 22)
                .offset(y: -28)
                .shadow(color: baseColor.opacity(0.35), radius: 6, y: 4)

            // Horizontal ribbon that wraps over the lid.
            Rectangle()
                .fill(.white)
                .frame(width: 12, height: 22)
                .offset(y: -28)

            // Bow.
            ZStack {
                Ellipse()
                    .fill(.white)
                    .frame(width: 18, height: 12)
                    .offset(x: -8, y: -44)
                Ellipse()
                    .fill(.white)
                    .frame(width: 18, height: 12)
                    .offset(x: 8, y: -44)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .offset(y: -44)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
    }

    private var innerGlow: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 50
                )
            )
            .frame(width: 80, height: 60)
            .offset(y: 14)
    }

    private var lidOffsetY: CGFloat {
        switch state {
        case .closed:  return 0
        case .opening: return -28
        case .open:    return -120
        }
    }

    private var lidRotation: Double {
        switch state {
        case .closed:  return 0
        case .opening: return -8
        case .open:    return -28
        }
    }
}
