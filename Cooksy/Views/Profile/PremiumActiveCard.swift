import SwiftUI

/// Replaces `ProfilePremiumBanner` when the user already has Cooksy Plus.
struct PremiumActiveCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.goldShimmer)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: 0xF5B14E).opacity(0.45), radius: 8, y: 3)

                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x6B3B03).opacity(0.4), radius: 0.6, y: 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Cooksy Plus actif")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6B3B03))
                }

                Text("Membre Premium — Recettes illimitées")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(CooksyTheme.warmCard)

                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(CooksyTheme.goldShimmer.opacity(0.18))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5B14E).opacity(0.7),
                            Color(hex: 0xFFE0A0).opacity(0.5),
                            Color(hex: 0xF5B14E).opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        PremiumActiveCard()
    }
    .padding(20)
    .background(CooksyTheme.background)
}
