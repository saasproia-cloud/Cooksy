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
        case needsBackendReview

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
            case .needsBackendReview:
                return "backend strict validator flagged needs-review"
            }
        }

        var userFacingBadge: String? {
            switch self {
            case .needsBackendReview:
                return "Recette à vérifier"
            default:
                return nil
            }
        }
    }

    struct Metrics {
        var ingredientCount: Int
        var stepCount: Int
        var validIngredientCount: Int
        var validStepCount: Int
        var hasCompleteNutrition: Bool
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
        if !canSave {
            return "Quelques ajustements sont recommandés avant l'enregistrement."
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
        "actually taste good"
    ]

    private static let socialNoisePhrases = [
        "original sound",
        "son original",
        "the playful waltz",
        "ajouter un commentaire",
        "watch more"
    ]

    private static let socialNoiseKeywords = [
        "audio",
        "follow",
        "playlist",
        "remix",
        "soundtrack",
        "suivre",
        "waltz"
    ]

    private static let narrativeNoiseFragments = [
        "je vais",
        "on va",
        "tu vas",
        "vous allez",
        "en plusieurs fois",
        "fois en tout",
        "toute petite louche",
        "c est super simple",
        "c est delicieux",
        "et ensuite",
        "on a"
    ]

    private static let articleKeywords: Set<String> = [
        "article", "articles", "breaking", "celebrity", "celebrities", "editor", "editorial",
        "entertainment", "fashion", "headline", "headlines", "lifestyle", "magazine", "news",
        "newsletter", "post", "posts", "read", "share", "story", "stories", "style",
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
        "serve", "simmer", "slice", "stir", "toast", "toss", "whisk", "bring", "assemble", "roll",
        "spread", "reheat", "prepare", "rectify",
        "ajouter", "assaisonner", "battre", "chauffer", "cuire", "couper", "deposer", "déposer", "disposer",
        "enfourner", "faire", "fouetter", "garnir", "griller", "hacher", "laisser", "melanger",
        "mélanger", "mijoter", "mixez", "mixer", "placer", "porter", "prechauffer", "préchauffer",
        "repartir", "répartir", "remuer", "rôtir", "servir", "sauter", "verser", "monter",
        "assembler", "rabattre", "rouler", "etaler", "étaler", "rechauffer", "réchauffer",
        "preparer", "préparer", "rectifier", "poursuivre", "dresser", "toaster", "émincer", "emincer"
    ]

    private static let actionVerbs: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "bring", "brush", "chop", "combine", "cook",
        "cover", "drain", "fold", "fry", "garnish", "grill", "heat", "knead", "marinate", "melt",
        "mix", "place", "pour", "preheat", "reduce", "remove", "roast", "season", "serve",
        "simmer", "stir", "toast", "top", "toss", "transfer", "whisk", "assemble", "roll",
        "spread", "reheat", "prepare", "rectify",
        "ajoutez", "assaisonnez", "battez", "chauffez", "coupez", "cuisez", "deposez", "déposez",
        "enfournez", "faites", "fouettez", "garnissez", "grillez", "hachez", "laissez", "melangez",
        "mélangez", "mijotez", "mixez", "placez", "portez", "prechauffez", "préchauffez",
        "retirez", "repartissez", "répartissez", "remuez", "servez", "versez", "montez", "disposez",
        "assemblez", "rabattez", "roulez", "etalez", "étalez", "rechauffez", "réchauffez",
        "preparez", "préparez", "rectifiez", "poursuivez", "dressez", "toastez", "émincez", "emincez"
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
        "broth", "burger", "burgers", "butter", "cake", "carrot", "cheese", "chicken", "chili", "chocolate", "cocoa",
        "cream", "cucumber", "dough", "egg", "eggs", "feta", "flour", "garlic", "ginger", "ham", "honey",
        "juice", "lemon", "lettuce", "lime", "meat", "milk", "mushroom", "mushrooms", "naan", "noodle",
        "noodles", "oil", "onion", "orange", "parmesan", "pasta", "pepper", "potato", "potatoes", "rice",
        "salad", "salt", "sauce", "shrimp", "spinach", "sugar", "syrup", "tomato", "tomatoes",
        "tortilla", "truffle", "water", "wrap", "wraps", "yogurt", "chickpea", "chickpeas",
        "ail", "amande", "amandes", "beurre", "boeuf", "bœuf", "bouillon", "carotte", "carottes",
        "burger", "burgers", "champignon", "champignons", "chocolat", "citron", "citron vert", "concombre", "creme",
        "crème", "eau", "farine", "feta", "fromage", "gingembre", "gruyere", "gruyère", "huile", "jaune", "lait",
        "levure", "miel", "naan", "oeuf", "œuf", "oeufs", "œufs", "oignon", "oignons", "parmesan",
        "pate", "pâtes", "persil", "piment", "poire", "poivre", "pomme", "poulet", "riz", "salade",
        "saumon", "sel", "sucre", "thon", "tomate", "tomates", "truffe", "vanille", "wrap", "wraps", "yaourt"
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
        let backendTrustedImport = seed.importDebug?.isLikelyValid == true
        let hasCompleteNutrition = nutritionIsComplete(in: seed)
        let normalizedTitle = normalizedPhrase(seed.normalizedTitle)
        let titleIsWeak = weakTitles.contains(normalizedTitle)
        let titleIsCredible = !normalizedTitle.isEmpty &&
            !titleLooksArticleLike &&
            !titleIsWeak &&
            tokenized(normalizedTitle).count <= 12 &&
            seed.normalizedTitle.count <= 80
        let minimumIngredientCount = minimumIngredientCountForCompleteRecipe(seed.normalizedTitle)
        let minimumStepCount = minimumStepCountForCompleteRecipe(seed.normalizedTitle)
        let minimumHardIngredientCount = min(3, minimumIngredientCount)
        let minimumHardStepCount = min(2, minimumStepCount)
        let hasEnoughRecipeStructure = validIngredientCount >= minimumHardIngredientCount &&
            validStepCount >= minimumHardStepCount
        let unrelatedWordPressure = unrelatedWordPressure(in: combinedText)
        let mostlyArticleText = proseLikeLineRatio >= 0.45 || unrelatedWordPressure >= 5
        let hasCompactCookableStructure = titleIsCredible &&
            validIngredientCount >= minimumHardIngredientCount &&
            validStepCount >= minimumHardStepCount &&
            !mostlyArticleText &&
            articleSignalCount < 4

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
            if hasCompactCookableStructure {
                warningReasons.insert(.notEnoughIngredients)
                score -= 12
            } else {
                hardReasons.insert(.notEnoughIngredients)
                score -= 32
            }
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

        if titleIsWeak {
            warningReasons.insert(.invalidTitle)
            score -= 8
        }

        if hasCompleteNutrition {
            score += 8
        }

        score -= min(max(0, rawSignals.removedNoiseLineCount - 1) * 2, 6)
        score = max(0, min(100, score))

        let backendCompactRecipeIsUsable = backendTrustedImport &&
            titleIsCredible &&
            validIngredientCount >= minimumHardIngredientCount &&
            validStepCount >= minimumHardStepCount
        if backendCompactRecipeIsUsable && hardReasons.contains(.notEnoughIngredients) {
            hardReasons.remove(.notEnoughIngredients)
            warningReasons.insert(.notEnoughIngredients)
        }

        let completeRecipeIsUsable = titleIsCredible &&
            validIngredientCount >= minimumIngredientCount &&
            validStepCount >= minimumStepCount &&
            longIngredientLineCount == 0 &&
            rawSignals.longIngredientLineCount == 0 &&
            articleSignalCount < 4 &&
            repeatedSignalCount == 0 &&
            !mostlyArticleText

        let canSave = completeRecipeIsUsable
        if hardReasons.isEmpty && !canSave {
            warningReasons.insert(.lowQualityScore)
        }

        if seed.importDebug?.needsReview == true {
            warningReasons.insert(.needsBackendReview)
        }

        let status: RecipeValidationResult.Status
        if !hardReasons.isEmpty {
            status = .rejected
        } else if canSave && score >= 82 {
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
                hasCompleteNutrition: hasCompleteNutrition,
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
        let sanitizedTitle = sanitizeTitle(seed.title)
        sanitized.title = sanitizedTitle
        sanitized.ingredientDrafts = sanitizeIngredients(seed.ingredientDrafts, title: sanitizedTitle)
        sanitized.stepDrafts = sanitizeSteps(seed.stepDrafts, title: sanitizedTitle)
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

    private static func sanitizeIngredients(_ drafts: [IngredientDraft], title: String) -> [IngredientDraft] {
        dedupeLines(
            drafts.flatMap { draft -> [IngredientDraft] in
                let line = cleanIngredientLine(ingredientLine(from: draft))
                guard !line.isEmpty else { return [] }
                guard !isExactNoiseLine(line) else { return [] }
                guard !shouldDropAsIrrelevantIngredient(line, title: title) else { return [] }

                return splitIngredientLine(line).compactMap { segment in
                    let cleanedSegment = cleanIngredientLine(segment)
                    guard !cleanedSegment.isEmpty else { return nil }
                    guard !isExactNoiseLine(cleanedSegment) else { return nil }
                    guard !shouldDropAsIrrelevantIngredient(cleanedSegment, title: title) else { return nil }
                    return parseIngredientLine(cleanedSegment)
                }
            },
            key: { normalizedPhrase(ingredientLine(from: $0)) }
        )
    }

    private static func sanitizeSteps(_ drafts: [StepDraft], title: String) -> [StepDraft] {
        dedupeLines(
            drafts.compactMap { draft in
                let line = cleanInstructionLine(draft.detail)
                guard !line.isEmpty else { return nil }
                guard !isExactNoiseLine(line) else { return nil }
                guard !shouldDropAsIrrelevantStep(line, title: title) else { return nil }
                guard looksLikeCookingStep(line) else { return nil }
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

    private static func splitIngredientLine(_ line: String) -> [String] {
        let cleaned = cleanIngredientLine(line)
            .replacingOccurrences(of: #"\s*(?:\.\.\.|…)\s*"#, with: " / ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(?:/|\||;|•|·|\+|&)\s*"#, with: " / ", options: .regularExpression)

        if let slashSegments = plausibleIngredientSegments(
            cleaned.components(separatedBy: " / ")
        ) {
            return slashSegments
        }

        if let commaSegments = plausibleIngredientSegments(
            cleaned.components(separatedBy: ",")
        ) {
            return commaSegments
        }

        let conjunctionNormalized = cleaned.replacingOccurrences(
            of: #"\s+\b(?:et|and)\b\s+"#,
            with: " / ",
            options: [.regularExpression, .caseInsensitive]
        )
        if let conjunctionSegments = plausibleIngredientSegments(
            conjunctionNormalized.components(separatedBy: " / ")
        ) {
            return conjunctionSegments
        }

        return [line]
    }

    private static func plausibleIngredientSegments(_ rawSegments: [String]) -> [String]? {
        let segments = rawSegments
            .map(cleanIngredientLine(_:))
            .filter { !$0.isEmpty }

        guard segments.count >= 2 else { return nil }
        guard segments.allSatisfy(isPlausibleIngredientSegment(_:)) else { return nil }
        return segments
    }

    private static func isPlausibleIngredientSegment(_ value: String) -> Bool {
        let stripped = stripLeadingMeasurement(from: value)
        let tokens = tokenized(stripped)
        guard !tokens.isEmpty, tokens.count <= 6 else { return false }
        return stripped.range(of: #"[A-Za-zÀ-ÿ]"#, options: .regularExpression) != nil
    }

    private static func stripLeadingMeasurement(from value: String) -> String {
        let cleaned = cleanIngredientLine(value)
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return cleaned }

        let first = normalizedPhrase(tokens[0])
        let second = tokens.count > 1 ? normalizedPhrase(tokens[1]) : ""
        let hasQuantityPrefix = first.range(of: #"^\d|^[¼½¾⅓⅔⅛]|^\d+/\d+"#, options: .regularExpression) != nil ||
            quantityWords.contains(first)

        guard hasQuantityPrefix else { return cleaned }
        if tokens.count >= 3, unitTokens.contains(second) {
            return tokens.dropFirst(2).joined(separator: " ")
        }

        return tokens.dropFirst().joined(separator: " ")
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
        exactNoiseLines.contains(normalizedPhrase(text)) || looksLikeSocialNoiseLine(text)
    }

    private static func containsHardArticlePhrase(_ text: String) -> Bool {
        let normalized = normalizedPhrase(text)
        return hardArticlePhrases.contains { normalized.contains($0) }
    }

    private static func looksLikeIngredientLine(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }
        guard !containsHardArticlePhrase(line) else { return false }
        guard !looksLikeSocialNoiseLine(line) else { return false }
        guard !containsNarrativeNoise(line) else { return false }
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
        guard !looksLikeSocialNoiseLine(line) else { return false }
        guard !containsNarrativeNoise(line) else { return false }
        guard !looksLikeIncompleteStepFragment(line) else { return false }
        guard !looksLikeProseLine(line) else { return false }

        let tokens = tokenized(normalized)
        guard tokens.count >= 3, tokens.count <= 32 else { return false }

        let prefix = Array(tokens.prefix(8))
        return prefix.contains(where: actionVerbs.contains(_:)) ||
            tokens.contains(where: actionVerbs.contains(_:)) ||
            tokens.contains(where: cookingWords.contains(_:))
    }

    private static func looksLikeIncompleteStepFragment(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }

        if containsNarrativeNoise(line) {
            return true
        }

        if normalized.contains("je vais") || normalized.contains("on va") || normalized.contains("tu vas") || normalized.contains("vous allez") {
            if normalized.contains("prendre") || normalized.contains("faire") || normalized.contains("mettre") || normalized.contains("voir") || normalized.contains("montrer") {
                return true
            }
        }

        if normalized.hasPrefix("ensuite") || normalized.hasPrefix("puis") || normalized.hasPrefix("apres") ||
            normalized.hasPrefix("et apres") || normalized.hasPrefix("comme ca") || normalized.hasPrefix("voila") ||
            normalized.hasPrefix("du coup") || normalized.hasPrefix("alors") {
            let tokens = tokenized(normalized)
            let hasAction = tokens.contains(where: actionVerbs.contains(_:)) || tokens.contains(where: cookingWords.contains(_:))
            return !hasAction
        }

        return normalized == "comme ca" || normalized == "voila" || normalized == "et voila"
    }

    private static func isVeryLongIngredientLine(_ line: String) -> Bool {
        line.count > 120 || tokenized(line).count > 18
    }

    private static func looksLikeProseLine(_ line: String) -> Bool {
        let words = tokenized(line).count
        let abbreviationSanitizedLine = line.replacingOccurrences(
            of: #"(?:\b[A-Za-zÀ-ÿ]\.){2,}[A-Za-zÀ-ÿ]?\.?"#,
            with: "",
            options: .regularExpression
        )
        let sentencePunctuation = abbreviationSanitizedLine.filter { ".!?".contains($0) }.count
        return line.count > 180 || words > 24 || sentencePunctuation >= 2
    }

    private static func shouldDropAsIrrelevantIngredient(_ line: String, title: String) -> Bool {
        if isVeryLongIngredientLine(line) {
            return true
        }

        if looksLikeTitleEcho(line, title: title) || containsNarrativeNoise(line) {
            return true
        }

        return looksLikeSocialNoiseLine(line) ||
            containsHardArticlePhrase(line) ||
            (!looksLikeIngredientLine(line) && looksLikeProseLine(line))
    }

    private static func shouldDropAsIrrelevantStep(_ line: String, title: String) -> Bool {
        if line.count > 240 {
            return true
        }

        if looksLikeTitleEcho(line, title: title) || containsNarrativeNoise(line) {
            return true
        }

        if looksLikeIncompleteStepFragment(line) {
            return true
        }

        return looksLikeSocialNoiseLine(line) ||
            containsHardArticlePhrase(line) ||
            !looksLikeCookingStep(line)
    }

    private static func nutritionIsComplete(in seed: RecipeEditorSeed) -> Bool {
        let values = [seed.caloriesText, seed.proteinText, seed.carbsText, seed.fatText]
        return values.allSatisfy { value in
            guard let number = numericValue(in: value) else { return false }
            return number > 0
        }
    }

    private static func numericValue(in text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = normalized.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }

        return Double(normalized[match])
    }

    private static func minimumIngredientCountForCompleteRecipe(_ title: String) -> Int {
        let normalized = normalizedPhrase(title)

        if normalized.contains("omelette") || normalized.contains("toast") {
            return 2
        }

        if normalized.contains("salade") || normalized.contains("salad") || normalized.contains("bowl") {
            return 4
        }

        return 5
    }

    private static func minimumStepCountForCompleteRecipe(_ title: String) -> Int {
        let normalized = normalizedPhrase(title)

        if normalized.contains("omelette") || normalized.contains("toast") {
            return 2
        }

        if normalized.contains("salade") || normalized.contains("salad") || normalized.contains("bowl") {
            return 3
        }

        return 4
    }

    private static func looksLikeSocialNoiseLine(_ text: String) -> Bool {
        let normalized = normalizedPhrase(text)
        guard !normalized.isEmpty else { return false }

        if socialNoisePhrases.contains(where: normalized.contains) {
            return true
        }

        if normalized.contains("follow") || normalized.contains("suivre") {
            return true
        }

        let tokens = tokenized(normalized)
        if tokens.count <= 5 && socialNoiseKeywords.contains(where: normalized.contains) {
            let hasFoodSignal = tokens.contains(where: foodTokens.contains(_:)) ||
                tokens.contains(where: cookingWords.contains(_:))
            return !hasFoodSignal
        }

        return false
    }

    private static func containsNarrativeNoise(_ text: String) -> Bool {
        let normalized = normalizedPhrase(text)
        guard !normalized.isEmpty else { return false }

        if narrativeNoiseFragments.contains(where: normalized.contains) {
            return true
        }

        let tokens = tokenized(normalized)
        let hasAction = tokens.contains(where: actionVerbs.contains(_:)) || tokens.contains(where: cookingWords.contains(_:))

        if normalized == "et ensuite" || normalized == "ensuite" || normalized == "puis" ||
            normalized == "alors" || normalized == "du coup" || normalized == "voila" ||
            normalized == "et voila"
        {
            return true
        }

        if (normalized.hasPrefix("et ensuite") || normalized.hasPrefix("ensuite") || normalized.hasPrefix("puis") ||
            normalized.hasPrefix("alors") || normalized.hasPrefix("du coup")) && !hasAction
        {
            return true
        }

        if normalized.hasPrefix("c est") || normalized.hasPrefix("on a") {
            return !hasAction || tokens.count <= 6
        }

        return false
    }

    private static func looksLikeTitleEcho(_ text: String, title: String) -> Bool {
        let normalizedText = normalizedPhrase(text)
        let normalizedTitle = normalizedPhrase(title)

        guard !normalizedText.isEmpty, normalizedTitle.count >= 8 else {
            return false
        }

        return normalizedText == normalizedTitle || normalizedText.contains(normalizedTitle)
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
            containsHardArticlePhrase($0) ||
                (looksLikeProseLine($0) && !looksLikeIngredientLine($0) && !looksLikeCookingStep($0))
        }.count

        let removedNoiseLineCount = allLines.filter {
            isExactNoiseLine($0) ||
                shouldDropAsIrrelevantIngredient($0, title: seed.title) ||
                shouldDropAsIrrelevantStep($0, title: seed.title)
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
