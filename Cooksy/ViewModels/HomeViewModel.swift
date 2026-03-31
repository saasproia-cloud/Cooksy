import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum Artwork: Hashable {
        case recipe(Recipe)
        case demo(DemoRecipeScenario)
    }

    struct RecentImportCard: Identifiable, Hashable {
        let id: String
        let title: String
        let sourceLabel: String
        let durationLabel: String
        let caloriesLabel: String
        let ratingLabel: String
        let artwork: Artwork
        let destinationRecipeID: Recipe.ID?
    }

    struct TrendingRecipe: Identifiable, Hashable {
        let id: String
        let rank: Int
        let title: String
        let handle: String
        let durationLabel: String
        let ratingLabel: String
        let artwork: Artwork
        let destinationRecipeID: Recipe.ID?
    }

    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var pendingImport: SharedImportDraft?
    @Published private(set) var dayRefreshDate: Date = .now

    private let sharedLinkInbox: SharedLinkInbox
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var midnightRefreshTimer: Timer?

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        calendar: Calendar = .cooksyHomeCalendar
    ) {
        self.sharedLinkInbox = sharedLinkInbox
        self.calendar = calendar

        store.$recipes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recipes in
                self?.recipes = recipes
            }
            .store(in: &cancellables)

        refreshPendingImport()
        scheduleMidnightRefresh()
    }

    var greetingLine: String {
        switch calendar.component(.hour, from: dayRefreshDate) {
        case 5..<12:
            return "Good morning"
        case 12..<18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    var homeHeadline: String {
        "What are we cooking today, Alex?"
    }

    var profileBadgeText: String {
        "A"
    }

    var importGuideTitle: String {
        "Guide d'importation..."
    }

    var importGuideSubtitle: String {
        "TikTok - Instagram - Any link"
    }

    var recentImportCards: [RecentImportCard] {
        let liveCards = Array(sortedRecipes.prefix(6)).map { makeRecentImportCard(for: $0) }
        let minimumVisibleCards = 4
        let fillerCount = max(0, minimumVisibleCards - liveCards.count)
        let fillerCards = rotatedScenarios(prefixCount: fillerCount).enumerated().map { makeDemoRecentImportCard($0) }
        return Array((liveCards + fillerCards).prefix(6))
    }

    var trendingTodayItems: [TrendingRecipe] {
        rotatedScenarios(prefixCount: 3)
            .enumerated()
            .map { index, scenario in
                TrendingRecipe(
                    id: "trending-\(daySeed)-\(scenario.id)",
                    rank: index + 1,
                    title: scenario.title,
                    handle: Self.trendingHandles[(stableNumber(for: scenario.id) + daySeed + index) % Self.trendingHandles.count],
                    durationLabel: "\(scenario.prepMinutes + scenario.cookMinutes)m",
                    ratingLabel: ratingLabel(for: scenario.id, base: 4.7, range: 3),
                    artwork: .demo(scenario),
                    destinationRecipeID: nil
                )
            }
    }

    func refreshPendingImport() {
        pendingImport = sharedLinkInbox.peek()
        refreshDailyContentIfNeeded()
    }

    private var sortedRecipes: [Recipe] {
        recipes.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private var daySeed: Int {
        calendar.ordinality(of: .day, in: .era, for: dayRefreshDate) ?? 0
    }

    private func makeRecentImportCard(for recipe: Recipe) -> RecentImportCard {
        RecentImportCard(
            id: "recent-\(recipe.id.uuidString)",
            title: recipe.title,
            sourceLabel: sourceLabel(for: recipe),
            durationLabel: durationLabel(for: recipe),
            caloriesLabel: caloriesLabel(for: recipe),
            ratingLabel: ratingLabel(for: recipe.id.uuidString, base: 4.6, range: 4),
            artwork: .recipe(recipe),
            destinationRecipeID: recipe.id
        )
    }

    private func makeDemoRecentImportCard(
        _ pair: EnumeratedSequence<[DemoRecipeScenario]>.Element
    ) -> RecentImportCard {
        let sourceLabel = Self.demoSourceLabels[(pair.offset + daySeed) % Self.demoSourceLabels.count]

        return RecentImportCard(
            id: "recent-demo-\(pair.element.id)",
            title: pair.element.title,
            sourceLabel: sourceLabel,
            durationLabel: "\(pair.element.prepMinutes + pair.element.cookMinutes)m",
            caloriesLabel: "\(420 + (stableNumber(for: pair.element.id) % 5) * 55) kcal",
            ratingLabel: ratingLabel(for: pair.element.id, base: 4.6, range: 4),
            artwork: .demo(pair.element),
            destinationRecipeID: nil
        )
    }

    private func rotatedScenarios(prefixCount: Int) -> [DemoRecipeScenario] {
        guard !DemoRecipeCatalog.scenarios.isEmpty else { return [] }

        let scenarios = DemoRecipeCatalog.scenarios
        let offset = daySeed % scenarios.count
        let rotated = Array(scenarios[offset...]) + Array(scenarios[..<offset])
        return Array(rotated.prefix(prefixCount))
    }

    private func sourceLabel(for recipe: Recipe) -> String {
        guard let host = recipe.sourceURL?.host(percentEncoded: false)?.lowercased() else {
            return "Cooksy"
        }

        if host.contains("tiktok") {
            return "TikTok"
        }

        if host.contains("instagram") {
            return "Instagram"
        }

        if host.contains("youtube") || host.contains("youtu.be") {
            return "YouTube"
        }

        if host.contains("pinterest") || host.contains("pin.it") {
            return "Pinterest"
        }

        return "Web"
    }

    private func durationLabel(for recipe: Recipe) -> String {
        let prep = recipe.details.prepTimeMinutes ?? 0
        let cook = recipe.details.cookTimeMinutes ?? 0
        let total = prep + cook

        if total > 0 {
            return "\(total)m"
        }

        if prep > 0 {
            return "\(prep)m"
        }

        if cook > 0 {
            return "\(cook)m"
        }

        return "\(20 + (stableNumber(for: recipe.id.uuidString) % 4) * 5)m"
    }

    private func caloriesLabel(for recipe: Recipe) -> String {
        if let calories = recipe.nutrition?.calories?.trimmingCharacters(in: .whitespacesAndNewlines),
           !calories.isEmpty {
            if calories.localizedCaseInsensitiveContains("kcal") {
                return calories
            }

            return "\(calories) kcal"
        }

        return "\(320 + (stableNumber(for: recipe.id.uuidString) % 6) * 60) kcal"
    }

    private func ratingLabel(for key: String, base: Double, range: Int) -> String {
        let stepCount = max(range, 1)
        let rating = base + Double(stableNumber(for: key) % stepCount) * 0.1
        return String(format: "%.1f", rating)
    }

    private func stableNumber(for value: String) -> Int {
        value.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
    }

    private func refreshDailyContentIfNeeded(referenceDate: Date = .now) {
        guard !calendar.isDate(dayRefreshDate, inSameDayAs: referenceDate) else { return }
        dayRefreshDate = referenceDate
        scheduleMidnightRefresh(referenceDate: referenceDate)
    }

    private func scheduleMidnightRefresh(referenceDate: Date = .now) {
        midnightRefreshTimer?.invalidate()

        let nextMidnight = calendar.nextDate(
            after: referenceDate,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate.addingTimeInterval(86_400)

        let interval = max(nextMidnight.timeIntervalSince(referenceDate), 1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dayRefreshDate = .now
                self.scheduleMidnightRefresh()
            }
        }

        midnightRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let demoSourceLabels = [
        "TikTok",
        "Instagram",
        "TikTok",
        "Instagram",
        "Pinterest",
        "YouTube"
    ]

    private static let trendingHandles = [
        "@brunchbae",
        "@miguelcooks",
        "@sweetmatcha_",
        "@ramennotes",
        "@pastadiary",
        "@toastatelier",
        "@cookwithlina",
        "@dailydishclub"
    ]
}

private extension Calendar {
    static var cooksyHomeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
