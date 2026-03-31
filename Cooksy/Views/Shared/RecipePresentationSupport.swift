import Foundation

enum RecipePresentationTab: String, CaseIterable, Identifiable {
    case ingredients = "Ingredients"
    case steps = "Steps"

    var id: String { rawValue }
}

struct RecipeIngredientPresentation: Identifiable, Hashable {
    let id: RecipeIngredient.ID
    let quantityText: String?
    let name: String

    var fullLine: String {
        [quantityText?.nilIfEmpty, name.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct RecipeNutritionDisplay: Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let caloriesText: String
    let proteinText: String
    let carbsText: String
    let fatText: String
}

enum IngredientIconKind: Hashable {
    case fish
    case produce
    case herb
    case bulb
    case dairy
    case cheese
    case grain
    case bread
    case egg
    case protein
    case sauce
    case spice
    case sweet
    case logo
}

enum RecipePresentationFormatter {
    static func sourceButtonTitle(for sourceURL: URL?) -> String? {
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "Ouvrez TikTok" }
        if host.contains("instagram") { return "Ouvrez Instagram" }
        if host.contains("youtube") { return "Ouvrez YouTube" }
        if host.contains("pinterest") { return "Ouvrez Pinterest" }
        if host.contains("cooksy.app"), sourceURL?.path(percentEncoded: false).contains("/demo/") == true {
            return "Voir la source demo"
        }
        return "Ouvrez la source"
    }

    static func sourceLabel(for sourceURL: URL?) -> String? {
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("instagram") { return "Instagram" }
        if host.contains("youtube") { return "YouTube" }
        if host.contains("pinterest") { return "Pinterest" }
        return host.replacingOccurrences(of: "www.", with: "").capitalized
    }

    static func sourceHostLabel(for sourceURL: URL?) -> String {
        sourceURL?.host(percentEncoded: false)?
            .replacingOccurrences(of: "www.", with: "") ?? "Source"
    }

    static func creatorHandle(explicitHandle: String?, sourceURL: URL?) -> String? {
        if let explicitHandle = normalizedHandle(explicitHandle) {
            return explicitHandle
        }

        guard let sourceURL else { return nil }
        let host = sourceURL.host(percentEncoded: false)?.lowercased() ?? ""
        let pathComponents = sourceURL.pathComponents.filter { $0 != "/" }

        if host.contains("tiktok"),
           let component = pathComponents.first(where: { $0.hasPrefix("@") }) {
            return normalizedHandle(component)
        }

        if host.contains("instagram"),
           let component = pathComponents.first,
           !["reel", "p", "tv", "stories", "explore"].contains(component.lowercased()) {
            return normalizedHandle(component)
        }

        return nil
    }

    static func ratingText(for rating: Double?) -> String? {
        guard let rating else { return nil }
        return String(format: "%.1f", rating)
    }

    static func ratingCountText(for count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        if count >= 1_000 {
            let compactValue = Double(count) / 1_000
            let suffix = compactValue >= 10 ? String(Int(compactValue.rounded())) : String(format: "%.1f", compactValue)
            return "(\(suffix)k)"
        }
        return "(\(count))"
    }

    static func totalTimeLabel(prepMinutes: Int?, cookMinutes: Int?) -> String? {
        let total = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        guard total > 0 else { return nil }
        return "\(total) min"
    }

    static func servingsLabel(for servings: Int) -> String {
        servings > 1 ? "\(servings) servings" : "1 serving"
    }

    static func selectedServingsLabel(for servings: Int) -> String {
        servings > 1 ? "\(servings) people" : "1 person"
    }

    static func baseServingsCaption(for servings: Int) -> String {
        "Base recipe: \(servings > 1 ? "\(servings) servings" : "1 serving")"
    }

    static func summaryText(noteText: String?, title: String, totalTimeLabel: String?, baseServings: Int) -> String {
        if let noteText = firstMeaningfulSentence(from: noteText) {
            return noteText
        }

        if let totalTimeLabel {
            return "\(title) ready in about \(totalTimeLabel.lowercased()) for \(servingsLabel(for: baseServings).lowercased())."
        }

        return "\(title) organised for \(servingsLabel(for: baseServings).lowercased()) with clear ingredients and steps."
    }

    static func difficultyLabel(for recipe: Recipe?) -> String {
        guard let recipe else { return "Medium" }

        let totalTime = (recipe.details.prepTimeMinutes ?? 0) + (recipe.details.cookTimeMinutes ?? 0)
        let ingredientCount = recipe.ingredients.count
        let stepCount = recipe.steps.count

        if totalTime >= 45 || ingredientCount >= 10 || stepCount >= 7 {
            return "Hard"
        }

        if totalTime <= 20 && ingredientCount <= 6 && stepCount <= 4 {
            return "Easy"
        }

        return "Medium"
    }

    static func parseNumber(from text: String?) -> Double? {
        let cleaned = text?
            .replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined() ?? ""
        return Double(cleaned)
    }

    static func formatCalories(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    static func formatMacro(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded())) g"
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)") g"
    }

    static func normalizedSearchText(for value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let handle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        let sanitized = handle.replacingOccurrences(of: "[^@A-Za-z0-9._]", with: "", options: .regularExpression)
        return sanitized.count > 1 ? sanitized : nil
    }

    private static func firstMeaningfulSentence(from text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sentence = trimmed
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .components(separatedBy: ". ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sentence, !sentence.isEmpty else { return nil }
        return sentence.count > 170 ? String(sentence.prefix(167)) + "..." : sentence
    }
}

