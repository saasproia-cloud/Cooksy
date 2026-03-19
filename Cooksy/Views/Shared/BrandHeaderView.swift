import SwiftUI

struct BrandHeaderView: View {
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("Cooksy")
                        .font(.custom("AvenirNext-HeavyItalic", size: 34))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("atelier")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.blush.opacity(0.85))
                        )
                }

                Text("Capturez une idée, Cooksy la transforme en recette claire, belle et retrouvable.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(CooksyTheme.heroGlowGradient)
                    .frame(width: 104, height: 104)
                    .blur(radius: 1)

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 94, height: 94)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1.5)
                    )
                    .shadow(color: CooksyTheme.shadow, radius: 18, y: 12)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1.2)
                )
                .shadow(color: CooksyTheme.softShadow, radius: 18, y: 10)
        )
    }
}
