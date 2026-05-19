import Foundation
import SwiftUI
import UIKit

enum RecipePresentationTab: String, CaseIterable, Identifiable {
    case ingredients = "Ingredients"
    case steps = "Steps"
    case nutrition = "Nutrition"

    var id: String { rawValue }
}

enum RecipePresentationDensity {
    case regular
    case compact
}

struct RecipeIngredientPresentation: Identifiable, Hashable {
    let id: RecipeIngredient.ID
    let quantityText: String?
    let rawAmount: String?
    let rawUnit: String?
    let name: String

    init(id: RecipeIngredient.ID, quantityText: String?, rawAmount: String? = nil, rawUnit: String? = nil, name: String) {
        self.id = id
        self.quantityText = quantityText
        self.rawAmount = rawAmount
        self.rawUnit = rawUnit
        self.name = name
    }

    var fullLine: String {
        [quantityText?.nilIfEmpty, name.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Display-normalized row for rendering.
    /// Uses the (possibly scaled) quantityText for the amount portion,
    /// but normalizes the unit and name for clean display.
    var normalizedDisplay: IngredientDisplayRow {
        // Extract the numeric portion from the already-scaled quantityText
        let scaledAmount: String?
        if let qt = quantityText {
            let parts = qt.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
            scaledAmount = parts.first
        } else {
            scaledAmount = nil
        }
        return IngredientDisplayNormalizer.displayRow(amount: scaledAmount, unit: rawUnit, name: name)
    }
}

struct RecipeNutritionDisplay: Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let salt: Double
    let saturatedFat: Double
    let caloriesText: String
    let proteinText: String
    let carbsText: String
    let fatText: String
    let fiberText: String
    let sugarText: String
    let saltText: String
    let saturatedFatText: String
}

struct IngredientVisualCatalogEntry: Codable, Hashable {
    let canonicalKey: String
    let assetName: String
    let aliases: [String]
    let family: String
    let priority: Int
}

struct NormalizedIngredient: Hashable {
    let original: String
    let normalizedText: String
    let candidateKeys: [String]
    let familyHints: [String]
}


enum IngredientVisualMatchKind: String, Hashable {
    case canonical
    case alias
    case family
    case logo
}

struct IngredientVisualResolution: Hashable {
    let assetName: String?
    let matchKind: IngredientVisualMatchKind
    let matchedEntry: IngredientVisualCatalogEntry?
    let normalizedIngredient: NormalizedIngredient

    var usesLogoFallback: Bool {
        matchKind == .logo || assetName == nil
    }
}

enum RecipePresentationFormatter {
    static func sourceButtonTitle(for sourceURL: URL?) -> String? {
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "Ouvrir TikTok" }
        if host.contains("instagram") { return "Ouvrir Instagram" }
        if host.contains("youtube") { return "Ouvrir YouTube" }
        if host.contains("pinterest") { return "Ouvrir Pinterest" }
        if host.contains("cooksy.app"), sourceURL?.path(percentEncoded: false).contains("/demo/") == true {
            return "Voir la démo source"
        }
        return "Ouvrir la source"
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
        servings > 1 ? "\(servings) portions" : "1 portion"
    }

    static func selectedServingsLabel(for servings: Int) -> String {
        servings > 1 ? "\(servings) personnes" : "1 personne"
    }

    static func baseServingsCaption(for servings: Int) -> String {
        "Recette de base : \(servings > 1 ? "\(servings) portions" : "1 portion")"
    }

    static func summaryText(noteText: String?, title: String, totalTimeLabel: String?, baseServings: Int) -> String {
        if let noteText = firstMeaningfulSentence(from: noteText) {
            return noteText
        }

        if let totalTimeLabel {
            return "\(title) prêt en environ \(totalTimeLabel.lowercased()) pour \(servingsLabel(for: baseServings).lowercased())."
        }

        return "\(title) structuré avec des ingrédients clairs et des étapes prêtes à cuisiner pour \(servingsLabel(for: baseServings).lowercased())."
    }