enum RecipeNutritionDisplayBuilder {
    static func displayNutrition(for recipe: Recipe, selectedServings: Int) -> RecipeNutritionDisplay? {
        guard let perServingNutrition = perServingNutrition(for: recipe) else { return nil }
        let factor = Double(max(selectedServings, 1))

        return RecipeNutritionDisplay(
            calories: perServingNutrition.calories * factor,
            protein: perServingNutrition.protein * factor,
            carbs: perServingNutrition.carbs * factor,
            fat: perServingNutrition.fat * factor,
            caloriesText: RecipePresentationFormatter.formatCalories(perServingNutrition.calories * factor),
            proteinText: RecipePresentationFormatter.formatMacro(perServingNutrition.protein * factor),
            carbsText: RecipePresentationFormatter.formatMacro(perServingNutrition.carbs * factor),
            fatText: RecipePresentationFormatter.formatMacro(perServingNutrition.fat * factor)
        )
    }

    static func totalCaloriesLabel(for recipe: Recipe) -> String? {
        guard let perServingNutrition = perServingNutrition(for: recipe) else { return nil }
        let totalCalories = perServingNutrition.calories * Double(max(RecipeQuantityScaler.baseServings(from: recipe), 1))
        return RecipePresentationFormatter.formatCalories(totalCalories)
    }

    static func isEstimated(for recipe: Recipe) -> Bool {
        recipe.nutrition == nil
    }

    private static func perServingNutrition(for recipe: Recipe) -> RecipeNutritionDisplay? {
        if let stored = recipe.nutrition {
            let calories = RecipePresentationFormatter.parseNumber(from: stored.calories) ?? 0
            let protein = RecipePresentationFormatter.parseNumber(from: stored.protein) ?? 0
            let carbs = RecipePresentationFormatter.parseNumber(from: stored.carbs) ?? 0
            let fat = RecipePresentationFormatter.parseNumber(from: stored.fat) ?? 0
            if calories > 0 || protein > 0 || carbs > 0 || fat > 0 {
                return RecipeNutritionDisplay(
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    caloriesText: stored.calories ?? RecipePresentationFormatter.formatCalories(calories),
                    proteinText: stored.protein ?? RecipePresentationFormatter.formatMacro(protein),
                    carbsText: stored.carbs ?? RecipePresentationFormatter.formatMacro(carbs),
                    fatText: stored.fat ?? RecipePresentationFormatter.formatMacro(fat)
                )
            }
        }

        let estimate = RecipeNutritionEstimator.estimate(
            recipe: recipe,
            forPortions: max(RecipeQuantityScaler.baseServings(from: recipe), 1)
        )
        return RecipeNutritionDisplay(
            calories: estimate.calories,
            protein: estimate.protein,
            carbs: estimate.carbs,
            fat: estimate.fat,
            caloriesText: RecipePresentationFormatter.formatCalories(estimate.calories),
            proteinText: RecipePresentationFormatter.formatMacro(estimate.protein),
            carbsText: RecipePresentationFormatter.formatMacro(estimate.carbs),
            fatText: RecipePresentationFormatter.formatMacro(estimate.fat)
        )
    }
}

enum IngredientIconCatalog {
    static func kind(for ingredientName: String) -> IngredientIconKind {
        let normalized = RecipePresentationFormatter.normalizedSearchText(for: ingredientName)
        guard !normalized.isEmpty else { return .logo }

        for mapping in mappings where mapping.keywords.contains(where: normalized.contains) {
            return mapping.kind
        }

        return .logo
    }

    private static let mappings: [(keywords: [String], kind: IngredientIconKind)] = [
        (["saumon", "thon", "cabillaud", "morue", "poisson", "crevette", "shrimp"], .fish),
        (["tomate", "poivron", "citron", "orange", "avocat", "fraise", "framboise", "pomme", "banane"], .produce),
        (["epinard", "épinard", "salade", "roquette", "basilic", "persil", "coriandre", "menthe", "courgette", "brocoli", "concombre"], .herb),
        (["oignon", "echalote", "échalote", "ail"], .bulb),
        (["lait", "creme", "crème", "yaourt", "beurre"], .dairy),
        (["fromage", "mozzarella", "parmesan", "cheddar", "emmental", "comte", "comté"], .cheese),
        (["farine", "riz", "quinoa", "lentille", "lentilles", "pois chiche", "haricot", "haricots", "avoine", "mais", "maïs", "pates", "pâtes", "spaghetti", "penne"], .grain),
        (["pain", "baguette", "brioche", "bun", "toast", "tortilla"], .bread),
        (["oeuf", "oeufs", "œuf", "œufs", "egg"], .egg),
        (["poulet", "boeuf", "bœuf", "steak", "viande", "porc", "tofu"], .protein),
        (["huile", "mayo", "mayonnaise", "ketchup", "moutarde", "sauce", "vinaigre", "sirop"], .sauce),
        (["piment", "harissa", "paprika", "epice", "épice", "gingembre", "ail en poudre"], .spice),
        (["miel", "sucre", "chocolat", "cacao", "vanille"], .sweet)
    ]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
