import Foundation

struct RecipeImportDebugInfo: Codable, Hashable {
    let ingredientsCount: Int
    let stepsCount: Int
    let strategy: String
    let durationMs: Int
    let isLikelyValid: Bool
    let missing: [String]
    let failureReason: String?
    let needsReview: Bool?

    var userFacingFailureMessage: String? {
        switch failureReason {
        case "not_food":
            return "Ce contenu ne semble pas montrer une recette"
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
    var creatorHandle: String?
    var externalRating: Double?
    var externalRatingCount: Int?
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
        creatorHandle: String? = nil,
        externalRating: Double? = nil,
        externalRatingCount: Int? = nil,
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
        self.creatorHandle = creatorHandle
        self.externalRating = externalRating
        self.externalRatingCount = externalRatingCount
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
            creatorHandle: recipe.creatorHandle,
            externalRating: recipe.externalRating,
            externalRatingCount: recipe.externalRatingCount,
            ingredientDrafts: recipe.ingredients.map {
                IngredientDraft(amount: $0.amount ?? "", unit: $0.unit ?? "", name: $0.name)
            },
            stepDrafts: recipe.steps.map { StepDraft(detail: $0.detail, section: $0.title, ingredientRefs: $0.ingredientRefs) },
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
        Self.normalizeImportedTitle(trimmed(title) ?? "")
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
            let sectionTitle = draft.section?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RecipeStep(
                title: sectionTitle?.isEmpty == false ? sectionTitle : nil,
                detail: detail,
                ingredientRefs: draft.ingredientRefs
            )
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
            creatorHandle: creatorHandle,
            externalRating: externalRating,
            externalRatingCount: externalRatingCount,
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

    private static func normalizeImportedTitle(_ rawValue: String) -> String {
        var cleaned = rawValue
            .replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "#[\\p{L}\\p{N}_]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\p{Extended_Pictographic}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = trimRepeatedLeadPhrase(in: cleaned)
        cleaned = cleaned.replacingOccurrences(
            of: "\\b(?:les|le|la|des|un|une)\\s*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 56,
           let range = cleaned.range(
                of: "\\b(?:avec|mais|sans|version|qui|qu[’']|pour)\\b",
                options: [.regularExpression, .caseInsensitive]
           ),
           cleaned.distance(from: cleaned.startIndex, to: range.lowerBound) >= 16 {
            cleaned = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned == cleaned.uppercased(), cleaned.rangeOfCharacter(from: .letters) != nil {
            cleaned = cleaned.localizedLowercase.capitalized
        }

        return cleaned.isEmpty ? rawValue : cleaned
    }

    private static func trimRepeatedLeadPhrase(in value: String) -> String {
        let lowercase = value.localizedLowercase
        let words = lowercase.matches(of: /[\p{L}\p{N}]+/).map { String($0.output) }

        for phraseLength in [3, 2] {
            guard words.count >= phraseLength * 2 else { continue }
            let phrase = words.prefix(phraseLength).joined(separator: " ")
            guard phrase.count >= 8 else { continue }
            guard let secondRange = lowercase.range(of: phrase, options: [], range: lowercase.index(lowercase.startIndex, offsetBy: min(lowercase.count, phrase.count + 1))..<lowercase.endIndex) else {
                continue
            }

            let trimmed = String(value[..<secondRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 6 {
                return trimmed
            }
        }

        return value
    }

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
    var nutritionQuery: String?

    init(
        id: UUID = UUID(),
        amount: String = "",
        unit: String = "",
        name: String = "",
        nutritionQuery: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.name = name
        self.nutritionQuery = nutritionQuery
    }
}

struct StepDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var detail: String
    var section: String?
    var ingredientRefs: [String]?

    init(id: UUID = UUID(), detail: String = "", section: String? = nil, ingredientRefs: [String]? = nil) {
        self.id = id
        self.detail = detail
        self.section = section
        self.ingredientRefs = ingredientRefs
    }
}
