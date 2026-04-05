import Foundation

struct RecipeNutritionEstimate: Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let salt: Double
    let saturatedFat: Double
    let portionCount: Int

    var nutrition: RecipeNutrition {
        RecipeNutrition(
            calories: Self.format(calories, decimals: 0, suffix: "kcal"),
            protein: Self.format(protein, decimals: 1, suffix: "g"),
            carbs: Self.format(carbs, decimals: 1, suffix: "g"),
            fat: Self.format(fat, decimals: 1, suffix: "g"),
            fiber: Self.format(fiber, decimals: 1, suffix: "g"),
            sugar: Self.format(sugar, decimals: 1, suffix: "g"),
            salt: Self.format(salt, decimals: 1, suffix: "g"),
            saturatedFat: Self.format(saturatedFat, decimals: 1, suffix: "g")
        )
    }

    private static func format(_ value: Double, decimals: Int, suffix: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        let number = NSNumber(value: value)
        return "\(formatter.string(from: number) ?? "\(value)") \(suffix)"
    }
}

enum RecipeQuantityScaler {
    static func baseServings(from recipe: Recipe) -> Int {
        guard let rawServings = recipe.details.servings else { return 1 }

        let digits = rawServings.compactMap { $0.isNumber ? String($0) : nil }.joined()
        if let value = Int(digits), value > 0 {
            return value
        }

        return 1
    }

