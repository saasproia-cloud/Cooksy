import SwiftUI

/// Picks the right mini-game to present for the current gift cycle.
///
/// `PremiumOffersService.giftCycleIndex` rotates through the available
/// games (`wheel → scratchCard → mysteryBox → cardFlip → cupShuffle →
/// balloonPop → wheel → …`) every time a fresh gift cycle starts (i.e.
/// after a reissue cooldown elapses). Within a cycle the choice is
/// stable, so closing and re-opening the gift sheet always shows the
/// same game until the user wins or the cycle rolls over.
///
/// Each underlying game shares the same `(onClose, onClaim)` contract,
/// so the host just forwards the closures unchanged. To plug in a new
/// game, add a case to `PremiumOffersService.GiftGameKind` and a
/// matching branch here.
struct GiftMiniGameHost: View {
    let onClose: () -> Void
    let onClaim: (Int) -> Void

    @StateObject private var offers = PremiumOffersService.shared

    var body: some View {
        switch offers.currentGiftGameKind {
        case .wheel:
            GiftWheelView(onClose: onClose, onClaim: onClaim)
        case .scratchCard:
            GiftScratchCardView(onClose: onClose, onClaim: onClaim)
        case .mysteryBox:
            GiftMysteryBoxView(onClose: onClose, onClaim: onClaim)
        case .cardFlip:
            GiftCardFlipView(onClose: onClose, onClaim: onClaim)
        case .cupShuffle:
            GiftCupShuffleView(onClose: onClose, onClaim: onClaim)
        case .balloonPop:
            GiftBalloonPopView(onClose: onClose, onClaim: onClaim)
        }
    }
}