    static func difficultyLabel(for recipe: Recipe?) -> String {
        guard let recipe else { return "Intermédiaire" }

        let totalTime = (recipe.details.prepTimeMinutes ?? 0) + (recipe.details.cookTimeMinutes ?? 0)
        let ingredientCount = recipe.ingredients.count
        let stepCount = recipe.steps.count

        if totalTime >= 45 || ingredientCount >= 10 || stepCount >= 7 {
            return "Difficile"
        }

        if totalTime <= 20 && ingredientCount <= 6 && stepCount <= 4 {
            return "Facile"
        }

        return "Intermédiaire"
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
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae")
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
            fiber: perServingNutrition.fiber * factor,
            sugar: perServingNutrition.sugar * factor,
            salt: perServingNutrition.salt * factor,
            saturatedFat: perServingNutrition.saturatedFat * factor,
            caloriesText: RecipePresentationFormatter.formatCalories(perServingNutrition.calories * factor),
            proteinText: RecipePresentationFormatter.formatMacro(perServingNutrition.protein * factor),
            carbsText: RecipePresentationFormatter.formatMacro(perServingNutrition.carbs * factor),
            fatText: RecipePresentationFormatter.formatMacro(perServingNutrition.fat * factor),
            fiberText: RecipePresentationFormatter.formatMacro(perServingNutrition.fiber * factor),
            sugarText: RecipePresentationFormatter.formatMacro(perServingNutrition.sugar * factor),
            saltText: RecipePresentationFormatter.formatMacro(perServingNutrition.salt * factor),
            saturatedFatText: RecipePresentationFormatter.formatMacro(perServingNutrition.saturatedFat * factor)
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
        let baseServings = max(RecipeQuantityScaler.baseServings(from: recipe), 1)
        let estimate = RecipeNutritionEstimator.estimate(
            recipe: recipe,
            forPortions: baseServings
        )

        if let stored = recipe.nutrition {
            let calories = RecipePresentationFormatter.parseNumber(from: stored.calories) ?? estimate.calories
            let protein = RecipePresentationFormatter.parseNumber(from: stored.protein) ?? estimate.protein
            let carbs = RecipePresentationFormatter.parseNumber(from: stored.carbs) ?? estimate.carbs
            let fat = RecipePresentationFormatter.parseNumber(from: stored.fat) ?? estimate.fat
            let fiber = RecipePresentationFormatter.parseNumber(from: stored.fiber) ?? estimate.fiber
            let sugar = RecipePresentationFormatter.parseNumber(from: stored.sugar) ?? estimate.sugar
            let salt = RecipePresentationFormatter.parseNumber(from: stored.salt) ?? estimate.salt
            let saturatedFat = RecipePresentationFormatter.parseNumber(from: stored.saturatedFat) ?? estimate.saturatedFat
            if calories > 0 || protein > 0 || carbs > 0 || fat > 0 {
                return RecipeNutritionDisplay(
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    fiber: fiber,
                    sugar: sugar,
                    salt: salt,
                    saturatedFat: saturatedFat,
                    caloriesText: stored.calories ?? RecipePresentationFormatter.formatCalories(calories),
                    proteinText: stored.protein ?? RecipePresentationFormatter.formatMacro(protein),
                    carbsText: stored.carbs ?? RecipePresentationFormatter.formatMacro(carbs),
                    fatText: stored.fat ?? RecipePresentationFormatter.formatMacro(fat),
                    fiberText: stored.fiber ?? RecipePresentationFormatter.formatMacro(fiber),
                    sugarText: stored.sugar ?? RecipePresentationFormatter.formatMacro(sugar),
                    saltText: stored.salt ?? RecipePresentationFormatter.formatMacro(salt),
                    saturatedFatText: stored.saturatedFat ?? RecipePresentationFormatter.formatMacro(saturatedFat)
                )
            }
        }
        return RecipeNutritionDisplay(
            calories: estimate.calories,
            protein: estimate.protein,
            carbs: estimate.carbs,
            fat: estimate.fat,
            fiber: estimate.fiber,
            sugar: estimate.sugar,
            salt: estimate.salt,
            saturatedFat: estimate.saturatedFat,
            caloriesText: RecipePresentationFormatter.formatCalories(estimate.calories),
            proteinText: RecipePresentationFormatter.formatMacro(estimate.protein),
            carbsText: RecipePresentationFormatter.formatMacro(estimate.carbs),
            fatText: RecipePresentationFormatter.formatMacro(estimate.fat),
            fiberText: RecipePresentationFormatter.formatMacro(estimate.fiber),
            sugarText: RecipePresentationFormatter.formatMacro(estimate.sugar),
            saltText: RecipePresentationFormatter.formatMacro(estimate.salt),
            saturatedFatText: RecipePresentationFormatter.formatMacro(estimate.saturatedFat)
        )
    }
}


struct IngredientVisualResolver {
    private let canonicalEntries: [String: IngredientVisualCatalogEntry]
    private let aliasEntries: [String: IngredientVisualCatalogEntry]
    private let familyAssetNames: [String: String]

