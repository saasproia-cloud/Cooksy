import Foundation
import OSLog

struct RecipeImportAssessment {
    var seed: RecipeEditorSeed
    var validation: RecipeValidationResult

    var userFacingFailureMessage: String {
        if let backendMessage = seed.importDebug?.userFacingFailureMessage {
            return backendMessage
        }

        let reasons = Set(validation.rejectionReasons)
        if reasons.contains(.notEnoughIngredients) && reasons.contains(.stepsNotValid) {
            return "Aucune recette détectée"
        }
        if reasons.contains(.notEnoughIngredients) {
            return "Pas assez d’ingrédients"
        }
        if reasons.contains(.stepsNotValid) {
            return "Pas assez d’étapes"
        }
        if reasons.contains(.articleLikeContentDetected) || reasons.contains(.sourcePageNotRecipe) {
            return "Données TikTok insuffisantes"
        }
        if reasons.contains(.repeatedTextDetected) || reasons.contains(.ingredientLineTooLong) {
            return "Résultat de recette invalide"
        }

        return "Résultat de recette invalide"
    }
}

enum RecipeImportSourceKind: String {
    case url
    case text
    case photo
    case shared
}

struct RecipeValidationResult {
    enum Status {
        case accepted
        case needsReview
        case rejected
    }

    enum Reason: String, CaseIterable, Hashable {
        case invalidTitle
        case notEnoughIngredients
        case stepsNotValid
        case articleLikeContentDetected
        case repeatedTextDetected
        case ingredientLineTooLong
        case sourcePageNotRecipe
        case lowQualityScore

        var logLabel: String {
            switch self {
            case .invalidTitle:
                return "invalid title"
            case .notEnoughIngredients:
                return "not enough ingredients"
            case .stepsNotValid:
                return "steps not valid"
            case .articleLikeContentDetected:
                return "article-like content detected"
            case .repeatedTextDetected:
                return "repeated text detected"
            case .ingredientLineTooLong:
                return "ingredient line too long"
            case .sourcePageNotRecipe:
                return "source page is not a recipe page"
            case .lowQualityScore:
                return "low quality score"
            }
        }
    }

    struct Metrics {
        var ingredientCount: Int
        var stepCount: Int
        var validIngredientCount: Int
        var validStepCount: Int
        var longIngredientLineCount: Int
        var articleSignalCount: Int
        var repeatedSignalCount: Int
        var proseLikeLineRatio: Double
        var stepActionRatio: Double
    }

    let status: Status
    let qualityScore: Int
    let canSave: Bool
    let rejectionReasons: [Reason]
    let warningReasons: [Reason]
    let metrics: Metrics

    var isRejected: Bool {
        status == .rejected
    }

    var reviewNotice: String? {
        guard !isRejected else { return nil }

        if !canSave {
            return "Import incomplet. Modifiez la recette pour l'enregistrer."
        }

        if status == .needsReview {
            return "Vérifiez les ingrédients et les étapes avant d'enregistrer."
        }

        return nil
    }
}

