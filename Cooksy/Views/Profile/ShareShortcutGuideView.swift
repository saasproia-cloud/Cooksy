import SwiftUI

/// Pushed from Profile → "Ajouter le raccourci Cooksy".
/// Step-by-step guide to enable the Cooksy share extension in the iOS share
/// sheet. The "more" / "edit" flow is something users routinely miss, so we
/// walk them through it explicitly with illustrations.
struct ShareShortcutGuideView: View {
    @State private var showsImportGuide = false

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroBlock

                    stepCard(
                        number: 1,
                        title: "Ouvre la feuille de partage",
                        body: "Depuis n'importe quelle vidéo TikTok ou Instagram, appuie sur le bouton Partager (icône avec la flèche vers le haut)."
                    )

                    stepCard(
                        number: 2,
                        title: "Fais défiler la rangée d'apps",
                        body: "Si Cooksy n'apparaît pas tout de suite, fais glisser la rangée d'apps vers la gauche, puis appuie sur « Plus »."
                    )

                    stepCard(
                        number: 3,
                        title: "Active Cooksy",
                        body: "Dans la liste « Activités favorites » ou « Suggestions », repère Cooksy et active l'interrupteur. Tu peux aussi le déplacer en haut de la liste pour qu'il apparaisse en premier."
                    )

                    stepCard(
                        number: 4,
                        title: "C'est terminé",
                        body: "Cooksy reste maintenant dans ta feuille de partage. Tu peux l'utiliser sur n'importe quel lien de vidéo cuisine sans repasser par cette étape."
                    )

                    bigCTA

                    secondaryCTA

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Ajouter le raccourci Cooksy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsImportGuide) {
            ImportGuideView(onClose: { showsImportGuide = false })
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: 64, height: 64)

                    Image(systemName: "square.and.arrow.up.on.square.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Importe en un clic")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                    Text("Ajoute Cooksy à la feuille de partage iOS pour importer une recette depuis n'importe quelle app.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func stepCard(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft)
                    .frame(width: 34, height: 34)
                Text("\(number)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    /// Primary CTA — opens the visual Import Guide tutorial.
    private var bigCTA: some View {
        Button(action: { showsImportGuide = true }) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Voir le tutoriel illustré")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .padding(.top, 4)
    }

    private var secondaryCTA: some View {
        Button(action: openShareSheetExample) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                Text("Tester maintenant avec un lien d'exemple")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }

    /// Opens an example TikTok URL in Safari so the user can practise the
    /// flow on a real share sheet right after reading the guide.
    private func openShareSheetExample() {
        if let url = URL(string: "https://www.tiktok.com/@chef_jeanchristophe") {
            UIApplication.shared.open(url)
        }
    }
}
