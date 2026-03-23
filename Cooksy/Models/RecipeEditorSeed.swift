import Foundation

struct RecipeImportDebugInfo: Codable, Hashable {
    let ingredientsCount: Int
    let stepsCount: Int
    let strategy: String
    let durationMs: Int
    let isLikelyValid: Bool
    let missing: [String]
    let failureReason: String?

    var userFacingFailureMessage: String? {
        switch failureReason {
        case "import_too_slow":
            return "Import trop lent"
        case "weak_tiktok_metadata":
            return "Données TikTok insuffisantes"
        case "not_enough_ingredients":
            return "Pas assez d’ingrédients"
        case "not_enough_steps":
            return "Pas assez d’étapes"
        case "no_recipe_detected":
            return "Aucune recette détectée"
        case "invalid_recipe_result":
            return "Résultat de recette invalide"
        default:
            break
        }

        let missingParts = Set(missing)
        if missingParts.contains("ingredients") && missingParts.contains("steps") {
            return "Aucune recette détectée"
        }
        if missingParts.contains("ingredients") {
            return "Pas assez d’ingrédients"
        }
        if missingParts.contains("steps") {
            return "Pas assez d’étapes"
        }

        return isLikelyValid ? nil : "Résultat de recette invalide"
    }
}

struct RecipeEditorSeed: Codable, Hashable {
    var title: String
    var sourceURL: URL?
    var ingredientDrafts: [IngredientDraft]
    var stepDrafts: [StepDraft]
    var notesText: String
    var prepTimeText: String
    var cookTimeText: String
    var servingsText: String
    var caloriesText: String
    var proteinText: String
    var carbsText: String
    var fatText: String
    var imageData: Data?
    var remoteImageURL: URL?
    var importDebug: RecipeImportDebugInfo?

    init(
        title: String = "",
        sourceURL: URL? = nil,
        ingredientDrafts: [IngredientDraft] = [],
        stepDrafts: [StepDraft] = [],
        notesText: String = "",
        prepTimeText: String = "",
        cookTimeText: String = "",
        servingsText: String = "",
        caloriesText: String = "",
        proteinText: String = "",
        carbsText: String = "",
        fatText: String = "",
        imageData: Data? = nil,
        remoteImageURL: URL? = nil,
        importDebug: RecipeImportDebugInfo? = nil
    ) {
        self.title = title
        self.sourceURL = sourceURL
        self.ingredientDrafts = ingredientDrafts
        self.stepDrafts = stepDrafts
        self.notesText = notesText
        self.prepTimeText = prepTimeText
        self.cookTimeText = cookTimeText
        self.servingsText = servingsText
        self.caloriesText = caloriesText
        self.proteinText = proteinText
        self.carbsText = carbsText
        self.fatText = fatText
        self.imageData = imageData
        self.remoteImageURL = remoteImageURL
        self.importDebug = importDebug
    }

    init(recipe: Recipe, imageData: Data? = nil) {
        self.init(
            title: recipe.title,
            sourceURL: recipe.sourceURL,
            ingredientDrafts: recipe.ingredients.map {
                IngredientDraft(amount: $0.amount ?? "", unit: $0.unit ?? "", name: $0.name)
            },
            stepDrafts: recipe.steps.map { StepDraft(detail: $0.detail) },
            notesText: recipe.notes ?? "",
            prepTimeText: recipe.details.prepTimeMinutes.map(String.init) ?? "",
            cookTimeText: recipe.details.cookTimeMinutes.map(String.init) ?? "",
            servingsText: recipe.details.servings ?? "",
            caloriesText: recipe.nutrition?.calories ?? "",
            proteinText: recipe.nutrition?.protein ?? "",
            carbsText: recipe.nutrition?.carbs ?? "",
            fatText: recipe.nutrition?.fat ?? "",
            imageData: imageData,
            remoteImageURL: recipe.heroImageURL,
            importDebug: nil
        )
    }

    var normalizedTitle: String {
        trimmed(title) ?? ""
    }

    var importNotice: String? {
        let lines = notesLines
        guard let first = lines.first, first.hasPrefix(Self.importNoticePrefix) else {
            return nil
        }

        let notice = String(first.dropFirst(Self.importNoticePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return notice.isEmpty ? nil : notice
    }

    var editableNotesText: String {
        notesWithoutImportNotice
    }

    var details: RecipeDetails {
        RecipeDetails(
            prepTimeMinutes: Int(trimmed(prepTimeText) ?? ""),
            cookTimeMinutes: Int(trimmed(cookTimeText) ?? ""),
            servings: trimmed(servingsText)
        )
    }

    var nutrition: RecipeNutrition? {
        let nutrition = RecipeNutrition(
            calories: trimmed(caloriesText),
            protein: trimmed(proteinText),
            carbs: trimmed(carbsText),
            fat: trimmed(fatText)
        )

        let values = [nutrition.calories, nutrition.protein, nutrition.carbs, nutrition.fat]
        return values.allSatisfy { ($0 ?? "").isEmpty } ? nil : nutrition
    }

    var normalizedIngredients: [RecipeIngredient] {
        ingredientDrafts.compactMap { draft in
            let name = trimmed(draft.name)
            guard let name else { return nil }
            return RecipeIngredient(
                amount: trimmed(draft.amount),
                unit: trimmed(draft.unit),
                name: name
            )
        }
    }

    var normalizedSteps: [RecipeStep] {
        stepDrafts.compactMap { draft in
            let detail = trimmed(draft.detail)
            guard let detail else { return nil }
            return RecipeStep(title: nil, detail: detail)
        }
    }

    func makeRecipe(
        id: UUID = UUID(),
        bookID: RecipeBook.ID? = nil,
        imageURL: URL? = nil
    ) -> Recipe {
        Recipe(
            id: id,
            title: normalizedTitle,
            sourceURL: sourceURL,
            heroImageURL: imageURL,
            heroStyle: imageURL == nil ? .warmCocoa : .ocean,
            details: details,
            nutrition: nutrition,
            ingredients: normalizedIngredients,
            steps: normalizedSteps,
            notes: trimmed(notesWithoutImportNotice),
            bookID: bookID
        )
    }

    private static let importNoticePrefix = "Import info:"

    private var notesWithoutImportNotice: String {
        notesLines
            .filter { !$0.hasPrefix(Self.importNoticePrefix) }
            .joined(separator: "\n")
    }

    private var notesLines: [String] {
        notesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct IngredientDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var amount: String
    var unit: String
    var name: String

    init(
        id: UUID = UUID(),
        amount: String = "",
        unit: String = "",
        name: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.name = name
    }
}

struct StepDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var detail: String

    init(id: UUID = UUID(), detail: String = "") {
        self.id = id
        self.detail = detail
    }
}
