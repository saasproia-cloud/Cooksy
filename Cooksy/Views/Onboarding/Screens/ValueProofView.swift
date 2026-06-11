import SwiftUI

/// A3 — Three-card value proposition + social proof stat.
/// Cards appear in cascade. The star rating animates counting up to 4.8.
struct ValueProofView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        OnboardingChrome(
            title: "Pourquoi 24\u{00A0}000 gourmets ont adopté Cooksy.",
            subtitle: "La cuisine te revient simple — comme elle aurait toujours dû l'être.",
            ctaTitle: "Personnaliser mon expérience",
            canAdvance: true,
            progress: nil,
            showsBack: true,
            showsSkip: false,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 14) {
                ValueCard(
                    index: 0,
                    appeared: appeared,
                    systemImage: "bookmark.fill",
                    title: "Jamais perdre une recette",
                    detail: "Sauve tous tes Reels et TikToks cuisine en un tap. Ils sont rangés, classés, cherchables."
                )

                ValueCard(
                    index: 1,
                    appeared: appeared,
                    systemImage: "wand.and.stars",
                    title: "Structure parfaite",
                    detail: "Ingrédients, étapes, sections — toujours clair, toujours cuisinable. Pas de vidéo à re-scroller."
                )

                ValueCard(
                    index: 2,
                    appeared: appeared,
                    systemImage: "cart.fill",
                    title: "Plan repas + liste de courses",
                    detail: "On te propose quoi cuisiner, on te fait la liste. Tu gagnes une heure par semaine."
                )

                Spacer(minLength: 12)

                SocialProofStrip(appeared: appeared)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.7), value: appeared)
            }
            .padding(.top, 6)
            .onAppear {
                appeared = false
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    await MainActor.run { appeared = true }
                }
            }
        }
    }
}

// MARK: - Value card

private struct ValueCard: View {
    let index: Int
    let appeared: Bool
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.28), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 10, y: 6)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(
            .spring(response: 0.55, dampingFraction: 0.82).delay(0.18 + Double(index) * 0.12),
            value: appeared
        )
    }
}

// MARK: - Social proof

private struct SocialProofStrip: View {
    let appeared: Bool
    @State private var displayedRating: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < Int(displayedRating.rounded()) ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CooksyTheme.sparkleYellow)
                }
            }

            Text(String(format: "%.1f", displayedRating))
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .monospacedDigit()

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(width: 1, height: 22)

            Text("24\u{00A0}000+ passionnés de cuisine")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.warmCard.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.warmCardMuted.opacity(0.5), lineWidth: 1)
        )
        .onChange(of: appeared) { _, newValue in
            guard newValue else { return }
            withAnimation(.easeOut(duration: 1.2).delay(0.8)) {
                displayedRating = 4.8
            }
        }
    }
}