enum RecipeValidationService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cooksy",
        category: "RecipeImportValidation"
    )

    private static let exactNoiseLines: Set<String> = [
        "read more",
        "view post",
        "voir plus",
        "voir l'article",
        "voir le post",
        "continue reading",
        "continuez la lecture",
        "jump to recipe",
        "aller a la recette",
        "aller à la recette",
        "print recipe",
        "imprimer la recette",
        "pin recipe",
        "save recipe",
        "sauvegarder",
        "advertisement",
        "publicite",
        "publicité",
        "newsletter",
        "sign up",
        "subscribe"
    ]

    private static let hardArticlePhrases = [
        "read more",
        "view post",
        "newsletter",
        "sign up",
        "subscribe",
        "celebrity",
        "fashion",
        "travel",
        "breaking news",
        "entertainment",
        "style",
        "shopping deals",
        "actually taste good"
    ]

    private static let articleKeywords: Set<String> = [
        "article", "articles", "breaking", "celebrity", "celebrities", "editor", "editorial",
        "entertainment", "fashion", "headline", "headlines", "lifestyle", "magazine", "news",
        "newsletter", "post", "posts", "read", "share", "shopping", "story", "stories", "style",
        "subscribe", "travel", "viral", "watch", "view"
    ]

    private static let articleURLKeywords = [
        "/news/",
        "/fashion/",
        "/travel/",
        "/entertainment/",
        "/celebrity/",
        "/lifestyle/",
        "/style/"
    ]

    private static let cookingWords: Set<String> = [
        "bake", "baked", "baking", "beat", "blend", "boil", "bowl", "browned", "chop", "combine",
        "cook", "cooked", "cooking", "cut", "drizzle", "fold", "fry", "garnish", "grill", "heat",
        "knead", "marinate", "melt", "mix", "pour", "preheat", "rest", "roast", "saute", "season",
        "serve", "simmer", "slice", "stir", "toast", "toss", "whisk", "bring",
        "ajouter", "assaisonner", "battre", "chauffer", "cuire", "couper", "deposer", "déposer",
        "enfourner", "faire", "fouetter", "garnir", "griller", "hacher", "laisser", "melanger",
        "mélanger", "mijoter", "mixez", "mixer", "placer", "porter", "prechauffer", "préchauffer",
        "repartir", "répartir", "remuer", "rôtir", "servir", "sauter", "verser"
    ]

    private static let actionVerbs: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "bring", "brush", "chop", "combine", "cook",
        "cover", "drain", "fold", "fry", "garnish", "grill", "heat", "knead", "marinate", "melt",
        "mix", "place", "pour", "preheat", "reduce", "remove", "roast", "season", "serve",
        "simmer", "stir", "toast", "top", "toss", "transfer", "whisk",
        "ajoutez", "assaisonnez", "battez", "chauffez", "coupez", "cuisez", "deposez", "déposez",
        "enfournez", "faites", "fouettez", "garnissez", "grillez", "hachez", "laissez", "melangez",
        "mélangez", "mijotez", "mixez", "placez", "portez", "prechauffez", "préchauffez",
        "retirez", "repartissez", "répartissez", "remuez", "servez", "versez"
    ]

    private static let quantityWords: Set<String> = [
        "a", "an", "one", "two", "three", "half", "few", "some",
        "un", "une", "deux", "trois", "demi", "quelques", "plusieurs"
    ]

    private static let unitTokens: Set<String> = [
        "c", "cac", "cas", "cc", "cl", "cup", "cups", "g", "gram", "grams", "gr", "kg", "lb",
        "lbs", "l", "ml", "oz", "pinch", "tbsp", "tsp",
        "càs", "càc", "cuillere", "cuillère", "cuilleres", "cuillères", "gousse", "gousses",
        "litre", "litres", "pincée", "pincées", "tranche", "tranches", "verre", "verres"
    ]

    private static let foodTokens: Set<String> = [
        "almond", "apple", "avocado", "banana", "basil", "bean", "beans", "beef", "broccoli",
        "broth", "butter", "cake", "carrot", "cheese", "chicken", "chili", "chocolate", "cocoa",
        "cream", "cucumber", "dough", "egg", "eggs", "flour", "garlic", "ginger", "ham", "honey",
        "juice", "lemon", "lettuce", "lime", "meat", "milk", "mushroom", "mushrooms", "noodle",
        "noodles", "oil", "onion", "orange", "pasta", "pepper", "potato", "potatoes", "rice",
        "salad", "salt", "sauce", "shrimp", "spinach", "sugar", "syrup", "tomato", "tomatoes",
        "tortilla", "vanilla", "water", "yogurt",
        "ail", "amande", "amandes", "beurre", "boeuf", "bœuf", "bouillon", "carotte", "carottes",
        "champignon", "champignons", "chocolat", "citron", "citron vert", "concombre", "creme",
        "crème", "farine", "fromage", "gingembre", "huile", "jaune", "lait", "miel", "oeuf",
        "œuf", "oeufs", "œufs", "oignon", "oignons", "pate", "pâtes", "persil", "piment", "poire",
        "poivre", "pomme", "poulet", "riz", "salade", "saumon", "sel", "sucre", "thon", "tomate",
        "tomates", "vanille", "yaourt"
    ]

    private static let weakTitles: Set<String> = [
        "recette importee",
        "recette importée",
        "recette depuis une photo"
    ]

    static func assess(_ seed: RecipeEditorSeed, sourceKind: RecipeImportSourceKind) -> RecipeImportAssessment {
        let rawSignals = collectRawSignals(from: seed)
        let sanitizedSeed = sanitize(seed)
        let validated = validate(
            sanitizedSeed,
            rawSignals: rawSignals,
            sourceKind: sourceKind
        )

        if validated.isRejected {
            logRejectedImport(
                seed: sanitizedSeed,
                result: validated,
                sourceKind: sourceKind
            )
        }

        return RecipeImportAssessment(seed: sanitizedSeed, validation: validated)
    }

    private static func validate(
        _ seed: RecipeEditorSeed,
        rawSignals: RawSignals,
        sourceKind: RecipeImportSourceKind
    ) -> RecipeValidationResult {
        let ingredientLines = seed.normalizedIngredients.map(ingredientLine(from:))
        let stepLines = seed.normalizedSteps.map(\.detail)
        let combinedLines = ingredientLines + stepLines
        let combinedText = ([seed.normalizedTitle] + combinedLines + [seed.notesText]).joined(separator: "\n")

        let validIngredientCount = ingredientLines.filter(looksLikeIngredientLine(_:)).count
        let validStepCount = stepLines.filter(looksLikeCookingStep(_:)).count
        let longIngredientLineCount = ingredientLines.filter(isVeryLongIngredientLine(_:)).count
        let articleSignalCount = articleSignalScore(in: combinedText) + rawSignals.articleLikeLineCount
        let repeatedSignalCount = rawSignals.repeatedNoiseCount + rawSignals.repeatedLongLineCount
        let proseLikeLines = combinedLines.filter(looksLikeProseLine(_:)).count
        let proseLikeLineRatio = combinedLines.isEmpty ? 0 : Double(proseLikeLines) / Double(combinedLines.count)
        let actionLikeStepCount = stepLines.filter(looksLikeCookingStep(_:)).count
        let stepActionRatio = stepLines.isEmpty ? 0 : Double(actionLikeStepCount) / Double(stepLines.count)
        let titleLooksArticleLike = isArticleStyleTitle(seed.normalizedTitle)
        let titleLooksRecipeLike = isRecipeLikeTitle(seed.normalizedTitle)
        let sourceLooksArticleLike = isLikelyNonRecipeURL(seed.sourceURL)
        let hasEnoughRecipeStructure = validIngredientCount >= 3 && validStepCount >= 2
        let unrelatedWordPressure = unrelatedWordPressure(in: combinedText)
        let mostlyArticleText = proseLikeLineRatio >= 0.45 || unrelatedWordPressure >= 5

        var score = 100
        var hardReasons = Set<RecipeValidationResult.Reason>()
        var warningReasons = Set<RecipeValidationResult.Reason>()

        if titleLooksArticleLike {
            hardReasons.insert(.invalidTitle)
            score -= 28
        } else if !titleLooksRecipeLike {
            warningReasons.insert(.invalidTitle)
            score -= 12
        }

        if validIngredientCount < 3 {
            hardReasons.insert(.notEnoughIngredients)
            score -= 32
        } else if validIngredientCount < ingredientLines.count {
            warningReasons.insert(.notEnoughIngredients)
            score -= 8
        }

        if validStepCount < 2 {
            hardReasons.insert(.stepsNotValid)
            score -= 32
        } else if stepActionRatio < 0.7 {
            warningReasons.insert(.stepsNotValid)
            score -= 10
        }

        if longIngredientLineCount > 0 || rawSignals.longIngredientLineCount > 0 {
            hardReasons.insert(.ingredientLineTooLong)
            score -= 24
        }

        if articleSignalCount >= 4 || mostlyArticleText {
            hardReasons.insert(.articleLikeContentDetected)
            score -= 28
        } else if articleSignalCount > 0 {
            warningReasons.insert(.articleLikeContentDetected)
            score -= 10
        }

        if repeatedSignalCount > 0 {
            hardReasons.insert(.repeatedTextDetected)
            score -= 20
        }

        if (sourceLooksArticleLike || titleLooksArticleLike) && !hasEnoughRecipeStructure {
            hardReasons.insert(.sourcePageNotRecipe)
            score -= 20
        }

        if weakTitles.contains(normalizedPhrase(seed.normalizedTitle)) {
            warningReasons.insert(.invalidTitle)
            score -= 8
        }

        score -= max(0, rawSignals.removedNoiseLineCount - 1) * 2
        score = max(0, min(100, score))

        let canSave = hardReasons.isEmpty && score >= 70
        if hardReasons.isEmpty && !canSave {
            warningReasons.insert(.lowQualityScore)
        }

        let status: RecipeValidationResult.Status
        if !hardReasons.isEmpty {
            status = .rejected
        } else if score >= 82 {
            status = .accepted
        } else {
            status = .needsReview
        }

        return RecipeValidationResult(
            status: status,
            qualityScore: score,
            canSave: canSave,
            rejectionReasons: hardReasons.sorted(by: sortReasons),
            warningReasons: warningReasons.sorted(by: sortReasons),
            metrics: RecipeValidationResult.Metrics(
                ingredientCount: ingredientLines.count,
                stepCount: stepLines.count,
                validIngredientCount: validIngredientCount,
                validStepCount: validStepCount,
                longIngredientLineCount: longIngredientLineCount + rawSignals.longIngredientLineCount,
                articleSignalCount: articleSignalCount,
                repeatedSignalCount: repeatedSignalCount,
                proseLikeLineRatio: proseLikeLineRatio,
                stepActionRatio: stepActionRatio
            )
        )
    }

    private static func sortReasons(
        _ lhs: RecipeValidationResult.Reason,
        _ rhs: RecipeValidationResult.Reason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func sanitize(_ seed: RecipeEditorSeed) -> RecipeEditorSeed {
        var sanitized = seed
        sanitized.title = sanitizeTitle(seed.title)
        sanitized.ingredientDrafts = sanitizeIngredients(seed.ingredientDrafts)
        sanitized.stepDrafts = sanitizeSteps(seed.stepDrafts)
        sanitized.notesText = sanitizeNotes(seed.notesText)
        return sanitized
    }

    private static func sanitizeTitle(_ title: String) -> String {
        var cleaned = cleanLine(title)

        for separator in ["|", "•", " – ", " — ", " - "] {
            let pieces = cleaned.components(separatedBy: separator).map(cleanLine(_:))
            guard pieces.count >= 2 else { continue }
            let first = pieces[0]
            let trailing = pieces.dropFirst().joined(separator: " ")
            if isRecipeLikeTitle(first), trailing.count <= 40 {
                cleaned = first
                break
            }
        }

        return cleaned
    }

    private static func sanitizeIngredients(_ drafts: [IngredientDraft]) -> [IngredientDraft] {
        dedupeLines(
            drafts.compactMap { draft in
                let line = cleanIngredientLine(ingredientLine(from: draft))
                guard !line.isEmpty else { return nil }
                guard !isExactNoiseLine(line) else { return nil }
                guard !shouldDropAsIrrelevantIngredient(line) else { return nil }
                return parseIngredientLine(line)
            },
            key: { normalizedPhrase(ingredientLine(from: $0)) }
        )
    }

    private static func sanitizeSteps(_ drafts: [StepDraft]) -> [StepDraft] {
        dedupeLines(
            drafts.compactMap { draft in
                let line = cleanInstructionLine(draft.detail)
                guard !line.isEmpty else { return nil }
                guard !isExactNoiseLine(line) else { return nil }
                guard !shouldDropAsIrrelevantStep(line) else { return nil }
                return StepDraft(detail: line)
            },
            key: { normalizedPhrase($0.detail) }
        )
    }

    private static func sanitizeNotes(_ notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("Source demo : ") {
            return trimmed
        }

        let filtered = normalizedLines(trimmed).filter { line in
            !isExactNoiseLine(line) &&
                !containsHardArticlePhrase(line) &&
                !looksLikeProseLine(line)
        }

        guard !filtered.isEmpty else { return "" }

        let cleaned = filtered.joined(separator: "\n")
        if cleaned.count > 220 {
            return ""
        }

        return cleaned
    }

    private static func ingredientLine(from ingredient: RecipeIngredient) -> String {
        [ingredient.amount, ingredient.unit, ingredient.name]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
    }

    private static func ingredientLine(from ingredient: IngredientDraft) -> String {
        [ingredient.amount, ingredient.unit, ingredient.name]
            .map(cleanLine(_:))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func cleanLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanIngredientLine(_ value: String) -> String {
        cleanLine(
            value.replacingOccurrences(
                of: #"^\s*[-•*]+\s*"#,
                with: "",
                options: .regularExpression
            )
        )
    }

    private static func cleanInstructionLine(_ value: String) -> String {
        cleanLine(
            value.replacingOccurrences(
                of: #"^\s*(\d+[\).\-\s]+|[-•*]+\s*)"#,
                with: "",
                options: .regularExpression
            )
        )
    }

    private static func parseIngredientLine(_ line: String) -> IngredientDraft {
        let cleaned = cleanIngredientLine(line)
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return IngredientDraft() }

        let first = normalizedPhrase(tokens[0])
        let second = tokens.count > 1 ? normalizedPhrase(tokens[1]) : ""
        let hasQuantityPrefix = first.range(of: #"^\d|^[¼½¾⅓⅔⅛]|^\d+/\d+"#, options: .regularExpression) != nil ||
            quantityWords.contains(first)

        if hasQuantityPrefix {
            if tokens.count >= 3, unitTokens.contains(second) {
                return IngredientDraft(
                    amount: tokens[0],
                    unit: tokens[1],
                    name: tokens.dropFirst(2).joined(separator: " ")
                )
            }

            return IngredientDraft(
                amount: tokens[0],
                unit: "",
                name: tokens.dropFirst().joined(separator: " ")
            )
        }

        return IngredientDraft(name: cleaned)
    }

    private static func dedupeLines<T>(
        _ items: [T],
        key: (T) -> String
    ) -> [T] {
        var seen = Set<String>()
        return items.filter { item in
            let value = key(item)
            guard !value.isEmpty else { return false }
            return seen.insert(value).inserted
        }
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanLine(_:))
            .filter { !$0.isEmpty }
    }

    private static func normalizedPhrase(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenized(_ text: String) -> [String] {
        normalizedPhrase(text)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private static func isExactNoiseLine(_ text: String) -> Bool {
        exactNoiseLines.contains(normalizedPhrase(text))
    }

    private static func containsHardArticlePhrase(_ text: String) -> Bool {
        let normalized = normalizedPhrase(text)
        return hardArticlePhrases.contains { normalized.contains($0) }
    }

    private static func looksLikeIngredientLine(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }
        guard !containsHardArticlePhrase(line) else { return false }
        guard !looksLikeProseLine(line) else { return false }

        let words = tokenized(normalized)
        let hasQuantity = line.range(
            of: #"(^|\s)(\d+([\/.,]\d+)?|[¼½¾⅓⅔⅛])(\s|$)"#,
            options: .regularExpression
        ) != nil || words.contains(where: quantityWords.contains(_:))
        let hasUnit = words.contains(where: unitTokens.contains(_:))
        let hasFood = words.contains(where: foodTokens.contains(_:))

        return (hasQuantity && (hasUnit || hasFood)) || (hasUnit && hasFood) || (hasFood && words.count <= 6)
    }

    private static func looksLikeCookingStep(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }
        guard !containsHardArticlePhrase(line) else { return false }
        guard !looksLikeProseLine(line) else { return false }

        let tokens = tokenized(normalized)
        guard tokens.count >= 3, tokens.count <= 32 else { return false }

        let prefix = Array(tokens.prefix(8))
        return prefix.contains(where: actionVerbs.contains(_:)) ||
            tokens.contains(where: actionVerbs.contains(_:)) ||
            tokens.contains(where: cookingWords.contains(_:))
    }

    private static func isVeryLongIngredientLine(_ line: String) -> Bool {
        line.count > 120 || tokenized(line).count > 18
    }

    private static func looksLikeProseLine(_ line: String) -> Bool {
        let words = tokenized(line).count
        let sentencePunctuation = line.filter { ".!?".contains($0) }.count
        return line.count > 180 || words > 24 || sentencePunctuation >= 2
    }

    private static func shouldDropAsIrrelevantIngredient(_ line: String) -> Bool {
        if isVeryLongIngredientLine(line) {
            return true
        }

        return containsHardArticlePhrase(line) || (!looksLikeIngredientLine(line) && looksLikeProseLine(line))
    }

    private static func shouldDropAsIrrelevantStep(_ line: String) -> Bool {
        if line.count > 240 {
            return true
        }

        return containsHardArticlePhrase(line) || (!looksLikeCookingStep(line) && looksLikeProseLine(line))
    }

    private static func isArticleStyleTitle(_ title: String) -> Bool {
        let normalized = normalizedPhrase(title)
        guard !normalized.isEmpty else { return false }

        if containsHardArticlePhrase(normalized) {
            return true
        }

        if normalized.range(of: #"^\d+\s+.*\brecipes\b"#, options: .regularExpression) != nil {
            return true
        }

        if normalized.contains("tiktok recipes") || normalized.contains("roundup") || normalized.contains("listicle") {
            return true
        }

        let words = tokenized(normalized)
        return words.count > 14 && !words.contains(where: foodTokens.contains(_:))
    }

    private static func isRecipeLikeTitle(_ title: String) -> Bool {
        let normalized = normalizedPhrase(title)
        guard !normalized.isEmpty else { return false }
        guard !isArticleStyleTitle(title) else { return false }

        let words = tokenized(normalized)
        guard words.count <= 12, title.count <= 80 else { return false }

        if weakTitles.contains(normalized) {
            return false
        }

        return words.contains(where: foodTokens.contains(_:)) ||
            words.contains(where: cookingWords.contains(_:))
    }

    private static func unrelatedWordPressure(in text: String) -> Int {
        let tokens = tokenized(text)
        let articleCount = tokens.filter { articleKeywords.contains($0) }.count
        let cookingCount = tokens.filter { cookingWords.contains($0) || foodTokens.contains($0) || unitTokens.contains($0) }.count
        return articleCount - cookingCount
    }

    private static func articleSignalScore(in text: String) -> Int {
        let tokens = tokenized(text)
        let articleHits = tokens.filter { articleKeywords.contains($0) }.count
        let phraseHits = hardArticlePhrases.reduce(into: 0) { result, phrase in
            if normalizedPhrase(text).contains(phrase) {
                result += 2
            }
        }
        return articleHits + phraseHits
    }

    private static func isLikelyNonRecipeURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let absolute = url.absoluteString.lowercased()
        return articleURLKeywords.contains { absolute.contains($0) } || absolute.contains("news.")
    }

    private static func collectRawSignals(from seed: RecipeEditorSeed) -> RawSignals {
        let rawIngredientLines = seed.ingredientDrafts.map(ingredientLine(from:))
        let rawStepLines = seed.stepDrafts.map(\.detail)
        let allLines = (rawIngredientLines + rawStepLines).map(cleanLine(_:)).filter { !$0.isEmpty }

        let normalized = allLines.map(normalizedPhrase(_:))
        let lineCounts = Dictionary(normalized.map { ($0, 1) }, uniquingKeysWith: +)

        let repeatedLongLineCount = lineCounts.filter { key, count in
            key.count > 24 && count > 1
        }.count

        let repeatedNoiseCount = lineCounts.filter { key, count in
            exactNoiseLines.contains(key) && count > 1
        }.count

        let articleLikeLineCount = allLines.filter {
            containsHardArticlePhrase($0) || looksLikeProseLine($0)
        }.count

        let removedNoiseLineCount = allLines.filter {
            isExactNoiseLine($0) || shouldDropAsIrrelevantIngredient($0) || shouldDropAsIrrelevantStep($0)
        }.count

        let longIngredientLineCount = rawIngredientLines.filter(isVeryLongIngredientLine(_:)).count

        return RawSignals(
            repeatedLongLineCount: repeatedLongLineCount,
            repeatedNoiseCount: repeatedNoiseCount,
            articleLikeLineCount: articleLikeLineCount,
            removedNoiseLineCount: removedNoiseLineCount,
            longIngredientLineCount: longIngredientLineCount
        )
    }

    private static func logRejectedImport(
        seed: RecipeEditorSeed,
        result: RecipeValidationResult,
        sourceKind: RecipeImportSourceKind
    ) {
        let reasonList = result.rejectionReasons.map(\.logLabel).joined(separator: ", ")
        let summary = [
            "source=\(sourceKind.rawValue)",
            "title=\(seed.normalizedTitle)",
            "reasons=\(reasonList)",
            "score=\(result.qualityScore)",
            "ingredients=\(result.metrics.validIngredientCount)/\(result.metrics.ingredientCount)",
            "steps=\(result.metrics.validStepCount)/\(result.metrics.stepCount)",
            "articleSignals=\(result.metrics.articleSignalCount)",
            "repeatedSignals=\(result.metrics.repeatedSignalCount)",
            "backendReason=\(seed.importDebug?.failureReason ?? "none")",
            "backendStrategy=\(seed.importDebug?.strategy ?? "unknown")",
            "backendDurationMs=\(seed.importDebug?.durationMs ?? 0)"
        ]
        .joined(separator: " | ")

        logger.error("\(summary, privacy: .public)")
    }
}

private struct RawSignals {
    var repeatedLongLineCount: Int
    var repeatedNoiseCount: Int
    var articleLikeLineCount: Int
    var removedNoiseLineCount: Int
    var longIngredientLineCount: Int
}
