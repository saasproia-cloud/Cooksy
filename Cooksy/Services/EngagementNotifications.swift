import Foundation

/// One engagement notification variant.
///
/// The scheduler in `NotificationScheduler.scheduleEngagementQueue()` picks
/// from this pool to fill the next 7 days of pending local pushes, ensuring
/// variety in tone, category, and time-of-day so the user never sees the
/// same nudge twice within a 30-day window.
///
/// Copy guidelines applied across every variant:
///   • tutoiement, no jargon
///   • ≤40 chars title, ≤120 chars body so the banner renders fully
///   • opens a curiosity gap, makes a specific promise, or asks a question
///   • emoji optional, never more than one
///   • French-FR locale
struct EngagementTemplate {
    let id: String
    let category: Category
    let title: String
    let body: String
    let deepLink: String
    /// Preferred local-time hour to fire (0–23). The scheduler clamps to
    /// the FR daytime window 9:00–20:00 — any value outside that range
    /// will be pushed inside.
    let preferredHour: Int
    let preferredMinute: Int
    /// Restrict to a specific day of the week. `nil` = any day.
    /// 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday)`).
    let weekday: Int?
    /// Some copy (e.g. "tu nous manques") feels off when the user is
    /// active. Templates flagged here only fire for users idle 3+ days.
    let requiresInactivity: Bool

    enum Category: String, CaseIterable {
        case curiosity      // open a question, tease a reveal
        case mealtime       // contextual at lunch/dinner hour
        case weekend        // Saturday/Sunday specific
        case streak         // gamified progress
        case discovery      // surface trending content
        case reactivation   // gentle pull-back for idle users
    }

