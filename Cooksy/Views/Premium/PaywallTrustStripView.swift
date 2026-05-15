import SwiftUI

/// Three-item trust strip displayed below the feature comparison.
///
/// Addresses the top conversion objections: payment safety, commitment
/// anxiety and cancellation friction. Shown after the CTA so it reads
/// as a reassurance layer rather than a pre-sell element.
struct PaywallTrustStripView: View {

    private struct TrustItem {
        let icon: String
        let line1: String
        let line2: String
    }

    private static let items: [TrustItem] = [
        TrustItem(icon: "lock.shield.fill",        line1: "Paiement",   line2: "sécurisé Apple"),
        TrustItem(icon: "arrow.counterclockwise",  line1: "Annulation", line2: "à tout moment"),
        TrustItem(icon: "checkmark.seal.fill",     line1: "Sans",       line2: "engagement")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.items.enumerated()), id: \.offset) { idx, item in
                trustItem(item)
                    .frame(maxWidth: .infinity)
                if idx < Self.items.count - 1 {
                    Rectangle()
                        .fill(CooksyTheme.stroke)
                        .frame(width: 1, height: 36)
                }
            }
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func trustItem(_ item: TrustItem) -> some View {
        VStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)

            VStack(spacing: 1) {
                Text(item.line1)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(item.line2)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .multilineTextAlignment(.center)
        }
    }
}