    init(entries: [IngredientVisualCatalogEntry]) {
        var canonicalEntries: [String: IngredientVisualCatalogEntry] = [:]
        var aliasEntries: [String: IngredientVisualCatalogEntry] = [:]
        var familyAssetNames: [String: (priority: Int, assetName: String)] = [:]

        for entry in entries {
            let canonicalKey = RecipePresentationFormatter.normalizedSearchText(for: entry.canonicalKey)
            if let existing = canonicalEntries[canonicalKey], existing.priority > entry.priority {
                // Keep the higher-priority mapping already registered.
            } else {
                canonicalEntries[canonicalKey] = entry
            }

            for alias in entry.aliases {
                let normalizedAlias = RecipePresentationFormatter.normalizedSearchText(for: alias)
                guard !normalizedAlias.isEmpty else { continue }

                if let existing = aliasEntries[normalizedAlias], existing.priority > entry.priority {
                    continue
                }

                aliasEntries[normalizedAlias] = entry
            }

            let normalizedFamily = RecipePresentationFormatter.normalizedSearchText(for: entry.family)
            guard !normalizedFamily.isEmpty else { continue }

            if let existing = familyAssetNames[normalizedFamily], existing.priority > entry.priority {
                continue
            }

            familyAssetNames[normalizedFamily] = (entry.priority, entry.assetName)
        }

        self.canonicalEntries = canonicalEntries
        self.aliasEntries = aliasEntries
        self.familyAssetNames = familyAssetNames.mapValues(\.assetName)
    }

    func resolve(_ ingredientName: String) -> IngredientVisualResolution {
        let normalizedIngredient = IngredientNameNormalizer.normalize(ingredientName)

        for candidate in normalizedIngredient.candidateKeys {
            if let entry = canonicalEntries[candidate] {
                return IngredientVisualResolution(
                    assetName: entry.assetName,
                    matchKind: .canonical,
                    matchedEntry: entry,
                    normalizedIngredient: normalizedIngredient
                )
            }
        }

        for candidate in normalizedIngredient.candidateKeys {
            if let entry = aliasEntries[candidate] {
                return IngredientVisualResolution(
                    assetName: entry.assetName,
                    matchKind: .alias,
                    matchedEntry: entry,
                    normalizedIngredient: normalizedIngredient
                )
            }
        }

        for familyHint in normalizedIngredient.familyHints {
            if let assetName = familyAssetNames[familyHint] {
                return IngredientVisualResolution(
                    assetName: assetName,
                    matchKind: .family,
                    matchedEntry: nil,
                    normalizedIngredient: normalizedIngredient
                )
            }
        }

        return IngredientVisualResolution(
            assetName: nil,
            matchKind: .logo,
            matchedEntry: nil,
            normalizedIngredient: normalizedIngredient
        )
    }
}

enum IngredientNameNormalizer {
    static func normalize(_ value: String) -> NormalizedIngredient {
        let normalizedText = cleanedSearchText(from: value)
        let tokens = normalizedText
            .split(separator: " ")
            .compactMap { cleanedToken(from: String($0)) }

        let candidateKeys = orderedUnique(
            (candidatePhrases(from: tokens) + [normalizedText])
                .map { RecipePresentationFormatter.normalizedSearchText(for: $0) }
                .filter { !$0.isEmpty }
        )

        let familyHints = orderedUnique(
            familyMappings.compactMap { mapping in
                let tokenSet = Set(tokens)
                if !tokenSet.isDisjoint(with: mapping.keywords) {
                    return mapping.family
                }

                if mapping.phrases.contains(where: normalizedText.contains) {
                    return mapping.family
                }

                return nil
            }
        )

        return NormalizedIngredient(
            original: value,
            normalizedText: normalizedText,
            candidateKeys: candidateKeys,
            familyHints: familyHints
        )
    }

    private static func cleanedSearchText(from value: String) -> String {
        let withoutParentheses = value.replacingOccurrences(
            of: "\\([^)]*\\)",
            with: " ",
            options: .regularExpression
        )

        let normalized = RecipePresentationFormatter.normalizedSearchText(for: withoutParentheses)
        return normalized
            .replacingOccurrences(of: "\\b\\d+[\\d.,/%]*\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(t\\d{2,3}|type\\s*\\d{2,3})\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedToken(from token: String) -> String? {
        guard !token.isEmpty else { return nil }
        guard !measurementPattern.matches(token) else { return nil }
        guard !units.contains(token), !stopWords.contains(token), !descriptors.contains(token) else { return nil }

        let singular = singularized(token)
        guard !singular.isEmpty, !units.contains(singular), !stopWords.contains(singular), !descriptors.contains(singular) else {
            return nil
        }

        return singular
    }

    private static func candidatePhrases(from tokens: [String]) -> [String] {
        guard !tokens.isEmpty else { return [] }
        var candidates: [String] = [tokens.joined(separator: " ")]

        let maxWindow = min(tokens.count, 4)
        if maxWindow > 1 {
            for length in stride(from: maxWindow, through: 1, by: -1) {
                for startIndex in 0...(tokens.count - length) {
                    let phrase = tokens[startIndex..<(startIndex + length)].joined(separator: " ")
                    candidates.append(phrase)
                }
            }
        }

        if let last = tokens.last {
            candidates.append(last)
        }

        return candidates
    }

    private static func singularized(_ token: String) -> String {
        guard !pluralExceptions.contains(token) else { return token }

        if token.count > 4, token.hasSuffix("ies") {
            return String(token.dropLast(3)) + "y"
        }

        if token.count > 4, token.hasSuffix("ves") {
            return String(token.dropLast(3)) + "f"
        }

        if token.count > 4, token.hasSuffix("oes") {
            return String(token.dropLast(2))
        }

        if token.count > 4, token.hasSuffix("ches") || token.hasSuffix("shes") {
            return String(token.dropLast(2))
        }

        if token.count > 3, token.hasSuffix("es"), !token.hasSuffix("ses"), !token.hasSuffix("ees") {
            return String(token.dropLast(1))
        }

        if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }

        return token
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }

