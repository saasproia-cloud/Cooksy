import Foundation

struct Recipe: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceURL: URL?
    var heroImageURL: URL?
    var heroStyle: HeroStyle
    var details: RecipeDetails
    var nutrition: RecipeNutrition?
    var ingredients: [RecipeIngredient]
    var steps: [RecipeStep]
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var bookID: RecipeBook.ID?

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL? = nil,
        heroImageURL: URL? = nil,
        heroStyle: HeroStyle = .warmCocoa,
        details: RecipeDetails = RecipeDetails(),
        nutrition: RecipeNutrition? = nil,
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        bookID: RecipeBook.ID? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.heroImageURL = heroImageURL
        self.heroStyle = heroStyle
        self.details = details
        self.nutrition = nutrition
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bookID = bookID
    }
}

enum HeroStyle: String, Codable, Hashable {
    case warmCocoa
    case citrus
    case ocean
    case meadow
}

struct RecipeDetails: Codable, Hashable {
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var servings: String?

    init(
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        servings: String? = nil
    ) {
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.servings = servings
    }
}

struct RecipeNutrition: Codable, Hashable {
    var calories: String?
    var protein: String?
    var carbs: String?
    var fat: String?

    init(
        calories: String? = nil,
        protein: String? = nil,
        carbs: String? = nil,
        fat: String? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

struct RecipeIngredient: Identifiable, Codable, Hashable {
    let id: UUID
    var amount: String?
    var unit: String?
    var name: String

    init(id: UUID = UUID(), amount: String? = nil, unit: String? = nil, name: String) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.name = name
    }

    var line: String {
        [amount, unit, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct RecipeStep: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String?
    var detail: String

    init(id: UUID = UUID(), title: String? = nil, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}
