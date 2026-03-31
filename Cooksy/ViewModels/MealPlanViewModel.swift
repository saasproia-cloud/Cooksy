import Combine
import Foundation

@MainActor
final class MealPlanViewModel: ObservableObject {
    struct DayTile: Identifiable, Hashable {
        let id: Date
        let date: Date
        let weekdayTitle: String
        let dayNumberText: String
        let plannedMealsCount: Int
        let isSelected: Bool

        var progressDots: Int {
            min(plannedMealsCount, MealPlanEntry.MealKind.allCases.count)
        }
    }

    struct MealSlot: Identifiable, Hashable {
        let kind: MealPlanEntry.MealKind
        let recipe: Recipe?

        var id: MealPlanEntry.MealKind { kind }

        var sectionTitle: String {
            switch kind {
            case .breakfast:
                return "BREAKFAST"
            case .lunch:
                return "LUNCH"
            case .dinner:
                return "DINNER"
            }
        }

        var title: String {
            switch kind {
            case .breakfast:
                return "Breakfast"
            case .lunch:
                return "Lunch"
            case .dinner:
                return "Dinner"
            }
        }

        var iconName: String {
            switch kind {
            case .breakfast:
                return "sun.max.fill"
            case .lunch:
                return "fork.knife"
            case .dinner:
                return "moon.stars.fill"
            }
        }

        var hasRecipe: Bool {
            recipe != nil
        }
    }

    struct DailySummary: Hashable {
        let completedMeals: Int
        let totalCalories: Int
        let progress: Double

        var progressText: String {
            "\(completedMeals) of \(MealPlanEntry.MealKind.allCases.count) meals done"
        }

        var totalCaloriesText: String {
            "\(totalCalories)"
        }
    }

    struct WeeklyOverview: Hashable {
        let plannedMeals: Int
        let completedMeals: Int
        let averageDailyCalories: Int
    }

    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var entries: [MealPlanEntry] = []
    @Published var currentWeekStart: Date
    @Published var selectedDate: Date

    private let store: RecipeStore
    private var cancellables = Set<AnyCancellable>()
    private let calendar: Calendar

    init(store: RecipeStore, calendar: Calendar = .cooksyEnglish) {
        self.store = store
        self.calendar = calendar
        self.currentWeekStart = calendar.startOfWeek(for: .now)
        self.selectedDate = calendar.startOfDay(for: .now)
        self.recipes = store.recipes
        self.entries = store.mealPlanEntries

        store.$recipes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recipes in
                self?.recipes = recipes
            }
            .store(in: &cancellables)