        return ordered
    }

    private struct FamilyMapping {
        let family: String
        let keywords: Set<String>
        let phrases: [String]
    }

    private static let measurementPattern = try! NSRegularExpression(pattern: #"^\d+[a-z0-9./%]*$"#)

    private static let stopWords: Set<String> = [
        "a", "au", "aux", "avec", "d", "de", "des", "du", "for", "la", "le", "les", "or", "ou", "the", "to"
    ]

    private static let units: Set<String> = [
        "c", "ca", "cac", "cac.", "cas", "cas.", "cl", "cup", "cups", "dl", "g", "kg", "lb", "l", "ml", "mg",
        "oz", "piece", "pieces", "pinch", "pincee", "pincees", "sachet", "sachets", "slice", "slices", "sprig",
        "sprigs", "tablespoon", "tablespoons", "tbsp", "teaspoon", "teaspoons", "tsp"
    ]

    private static let descriptors: Set<String> = [
        "bio", "chopped", "cooked", "coupe", "coupes", "diced", "emince", "emincee", "emincees", "fresh", "freshly",
        "frozen", "grated", "ground", "halved", "minced", "nature", "naturel", "naturelle", "optional", "organic",
        "peeled", "rinsed", "roasted", "salted", "softened", "toasted", "unsalted", "vierge", "virgin", "warm"
    ]

    private static let pluralExceptions: Set<String> = [
        "couscous", "greens", "herbs", "leeks", "molasses", "oats", "pasta", "rice", "spinach"
    ]

    private static let familyMappings: [FamilyMapping] = [
        FamilyMapping(family: "flour", keywords: ["farine", "flour"], phrases: []),
        FamilyMapping(family: "butter", keywords: ["beurre", "butter"], phrases: []),
        FamilyMapping(family: "sugar", keywords: ["sucre", "sugar", "cassonade", "vergeoise"], phrases: ["powdered sugar", "sucre glace"]),
        FamilyMapping(family: "egg", keywords: ["egg", "oeuf"], phrases: ["blanc d oeuf", "jaune d oeuf"]),
        FamilyMapping(family: "milk", keywords: ["lait", "milk"], phrases: []),
        FamilyMapping(family: "cream", keywords: ["cream", "creme"], phrases: ["creme fraiche", "crème fraîche"]),
        FamilyMapping(family: "yogurt", keywords: ["yaourt", "yogurt", "yoghurt"], phrases: []),
        FamilyMapping(family: "cheese", keywords: ["cheese", "fromage", "parmesan", "cheddar", "mozzarella", "gruyere"], phrases: []),
        FamilyMapping(family: "white cheese", keywords: ["feta", "ricotta", "mascarpone", "chevre"], phrases: ["fromage blanc", "goat cheese", "cream cheese", "cottage cheese"]),
        FamilyMapping(family: "baking powder", keywords: ["baking", "levure"], phrases: ["baking powder", "levure chimique"]),
        FamilyMapping(family: "yeast", keywords: ["yeast"], phrases: ["levure boulangere", "levure boulangère"]),
        FamilyMapping(family: "salt", keywords: ["salt", "sel"], phrases: []),
        FamilyMapping(family: "spice", keywords: ["cumin", "curry", "curcuma", "ginger", "gingembre", "paprika", "piment"], phrases: ["garam masala", "hot sauce"]),
        FamilyMapping(family: "herbs", keywords: ["basilic", "basil", "ciboulette", "coriandre", "cilantro", "dill", "herbe", "herb", "menthe", "mint", "parsley", "persil", "rosemary", "romarin", "thym", "thyme"], phrases: []),
        FamilyMapping(family: "oil", keywords: ["huile", "oil"], phrases: ["olive oil", "sesame oil"]),
        FamilyMapping(family: "honey", keywords: ["agave", "honey", "miel"], phrases: ["maple syrup", "sirop d erable", "sirop d'érable"]),
        FamilyMapping(family: "chocolate", keywords: ["cacao", "chocolate", "chocolat", "cocoa"], phrases: ["cocoa powder"]),
        FamilyMapping(family: "vanilla", keywords: ["vanilla", "vanille"], phrases: []),
        FamilyMapping(family: "water", keywords: ["eau", "water"], phrases: []),
        FamilyMapping(family: "stock", keywords: ["bouillon", "broth", "stock"], phrases: ["chicken stock", "vegetable stock", "beef stock"]),
        FamilyMapping(family: "rice", keywords: ["arborio", "basmati", "jasmine", "rice", "riz"], phrases: ["risotto rice"]),
        FamilyMapping(family: "pasta", keywords: ["linguine", "noodle", "nouille", "pasta", "penne", "ramen", "spaghetti", "udon"], phrases: []),
        FamilyMapping(family: "bread", keywords: ["baguette", "bread", "breadcrumbs", "brioche", "bun", "pain", "toast"], phrases: ["burger bun", "panko breadcrumbs"]),
        FamilyMapping(family: "tortilla", keywords: ["flatbread", "naan", "pita", "tortilla", "wrap"], phrases: []),
        FamilyMapping(family: "beans", keywords: ["bean", "chickpea", "haricot", "lentil", "lentille", "pea", "pois"], phrases: ["black beans", "kidney beans", "pois chiches", "petits pois"]),
        FamilyMapping(family: "nuts", keywords: ["almond", "amande", "cashew", "noix", "peanut", "pecan", "sesame"], phrases: ["sunflower seeds", "graines de sesame"]),
        FamilyMapping(family: "tofu", keywords: ["tempeh", "tofu"], phrases: []),
        FamilyMapping(family: "chicken", keywords: ["chicken", "poulet"], phrases: ["chicken breast", "chicken thigh"]),
        FamilyMapping(family: "beef", keywords: ["beef", "boeuf", "steak", "viande"], phrases: ["ground beef", "minced beef", "viande hachee", "viande hachée"]),
        FamilyMapping(family: "pork", keywords: ["bacon", "ham", "lardon", "pork", "porc", "prosciutto", "sausage", "saucisse"], phrases: []),
        FamilyMapping(family: "fish", keywords: ["cabillaud", "cod", "fish", "poisson", "salmon", "saumon", "thon", "tilapia", "trout", "tuna"], phrases: ["sea bass"]),
        FamilyMapping(family: "shrimp", keywords: ["crab", "crevette", "lobster", "prawn", "shrimp"], phrases: ["langoustine"]),
        FamilyMapping(family: "tomato", keywords: ["tomate", "tomato"], phrases: ["cherry tomato", "tomato sauce", "tomato paste", "sauce tomate"]),
        FamilyMapping(family: "onion", keywords: ["echalote", "oignon", "onion", "scallion", "shallot"], phrases: ["green onion", "spring onion"]),
        FamilyMapping(family: "garlic", keywords: ["ail", "garlic"], phrases: ["garlic cloves"]),
        FamilyMapping(family: "potato", keywords: ["patate", "pomme", "potato"], phrases: ["pomme de terre", "pommes de terre", "sweet potato", "patate douce"]),
        FamilyMapping(family: "carrot", keywords: ["carotte", "carrot"], phrases: []),
        FamilyMapping(family: "mushroom", keywords: ["champignon", "mushroom", "portobello", "shiitake"], phrases: []),
        FamilyMapping(family: "leafy green", keywords: ["epinard", "kale", "laitue", "lettuce", "rocket", "romaine", "roquette", "salad", "salade", "spinach"], phrases: ["bok choy", "chou kale"]),
        FamilyMapping(family: "broccoli", keywords: ["broccoli", "brocoli", "cauliflower"], phrases: ["chou fleur"]),
        FamilyMapping(family: "pepper", keywords: ["jalapeno", "pepper", "poivron"], phrases: ["bell pepper"]),
        FamilyMapping(family: "cucumber", keywords: ["concombre", "cucumber", "pickle"], phrases: ["cornichon"]),
        FamilyMapping(family: "zucchini", keywords: ["aubergine", "courgette", "eggplant", "zucchini"], phrases: []),
        FamilyMapping(family: "corn", keywords: ["corn", "mais"], phrases: ["maïs"]),
        FamilyMapping(family: "avocado", keywords: ["avocado", "avocat"], phrases: []),
        FamilyMapping(family: "lemon", keywords: ["citron", "lemon"], phrases: ["lemon juice", "jus de citron"]),
        FamilyMapping(family: "lime", keywords: ["lime"], phrases: ["citron vert", "lime juice"]),
        FamilyMapping(family: "orange", keywords: ["orange"], phrases: ["orange juice", "jus d orange"]),
        FamilyMapping(family: "apple", keywords: ["apple", "pear", "poire", "pomme"], phrases: []),
        FamilyMapping(family: "berry", keywords: ["berry", "blueberry", "cranberry", "fraise", "framboise", "myrtille", "raspberry", "strawberry"], phrases: []),
        FamilyMapping(family: "banana", keywords: ["banana", "banane"], phrases: []),
        FamilyMapping(family: "coconut", keywords: ["coconut", "coco"], phrases: ["coconut milk", "coconut cream", "noix de coco"]),
        FamilyMapping(family: "sauce", keywords: ["ketchup", "mayo", "mayonnaise", "moutarde", "mustard", "sauce", "soy", "vinaigre", "vinegar"], phrases: ["sauce soja", "soy sauce", "hot sauce", "sauce piquante"]),
    ]
}

