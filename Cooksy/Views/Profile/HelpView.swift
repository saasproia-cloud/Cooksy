import SwiftUI

/// Pushed from Profile → "Aide".
/// Real help center with collapsible FAQ + a contact button that opens
/// the user's mail client pre-filled with a support template.
struct HelpView: View {
    @State private var expanded: Set<String> = []

    private let faqs: [FAQItem] = [
        FAQItem(
            id: "import",
            question: "Comment importer une recette ?",
            answer: "Tu as deux moyens : depuis l'app, appuie sur le bouton + et colle un lien TikTok / Instagram. Ou depuis n'importe quelle app, appuie sur le bouton Partager et choisis Cooksy. L'extraction prend environ 15 secondes."
        ),
        FAQItem(
            id: "share-sheet",
            question: "Cooksy n'apparaît pas dans la feuille de partage",
            answer: "C'est normal au premier lancement. Ouvre une feuille de partage, fais glisser la rangée d'apps vers la gauche, appuie sur « Plus », puis active Cooksy. Il restera ensuite disponible en permanence."
        ),
        FAQItem(
            id: "quota",
            question: "Combien de recettes puis-je importer ?",
            answer: "Avec le plan gratuit, tu peux importer jusqu'à 3 recettes par semaine. Avec Cooksy Plus, c'est illimité, et tu débloques aussi l'IA avancée pour des recettes plus précises."
        ),
        FAQItem(
            id: "premium",
            question: "Comment fonctionne Cooksy Plus ?",
            answer: "Cooksy Plus est un abonnement géré via l'App Store. Le paiement est prélevé sur ton compte Apple. Tu peux annuler à tout moment depuis Réglages → ton identifiant Apple → Abonnements. La résiliation prend effet à la fin de la période payée."
        ),
        FAQItem(
            id: "edit-profile",
            question: "Comment changer ma photo ou mon nom ?",
            answer: "Depuis l'onglet Profil, appuie sur « Modifier le profil ». Tu peux changer ta photo (depuis ta galerie) et ton nom affiché. Les modifications sont synchronisées sur tous tes appareils."
        ),
        FAQItem(
            id: "wrong-recipe",
            question: "La recette extraite est incorrecte ou incomplète",
            answer: "L'extraction dépend de la qualité de la légende et de l'audio. Tu peux toujours modifier manuellement la recette après import : ouvre-la, appuie sur « Modifier », et corrige les ingrédients ou les étapes."
        ),
        FAQItem(
            id: "delete-account",
            question: "Comment supprimer mon compte ?",
            answer: "Écris-nous à saasproia@gmail.com en précisant l'adresse e-mail liée à ton compte. Nous supprimons toutes tes données dans un délai de 30 jours, conformément au RGPD."
        ),
        FAQItem(
            id: "languages",
            question: "Cooksy va-t-il être traduit en anglais ?",
            answer: "Oui, c'est prévu. Pour le moment l'app est uniquement en français pour qu'on puisse soigner chaque détail. Les autres langues arriveront dans une prochaine mise à jour."
        )
    ]

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    Text("FAQ")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .padding(.top, 4)

                    VStack(spacing: 8) {
                        ForEach(faqs) { item in
                            FAQRow(
                                item: item,
                                isExpanded: expanded.contains(item.id),
                                onToggle: { toggle(item.id) }
                            )
                        }
                    }

                    Text("CONTACT")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .padding(.top, 12)

                    contactCard

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Aide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 56, height: 56)

                Image(systemName: "lifepreserver.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("On est là pour t'aider")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Trouve une réponse rapide ou écris-nous directement.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var contactCard: some View {
        VStack(spacing: 12) {
            Text("Pas trouvé ce que tu cherches ?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: openMail) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Écrire à l'équipe Cooksy")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
                .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(CooksyTheme.pressScale())

            Text("Réponse sous 48 h en moyenne (jours ouvrés).")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func toggle(_ id: String) {
        OnboardingHaptics.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }

    private func openMail() {
        let subject = "Aide Cooksy"
        let body = "Bonjour,\n\nJe rencontre la situation suivante :\n\n\n\n— Mon iPhone : \(UIDevice.current.model)\n— Version iOS : \(UIDevice.current.systemVersion)\n"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailto = "mailto:saasproia@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: mailto) {
            UIApplication.shared.open(url)
        }
    }
}

private struct FAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

private struct FAQRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 12) {
                    Text(item.question)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(item.answer)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}