        store.$mealPlanEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.entries = entries
            }
            .store(in: &cancellables)
    }

    var weekDays: [DayTile] {
        (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: currentWeekStart) ?? currentWeekStart
            let normalizedDate = calendar.startOfDay(for: date)
            let plannedMealsCount = mealEntries(for: normalizedDate).count

            return DayTile(
                id: normalizedDate,
                date: normalizedDate,
                weekdayTitle: Self.weekdayFormatter.string(from: normalizedDate),
                dayNumberText: Self.dayNumberFormatter.string(from: normalizedDate),
                plannedMealsCount: plannedMealsCount,
                isSelected: calendar.isDate(normalizedDate, inSameDayAs: selectedDate)
            )
        }
    }

    var selectedDayTitle: String {
        Self.selectedDayFormatter.string(from: selectedDate)
    }

    var weekLabel: String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        return "\(Self.shortMonthDayFormatter.string(from: currentWeekStart)) - \(Self.shortMonthDayFormatter.string(from: weekEnd))"
    }

    var selectedDayMeals: [MealSlot] {
        let recipesByMeal = Dictionary(uniqueKeysWithValues: plannedMeals(for: selectedDate).map { ($0.kind, $0.recipe) })

        return MealPlanEntry.MealKind.allCases.map { kind in
            MealSlot(kind: kind, recipe: recipesByMeal[kind])
        }
    }

    var dailySummary: DailySummary {
        let completedMeals = selectedDayMeals.filter(\.hasRecipe).count
        let totalCalories = selectedDayMeals
            .compactMap(\.recipe)
            .map(calories(for:))
            .reduce(0, +)

        return DailySummary(
            completedMeals: completedMeals,
            totalCalories: totalCalories,
            progress: Double(completedMeals) / Double(MealPlanEntry.MealKind.allCases.count)
        )
    }

    var weeklyOverview: WeeklyOverview {
        let today = calendar.startOfDay(for: .now)
        let weekEntries = entriesForCurrentWeek()
        let plannedMeals = weekEntries.count
        let completedMeals = weekEntries.filter { $0.dayDate <= today }.count
        let totalCalories = weekEntries
            .compactMap { recipeLookup[$0.recipeID] }
            .map(calories(for:))
            .reduce(0, +)

        return WeeklyOverview(
            plannedMeals: plannedMeals,
            completedMeals: completedMeals,
            averageDailyCalories: Int((Double(totalCalories) / 7.0).rounded())
        )
    }

    var firstEmptyMealKind: MealPlanEntry.MealKind? {
        selectedDayMeals.first(where: { !$0.hasRecipe })?.kind
    }

    func selectDay(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
    }

    func showPreviousWeek() {
        currentWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        selectedDate = currentWeekStart
    }

    func showNextWeek() {
        currentWeekStart = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        selectedDate = currentWeekStart
    }

    func addRecipe(_ recipe: Recipe, to day: Date, meal kind: MealPlanEntry.MealKind) {
        store.addMealPlanRecipe(recipeID: recipe.id, for: calendar.startOfDay(for: day), meal: kind)
    }

    func removeRecipe(from day: Date, meal kind: MealPlanEntry.MealKind) {
        store.removeMealPlanRecipe(from: calendar.startOfDay(for: day), meal: kind)
    }

    func recipe(for day: Date, meal kind: MealPlanEntry.MealKind) -> Recipe? {
        plannedMeals(for: day)
            .first(where: { $0.kind == kind })?
            .recipe
    }

    private func plannedMeals(for day: Date) -> [(kind: MealPlanEntry.MealKind, recipe: Recipe)] {
        mealEntries(for: day)
            .compactMap { entry in
                guard let recipe = recipeLookup[entry.recipeID] else { return nil }
                return (kind: entry.resolvedMealKind, recipe: recipe)
            }
            .sorted { lhs, rhs in
                mealOrder(for: lhs.kind) < mealOrder(for: rhs.kind)
            }
    }

    private func mealEntries(for day: Date) -> [MealPlanEntry] {
        let normalizedDay = calendar.startOfDay(for: day)
        return entries
            .filter { calendar.isDate($0.dayDate, inSameDayAs: normalizedDay) }
            .sorted { lhs, rhs in
                if mealOrder(for: lhs.resolvedMealKind) == mealOrder(for: rhs.resolvedMealKind) {
                    return lhs.createdAt < rhs.createdAt
                }
                return mealOrder(for: lhs.resolvedMealKind) < mealOrder(for: rhs.resolvedMealKind)
            }
    }

    private func entriesForCurrentWeek() -> [MealPlanEntry] {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        let normalizedWeekEnd = calendar.startOfDay(for: weekEnd)

        return entries.filter { entry in
            let day = calendar.startOfDay(for: entry.dayDate)
            return day >= currentWeekStart && day <= normalizedWeekEnd
        }
    }

    private func calories(for recipe: Recipe) -> Int {
        Int((RecipePresentationFormatter.parseNumber(from: recipe.nutrition?.calories) ?? 0).rounded())
    }

    private func mealOrder(for kind: MealPlanEntry.MealKind) -> Int {
        switch kind {
        case .breakfast:
            return 0
        case .lunch:
            return 1
        case .dinner:
            return 2
        }
    }

    private var recipeLookup: [Recipe.ID: Recipe] {
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd"
        return formatter
    }()

    private static let selectedDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let shortMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private extension Calendar {
    static var cooksyEnglish: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    func startOfWeek(for date: Date) -> Date {
        if let interval = dateInterval(of: .weekOfYear, for: date) {
            return startOfDay(for: interval.start)
        }

        return startOfDay(for: date)
    }
}
