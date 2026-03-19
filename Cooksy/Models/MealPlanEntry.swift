import Foundation

struct MealPlanEntry: Identifiable, Codable, Hashable {
    enum MealKind: String, Codable, CaseIterable, Hashable {
        case breakfast
        case lunch
        case dinner
    }

    let id: UUID
    var dayDate: Date
    var recipeID: Recipe.ID
    var mealKind: MealKind?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dayDate: Date,
        recipeID: Recipe.ID,
        mealKind: MealKind? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dayDate = dayDate
        self.recipeID = recipeID
        self.mealKind = mealKind
        self.createdAt = createdAt
    }

    var resolvedMealKind: MealKind {
        mealKind ?? .breakfast
    }
}
