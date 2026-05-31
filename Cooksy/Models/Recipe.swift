import Foundation

struct Recipe: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceURL: URL?
    var creatorHandle: String?
    var externalRating: Double?
    var externalRatingCount: Int?
    var heroImageURL: URL?
    var heroStyle: HeroStyle
    var details: RecipeDetails
    var nutrition: RecipeNutrition?
    var ingredients: [RecipeIngredient]
    var steps: [RecipeStep]
    var notes: String?
    var allergens: [String]?
    var createdAt: Date
    var updatedAt: Date
    var bookID: RecipeBook.ID?

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL? = nil,
        creatorHandle: String? = nil,
        externalRating: Double? = nil,
        externalRatingCount: Int? = nil,
        heroImageURL: URL? = nil,
        heroStyle: HeroStyle = .warmCocoa,
        details: RecipeDetails = RecipeDetails(),
        nutrition: RecipeNutrition? = nil,
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        notes: String? = nil,
        allergens: [String]? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        bookID: RecipeBook.ID? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.creatorHandle = creatorHandle
        self.externalRating = externalRating
        self.externalRatingCount = externalRatingCount
        self.heroImageURL = heroImageURL
        self.heroStyle = heroStyle
        self.details = details
        self.nutrition = nutrition
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
        self.allergens = allergens
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
    var fiber: String?
    var sugar: String?
    var salt: String?
    var saturatedFat: String?

    init(
        calories: String? = nil,
        protein: String? = nil,
        carbs: String? = nil,
        fat: String? = nil,
        fiber: String? = nil,
        sugar: String? = nil,
        salt: String? = nil,
        saturatedFat: String? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.salt = salt
        self.saturatedFat = saturatedFat
    }
}

struct RecipeIngredient: Identifiable, Codable, Hashable {
    let id: UUID
    var amount: String?
    var unit: String?
    var name: String
    // Set when this ingredient has been swapped by the chat assistant.
    // `originIngredientId` always equals `id` for the first swap and
    // never changes on subsequent swaps, so multiple successive swaps
    // still walk back to the true original.
    var originIngredientId: UUID?
    var originName: String?
    var originAmount: String?
    var originUnit: String?
    /// Server-side id of the chat modification that produced the current
    /// swap. Stamped on the ingredient when an `ingredient_swap` is
    /// applied so the per-row ↺ chip can revert without first listing
    /// modifications. Cleared on revert.
    var lastModificationId: UUID?

    init(
        id: UUID = UUID(),
        amount: String? = nil,
        unit: String? = nil,
        name: String,
        originIngredientId: UUID? = nil,
        originName: String? = nil,
        originAmount: String? = nil,
        originUnit: String? = nil,
        lastModificationId: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.name = name
        self.originIngredientId = originIngredientId
        self.originName = originName
        self.originAmount = originAmount
        self.originUnit = originUnit
        self.lastModificationId = lastModificationId
    }

    var isSwapped: Bool { originIngredientId != nil }

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
    var ingredientRefs: [String]?

    init(id: UUID = UUID(), title: String? = nil, detail: String, ingredientRefs: [String]? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.ingredientRefs = ingredientRefs
    }
}
