import Combine
import Foundation
import SwiftUI

@MainActor
final class MealPlanViewModel: ObservableObject {
    struct DayPlan: Identifiable, Hashable {
        struct PlannedMeal: Hashable {
            let kind: MealPlanEntry.MealKind
            let recipe: Recipe
        }

        let id: Date
        let date: Date
        let meals: [PlannedMeal]
        let isToday: Bool
        let weekdayTitle: String
        let shortWeekdayTitle: String
        let isSelected: Bool

        var hasRecipes: Bool {
            !meals.isEmpty
        }

        var completedMealsCount: Int {
            meals.count
        }

        var dayNumberText: String {
            Self.dayNumberFormatter.string(from: date)
        }

        private static let dayNumberFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "dd"
            return formatter
        }()
    }

    struct MealSection: Identifiable, Hashable {
        let kind: MealPlanEntry.MealKind
        let recipe: Recipe?

        var id: MealPlanEntry.MealKind { kind }

        var title: String {
            switch kind {
            case .breakfast:
                return "Petit déjeuner"
            case .lunch:
                return "Déjeuner"
            case .dinner:
                return "Dîner"
            }
        }

        var timeLabel: String {
            switch kind {
            case .breakfast:
                return "08:30"
            case .lunch:
                return "12:30"
            case .dinner:
                return "19:45"
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

    struct WeekSummary: Hashable {
        let calories: Int
        let progress: Double
        let label: String
        let detail: String

        var caloriesText: String {
            calories > 0 ? "\(calories)" : "--"
        }
    }

    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var entries: [MealPlanEntry] = []
    @Published var currentWeekStart: Date
    @Published var selectedDate: Date

    private let store: RecipeStore
    private var cancellables = Set<AnyCancellable>()
    private let calendar: Calendar

    init(store: RecipeStore, calendar: Calendar = .cooksyFrench) {
        self.store = store
        self.calendar = calendar
        self.currentWeekStart = calendar.startOfWeek(for: .now)
        self.selectedDate = calendar.startOfDay(for: .now)

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

    var currentMonthLabel: String {
        Self.monthYearFormatter.string(from: weekMidpointDate).capitalized
    }

    var weekCaptionLabel: String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        let startDay = Self.rangeDayFormatter.string(from: currentWeekStart)
        let endDay = Self.rangeDayFormatter.string(from: weekEnd)
        let month = Self.shortMonthFormatter.string(from: weekMidpointDate).capitalized
        return "Semaine du \(startDay) au \(endDay) \(month)"
    }

    var selectedDayTitle: String {
        Self.fullDayFormatter.string(from: selectedDate).capitalized
    }

    var weekPlans: [DayPlan] {
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: currentWeekStart) ?? currentWeekStart
            let normalizedDate = calendar.startOfDay(for: date)

            let plannedMeals = entries
                .filter { calendar.isDate($0.dayDate, inSameDayAs: normalizedDate) }
                .sorted { lhs, rhs in
                    if lhs.resolvedMealKind.sortOrder == rhs.resolvedMealKind.sortOrder {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.resolvedMealKind.sortOrder < rhs.resolvedMealKind.sortOrder
                }
                .compactMap { entry -> DayPlan.PlannedMeal? in
                    guard let recipe = recipesByID[entry.recipeID] else { return nil }
                    return DayPlan.PlannedMeal(kind: entry.resolvedMealKind, recipe: recipe)
                }

            return DayPlan(
                id: normalizedDate,
                date: normalizedDate,
                meals: plannedMeals,
                isToday: calendar.isDateInToday(normalizedDate),
                weekdayTitle: Self.fullDayFormatter.string(from: normalizedDate),
                shortWeekdayTitle: Self.shortDayLabelFormatter.string(from: normalizedDate),
                isSelected: calendar.isDate(normalizedDate, inSameDayAs: selectedDate)
            )
        }
    }

    var selectedDayPlan: DayPlan {
        weekPlans.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) ?? weekPlans[0]
    }

    var selectedDayMeals: [MealSection] {
        let recipesByMeal = Dictionary(uniqueKeysWithValues: selectedDayPlan.meals.map { ($0.kind, $0.recipe) })

        return MealPlanEntry.MealKind.allCases.map { kind in
            MealSection(kind: kind, recipe: recipesByMeal[kind])
        }
    }

    var weekSummary: WeekSummary {
        let filledMeals = selectedDayMeals.filter(\.hasRecipe).count
        let calories = selectedDayMeals
            .compactMap(\.recipe)
            .compactMap { recipe in
                Int(recipe.nutrition?.calories?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "")
            }
            .reduce(0, +)

        let completionProgress = Double(filledMeals) / Double(MealPlanEntry.MealKind.allCases.count)
        let calorieProgress = calories > 0 ? min(Double(calories) / 2100, 1) : 0
        let progress: Double
        if filledMeals == 0, calories == 0 {
            progress = 0
        } else {
            progress = max(max(completionProgress, calorieProgress), 0.22)
        }

        let label: String
        switch filledMeals {
        case 0:
            label = "Journée à compléter"
        case 1:
            label = "Premier repas planifié"
        case 2:
            label = "Très bon équilibre"
        default:
            label = "Journée bien organisée"
        }

        let detail = "\(filledMeals)/3 repas planifiés"
        return WeekSummary(calories: calories, progress: progress, label: label, detail: detail)
    }

    func showPreviousWeek() {
        currentWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        selectedDate = currentWeekStart
    }

    func showNextWeek() {
        currentWeekStart = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        selectedDate = currentWeekStart
    }

    func showCurrentWeek() {
        currentWeekStart = calendar.startOfWeek(for: .now)
        selectedDate = calendar.startOfDay(for: .now)
    }

    func selectDay(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
    }

    func addRecipe(_ recipe: Recipe, to day: Date, meal kind: MealPlanEntry.MealKind) {
        store.addMealPlanRecipe(recipeID: recipe.id, for: calendar.startOfDay(for: day), meal: kind)
    }

    func removeRecipe(from day: Date, meal kind: MealPlanEntry.MealKind) {
        store.removeMealPlanRecipe(from: calendar.startOfDay(for: day), meal: kind)
    }

    func recipe(for day: Date, meal kind: MealPlanEntry.MealKind) -> Recipe? {
        let normalizedDay = calendar.startOfDay(for: day)
        return weekPlans
            .first(where: { calendar.isDate($0.date, inSameDayAs: normalizedDay) })?
            .meals
            .first(where: { $0.kind == kind })?
            .recipe
    }

    func clearCurrentWeek() {
        store.clearMealPlanRecipes(inWeekStartingAt: currentWeekStart, calendar: calendar)
    }

    private var weekMidpointDate: Date {
        calendar.date(byAdding: .day, value: 3, to: currentWeekStart) ?? currentWeekStart
    }

    private static let shortDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let rangeDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "dd"
        return formatter
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM"
        return formatter
    }()
}

private extension Calendar {
    static var cooksyFrench: Calendar {
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
    var sortOrder: Int {
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
