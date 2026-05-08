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
    @StateObject private var rewards = InviteRewardService.shared

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
                    Text("\(min(quota.remainingThisWeek, quota.weeklyLimit))/\(quota.weeklyLimit)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.heroDark)
                    bonusBoltAccent
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

    /// Tiny bolt rendered after the count for free users to surface the
    /// invite-reward bonus slot:
    /// - Green active when the bonus is earned.
    /// - Muted gray-green ghost when still locked — the parent button
    ///   already routes the tap to the weekly imports sheet, where the
    ///   user can interact with the larger bonus bolt to reach the
    ///   invite-friends page.
    @ViewBuilder
    private var bonusBoltAccent: some View {
        if rewards.bonusUnlocked {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x6DAA5E), Color(hex: 0x4D8B47)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 22, height: 22)
                    .shadow(color: Color(hex: 0x6DAA5E).opacity(0.45), radius: 4, y: 1)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xC8DDC0).opacity(0.65))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: 0x6DAA5E).opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(hex: 0x4D8B47).opacity(0.6))
            }
        }
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

// MARK: - Fresh-gift celebration toast

/// Small auto-presented banner that fires the first time the user opens
/// the app after a gift cooldown elapses — i.e. their previous gift
/// expired without claim and a fresh one is now available.
///
/// Acknowledging happens explicitly: tapping "Jouer" opens the wheel
/// and clears the flag; tapping the X also clears it. The toast won't
/// re-appear next launch unless another full reissue cycle completes.
struct FreshGiftCelebrationToast: View {
    let onTapPlay: () -> Void
    let onDismiss: () -> Void

    @State private var pulse: Bool = false
    @State private var sparkleTick: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xC084FC), Color(hex: 0x8B5CF6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color(hex: 0x8B5CF6).opacity(0.45), radius: 8, y: 3)
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.08 : 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Nouveau cadeau disponible !")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                Text("Retente ta chance et débloque ta remise.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onTapPlay) {
                Text("Jouer")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(CooksyTheme.accentGradient))
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(CooksyTheme.pressScale())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: 0x8B5CF6).opacity(0.45), lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x8B5CF6).opacity(0.18), radius: 16, y: 6)
        )
        .padding(.horizontal, 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