enum IngredientVisualCatalog {
    static func preload() {
        _ = resolver
    }

    static func assetName(for ingredientName: String) -> String? {
        resolution(for: ingredientName).assetName
    }

    static func resolution(for ingredientName: String) -> IngredientVisualResolution {
        resolver.resolve(ingredientName)
    }

    private static let resolver = IngredientVisualResolver(entries: loadEntries())

    private static func loadEntries() -> [IngredientVisualCatalogEntry] {
        let decoder = JSONDecoder()

        for bundle in bundleCandidates {
            if let dataAsset = NSDataAsset(name: manifestAssetName, bundle: bundle),
               let entries = try? decoder.decode([IngredientVisualCatalogEntry].self, from: dataAsset.data),
               !entries.isEmpty {
                return entries
            }
        }

        return []
    }

    private static var bundleCandidates: [Bundle] {
        let bundles = [Bundle.main, Bundle(for: IngredientVisualBundleSentinel.self)] + Bundle.allBundles + Bundle.allFrameworks
        var seen = Set<String>()
        var ordered: [Bundle] = []

        for bundle in bundles where seen.insert(bundle.bundlePath).inserted {
            ordered.append(bundle)
        }

        return ordered
    }

    private static let manifestAssetName = "IngredientIconManifest"
}

