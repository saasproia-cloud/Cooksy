import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(
            title: "Politique de confidentialité",
            lastUpdated: "1er mai 2026",
            intro: """
            Cooksy respecte ta vie privée. Cette politique explique quelles données nous collectons, \
            pourquoi, comment elles sont stockées, et quels sont tes droits. Elle s'applique à \
            l'application Cooksy sur iOS et à ses services associés.
            """,
            sections: [
                LegalSection(
                    title: "1. Données que nous collectons",
                    body: """
                    Lorsque tu crées un compte : ton adresse e-mail, ton nom (si tu le fournis ou si \
                    Sign in with Apple le partage), et un identifiant unique. Lorsque tu utilises \
                    l'app : les recettes que tu importes ou crées, ta liste de courses, tes plans \
                    de repas, tes préférences culinaires (objectifs, régime, allergies, cuisines), \
                    ainsi que ta photo de profil si tu en ajoutes une.
                    """
                ),
                LegalSection(
                    title: "2. Pourquoi nous collectons ces données",
                    body: """
                    Pour faire fonctionner l'app : afficher tes recettes, synchroniser entre appareils, \
                    personnaliser les suggestions, gérer ton abonnement Cooksy Plus le cas échéant. \
                    Nous n'utilisons pas tes données pour faire de la publicité et nous ne les vendons \
                    à personne.
                    """
                ),
                LegalSection(
                    title: "3. Stockage et hébergement",
                    body: """
                    Tes données sont stockées chez Supabase (infrastructure hébergée en Europe). Les \
                    photos de profil et de recettes sont stockées dans un espace privé, accessible \
                    uniquement par toi via ton compte. Les communications avec nos serveurs sont \
                    chiffrées (HTTPS/TLS).
                    """
                ),
                LegalSection(
                    title: "4. Cookies et analytics",
                    body: """
                    L'app n'utilise pas de cookies tiers. Nous utilisons des outils techniques pour \
                    diagnostiquer les pannes (logs anonymisés). Aucune donnée personnelle n'est \
                    transmise à des régies publicitaires.
                    """
                ),
                LegalSection(
                    title: "5. Tes droits (RGPD)",
                    body: """
                    Tu peux à tout moment : accéder à tes données, les rectifier, les exporter, ou \
                    demander leur suppression. Pour cela, écris-nous à azizelghazel@gmail.com en \
                    précisant l'adresse e-mail liée à ton compte. Nous répondons sous 30 jours.
                    """
                ),
                LegalSection(
                    title: "6. Suppression de compte",
                    body: """
                    La suppression de ton compte entraîne la suppression définitive de toutes tes \
                    recettes, plans de repas et données personnelles dans un délai de 30 jours. \
                    Certaines données peuvent être conservées plus longtemps si la loi l'exige \
                    (par exemple, factures liées à un abonnement).
                    """
                ),
                LegalSection(
                    title: "7. Modifications",
                    body: """
                    Nous pouvons mettre à jour cette politique pour refléter des changements \
                    techniques ou légaux. La date de dernière mise à jour est indiquée en haut de \
                    cette page. Si les changements sont significatifs, nous t'en informerons dans \
                    l'app.
                    """
                ),
                LegalSection(
                    title: "8. Responsable du traitement",
                    body: """
                    Cooksy — contact azizelghazel@gmail.com. Pour toute réclamation, tu peux aussi \
                    saisir la CNIL (cnil.fr) ou ton autorité locale de protection des données.
                    """
                )
            ]
        )
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
