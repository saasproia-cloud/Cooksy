import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        LegalDocumentView(
            title: "Conditions d'utilisation",
            lastUpdated: "1er mai 2026",
            intro: """
            Bienvenue sur Cooksy. En utilisant l'application, tu acceptes les conditions ci-dessous. \
            Lis-les attentivement — elles définissent les règles du jeu entre toi et nous.
            """,
            sections: [
                LegalSection(
                    title: "1. Acceptation des conditions",
                    body: """
                    En créant un compte ou en utilisant Cooksy, tu confirmes avoir lu et accepté \
                    ces conditions ainsi que notre politique de confidentialité. Si tu n'es pas \
                    d'accord, n'utilise pas l'application.
                    """
                ),
                LegalSection(
                    title: "2. Compte utilisateur",
                    body: """
                    Tu es responsable de la confidentialité de tes identifiants et de toute activité \
                    réalisée depuis ton compte. Tu dois avoir au moins 13 ans pour utiliser Cooksy \
                    (16 ans dans certains pays de l'UE). Un seul compte par personne.
                    """
                ),
                LegalSection(
                    title: "3. Contenu utilisateur",
                    body: """
                    Tu restes propriétaire des recettes, photos et notes que tu importes ou crées. \
                    En les ajoutant à Cooksy, tu nous accordes uniquement les droits techniques \
                    nécessaires pour te les afficher et les synchroniser sur tes appareils. Tu \
                    t'engages à ne pas importer de contenu illégal ou portant atteinte aux droits \
                    d'autrui.
                    """
                ),
                LegalSection(
                    title: "4. Cooksy Plus — abonnement",
                    body: """
                    Cooksy Plus est un abonnement payant à renouvellement automatique géré par \
                    Apple via l'App Store. Le paiement est prélevé sur ton compte iTunes/App Store \
                    à la confirmation. Le renouvellement intervient 24 h avant la fin de la période \
                    en cours, sauf annulation. Tu peux gérer ou annuler ton abonnement à tout \
                    moment depuis Réglages → ton identifiant Apple → Abonnements. La résiliation \
                    prend effet à la fin de la période payée.
                    """
                ),
                LegalSection(
                    title: "5. Bon usage",
                    body: """
                    Tu t'engages à ne pas tenter de pirater l'app, contourner les limites de quota, \
                    revendre l'accès à ton compte, ou utiliser des moyens automatisés (bots, \
                    scrapers) pour interagir avec le service.
                    """
                ),
                LegalSection(
                    title: "6. Limitation de responsabilité",
                    body: """
                    Cooksy est fourni « tel quel ». Nous faisons de notre mieux pour que les \
                    recettes générées soient fiables, mais nous ne pouvons garantir leur exactitude \
                    nutritionnelle ou la sécurité d'un plat préparé chez toi. Vérifie toujours les \
                    ingrédients (notamment en cas d'allergie) et les températures de cuisson. Notre \
                    responsabilité est limitée au montant payé pour ton abonnement sur les 12 \
                    derniers mois.
                    """
                ),
                LegalSection(
                    title: "7. Suspension / résiliation",
                    body: """
                    Nous pouvons suspendre ou supprimer un compte qui violerait ces conditions. \
                    Tu peux supprimer ton compte à tout moment depuis l'application ou en nous \
                    écrivant à saasproia@gmail.com.
                    """
                ),
                LegalSection(
                    title: "8. Modifications des conditions",
                    body: """
                    Nous pouvons faire évoluer ces conditions. Les changements significatifs te \
                    seront notifiés dans l'app. La poursuite de l'utilisation après notification \
                    vaut acceptation.
                    """
                ),
                LegalSection(
                    title: "9. Droit applicable",
                    body: """
                    Ces conditions sont régies par le droit français. En cas de litige, une \
                    solution amiable sera recherchée en priorité. À défaut, les tribunaux \
                    compétents seront ceux du ressort du domicile du défendeur ou du lieu \
                    d'exécution du service.
                    """
                )
            ]
        )
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}
