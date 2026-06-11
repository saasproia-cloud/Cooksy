import SwiftUI

/// Card-flip mini-game — fourth gift variant alongside the wheel, the
/// scratch card and the mystery box.
///
/// Three face-down cards float gently. The user picks one; it performs
/// a 3D flip on its Y axis to reveal the −25 % jackpot, while the two
/// unpicked cards flip to weaker prizes so the chosen card feels like
/// the best call. Rigged like every gift game: the picked card always
/// wins the jackpot.
///
/// Same `(onClose, onClaim)` contract as the other games so it slots
/// straight into `GiftMiniGameHost` with no plumbing changes.
struct GiftCardFlipView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    @State private var phase: Phase = .idle
    @State private var pickedIndex: Int?
    @State private var flipped: Set<Int> = []
    @State private var bob: Bool = false
    @State private var showsConfetti: Bool = false

    private let winningDiscount: Int = 25
    /// Cosmetic prizes shown on the two unpicked cards after the round
    /// — purely there to make the −25 % feel like the best outcome.
    private let consolationPrizes: [String] = ["−5 %", "Rien"]

    private let cardAccents: [Color] = [
        Color(hex: 0xF59E0B),
        Color(hex: 0xC084FC),
        Color(hex: 0x4D8B47)
    ]

    enum Phase {
        case idle       // cards face-down, awaiting a pick
        case flipping   // cards turning over
        case revealed   // prize visible, CTA flips to "Recevoir"
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

                cardRow
                    .padding(.vertical, 16)

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
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
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

            // Apple Guideline 4: subtitle "Réduction valable 24 h sur ton 1ᵉʳ paiement…"
            // was truncated on iPad. Allow wrap to 4 lines + shrink.
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
        case .idle:      return "CARTE GAGNANTE"
        case .flipping:  return "ON RETOURNE…"
        case .revealed:  return "TU AS GAGNÉ"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .idle:      return "Choisis une carte\npour révéler ton lot"
        case .flipping:  return "On retourne les cartes…"
        case .revealed:  return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .idle:
            return "Trois cartes, une seule remise maximale."
        case .flipping:
            return "Croise les doigts !"
        case .revealed:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Cards

    private var cardRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let cardWidth = min((geo.size.width - 2 * spacing) / 3, 104)
            let cardHeight = cardWidth * 1.42
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    card(at: index, width: cardWidth, height: cardHeight)
                }
            }
            .frame(width: geo.size.width, alignment: .center)
        }
        .frame(height: 200)
    }

    private func card(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        let isPicked = pickedIndex == index
        let isOther = pickedIndex != nil && !isPicked
        let isFlipped = flipped.contains(index)
        let accent = cardAccents[index % cardAccents.count]

        return ZStack {
            cardBack(accent: accent, width: width, height: height)
                .opacity(isFlipped ? 0 : 1)

            // Front face pre-rotated 180° so the text reads correctly
            // once the whole card has flipped to its resting angle.
            cardFront(index: index, isPicked: isPicked, width: width, height: height)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.4
        )
        .scaleEffect(isPicked ? 1.08 : (isOther ? 0.9 : 1.0))
        .opacity(isOther ? 0.62 : 1)
        .offset(y: pickedIndex == nil ? (bob ? -7 : 7) : 0)
        .animation(.easeInOut(duration: 1.7), value: bob)
        .animation(.spring(response: 0.62, dampingFraction: 0.74), value: flipped)
        .animation(.spring(response: 0.5, dampingFraction: 0.76), value: pickedIndex)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(index) }
    }

    private func cardBack(accent: Color, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.95), accent.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 1.5)
                    .padding(5)
            )
            .overlay(
                Image(systemName: "questionmark")
                    .font(.system(size: width * 0.4, weight: .black))
                    .foregroundStyle(.white.opacity(0.95))
            )
            .shadow(color: accent.opacity(0.4), radius: 12, y: 8)
    }

    private func cardFront(index: Int, isPicked: Bool, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(CooksyTheme.elevatedSurface)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isPicked ? CooksyTheme.ctaOrange.opacity(0.5) : CooksyTheme.stroke,
                        lineWidth: isPicked ? 2 : 1
                    )
            )
            .overlay(
                VStack(spacing: 3) {
                    if isPicked {
                        Text("JACKPOT")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        Text("−\(winningDiscount)%")
                            .font(.system(size: width * 0.32, weight: .black, design: .serif))
                            .foregroundStyle(CooksyTheme.heroDark)
                            .minimumScaleFactor(0.5)
                    } else {
                        Text(consolationPrizes[index % consolationPrizes.count])
                            .font(.system(size: width * 0.2, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .minimumScaleFactor(0.5)
                    }
                }
                .padding(6)
            )
            .shadow(color: .black.opacity(0.1), radius: 10, y: 6)
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
        case .idle:      return "Choisis une carte"
        case .flipping:  return "On retourne les cartes…"
        case .revealed:  return "Recevoir mon cadeau"
        }
    }

    // MARK: - Interaction

    private func handleTap(_ index: Int) {
        guard phase == .idle else { return }
        OnboardingHaptics.selection()
        pickedIndex = index
        phase = .flipping
        flipped.insert(index)

        // The two unpicked cards flip a beat later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            OnboardingHaptics.selection()
            for i in 0..<3 where i != index {
                flipped.insert(i)
            }
        }

        // Win sequence once the chosen card has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            OnboardingHaptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                phase = .revealed
            }
            showsConfetti = true
        }
    }

    private func handlePrimaryAction() {
        guard phase == .revealed else { return }
        OnboardingHaptics.medium()
        onClaim(winningDiscount)
    }
}
