import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    struct UpcomingMealPreview: Identifiable, Hashable {
        let entry: MealPlanEntry
        let recipe: Recipe
        let dayLabel: String

        var id: MealPlanEntry.ID { entry.id }

        var mealLabel: String {
            entry.resolvedMealKind.homeTitle
        }
    }

    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var mealPlanEntries: [MealPlanEntry] = []
    @Published private(set) var pendingImport: SharedImportDraft?

    private let store: RecipeStore
    private let sharedLinkInbox: SharedLinkInbox
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        calendar: Calendar = .cooksyFrenchHome
    ) {
        self.store = store
        self.sharedLinkInbox = sharedLinkInbox
        self.calendar = calendar

        store.$books
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                self?.books = books
            }
            .store(in: &cancellables)

        store.$recipes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recipes in
                self?.recipes = recipes
            }
            .store(in: &cancellables)

        store.$mealPlanEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.mealPlanEntries = entries
            }
            .store(in: &cancellables)

        refreshPendingImport()
    }

    var totalRecipeCount: Int {
        recipes.count
    }

    var displayedBookCount: Int {
        (uncategorizedBook == nil ? 0 : 1) + customBooks.count
    }

    var uncategorizedBook: RecipeBook? {
        books.first(where: { $0.kind == .uncategorized })
    }

    var customBooks: [RecipeBook] {
        books
            .filter { $0.kind == .collection }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var highlightedBooks: [RecipeBook] {
        Array(([uncategorizedBook].compactMap { $0 } + customBooks).prefix(4))
    }

    var featuredRecipe: Recipe? {
        recentRecipes.first
    }

    var recentRecipes: [Recipe] {
        Array(recipes.prefix(4))
    }

    var currentDateLabel: String {
        Self.headerDateFormatter.string(from: .now).capitalized
    }

    var headerSubtitle: String {
        if let pendingImport {
            return "Lien partagé prêt depuis \(pendingImport.hostLabel)."
        }

        if totalRecipeCount == 0 {
            return "Importez votre première recette pour lancer votre carnet."
        }

        return "\(currentDateLabel) • \(totalRecipeCount) recette\(totalRecipeCount > 1 ? "s" : "") prête\(totalRecipeCount > 1 ? "s" : "")"
    }

    var welcomeHeadline: String {
        if totalRecipeCount == 0 {
            return "Un vrai accueil pour cuisiner sans se perdre."
        }

        if !upcomingMeals.isEmpty {
            return "Votre semaine culinaire est déjà en mouvement."
        }

        return "Tout votre univers recette, sans écran fourre-tout."
    }

    var welcomeCopy: String {
        if pendingImport != nil {
            return "Le prochain import vous attend déjà. Vous pouvez le relire, l’enregistrer puis revenir ici pour continuer votre semaine."
        }

        if totalRecipeCount == 0 {
            return "Commencez par une recette TikTok, Instagram ou un lien web. Ensuite Cooksy vous ramène au plan, aux recettes récentes et à vos livres en un seul coup d’œil."
        }

        return "L’accueil doit donner envie de cuisiner vite: une relance claire, le plan de la semaine, vos dernières recettes et un passage simple vers la bibliothèque."
    }

    var weekPlannedCount: Int {
        let weekStart = calendar.startOfWeek(for: .now)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        return mealPlanEntries.filter { entry in
            let day = calendar.startOfDay(for: entry.dayDate)
            return day >= weekStart && day <= weekEnd
        }.count
    }

    var libraryBridgeCaption: String {
        if displayedBookCount == 0 {
            return "Créez votre premier livre pour ranger vos recettes comme un vrai carnet."
        }

        return "\(displayedBookCount) livre\(displayedBookCount > 1 ? "s" : "") • touchez un livre pour rejoindre l’onglet Recettes."
    }

    var upcomingMeals: [UpcomingMealPreview] {
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        let today = calendar.startOfDay(for: .now)

        return mealPlanEntries
            .filter { calendar.startOfDay(for: $0.dayDate) >= today }
            .sorted { lhs, rhs in
                let lhsDay = calendar.startOfDay(for: lhs.dayDate)
                let rhsDay = calendar.startOfDay(for: rhs.dayDate)

                if lhsDay == rhsDay {
                    return lhs.resolvedMealKind.homeSortOrder < rhs.resolvedMealKind.homeSortOrder
                }

                return lhsDay < rhsDay
            }
            .compactMap { entry -> UpcomingMealPreview? in
                guard let recipe = recipesByID[entry.recipeID] else { return nil }
                return UpcomingMealPreview(
                    entry: entry,
                    recipe: recipe,
                    dayLabel: dayLabel(for: entry.dayDate)
                )
            }
            .prefix(3)
            .map { $0 }
    }

    func refreshPendingImport() {
        pendingImport = sharedLinkInbox.peek()
    }

    private func dayLabel(for date: Date) -> String {
        let normalizedDate = calendar.startOfDay(for: date)

        if calendar.isDateInToday(normalizedDate) {
            return "Aujourd’hui"
        }

        if calendar.isDateInTomorrow(normalizedDate) {
            return "Demain"
        }

        return Self.shortDayFormatter.string(from: normalizedDate).capitalized
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}

private extension Calendar {
    static var cooksyFrenchHome: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func startOfWeek(for date: Date) -> Date {
        if let interval = dateInterval(of: .weekOfYear, for: date) {
            return startOfDay(for: interval.start)
        }

        return startOfDay(for: date)
    }
}

private extension MealPlanEntry.MealKind {
    var homeTitle: String {
        switch self {
        case .breakfast:
            return "Petit déjeuner"
        case .lunch:
            return "Déjeuner"
        case .dinner:
            return "Dîner"
        }
    }

    var homeSortOrder: Int {
        switch self {
        case .breakfast:
            return 0
        case .lunch:
            return 1
        case .dinner:
            return 2
        }
    }
}