private final class IngredientVisualBundleSentinel {}

private extension NSRegularExpression {
    func matches(_ value: String) -> Bool {
        let range = NSRange(location: 0, length: value.utf16.count)
        return firstMatch(in: value, options: [], range: range) != nil
    }
}

// MARK: - Ingredient Display Normalization

struct IngredientDisplayRow: Hashable {
    let quantityColumn: String   // e.g. "300 g", "2 c. à soupe", "1"
    let nameColumn: String       // e.g. "Farine", "Huile d'olive"
}

enum IngredientDisplayNormalizer {

    /// Produces a display-ready row from a raw ingredient.
    /// Does **not** mutate stored data — display-only transform.
    static func displayRow(amount: String?, unit: String?, name: String) -> IngredientDisplayRow {
        let normalizedUnit = normalizeUnit(unit)
        let cleanedName = cleanName(name)

        let quantityColumn: String
        let trimmedAmount = amount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedAmount.isEmpty && normalizedUnit.isEmpty {
            quantityColumn = ""
        } else if normalizedUnit.isEmpty {
            quantityColumn = trimmedAmount
        } else {
            quantityColumn = trimmedAmount.isEmpty ? normalizedUnit : "\(trimmedAmount) \(normalizedUnit)"
        }

        return IngredientDisplayRow(quantityColumn: quantityColumn, nameColumn: cleanedName)
    }

    // MARK: - Unit normalization

    private static func normalizeUnit(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }

        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let mapped = unitMap[folded] {
            return mapped
        }

        // Partial / compound match
        for (key, value) in unitMap where folded.contains(key) {
            return value
        }

        // Already clean — return as-is with lowercase
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let unitMap: [String: String] = [
        // Teaspoon family → c. à café
        "cac": "c. à café",
        "c.a.c.": "c. à café",
        "c.a.c": "c. à café",
        "c a c": "c. à café",
        "cc": "c. à café",
        "cac.": "c. à café",
        "cuillere a cafe": "c. à café",
        "cuilleres a cafe": "c. à café",
        "a cafe": "c. à café",
        "tsp": "c. à café",
        "teaspoon": "c. à café",
        "teaspoons": "c. à café",

        // Tablespoon family → c. à soupe
        "cas": "c. à soupe",
        "c.a.s.": "c. à soupe",
        "c.a.s": "c. à soupe",
        "c a s": "c. à soupe",
        "cs": "c. à soupe",
        "cas.": "c. à soupe",
        "cuillere a soupe": "c. à soupe",
        "cuilleres a soupe": "c. à soupe",
        "a soupe": "c. à soupe",
        "tbsp": "c. à soupe",
        "tablespoon": "c. à soupe",
        "tablespoons": "c. à soupe",

        // Weight
        "g": "g",
        "gr": "g",
        "gramme": "g",
        "grammes": "g",
        "gram": "g",
        "grams": "g",
        "kg": "kg",
        "kilogramme": "kg",
        "kilogrammes": "kg",
        "mg": "mg",

        // Volume
        "ml": "ml",
        "millilitre": "ml",
        "millilitres": "ml",
        "cl": "cl",
        "dl": "dl",
        "l": "l",
        "litre": "l",
        "litres": "l",

        // Cup
        "tasse": "tasse",
        "tasses": "tasses",
        "cup": "tasse",
        "cups": "tasses",

        // Glass
        "verre": "verre",
        "verres": "verres",

        // Count-like units → omit from display
        "piece": "",
        "pieces": "",
        "pce": "",
        "unite": "",
        "unites": "",
        "unit": "",
        "units": "",

        // Keep as-is with clean form
        "pincee": "pincée",
        "pincees": "pincées",
        "pinch": "pincée",
        "tranche": "tranche",
        "tranches": "tranches",
        "gousse": "gousse",
        "gousses": "gousses",
        "sachet": "sachet",
        "sachets": "sachets",
        "botte": "botte",
        "bottes": "bottes",
        "feuille": "feuille",
        "feuilles": "feuilles",
        "branche": "branche",
        "branches": "branches",
    ]