    static func scaledQuantityText(
        for ingredient: RecipeIngredient,
        baseServings: Int,
        targetServings: Int
    ) -> String? {
        let scale = max(Double(targetServings), 1) / max(Double(baseServings), 1)

        guard let amount = ingredient.amount?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty else {
            return ingredient.unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        guard let numericAmount = numericValue(from: amount) else {
            return [amount, ingredient.unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        let scaledAmount = numericAmount * scale
        let amountText = formattedNumber(scaledAmount)
        let unit = ingredient.unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return [amountText, unit].compactMap { $0 }.joined(separator: " ")
    }

    static func scaledLine(
        for ingredient: RecipeIngredient,
        baseServings: Int,
        targetServings: Int
    ) -> String {
        let quantityText = scaledQuantityText(for: ingredient, baseServings: baseServings, targetServings: targetServings)
        return [quantityText, ingredient.name].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
    }

    static func numericValue(from rawText: String) -> Double? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let direct = Double(normalized) {
            return direct
        }

        if normalized.contains(" ") {
            let parts = normalized.split(separator: " ")
            if parts.count == 2,
               let whole = Double(parts[0]),
               let fraction = fractionValue(from: String(parts[1])) {
                return whole + fraction
            }
        }

        return fractionValue(from: normalized)
    }

    fileprivate static func approximateGrams(
        for ingredient: RecipeIngredient,
        profile: RecipeNutritionProfile,
        baseServings: Int,
        targetServings: Int
    ) -> Double? {
        let scale = max(Double(targetServings), 1) / max(Double(baseServings), 1)
        let amount = numericValue(from: ingredient.amount ?? "") ?? 1
        let scaledAmount = amount * scale
        let unit = normalizedUnit(from: ingredient.unit)

        switch unit {
        case "g", "gr", "gramme", "grammes":
            return scaledAmount
        case "kg", "kilogramme", "kilogrammes":
            return scaledAmount * 1000
        case "mg":
            return scaledAmount / 1000
        case "ml":
            return scaledAmount
        case "cl":
            return scaledAmount * 10
        case "l":
            return scaledAmount * 1000
        case "cas", "c a s", "c. a. s.", "cuillere a soupe", "cuillere a soupe rase":
            return scaledAmount * 15
        case "cac", "c a c", "c. a. c.", "cuillere a cafe":
            return scaledAmount * 5
        case "piece", "pieces", "oeuf", "oeufs", "tranche", "tranches", "gousse", "gousses", "":
            return profile.defaultUnitGrams.map { scaledAmount * $0 }
        default:
            return profile.defaultUnitGrams.map { scaledAmount * $0 }
        }
    }

    static func formattedNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.05 {
            return String(Int(rounded.rounded()))
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    private static func fractionValue(from string: String) -> Double? {
        let parts = string.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0
        else {
            return nil
        }

        return numerator / denominator
    }

    private static func normalizedUnit(from unit: String?) -> String {
        unit?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum RecipeNutritionEstimator {
    static func estimate(recipe: Recipe, forPortions portionCount: Int) -> RecipeNutritionEstimate {
        let safePortionCount = max(portionCount, 1)
        let baseServings = RecipeQuantityScaler.baseServings(from: recipe)

        var totalCalories = 0.0
        var totalProtein = 0.0
        var totalCarbs = 0.0
        var totalFat = 0.0
        var totalFiber = 0.0
        var totalSugar = 0.0
        var totalSalt = 0.0
        var totalSaturatedFat = 0.0

        for ingredient in recipe.ingredients {
            guard let profile = matchingProfile(for: ingredient.name) else { continue }
            guard let grams = RecipeQuantityScaler.approximateGrams(
                for: ingredient,
                profile: profile,
                baseServings: baseServings,
                targetServings: baseServings
            ) else { continue }

            let ratio = grams / 100
            totalCalories += profile.caloriesPer100g * ratio
            totalProtein += profile.proteinPer100g * ratio
            totalCarbs += profile.carbsPer100g * ratio
            totalFat += profile.fatPer100g * ratio
            totalFiber += profile.fiberPer100g * ratio
            totalSugar += profile.sugarPer100g * ratio
            totalSalt += profile.saltPer100g * ratio
            totalSaturatedFat += profile.saturatedFatPer100g * ratio
        }

        return RecipeNutritionEstimate(
            calories: totalCalories / Double(safePortionCount),
            protein: totalProtein / Double(safePortionCount),
            carbs: totalCarbs / Double(safePortionCount),
            fat: totalFat / Double(safePortionCount),
            fiber: totalFiber / Double(safePortionCount),
            sugar: totalSugar / Double(safePortionCount),
            salt: totalSalt / Double(safePortionCount),
            saturatedFat: totalSaturatedFat / Double(safePortionCount),
            portionCount: safePortionCount
        )
    }

    private static func matchingProfile(for ingredientName: String) -> RecipeNutritionProfile? {
        let normalized = normalizedIngredientName(ingredientName)
        return profiles.first { profile in
            profile.keywords.contains(where: normalized.contains)
        }
    }

    private static func normalizedIngredientName(_ ingredientName: String) -> String {
        ingredientName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let profiles: [RecipeNutritionProfile] = [
        .init(keywords: ["farine"], caloriesPer100g: 364, proteinPer100g: 10.3, carbsPer100g: 76.3, fatPer100g: 1, fiberPer100g: 2.7, sugarPer100g: 0.3, saturatedFatPer100g: 0.2),
        .init(keywords: ["beurre"], caloriesPer100g: 717, proteinPer100g: 0.9, carbsPer100g: 0.1, fatPer100g: 81.1, sugarPer100g: 0.1, saltPer100g: 0.1, saturatedFatPer100g: 51.4),
        .init(keywords: ["sucre glace", "sucre"], caloriesPer100g: 387, proteinPer100g: 0, carbsPer100g: 100, fatPer100g: 0, sugarPer100g: 100),
        .init(keywords: ["poudre d amande", "amandes", "amande"], caloriesPer100g: 579, proteinPer100g: 21.2, carbsPer100g: 21.6, fatPer100g: 49.9, fiberPer100g: 12.5, sugarPer100g: 4.4, saturatedFatPer100g: 3.8),
        .init(keywords: ["jaune"], caloriesPer100g: 322, proteinPer100g: 15.9, carbsPer100g: 3.6, fatPer100g: 26.5, sugarPer100g: 0.6, saturatedFatPer100g: 9.6, defaultUnitGrams: 18),
        .init(keywords: ["oeuf", "oeufs"], caloriesPer100g: 143, proteinPer100g: 12.6, carbsPer100g: 0.7, fatPer100g: 9.5, sugarPer100g: 0.4, saturatedFatPer100g: 3.1, defaultUnitGrams: 50),
        .init(keywords: ["creme", "cr me"], caloriesPer100g: 340, proteinPer100g: 2.1, carbsPer100g: 3.4, fatPer100g: 36, sugarPer100g: 3.2, saturatedFatPer100g: 23),
        .init(keywords: ["chocolat noir", "chocolat"], caloriesPer100g: 598, proteinPer100g: 7.8, carbsPer100g: 45.9, fatPer100g: 42.6, fiberPer100g: 10.9, sugarPer100g: 24, saturatedFatPer100g: 24.5),
        .init(keywords: ["grue de cacao", "grue", "cacao nib", "cacao"], caloriesPer100g: 600, proteinPer100g: 13.6, carbsPer100g: 30.4, fatPer100g: 54),
        .init(keywords: ["miel"], caloriesPer100g: 304, proteinPer100g: 0.3, carbsPer100g: 82.4, fatPer100g: 0, sugarPer100g: 82.1),
        .init(keywords: ["sirop de glucose", "glucose"], caloriesPer100g: 286, proteinPer100g: 0, carbsPer100g: 71, fatPer100g: 0, sugarPer100g: 71),
        .init(keywords: ["lait"], caloriesPer100g: 61, proteinPer100g: 3.2, carbsPer100g: 4.8, fatPer100g: 3.3, sugarPer100g: 5, saturatedFatPer100g: 1.9),
        .init(keywords: ["huile"], caloriesPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100, saturatedFatPer100g: 14),
        .init(keywords: ["tomate"], caloriesPer100g: 18, proteinPer100g: 0.9, carbsPer100g: 3.9, fatPer100g: 0.2, fiberPer100g: 1.2, sugarPer100g: 2.6, defaultUnitGrams: 120),
        .init(keywords: ["oignon"], caloriesPer100g: 40, proteinPer100g: 1.1, carbsPer100g: 9.3, fatPer100g: 0.1, fiberPer100g: 1.7, sugarPer100g: 4.2, defaultUnitGrams: 110),
        .init(keywords: ["echalote"], caloriesPer100g: 72, proteinPer100g: 2.5, carbsPer100g: 16.8, fatPer100g: 0.1, fiberPer100g: 3.2, sugarPer100g: 7.9, defaultUnitGrams: 30),
        .init(keywords: ["ail"], caloriesPer100g: 149, proteinPer100g: 6.4, carbsPer100g: 33.1, fatPer100g: 0.5, fiberPer100g: 2.1, sugarPer100g: 1, defaultUnitGrams: 5),
        .init(keywords: ["poivron"], caloriesPer100g: 31, proteinPer100g: 1, carbsPer100g: 6, fatPer100g: 0.3, fiberPer100g: 2.1, sugarPer100g: 4.2, defaultUnitGrams: 120),
        .init(keywords: ["concombre"], caloriesPer100g: 15, proteinPer100g: 0.7, carbsPer100g: 3.6, fatPer100g: 0.1, fiberPer100g: 0.5, sugarPer100g: 1.7, defaultUnitGrams: 250),
        .init(keywords: ["courgette", "zucchini"], caloriesPer100g: 17, proteinPer100g: 1.2, carbsPer100g: 3.1, fatPer100g: 0.3, fiberPer100g: 1, sugarPer100g: 2.5, defaultUnitGrams: 180),
        .init(keywords: ["aubergine"], caloriesPer100g: 25, proteinPer100g: 1, carbsPer100g: 5.9, fatPer100g: 0.2, fiberPer100g: 3, sugarPer100g: 3.5, defaultUnitGrams: 250),
        .init(keywords: ["brocoli"], caloriesPer100g: 34, proteinPer100g: 2.8, carbsPer100g: 6.6, fatPer100g: 0.4, fiberPer100g: 2.6, sugarPer100g: 1.7, defaultUnitGrams: 250),
        .init(keywords: ["champignon"], caloriesPer100g: 22, proteinPer100g: 3.1, carbsPer100g: 3.3, fatPer100g: 0.3, fiberPer100g: 1, sugarPer100g: 2, defaultUnitGrams: 80),
        .init(keywords: ["epinard"], caloriesPer100g: 23, proteinPer100g: 2.9, carbsPer100g: 3.6, fatPer100g: 0.4, fiberPer100g: 2.2, sugarPer100g: 0.4, defaultUnitGrams: 60),
        .init(keywords: ["salade", "laitue"], caloriesPer100g: 15, proteinPer100g: 1.4, carbsPer100g: 2.9, fatPer100g: 0.2, fiberPer100g: 1.3, sugarPer100g: 0.8, defaultUnitGrams: 80),
        .init(keywords: ["persil", "coriandre", "basilic"], caloriesPer100g: 36, proteinPer100g: 3, carbsPer100g: 6.3, fatPer100g: 0.8, defaultUnitGrams: 5),
        .init(keywords: ["gingembre"], caloriesPer100g: 80, proteinPer100g: 1.8, carbsPer100g: 18, fatPer100g: 0.8, fiberPer100g: 2, sugarPer100g: 1.7, defaultUnitGrams: 10),
        .init(keywords: ["pomme de terre"], caloriesPer100g: 77, proteinPer100g: 2, carbsPer100g: 17.5, fatPer100g: 0.1, fiberPer100g: 2.2, sugarPer100g: 0.8, defaultUnitGrams: 150),
        .init(keywords: ["patate douce"], caloriesPer100g: 86, proteinPer100g: 1.6, carbsPer100g: 20.1, fatPer100g: 0.1, fiberPer100g: 3, sugarPer100g: 4.2, defaultUnitGrams: 180),
        .init(keywords: ["poulet"], caloriesPer100g: 239, proteinPer100g: 27.3, carbsPer100g: 0, fatPer100g: 13.6, saltPer100g: 0.2, saturatedFatPer100g: 3.8),
        .init(keywords: ["boeuf", "b uf", "steak"], caloriesPer100g: 250, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 15, saturatedFatPer100g: 6),
        .init(keywords: ["tofu"], caloriesPer100g: 144, proteinPer100g: 17.3, carbsPer100g: 3.5, fatPer100g: 8.7, fiberPer100g: 2.3, sugarPer100g: 0.6, saturatedFatPer100g: 1.3),
        .init(keywords: ["crevette", "shrimp"], caloriesPer100g: 99, proteinPer100g: 24, carbsPer100g: 0.2, fatPer100g: 0.3, saltPer100g: 0.4, saturatedFatPer100g: 0.1),
        .init(keywords: ["saumon"], caloriesPer100g: 208, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 13, saturatedFatPer100g: 3.1),
        .init(keywords: ["thon"], caloriesPer100g: 132, proteinPer100g: 28, carbsPer100g: 0, fatPer100g: 1.3),
        .init(keywords: ["cabillaud", "morue"], caloriesPer100g: 82, proteinPer100g: 18, carbsPer100g: 0, fatPer100g: 0.7, saturatedFatPer100g: 0.1),
        .init(keywords: ["riz"], caloriesPer100g: 360, proteinPer100g: 7.1, carbsPer100g: 79, fatPer100g: 0.7, fiberPer100g: 1, sugarPer100g: 0.1, saturatedFatPer100g: 0.2),
        .init(keywords: ["pates", "spaghetti", "pasta"], caloriesPer100g: 371, proteinPer100g: 13, carbsPer100g: 75, fatPer100g: 1.5, fiberPer100g: 3.2, sugarPer100g: 2.7, saturatedFatPer100g: 0.3),
        .init(keywords: ["quinoa"], caloriesPer100g: 368, proteinPer100g: 14.1, carbsPer100g: 64.2, fatPer100g: 6.1, fiberPer100g: 7, sugarPer100g: 4.5, saturatedFatPer100g: 0.7),
        .init(keywords: ["lentille", "lentilles"], caloriesPer100g: 353, proteinPer100g: 25.8, carbsPer100g: 60.1, fatPer100g: 1.1, fiberPer100g: 10.7, sugarPer100g: 2, saturatedFatPer100g: 0.2),
        .init(keywords: ["pois chiche", "pois chiches"], caloriesPer100g: 364, proteinPer100g: 19, carbsPer100g: 61, fatPer100g: 6, fiberPer100g: 17.4, sugarPer100g: 10.7, saturatedFatPer100g: 0.6),
        .init(keywords: ["haricot", "haricots"], caloriesPer100g: 333, proteinPer100g: 21.4, carbsPer100g: 60, fatPer100g: 1.2, fiberPer100g: 15.2, sugarPer100g: 2.1, saturatedFatPer100g: 0.2),
        .init(keywords: ["avoine", "flocons d avoine"], caloriesPer100g: 389, proteinPer100g: 16.9, carbsPer100g: 66.3, fatPer100g: 6.9, fiberPer100g: 10.6, sugarPer100g: 1, saturatedFatPer100g: 1.2),
        .init(keywords: ["mais", "maïs"], caloriesPer100g: 365, proteinPer100g: 9.4, carbsPer100g: 74.3, fatPer100g: 4.7, fiberPer100g: 7.3, sugarPer100g: 0.6, saturatedFatPer100g: 0.7),
        .init(keywords: ["fromage", "parmesan", "mozzarella", "cheddar", "emmental", "gruyere"], caloriesPer100g: 380, proteinPer100g: 24, carbsPer100g: 2.5, fatPer100g: 30, sugarPer100g: 1, saltPer100g: 1.4, saturatedFatPer100g: 19, defaultUnitGrams: 20),
        .init(keywords: ["pain burger", "hamburger bun", "bun"], caloriesPer100g: 270, proteinPer100g: 8.5, carbsPer100g: 51, fatPer100g: 3.5, fiberPer100g: 2.3, sugarPer100g: 5.5, saltPer100g: 1.1, saturatedFatPer100g: 0.8, defaultUnitGrams: 75),
        .init(keywords: ["cornichon", "pickle"], caloriesPer100g: 12, proteinPer100g: 0.5, carbsPer100g: 2.3, fatPer100g: 0.2, fiberPer100g: 1.2, sugarPer100g: 1.1, saltPer100g: 1.2, defaultUnitGrams: 8),
        .init(keywords: ["mayonnaise", "mayo"], caloriesPer100g: 680, proteinPer100g: 1, carbsPer100g: 1, fatPer100g: 75, sugarPer100g: 0.6, saltPer100g: 1.5, saturatedFatPer100g: 11.7),
        .init(keywords: ["ketchup"], caloriesPer100g: 112, proteinPer100g: 1.3, carbsPer100g: 25.8, fatPer100g: 0.2, fiberPer100g: 0.3, sugarPer100g: 22.8, saltPer100g: 2.2),
        .init(keywords: ["moutarde", "mustard"], caloriesPer100g: 66, proteinPer100g: 4.4, carbsPer100g: 5.8, fatPer100g: 4.4, fiberPer100g: 3.3, sugarPer100g: 0.4, saltPer100g: 5, saturatedFatPer100g: 0.2),
        .init(keywords: ["yaourt", "yogurt", "yaourt grec"], caloriesPer100g: 97, proteinPer100g: 9, carbsPer100g: 3.9, fatPer100g: 5, sugarPer100g: 3.6, saturatedFatPer100g: 3.2),
        .init(keywords: ["fromage blanc"], caloriesPer100g: 98, proteinPer100g: 8, carbsPer100g: 3.7, fatPer100g: 4.2, sugarPer100g: 3.7, saturatedFatPer100g: 2.6),
        .init(keywords: ["ricotta"], caloriesPer100g: 174, proteinPer100g: 11.3, carbsPer100g: 3, fatPer100g: 13, sugarPer100g: 0.3, saltPer100g: 0.3, saturatedFatPer100g: 8.3),
        .init(keywords: ["mascarpone"], caloriesPer100g: 429, proteinPer100g: 4.6, carbsPer100g: 4.1, fatPer100g: 44.5, sugarPer100g: 3.6, saturatedFatPer100g: 29.3),
        .init(keywords: ["avocat"], caloriesPer100g: 160, proteinPer100g: 2, carbsPer100g: 8.5, fatPer100g: 14.7, fiberPer100g: 6.7, sugarPer100g: 0.7, saturatedFatPer100g: 2.1, defaultUnitGrams: 150),
        .init(keywords: ["banane"], caloriesPer100g: 89, proteinPer100g: 1.1, carbsPer100g: 22.8, fatPer100g: 0.3, fiberPer100g: 2.6, sugarPer100g: 12.2, defaultUnitGrams: 120),
        .init(keywords: ["citron"], caloriesPer100g: 29, proteinPer100g: 1.1, carbsPer100g: 9.3, fatPer100g: 0.3, fiberPer100g: 2.8, sugarPer100g: 2.5, defaultUnitGrams: 80),
        .init(keywords: ["orange"], caloriesPer100g: 47, proteinPer100g: 0.9, carbsPer100g: 11.8, fatPer100g: 0.1, fiberPer100g: 2.4, sugarPer100g: 9.4, defaultUnitGrams: 130),
        .init(keywords: ["pomme"], caloriesPer100g: 52, proteinPer100g: 0.3, carbsPer100g: 13.8, fatPer100g: 0.2, fiberPer100g: 2.4, sugarPer100g: 10.4, defaultUnitGrams: 150),
        .init(keywords: ["poire"], caloriesPer100g: 57, proteinPer100g: 0.4, carbsPer100g: 15.2, fatPer100g: 0.1, fiberPer100g: 3.1, sugarPer100g: 9.8, defaultUnitGrams: 160),
        .init(keywords: ["fraise"], caloriesPer100g: 32, proteinPer100g: 0.7, carbsPer100g: 7.7, fatPer100g: 0.3, fiberPer100g: 2, sugarPer100g: 4.9, defaultUnitGrams: 18),
        .init(keywords: ["framboise"], caloriesPer100g: 52, proteinPer100g: 1.2, carbsPer100g: 11.9, fatPer100g: 0.7, fiberPer100g: 6.5, sugarPer100g: 4.4, defaultUnitGrams: 5),
        .init(keywords: ["myrtille"], caloriesPer100g: 57, proteinPer100g: 0.7, carbsPer100g: 14.5, fatPer100g: 0.3, fiberPer100g: 2.4, sugarPer100g: 10, defaultUnitGrams: 2),
        .init(keywords: ["raisin"], caloriesPer100g: 69, proteinPer100g: 0.7, carbsPer100g: 18.1, fatPer100g: 0.2, fiberPer100g: 0.9, sugarPer100g: 15.5, defaultUnitGrams: 5),
        .init(keywords: ["sel", "fleur de sel"], caloriesPer100g: 0, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0, saltPer100g: 100)
    ]
}

fileprivate struct RecipeNutritionProfile: Hashable {
    let keywords: [String]
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let fiberPer100g: Double
    let sugarPer100g: Double
    let saltPer100g: Double
    let saturatedFatPer100g: Double
    let defaultUnitGrams: Double?

    init(
        keywords: [String],
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        saltPer100g: Double = 0,
        saturatedFatPer100g: Double = 0,
        defaultUnitGrams: Double? = nil
    ) {
        self.keywords = keywords
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.saltPer100g = saltPer100g
        self.saturatedFatPer100g = saturatedFatPer100g
        self.defaultUnitGrams = defaultUnitGrams
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
