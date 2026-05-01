import SwiftUI

/// 3×3 grid mini-game offered to every new user once.
///
/// Mechanic: the user picks 2 boxes. The 1st one always reveals "raté"
/// (creates anticipation), the 2nd one always reveals a fixed –25 % discount
/// on the yearly plan. After winning, a confirmation prompts them to use
/// the offer immediately or save it for later. The won state persists for
/// 24 h via `PremiumOffersService` so the user can re-open the gift from
/// the home top-bar and apply the discount whenever.
///
/// Designed to feel rewarding without being deceptive — the legal "1ère
/// année · puis 39,99 €/an" disclaimer is shown when the offer is applied.
struct GiftBoxMiniGameView: View {
    let onClose: () -> Void
    let onClaim: () -> Void
    /// Called when the user taps "Plus tard" after winning. Lets the
    /// host route them to the paywall **without** the promo (and
    /// optionally show a reminder banner). If `nil`, the button
    /// behaves like `onClose` — used by the paywall when it presents
    /// the mini-game inline.
    var onContinueWithoutGift: (() -> Void)? = nil

    @StateObject private var offers = PremiumOffersService.shared

    enum Phase: Equatable {
        case awaitingFirst    // user must pick the 1st box
        case revealedLoss     // 1st box flipped, shows raté
        case awaitingSecond   // user must pick the 2nd box
        case revealedWin      // 2nd box flipped, shows the prize
        case alreadyWon       // user re-opened after winning earlier
    }

    @State private var phase: Phase = .awaitingFirst
    @State private var firstPickIndex: Int?
    @State private var secondPickIndex: Int?
    @State private var revealAnimationFor: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let winningDiscount: Int = 25

    var body: some View {
        ZStack {
            CooksyTheme.heroDarkGradient
                .ignoresSafeArea()
            SparkleCanvas(count: 18, baseColor: CooksyTheme.primaryAccentGlow.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar
                Spacer(minLength: 0)
                header
                gridSection
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .onAppear { rehydrate() }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: {
                OnboardingHaptics.selection()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(headerEmoji)
                .font(.system(size: 44))
            Text(headerTitle)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var gridSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<9, id: \.self) { index in
                giftBox(at: index)
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            switch phase {
            case .revealedWin, .alreadyWon:
                Button(action: {
                    OnboardingHaptics.medium()
                    onClaim()
                }) {
                    Text("Réclamer mon cadeau")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.heroDark)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule(style: .continuous).fill(CooksyTheme.goldShimmer))
                        .shadow(color: CooksyTheme.primaryAccentGlow.opacity(0.5), radius: 18, y: 10)
                }
                .buttonStyle(CooksyTheme.pressScale())

                Button(action: {
                    OnboardingHaptics.selection()
                    // Route to paywall without promo if the host wants
                    // it; otherwise just close.
                    if let onContinueWithoutGift {
                        onContinueWithoutGift()
                    } else {
                        onClose()
                    }
                }) {
                    Text("Plus tard")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                if phase == .alreadyWon {
                    Text("Cadeau valable 24 h")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFCA5A5))
                }
                Text("1ère année · puis 39,99 €/an")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

            default:
                Text("Choisis deux boîtes pour découvrir ton offre.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Box

    @ViewBuilder
    private func giftBox(at index: Int) -> some View {
        let state = boxState(for: index)

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(boxFillColor(for: state))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(boxStrokeColor(for: state), lineWidth: 1.5)
                )

            switch state {
            case .closed:
                Image(systemName: "gift.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentGlow)

            case .losing:
                VStack(spacing: 4) {
                    Text("😕")
                        .font(.system(size: 22))
                    Text("Raté")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

            case .winning:
                VStack(spacing: 2) {
                    Text("✨")
                        .font(.system(size: 18))
                    Text("-\(winningDiscount) %")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.heroDark)
                }

            case .disabled:
                Image(systemName: "gift.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.18))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(revealAnimationFor == index ? 1.06 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: revealAnimationFor)
        .animation(.easeInOut(duration: 0.25), value: state)
        .onTapGesture { handleTap(on: index) }
        .allowsHitTesting(state == .closed && phase != .revealedWin && phase != .alreadyWon)
    }

    // MARK: - Logic

    private enum BoxState {
        case closed     // tappable
        case losing     // already-revealed first pick
        case winning    // already-revealed second pick (the prize)
        case disabled   // game over, untouched boxes greyed out
    }

    private func boxState(for index: Int) -> BoxState {
        if let firstPickIndex, index == firstPickIndex { return .losing }
        if let secondPickIndex, index == secondPickIndex { return .winning }
        switch phase {
        case .awaitingFirst, .revealedLoss, .awaitingSecond:
            return .closed
        case .revealedWin, .alreadyWon:
            return .disabled
        }
    }

    private func boxFillColor(for state: BoxState) -> Color {
        switch state {
        case .closed:   return Color.white.opacity(0.08)
        case .losing:   return Color.white.opacity(0.05)
        case .winning:  return CooksyTheme.primaryAccentGlow
        case .disabled: return Color.white.opacity(0.04)
        }
    }

    private func boxStrokeColor(for state: BoxState) -> Color {
        switch state {
        case .closed:   return Color.white.opacity(0.18)
        case .losing:   return Color.white.opacity(0.10)
        case .winning:  return Color.white.opacity(0.6)
        case .disabled: return Color.white.opacity(0.06)
        }
    }

    private func handleTap(on index: Int) {
        switch phase {
        case .awaitingFirst:
            firstPickIndex = index
            revealAnimationFor = index
            OnboardingHaptics.warning()
            phase = .revealedLoss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                revealAnimationFor = nil
                phase = .awaitingSecond
            }
        case .awaitingSecond:
            guard index != firstPickIndex else { return }
            secondPickIndex = index
            revealAnimationFor = index
            OnboardingHaptics.success()
            phase = .revealedWin
            offers.recordGiftWon(percent: winningDiscount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                revealAnimationFor = nil
            }
        default:
            break
        }
    }

    private func rehydrate() {
        if offers.giftHasBeenWon {
            phase = .alreadyWon
            firstPickIndex = nil
            secondPickIndex = 4 // visually centred reveal
        }
    }

    // MARK: - Copy

    private var headerEmoji: String {
        switch phase {
        case .awaitingFirst:                 return "🎁"
        case .revealedLoss:                  return "🤞"
        case .awaitingSecond:                return "🤞"
        case .revealedWin, .alreadyWon:      return "🎉"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .awaitingFirst:    return "Choisis ton cadeau"
        case .revealedLoss:     return "Pas de chance…"
        case .awaitingSecond:   return "Tente une dernière fois"
        case .revealedWin:      return "Tu as gagné −\(winningDiscount) %"
        case .alreadyWon:
            let percent = offers.giftDiscountPercent ?? winningDiscount
            return "Ton cadeau : −\(percent) %"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .awaitingFirst:
            return "9 boîtes, 2 chances. Une seule cache une vraie remise."
        case .revealedLoss:
            return "Cette boîte était vide. Il te reste une dernière chance."
        case .awaitingSecond:
            return "Choisis bien — c'est ta dernière tentative."
        case .revealedWin:
            return "Réduction sur ton abonnement annuel · valable 24 h."
        case .alreadyWon:
            return "Réduction sur ton abonnement annuel · revient avant l'expiration."
        }
    }
}
