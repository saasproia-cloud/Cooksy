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

        // ====================================================================
        // CURIOSITÉ — questions, teasings, révélations (15)
        // ====================================================================

        EngagementTemplate(id: "curiosity.guess_viral", category: .curiosity,
            title: "🤔 Devine la recette la plus copiée…",
            body: "Importée 1247 fois cette semaine. Tu cliques pour voir ?",
            deepLink: "cooksy://home/trending",
            preferredHour: 18, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.pasta_secret", category: .curiosity,
            title: "🤫 L'astuce pâtes que personne ne partage",
            body: "Anti-coller, anti-fades, anti-trop salées. Test ce soir ?",
            deepLink: "cooksy://library",
            preferredHour: 12, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.no_bs", category: .curiosity,
            title: "✨ Une recette virale, zéro bla-bla",
            body: "Juste ingrédients + étapes claires. C'est rare, profite.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.tiktok_why", category: .curiosity,
            title: "👀 Pourquoi cette recette TikTok cartonne ?",
            body: "On a décrypté. Spoiler : c'est PAS l'huile 🌶️",
            deepLink: "cooksy://home/trending",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.reel_seen", category: .curiosity,
            title: "🎥 Tu vois ce Reel qui tourne ?",
            body: "On l'a transformé en recette claire. 30 sec à lire.",
            deepLink: "cooksy://import",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.10s_reveal", category: .curiosity,
            title: "🍳 10 secondes pour une révélation cuisine",
            body: "On a testé. Ça vaut le coup, vraiment.",
            deepLink: "cooksy://library",
            preferredHour: 15, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.spice", category: .curiosity,
            title: "🌶️ Cette épice change 3 plats que tu adores",
            body: "On te dit lesquels dans l'app. Promis, c'est bluffant.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.salty_pasta", category: .curiosity,
            title: "🧂 Pourquoi tes pâtes sont trop salées ?",
            body: "Pas ce que tu crois. La vraie raison est dans l'app 👀",
            deepLink: "cooksy://home",
            preferredHour: 19, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.chef_secret", category: .curiosity,
            title: "🤐 Un secret de chef qu'aucun resto ne révèle",
            body: "On l'a chopé. C'est trop simple pour être enseigné.",
            deepLink: "cooksy://home",
            preferredHour: 16, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.knife_trick", category: .curiosity,
            title: "🔪 La technique cachée des chefs",
            body: "Trop évidente pour être partagée. La voici.",
            deepLink: "cooksy://library",
            preferredHour: 14, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.10min_fancy", category: .curiosity,
            title: "⏱️ Un dîner gastro en 10 minutes ?",
            body: "Spoiler : c'est possible. La recette est prête.",
            deepLink: "cooksy://home/trending",
            preferredHour: 17, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.expensive_taste", category: .curiosity,
            title: "💸 Mange comme au resto, sans payer le resto",
            body: "5 recettes qui font illusion. Et c'est facile.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.5ingredients", category: .curiosity,
            title: "🛒 5 ingrédients. 1 plat fou.",
            body: "Tu as déjà tout dans ton frigo. Promis.",
            deepLink: "cooksy://library",
            preferredHour: 11, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.failed_recipe", category: .curiosity,
            title: "🆘 Ta dernière recette a foiré ?",
            body: "On a la solution. 2 ajustements et c'est gagné.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "curiosity.fridge_magic", category: .curiosity,
            title: "🪄 Ton frigo cache une recette qui claque",
            body: "On t'aide à la trouver en 3 questions.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        // ====================================================================
        // MEALTIME (10)
        // ====================================================================

        EngagementTemplate(id: "mealtime.lunch_hello", category: .mealtime,
            title: "🥗 L'heure du déj approche",
            body: "Une idée rapide et bonne pour aujourd'hui ?",
            deepLink: "cooksy://home",
            preferredHour: 12, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.lunch_30min", category: .mealtime,
            title: "🍱 Pause déj dans 30 min ?",
            body: "On a un truc sain qui se fait en 15. Cliquable.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.dinner_help", category: .mealtime,
            title: "🍽️ Ce soir, tu cuisines quoi ?",
            body: "On t'aide à choisir en 3 questions. Sans pression.",
            deepLink: "cooksy://library",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.dinner_ready", category: .mealtime,
            title: "🔥 L'heure du dîner, ça se prépare",
            body: "Cherche pas, on a LA recette qu'il te faut.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.aperitif", category: .mealtime,
            title: "🍷 Apéro improvisé ce soir ?",
            body: "3 ingrédients, un truc bluffant. C'est parti.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.breakfast", category: .mealtime,
            title: "☀️ Bonjour ✨",
            body: "Un petit déj qui change pour bien démarrer ?",
            deepLink: "cooksy://home",
            preferredHour: 9, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.snack_4pm", category: .mealtime,
            title: "🍫 16h, la faim qui revient ?",
            body: "Un snack sain et rapide t'attend dans l'app.",
            deepLink: "cooksy://home",
            preferredHour: 16, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.dessert", category: .mealtime,
            title: "🍰 Tu mérites un dessert ce soir",
            body: "3 idées rapides à faire avec ce que tu as.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.lunch_rich", category: .mealtime,
            title: "🤌 Pour midi, on se fait plaisir",
            body: "Un plat gourmand et rapide. On te montre.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 45, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "mealtime.evening_quick", category: .mealtime,
            title: "⚡ 15 min en cuisine ce soir, max",
            body: "On a trois recettes qui changent. Cliquable.",
            deepLink: "cooksy://home",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        // ====================================================================
        // WEEKEND (6)
        // ====================================================================

        EngagementTemplate(id: "weekend.sat_brunch", category: .weekend,
            title: "🥞 Ton samedi mérite un truc qui claque",
            body: "On en a 8 prêts. Tu choisis, on cuisine.",
            deepLink: "cooksy://library",
            preferredHour: 11, preferredMinute: 0, weekday: 7, requiresInactivity: false),

        EngagementTemplate(id: "weekend.sun_brunch", category: .weekend,
            title: "☕ Dimanche = brunch day",
            body: "On t'a préparé une sélection juste pour toi.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0, weekday: 1, requiresInactivity: false),

        EngagementTemplate(id: "weekend.sat_batch", category: .weekend,
            title: "🍱 Samedi cuisine = semaine sereine",
            body: "Batch cooking en 1h. On te guide pas à pas.",
            deepLink: "cooksy://plan",
            preferredHour: 10, preferredMinute: 30, weekday: 7, requiresInactivity: false),

        EngagementTemplate(id: "weekend.sun_mealprep", category: .weekend,
            title: "📋 Prêt à préparer ta semaine ?",
            body: "5 recettes + 1 liste de courses + 10 min de ta vie.",
            deepLink: "cooksy://plan",
            preferredHour: 17, preferredMinute: 30, weekday: 1, requiresInactivity: false),

        EngagementTemplate(id: "weekend.sat_pizza", category: .weekend,
            title: "🍕 Samedi soir = pizza maison ?",
            body: "Pâte qui claque, garnitures qui tuent. Recette dispo.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 30, weekday: 7, requiresInactivity: false),

        EngagementTemplate(id: "weekend.sun_cozy", category: .weekend,
            title: "🛋️ Dimanche cosy en cuisine ?",
            body: "Un plat mijoté, ça mijote et c'est divin.",
            deepLink: "cooksy://library",
            preferredHour: 14, preferredMinute: 0, weekday: 1, requiresInactivity: false),

        // ====================================================================
        // STREAK / PROGRESS (5)
        // ====================================================================

        EngagementTemplate(id: "streak.2days", category: .streak,
            title: "🔥 2 jours d'affilée en cuisine",
            body: "Ne casse pas la chaîne ce soir. Allez.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "streak.badge_soon", category: .streak,
            title: "🏅 Ton 1er badge dans 2 recettes",
            body: "Continue, c'est bientôt à toi.",
            deepLink: "cooksy://library",
            preferredHour: 17, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "streak.weekly_recap", category: .streak,
            title: "📊 Ta semaine en cuisine, en chiffres",
            body: "Tu progresses. On te montre comment.",
            deepLink: "cooksy://profile/stats",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "streak.organize_10", category: .streak,
            title: "💪 10 recettes, c'est pas rien",
            body: "Range-les en collections pour mieux t'y retrouver.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "streak.cooking_pro", category: .streak,
            title: "👨‍🍳 Tu deviens un vrai cuisinier",
            body: "Voilà tes stats. Tu vas être surpris.",
            deepLink: "cooksy://profile/stats",
            preferredHour: 16, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        // ====================================================================
        // DISCOVERY — trending content (10)
        // ====================================================================

        EngagementTemplate(id: "discovery.viral_3", category: .discovery,
            title: "🚀 3 recettes virales viennent d'arriver",
            body: "Les plus partagées cette semaine, décryptées.",
            deepLink: "cooksy://home/trending",
            preferredHour: 16, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.5m_views", category: .discovery,
            title: "💥 Une vidéo à 5M de vues, vraiment ?",
            body: "Cette recette mérite ton attention. 2 min suffisent.",
            deepLink: "cooksy://home/trending",
            preferredHour: 14, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.ramen", category: .discovery,
            title: "🍜 Bestseller du jour : ramen express",
            body: "8 min, 4 ingrédients, c'est fou.",
            deepLink: "cooksy://home/trending",
            preferredHour: 17, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.creator_hit", category: .discovery,
            title: "💫 Cette créatrice TikTok explose",
            body: "Ses 3 recettes phares sont sur Cooksy. À tester.",
            deepLink: "cooksy://home/trending",
            preferredHour: 18, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.reel_2m", category: .discovery,
            title: "📱 Un Reel à 2M de vues, décrypté",
            body: "Ouvre, c'est court et c'est super bon.",
            deepLink: "cooksy://home/trending",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.weekend_hit", category: .discovery,
            title: "🌟 Top recette du week-end dernier",
            body: "Elle a régalé +1000 personnes. À ton tour.",
            deepLink: "cooksy://home/trending",
            preferredHour: 12, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.chef_select", category: .discovery,
            title: "👨‍🍳 Sélection chef invité",
            body: "3 recettes signature, importées pour toi.",
            deepLink: "cooksy://home/trending",
            preferredHour: 15, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.asian_5", category: .discovery,
            title: "🥢 La cuisine du moment, c'est asiatique",
            body: "5 recettes virales qu'on a chopées rien que pour toi.",
            deepLink: "cooksy://home/trending",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.italian", category: .discovery,
            title: "🇮🇹 Italie : 4 nouveaux classiques",
            body: "Carbonara la vraie, pizza facile, tiramisu express…",
            deepLink: "cooksy://home/trending",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        EngagementTemplate(id: "discovery.dessert_hits", category: .discovery,
            title: "🍪 Top 3 desserts qui cartonnent",
            body: "Faciles, jolis, addictifs. Choisis le tien.",
            deepLink: "cooksy://home/trending",
            preferredHour: 16, preferredMinute: 30, weekday: nil, requiresInactivity: false),

        // ====================================================================
        // SOFT REACTIVATION — only for idle 3+ days (8)
        // ====================================================================

        EngagementTemplate(id: "react.come_back", category: .reactivation,
            title: "🤍 Tu reviens quand tu veux",
            body: "On a sauvé tes recettes au chaud. Aucune pression.",
            deepLink: "cooksy://library",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.new_recipes", category: .reactivation,
            title: "🎁 2 nouvelles recettes pour toi",
            body: "Sélectionnées exprès pendant ton absence.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.reel_for_you", category: .reactivation,
            title: "🎬 Un Reel qui pourrait te plaire",
            body: "On l'a transformé en recette. Très rapide.",
            deepLink: "cooksy://import",
            preferredHour: 18, preferredMinute: 30, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.waiting", category: .reactivation,
            title: "⏳ Ta dernière recette t'attend",
            body: "Cuisine-la quand tu veux. On garde tout.",
            deepLink: "cooksy://library",
            preferredHour: 19, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.5min_back", category: .reactivation,
            title: "⚡ Cooksy en 5 min ce soir ?",
            body: "Une recette express, c'est tout ce qu'il te faut.",
            deepLink: "cooksy://home",
            preferredHour: 18, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.missing", category: .reactivation,
            title: "✨ On a une surprise pour toi",
            body: "Une recette qu'on a dégotée pendant que t'étais loin.",
            deepLink: "cooksy://home",
            preferredHour: 15, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.simple_return", category: .reactivation,
            title: "🌸 Un petit coucou de Cooksy",
            body: "Pas de pression. Juste : tu nous manques un peu.",
            deepLink: "cooksy://home",
            preferredHour: 11, preferredMinute: 0, weekday: nil, requiresInactivity: true),

        EngagementTemplate(id: "react.fridge_help", category: .reactivation,
            title: "🥦 T'as quoi dans ton frigo ?",
            body: "On te fait une recette avec ce que tu as. Promis facile.",
            deepLink: "cooksy://home",
            preferredHour: 17, preferredMinute: 30, weekday: nil, requiresInactivity: true)
    ]
}
