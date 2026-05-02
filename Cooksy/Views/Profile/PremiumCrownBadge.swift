import SwiftUI

/// Small circular crown badge designed to overlap a profile avatar.
///
/// Two visual states share the same footprint so layout never shifts:
/// - **Premium (true)**: warm gold gradient with a glow — celebratory.
/// - **Premium (false)**: muted, desaturated greys — a "locked" teaser
///   inviting the user to upgrade. Tapping the locked state can route to
///   the paywall via the optional `onTapWhenLocked` closure.
///
/// Usage:
/// ```
/// AvatarCircle(...)
///     .overlay(alignment: .topTrailing) {
///         PremiumCrownBadge(isPremium: store.isPremium)
///             .offset(x: 4, y: -4)
///     }
/// ```
struct PremiumCrownBadge: View {
    let isPremium: Bool
    var size: CGFloat = 22
    var onTapWhenLocked: (() -> Void)? = nil

    private var iconSize: CGFloat { size * 0.55 }
    private var strokeWidth: CGFloat { max(1, size * 0.08) }

    var body: some View {
        Group {
            if isPremium {
                premiumBody
            } else {
                lockedBody
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Premium (gold)

    private var premiumBody: some View {
        ZStack {
            Circle()
                .fill(CooksyTheme.goldShimmer)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: strokeWidth)
                )
                .shadow(color: Color(hex: 0xF5B14E).opacity(0.55), radius: size * 0.35, y: 1)

            Image(systemName: "crown.fill")
                .font(.system(size: iconSize, weight: .black))
                .foregroundStyle(Color.white)
                .shadow(color: Color(hex: 0x6B3B03).opacity(0.35), radius: 0.6, y: 0.5)
        }
        .frame(width: size, height: size)
    }

    // MARK: Locked (greyed-out — non-premium teaser)

    private var lockedBody: some View {
        Button {
            onTapWhenLocked?()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(white: 0.92))
                    .overlay(
                        Circle()
                            .stroke(Color(white: 0.78), lineWidth: strokeWidth)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: size * 0.18, y: 1)

                Image(systemName: "crown.fill")
                    .font(.system(size: iconSize, weight: .black))
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(onTapWhenLocked == nil)
    }
}

#Preview {
    HStack(spacing: 28) {
        VStack(spacing: 12) {
            Circle()
                .fill(CooksyTheme.warmCard)
                .frame(width: 72, height: 72)
                .overlay(
                    PremiumCrownBadge(isPremium: true)
                        .offset(x: 28, y: -28)
                )
            Text("Premium")
                .font(.caption)
        }

        VStack(spacing: 12) {
            Circle()
                .fill(CooksyTheme.softCloud)
                .frame(width: 72, height: 72)
                .overlay(
                    PremiumCrownBadge(isPremium: false, onTapWhenLocked: {})
                        .offset(x: 28, y: -28)
                )
            Text("Verrouillé")
                .font(.caption)
        }

        VStack(spacing: 8) {
            PremiumCrownBadge(isPremium: true, size: 14)
            PremiumCrownBadge(isPremium: false, size: 14, onTapWhenLocked: {})
            Text("14pt")
                .font(.caption2)
        }
    }
    .padding(40)
    .background(CooksyTheme.background)
}