    // MARK: - Name cleaning

    private static func cleanName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }

        // Strip parenthetical content (brand, type info)
        name = name.replacingOccurrences(
            of: "\\s*\\([^)]*\\)",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading articles: "de la ", "du ", "d'", "de ", "le ", "la ", "les ", "des "
        let articlePattern = "^(?:de\\s+la\\s+|du\\s+|d'|de\\s+|le\\s+|la\\s+|les\\s+|des\\s+|l')"
        name = name.replacingOccurrences(
            of: articlePattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter
        guard let first = name.first else { return name }
        return String(first).uppercased() + name.dropFirst()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Step Display Cleanup

enum RecipeStepDisplayBuilder {
    static func cleanedSteps(from steps: [RecipeStep], ingredients: [RecipeIngredient]) -> [RecipeStep] {
        var cleanedSteps: [RecipeStep] = []
        var exactMatches = Set<String>()
        var signatureTokens: [String: [Set<String>]] = [:]

        for step in steps {
            let normalizedTitle = normalizedSectionTitle(step.title)

            for detail in splitStepDetail(step.detail) {
                let cleanedDetail = cleanedStepDetail(detail)
                let normalizedDetail = normalizedComparableText(cleanedDetail)

                guard !normalizedDetail.isEmpty, !noisePhrases.contains(normalizedDetail) else { continue }
                guard exactMatches.insert(normalizedDetail).inserted else { continue }

                let refs = mergedIngredientRefs(
                    explicit: step.ingredientRefs ?? [],
                    inferred: inferredIngredientRefs(in: cleanedDetail, ingredients: ingredients)
                )

                if let signature = duplicateSensitiveSignature(for: cleanedDetail, ingredientRefs: refs) {
                    let tokens = Set(normalizedDetail.split(separator: " ").map(String.init))
                    let existing = signatureTokens[signature] ?? []
                    if existing.contains(where: { similarity(between: $0, and: tokens) >= 0.62 }) {
                        continue
                    }
                    signatureTokens[signature, default: []].append(tokens)
                }

                cleanedSteps.append(
                    RecipeStep(
                        id: UUID(),
                        title: normalizedTitle,
                        detail: cleanedDetail,
                        ingredientRefs: refs.isEmpty ? nil : refs
                    )
                )
            }
        }

        if cleanedSteps.isEmpty {
            return steps.filter { !$0.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return cleanedSteps
    }

    private static func splitStepDetail(_ detail: String) -> [String] {
        let normalized = detail
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: #"^\s*(?:step|etape|étape)\s*\d+[:.)-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let sentenceSeparators = CharacterSet(charactersIn: ".;!\n")
        let sentenceLikeChunks = normalized
            .components(separatedBy: sentenceSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidates = sentenceLikeChunks.isEmpty ? [normalized] : sentenceLikeChunks
        var splitDetails: [String] = []

        for candidate in candidates {
            splitDetails.append(contentsOf: splitLongCandidate(candidate))
        }

        var merged: [String] = []
        for candidate in splitDetails where !candidate.isEmpty {
            if let last = merged.last, last.count < 36, (last.count + candidate.count) < 110 {
                merged[merged.count - 1] = "\(last). \(candidate)"
            } else {
                merged.append(candidate)
            }
        }

        return merged.isEmpty ? [normalized] : merged
    }

    private static func splitLongCandidate(_ candidate: String) -> [String] {
        guard candidate.count > 110 else { return [candidate] }

        let connectors = [
            " puis ",
            " then ",
            " ensuite ",
            " after that ",
            " et ajoutez ",
            " and add "
        ]

        for connector in connectors {
            if let range = candidate.range(of: connector, options: .caseInsensitive) {
                let first = String(candidate[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let second = String(candidate[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let pieces = [first, second].filter { !$0.isEmpty }
                if pieces.count > 1 {
                    return pieces
                }
            }
        }

        let words = candidate.split(separator: " ")
        guard words.count > 12 else { return [candidate] }
        let midpoint = words.count / 2
        let left = words[..<midpoint].joined(separator: " ")
        let right = words[midpoint...].joined(separator: " ")
        return [left, right]
    }

    private static func cleanedStepDetail(_ detail: String) -> String {
        let trimmed = detail
            .replacingOccurrences(of: #"^\s*[-•\d.)]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = trimmed.first else { return trimmed }
        let sentence = String(first).uppercased() + trimmed.dropFirst()
        return sentence.hasSuffix(".") ? sentence : "\(sentence)."
    }

    private static func normalizedSectionTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard let first = cleaned.first else { return nil }
        return String(first).uppercased() + cleaned.dropFirst()
    }

    private static func inferredIngredientRefs(in detail: String, ingredients: [RecipeIngredient]) -> [String] {
        let comparableDetail = normalizedComparableText(detail)
        guard !comparableDetail.isEmpty else { return [] }

        return ingredients.compactMap { ingredient in
            let normalizedName = IngredientNameNormalizer.normalize(ingredient.name)
            let candidates = normalizedName.candidateKeys.filter { $0.count >= 3 }
            guard candidates.contains(where: { containsWholePhrase($0, in: comparableDetail) }) else { return nil }
            return ingredient.name
        }
    }

    private static func mergedIngredientRefs(explicit: [String], inferred: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for ref in explicit + inferred {
            let cleaned = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = normalizedComparableText(cleaned)
            if seen.insert(key).inserted {
                merged.append(cleaned)
            }
        }

        return merged
    }

    private static func duplicateSensitiveSignature(for detail: String, ingredientRefs: [String]) -> String? {
        let normalizedDetail = normalizedComparableText(detail)
        guard let action = cookingActionMatch(in: normalizedDetail) else { return nil }
        guard !ingredientRefs.isEmpty else { return nil }

        let ingredientKey = ingredientRefs
            .map { normalizedComparableText($0) }
            .sorted()
            .joined(separator: "|")

        return "\(action)#\(ingredientKey)"
    }

    private static func cookingActionMatch(in detail: String) -> String? {
        for (action, patterns) in duplicateSensitiveActions {
            if patterns.contains(where: { detail.contains($0) }) {
                return action
            }
        }

        return nil
    }

    private static func normalizedComparableText(_ value: String) -> String {
        RecipePresentationFormatter.normalizedSearchText(for: value)
            .replacingOccurrences(of: "\\b(?:the|a|an|and|with|for|de|des|du|la|le|les|avec|puis|then|ensuite)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "(^| )" + NSRegularExpression.escapedPattern(for: phrase) + "( |$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func similarity(between lhs: Set<String>, and rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    private static let noisePhrases: Set<String> = [
        "continue reading",
        "read more",
        "view post",
        "voir plus",
        "voir le post",
        "watch more"
    ]

    private static let duplicateSensitiveActions: [String: [String]] = [
        "bake": ["bake", "roast", "enfourne", "enfourner", "rotir"],
        "boil": ["boil", "simmer", "mijoter", "porter a ebullition"],
        "cook": ["cook", "saute", "sauter", "fry", "sear", "brown", "cuire", "saisir", "faire revenir", "grill"]
    ]
}

// MARK: - Step Ingredient Highlighter

enum StepIngredientHighlighter {

    static func highlighted(
        _ text: String,
        ingredientRefs: [String]?,
        fontSize: CGFloat = 15,
        highlightColor: Color = CooksyTheme.brandBlueDark
    ) -> AttributedString {
        guard let refs = ingredientRefs, !refs.isEmpty else {
            return AttributedString(text)
        }

        var attributed = AttributedString(text)

        for ref in refs {
            let tokens = tokenize(ref)
            for token in tokens where token.count >= 3 {
                // Search directly in the ORIGINAL text using case- and
                // diacritic-insensitive options. This keeps the returned
                // Range<String.Index> aligned with `attributed`'s native
                // index space — previously we searched a folded copy of
                // the text (where "œufs" → "oeufs" or other ligatures
                // shifted positions), so the highlight ranges sometimes
                // missed letters at the boundaries.
                var searchStart = text.startIndex
                while let range = text.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                ) {
                    let hasWordBoundaryBefore = range.lowerBound == text.startIndex
                        || !text[text.index(before: range.lowerBound)].isLetter
                    let hasWordBoundaryAfter = range.upperBound == text.endIndex
                        || !text[range.upperBound].isLetter

                    if hasWordBoundaryBefore && hasWordBoundaryAfter {
                        if let attrStart = AttributedString.Index(range.lowerBound, within: attributed),
                           let attrEnd = AttributedString.Index(range.upperBound, within: attributed) {
                            attributed[attrStart..<attrEnd].foregroundColor = highlightColor
                            attributed[attrStart..<attrEnd].font = .system(size: fontSize, weight: .bold, design: .rounded)
                        }
                    }
                    searchStart = range.upperBound
                }
            }
        }

        return attributed
    }

    private static func tokenize(_ name: String) -> [String] {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "'", with: " ")
        return normalized.split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    private static let stopWords: Set<String> = [
        "a", "au", "aux", "d", "de", "des", "du", "la", "le", "les", "ou", "the", "to", "un", "une"
    ]
}
