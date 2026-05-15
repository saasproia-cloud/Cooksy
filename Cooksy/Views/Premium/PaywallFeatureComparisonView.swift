import SwiftUI

/// Free vs Premium feature comparison table.
///
/// Shows 7 capabilities side-by-side so users understand exactly what
/// they unlock. Displayed below the primary CTA (social-proof layer for
/// users who scroll before deciding).
///
/// Values are static — the quantities (5 imports, 10 recettes) match the
/// server-side limits enforced by `entitlementService.ts`.
struct PaywallFeatureComparisonView: View {

    // MARK: - Data model

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let free: CellValue
        let premium: CellValue
    }

    private enum CellValue {
        case yes
        case no
        case text(String)
    }

    private static let rows: [Row] = [
        Row(label: "Imports / semaine",       free: .text("5"),   premium: .text("Illimité")),
        Row(label: "Recettes sauvegardées",    free: .text("10"),  premium: .text("Illimitées")),
        Row(label: "Sections structurées",     free: .no,          premium: .yes),
        Row(label: "Nutrition détaillée",      free: .no,          premium: .yes),
        Row(label: "Mode guidé pas-à-pas",     free: .no,          premium: .yes),
        Row(label: "Liste de courses",         free: .no,          premium: .yes),
        Row(label: "Support prioritaire",      free: .no,          premium: .yes)
    ]

    // MARK: - Layout constants

    private let freeWidth: CGFloat  = 58
    private let premiumWidth: CGFloat = 72

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(Array(Self.rows.enumerated()), id: \.element.id) { idx, row in
                featureRow(row, isEven: idx % 2 == 0)
                if idx < Self.rows.count - 1 {
                    Divider()
                        .padding(.leading, 14)
                        .opacity(0.5)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 14, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("FONCTIONNALITÉ")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Gratuit")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: freeWidth)

            Text("Premium")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
                .frame(width: premiumWidth)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CooksyTheme.primaryText.opacity(0.035))
    }

    // MARK: - Feature row

    private func featureRow(_ row: Row, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            Text(row.label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            cellView(row.free, isPremium: false)
                .frame(width: freeWidth)

            cellView(row.premium, isPremium: true)
                .frame(width: premiumWidth)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isEven ? Color.clear : CooksyTheme.primaryText.opacity(0.015))
    }

    // MARK: - Cell rendering

    @ViewBuilder
    private func cellView(_ value: CellValue, isPremium: Bool) -> some View {
        switch value {
        case .yes:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    isPremium
                    ? AnyShapeStyle(CooksyTheme.accentGradient)
                    : AnyShapeStyle(Color.green.opacity(0.7))
                )
        case .no:
            Image(systemName: "xmark.circle")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.5))
        case .text(let str):
            Text(str)
                .font(.system(size: 12, weight: isPremium ? .bold : .semibold, design: .rounded))
                .foregroundStyle(
                    isPremium
                    ? CooksyTheme.primaryAccentStrong
                    : CooksyTheme.secondaryText
                )
                .multilineTextAlignment(.center)
        }
    }
}
