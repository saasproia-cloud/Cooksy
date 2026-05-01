import SwiftUI

/// Pair of pill-shaped badges shown in the top-bar of the home screen:
///
///   • A lightning counter "3 / 3" showing the remaining weekly imports
///     (free) or `∞` for premium users.
///   • A gift button that re-opens the won discount (or the mini-game if
///     the user hasn't played yet). Hidden for premium users — they
///     don't need the discount loop anymore.
struct FreePlanHomeBadges: View {
    @StateObject private var quota = ImportQuotaService.shared
    @StateObject private var offers = PremiumOffersService.shared

    let onTapQuota: () -> Void
    let onTapGift: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            quotaPill
            // Gift pill is suppressed when:
            //   • the user is premium (no discount loop applies)
            //   • the gift is on cooldown after a consumed purchase (7 d)
            //     or a cancelled trial (3 d)
            //   • a trial is currently pending (gift is held in escrow)
            // The `shouldShowGiftPill` flag in PremiumOffersService
            // centralises that policy.
            if !quota.isPremium && offers.shouldShowGiftPill {
                giftPill
            }
        }
    }

    // MARK: - Quota pill (lightning + remaining or ∞)

    private var quotaPill: some View {
        Button(action: onTapQuota) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(quota.isPremium
                              ? AnyShapeStyle(CooksyTheme.goldShimmer)
                              : AnyShapeStyle(CooksyTheme.primaryAccentGlow))
                        .frame(width: 26, height: 26)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CooksyTheme.heroDark)
                }
                if quota.isPremium {
                    Image(systemName: "infinity")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(CooksyTheme.heroDark)
                        .padding(.trailing, 4)
                } else {
                    Text("\(quota.remainingThisWeek)/\(ImportQuotaService.freeWeeklyLimit)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.heroDark)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(quota.isPremium
                          ? AnyShapeStyle(CooksyTheme.goldShimmer.opacity(0.18))
                          : AnyShapeStyle(CooksyTheme.primaryAccentSoft))
            )
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    // MARK: - Gift pill

    private var giftPill: some View {
        Button(action: onTapGift) {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: 0xC084FC), Color(hex: 0x8B5CF6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )

                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.heroDark)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xF3E8FF))
            )
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var label: String {
        if offers.giftHasBeenWon, offers.giftOfferIsActive,
           let percent = offers.giftDiscountPercent {
            return "−\(percent) %"
        }
        return "Cadeau"
    }
}