    /// The complete catalogue. Adding a new variant here is the only
    /// step needed to surface it — the scheduler picks it up next launch.
    static let pool: [EngagementTemplate] = [

        // MARK: Curiosity (10)

        EngagementTemplate(
            id: "engagement.curiosity.1",
            category: .curiosity,
            title: "Devine la recette la plus copiée 👀",
            body: "Importée 1247 fois cette semaine. Tu cliques ?",
            deepLink: "cooksy://home/trending",
            preferredHour: 18, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.2",
            category: .curiosity,
            title: "On a trouvé l'astuce qui change tout 🤫",
            body: "Une technique anti-coller pour les pâtes. Bluffant.",
            deepLink: "cooksy://library",
            preferredHour: 12, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.3",
            category: .curiosity,
            title: "Une recette virale sans bla-bla",
            body: "Juste les ingrédients et les étapes. Promis.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.4",
            category: .curiosity,
            title: "Pourquoi cette recette TikTok marche autant ?",
            body: "On a décrypté. Spoiler : c'est pas l'huile.",
            deepLink: "cooksy://home/trending",
            preferredHour: 19, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.5",
            category: .curiosity,
            title: "Tu vois cette vidéo qui tourne ?",
            body: "On l'a transformée en recette claire pour toi.",
            deepLink: "cooksy://import",
            preferredHour: 18, preferredMinute: 30,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.6",
            category: .curiosity,
            title: "10 secondes pour une vraie révélation 🍳",
            body: "On a testé en cuisine. Ça vaut le détour.",
            deepLink: "cooksy://library",
            preferredHour: 15, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.7",
            category: .curiosity,
            title: "Cette épice change 3 plats que tu aimes",
            body: "On te dit lesquels dans l'app.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.8",
            category: .curiosity,
            title: "On a trouvé pourquoi tes pâtes accrochent 👀",
            body: "Pas ce que tu crois. Promis.",
            deepLink: "cooksy://home",
            preferredHour: 19, preferredMinute: 30,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.9",
            category: .curiosity,
            title: "Un secret de chef qu'aucun resto révèle 🤐",
            body: "On l'a chopé. C'est dans l'app.",
            deepLink: "cooksy://home",
            preferredHour: 16, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.curiosity.10",
            category: .curiosity,
            title: "La technique que TOUS les chefs cachent 🔪",
            body: "Trop simple pour être enseignée. La voici.",
            deepLink: "cooksy://library",
            preferredHour: 14, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),

        // MARK: Mealtime (6)

        EngagementTemplate(
            id: "engagement.mealtime.lunch.1",
            category: .mealtime,
            title: "L'heure du déj 🥗",
            body: "Une idée rapide pour aujourd'hui ?",
            deepLink: "cooksy://home",
            preferredHour: 12, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.mealtime.lunch.2",
            category: .mealtime,
            title: "Pause déj dans 30 min ?",
            body: "On a un plat sain et rapide pour toi.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 30,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.mealtime.dinner.1",
            category: .mealtime,
            title: "Ce soir, tu cuisines quoi ?",
            body: "On peut t'aider à choisir en 3 questions.",
            deepLink: "cooksy://library",
            preferredHour: 18, preferredMinute: 30,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.mealtime.dinner.2",
            category: .mealtime,
            title: "L'heure du dîner 🍽️",
            body: "Cherche pas, on a la recette qu'il te faut.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 30,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.mealtime.aperitif",
            category: .mealtime,
            title: "Apéro improvisé ce soir ? 🍷",
            body: "Avec 3 ingrédients, t'as un truc bluffant.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.mealtime.breakfast",
            category: .mealtime,
            title: "Bonjour ✨",
            body: "Un petit déj qui change pour bien commencer ?",
            deepLink: "cooksy://home",
            preferredHour: 9, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),

        // MARK: Weekend (4)

        EngagementTemplate(
            id: "engagement.weekend.brunch.sat",
            category: .weekend,
            title: "Ton samedi mérite une recette qui claque",
            body: "On en a 8. Choisis.",
            deepLink: "cooksy://library",
            preferredHour: 11, preferredMinute: 0,
            weekday: 7, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.weekend.brunch.sun",
            category: .weekend,
            title: "Dimanche, jour du brunch ☕",
            body: "On t'a préparé une sélection juste pour toi.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0,
            weekday: 1, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.weekend.batch.sat",
            category: .weekend,
            title: "Samedi cuisine = semaine sereine 🍱",
            body: "Batch cooking en 1h. On te montre.",
            deepLink: "cooksy://plan",
            preferredHour: 10, preferredMinute: 30,
            weekday: 7, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.weekend.mealprep.sun",
            category: .weekend,
            title: "Prêt à préparer la semaine ?",
            body: "5 recettes, 1 liste de courses, 10 minutes.",
            deepLink: "cooksy://plan",
            preferredHour: 17, preferredMinute: 30,
            weekday: 1, requiresInactivity: false
        ),

        // MARK: Streak / Progress (4)

        EngagementTemplate(
            id: "engagement.streak.2days",
            category: .streak,
            title: "2 jours d'affilée en cuisine 🔥",
            body: "Ne casse pas la chaîne ce soir.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.streak.badge",
            category: .streak,
            title: "Ton 1er badge dans 2 recettes 👀",
            body: "Continue, c'est bientôt à toi.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.streak.weekly",
            category: .streak,
            title: "Ta semaine en cuisine, en chiffres 📊",
            body: "Tu progresses. On te montre comment.",
            deepLink: "cooksy://profile/stats",
            preferredHour: 11, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.streak.organize",
            category: .streak,
            title: "10 recettes, c'est pas rien 💪",
            body: "Range-les en collections pour t'y retrouver.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),

        // MARK: Discovery (8)

        EngagementTemplate(
            id: "engagement.discovery.viral.1",
            category: .discovery,
            title: "3 recettes virales viennent d'arriver 🚀",
            body: "Les plus partagées cette semaine, décryptées.",
            deepLink: "cooksy://home/trending",
            preferredHour: 16, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.viral.2",
            category: .discovery,
            title: "Une vidéo à 5M de vues, vraiment ?",
            body: "Cette recette mérite ton attention.",
            deepLink: "cooksy://home/trending",
            preferredHour: 14, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.ramen",
            category: .discovery,
            title: "Bestseller du jour : Ramen express 🍜",
            body: "8 min, 4 ingrédients. Fou.",
            deepLink: "cooksy://home/trending",
            preferredHour: 17, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.creator",
            category: .discovery,
            title: "Cette créatrice TikTok explose 💥",
            body: "Ses 3 recettes phares sont sur Cooksy.",
            deepLink: "cooksy://home/trending",
            preferredHour: 18, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.reel",
            category: .discovery,
            title: "Un Reel à 2M de vues, décrypté",
            body: "Ouvre — c'est court et c'est bon.",
            deepLink: "cooksy://home/trending",
            preferredHour: 11, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.weekend_hit",
            category: .discovery,
            title: "Top recette du week-end dernier",
            body: "Elle a régalé +1000 personnes. À toi de jouer.",
            deepLink: "cooksy://home/trending",
            preferredHour: 12, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.chef",
            category: .discovery,
            title: "Sélection chef invité 👨‍🍳",
            body: "3 recettes signature, importées pour toi.",
            deepLink: "cooksy://home/trending",
            preferredHour: 15, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),
        EngagementTemplate(
            id: "engagement.discovery.asia",
            category: .discovery,
            title: "La cuisine du moment, c'est asiatique",
            body: "5 recettes virales qu'on a chopées.",
            deepLink: "cooksy://home/trending",
            preferredHour: 19, preferredMinute: 0,
            weekday: nil, requiresInactivity: false
        ),

        // MARK: Soft reactivation (5) — only fire when user is idle 3+ days

        EngagementTemplate(
            id: "engagement.react.come_back",
            category: .reactivation,
            title: "Tu reviens quand tu veux 🤍",
            body: "On a sauvé tes recettes au chaud.",
            deepLink: "cooksy://library",
            preferredHour: 11, preferredMinute: 0,
            weekday: nil, requiresInactivity: true
        ),
        EngagementTemplate(
            id: "engagement.react.new_recipes",
            category: .reactivation,
            title: "2 nouvelles recettes pour toi 🎁",
            body: "Sélectionnées exprès. Sans pression.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0,
            weekday: nil, requiresInactivity: true
        ),
        EngagementTemplate(
            id: "engagement.react.reel",
            category: .reactivation,
            title: "Un Reel qui pourrait te plaire 👀",
            body: "On l'a transformé en recette. Rapide.",
            deepLink: "cooksy://import",
            preferredHour: 18, preferredMinute: 30,
            weekday: nil, requiresInactivity: true
        ),
        EngagementTemplate(
            id: "engagement.react.waiting",
            category: .reactivation,
            title: "Ta dernière recette t'attend toujours",
            body: "Cuisine-la quand tu veux. On garde tout.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0,
            weekday: nil, requiresInactivity: true
        ),
        EngagementTemplate(
            id: "engagement.react.express",
            category: .reactivation,
            title: "Cooksy en 5 min ce soir ?",
            body: "Une recette express, c'est tout.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 0,
            weekday: nil, requiresInactivity: true
        )
    ]
}
