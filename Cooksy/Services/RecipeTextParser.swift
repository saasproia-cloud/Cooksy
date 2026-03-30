import Foundation

enum RecipeTextParser {
    private enum Section {
        case header
        case ingredients
        case steps
        case notes
    }

    private static let ingredientKeywords: Set<String> = [
        "ail", "amande", "amandes", "beurre", "boeuf", "bœuf", "burger", "burgers", "chapelure",
        "cheddar", "cheese", "chicken", "coriandre", "corn", "cornflakes", "cream", "creme", "crème",
        "eau", "egg", "eggs", "escalope", "farine", "fish", "flour", "fromage", "garlic", "huile",
        "levure", "lait", "mayonnaise", "milk", "naan", "oeuf", "oeufs", "oeufs", "onion", "panure",
        "paprika", "pane", "pané", "pate", "poulet", "sauce", "sel", "semoule", "sugar", "sucre",
        "taco", "tacos", "tikka", "tortilla", "wings", "yaourt", "yogurt"
    ]

    private static let quantityWords: Set<String> = [
        "a", "an", "one", "two", "three", "half", "few",
        "un", "une", "deux", "trois", "demi", "quelques"
    ]

    private static let unitWords: Set<String> = [
        "g", "gr", "gram", "grams", "kg", "mg", "ml", "cl", "dl", "l", "lb", "lbs", "oz",
        "cas", "cac", "cac", "c.a.c", "c.a.s", "càs", "càc", "cs", "cc",
        "cuillere", "cuillère", "cuilleres", "cuillères",
        "tasse", "verre", "verres", "piece", "pieces", "pièce", "pièces", "tranche", "tranches",
        "gousse", "gousses", "packet", "packets", "sachet", "sachets"
    ]

    private static let stepVerbs = [
        "ajouter", "commencer", "cuire", "diluer", "disposer", "etaler", "étaler", "faire",
        "fariner", "fermer", "finir", "former", "laisser", "melanger", "mélanger", "mettre",
        "ouvrir", "petrir", "pétrir", "plier", "proceder", "procéder", "retourner", "servir",
        "verser", "aplati", "aplatir", "degazer", "dégazer", "incorporer", "chauffer"
    ]

    private static let ingredientSubsectionHeaders: Set<String> = [
        "assemblage", "coating", "cuisson", "dough", "extra", "extras", "farce", "filling",
        "garniture", "marinade", "mixture", "panure", "poulet pane", "poulet pané", "sauce"
    ]

    private static let musicKeywords = [
        "original sound", "son original", "soundtrack", "playlist", "remix",
        "waltz", "instrumental", "piano", "violin", "audio"
    ]

    static func parse(_ input: String, imageData: Data? = nil) -> RecipeEditorSeed {
        let lines = normalizedLines(from: input)
        guard !lines.isEmpty else {
            return RecipeEditorSeed(imageData: imageData)
        }

        var title = explicitTitle(in: lines) ?? fallbackTitle(in: lines)
        var ingredientLines: [String] = []
        var stepLines: [String] = []
        var noteLines: [String] = []

        var currentSection: Section = .header

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !isLikelyNoise(line) else { continue }

            if isIngredientsHeader(line) {
                currentSection = .ingredients
                continue
            }

            if isStepsHeader(line) {
                currentSection = .steps
                continue
            }

            if isNotesHeader(line) {
                currentSection = .notes
                continue
            }

            if isIngredientSubsectionHeader(line) {
                currentSection = .ingredients
                continue
            }

            if currentSection == .ingredients, looksLikeStep(line), !looksLikeIngredient(line) {
                currentSection = .steps
            } else if currentSection == .steps, looksLikeIngredient(line), !looksLikeStep(line) {
                currentSection = .ingredients
            }

            if currentSection == .header, title.isEmpty {
                let candidateTitle = cleanedTitle(line)
                if isLikelyRecipeTitle(candidateTitle) {
                    title = candidateTitle
                    continue
                }
            }

            if cleanedTitle(line) == title || isLikelyRecipeTitle(line) {
                continue
            }

            switch currentSection {
            case .ingredients:
                if looksLikeIngredient(line) {
                    ingredientLines.append(cleanedListLine(line))
                } else {
                    noteLines.append(line)
                }
            case .steps:
                if looksLikeStep(line) {
                    stepLines.append(cleanedStepLine(line))
                } else if looksLikeIngredient(line) {
                    ingredientLines.append(cleanedListLine(line))
                } else {
                    noteLines.append(line)
                }
            case .notes:
                noteLines.append(line)
            case .header:
                if looksLikeIngredient(line) {
                    currentSection = .ingredients
                    ingredientLines.append(cleanedListLine(line))
                } else if looksLikeStep(line) {
                    currentSection = .steps
                    stepLines.append(cleanedStepLine(line))
                } else {
                    noteLines.append(line)
                }
            }
        }

        if ingredientLines.isEmpty && stepLines.isEmpty {
            let blocks = input
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n\n")
                .map { block in
                    block
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
                .filter { !$0.isEmpty }

            if blocks.count >= 2 {
                let probableIngredients = blocks[1]
                let probableSteps = blocks.count >= 3 ? Array(blocks.dropFirst(2).joined()) : []

                if probableIngredients.contains(where: looksLikeIngredient) {
                    ingredientLines = probableIngredients.map(cleanedListLine)
                }
                if !probableSteps.isEmpty {
                    stepLines = probableSteps.map(cleanedStepLine)
                }
            }
        }

        if ingredientLines.isEmpty && stepLines.isEmpty {
            let candidateLines = lines
                .filter { cleanedTitle($0) != title }
                .filter { !isLikelyNoise($0) }

            ingredientLines = candidateLines
                .filter { !isIngredientSubsectionHeader($0) }
                .filter(looksLikeIngredient)
            stepLines = candidateLines
                .filter { !looksLikeIngredient($0) && looksLikeStep($0) }
                .map(cleanedStepLine)
        }

        if title.isEmpty {
            title = "Recette importée"
        }

        let ingredientDrafts = ingredientLines
            .map(parseIngredientLine(_:))
            .filter { !$0.name.isEmpty }

        let stepDrafts = stepLines
            .map { StepDraft(detail: cleanedStepLine($0)) }
            .filter { !$0.detail.isEmpty }

        let notesText = noteLines
            .filter { cleanedTitle($0) != title }
            .joined(separator: "\n")

        return RecipeEditorSeed(
            title: title,
            ingredientDrafts: ingredientDrafts,
            stepDrafts: stepDrafts,
            notesText: notesText,
            imageData: imageData
        )
    }

    private static func normalizedLines(from input: String) -> [String] {
        let directLines = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanedSocialLine(_:))
            .filter { !$0.isEmpty }

        let expandedLines = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\s*(?:[•·▪◦●])\s*"#, with: "\n- ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(?=\d+[\).\:-]\s)"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map(cleanedSocialLine(_:))
            .filter { !$0.isEmpty }

        return uniqueNonEmptyLines(expandedLines.count >= directLines.count ? expandedLines : directLines)
    }

    private static func uniqueNonEmptyLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for line in lines where !line.isEmpty {
            if seen.insert(line).inserted {
                result.append(line)
            }
        }

        return result
    }

    private static func explicitTitle(in lines: [String]) -> String? {
        for line in lines {
            let lowercased = normalizedPhrase(line)
            guard lowercased.hasPrefix("titre") || lowercased.hasPrefix("title") else { continue }
            let raw = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let cleaned = cleanedTitle(raw)
            if isLikelyRecipeTitle(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private static func fallbackTitle(in lines: [String]) -> String {
        for line in lines where !isSectionHeader(line) && !isLikelyNoise(line) {
            let cleaned = cleanedTitle(line)
            if isLikelyRecipeTitle(cleaned) {
                return cleaned
            }
        }
        return ""
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        isIngredientsHeader(line) || isStepsHeader(line) || isNotesHeader(line)
    }

    private static func isIngredientsHeader(_ line: String) -> Bool {
        matches(line, against: ["ingredients", "ingrédients", "ingredient", "liste des ingrédients"])
    }

    private static func isStepsHeader(_ line: String) -> Bool {
        matches(line, against: ["instructions", "étapes", "etapes", "préparation", "preparation", "méthode", "methode", "directions", "marche a suivre", "marche à suivre"])
    }

    private static func isNotesHeader(_ line: String) -> Bool {
        matches(line, against: ["notes", "astuces", "conseils"])
    }

    private static func isIngredientSubsectionHeader(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty, normalized.count <= 36 else { return false }
        return ingredientSubsectionHeaders.contains(normalized)
    }

    private static func matches(_ line: String, against patterns: [String]) -> Bool {
        let normalized = normalizedPhrase(line)
        return patterns.contains(normalized)
    }

    private static func cleanedTitle(_ line: String) -> String {
        var cleaned = line
            .replacingOccurrences(of: #"^(titre|title)\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"#[\p{L}\p{N}_]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"@[\p{L}\p{N}_\.]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\+\s*(suivre|follow)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\p{Extended_Pictographic}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[^A-Za-zÀ-ÿ0-9]+|[^A-Za-zÀ-ÿ0-9]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isMostlyUppercased(cleaned) {
            cleaned = cleaned.localizedLowercase.capitalized
        }

        return cleaned
    }

    private static func cleanedListLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*(?:[-•*]|[⭐✨👉👇☝️🟠🔸▪️◦])+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedStepLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*(?:[⭐✨👉👇☝️]+\s*)*(\d+[\).\-\s:]+|[-•*]\s*)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        let cleaned = cleanedListLine(line)
        guard !cleaned.isEmpty else { return false }
        guard !isLikelyNoise(cleaned) else { return false }
        guard !isIngredientSubsectionHeader(cleaned) else { return false }
        guard !isLikelyRecipeTitle(cleaned) else { return false }
        guard !looksLikeMusicCredit(cleaned) else { return false }

        let normalized = normalizedPhrase(cleaned)
        let words = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let hasQuantity = cleaned.range(of: #"^\d+([,./]\d+)?|^\d+/\d+|^[¼½¾⅓⅔⅛]"#, options: .regularExpression) != nil ||
            words.contains(where: quantityWords.contains(_:))
        let hasUnit = words.contains(where: unitWords.contains(_:))
        let hasFoodWord = words.contains(where: ingredientKeywords.contains(_:))

        if hasQuantity && (hasUnit || hasFoodWord || words.count <= 8) {
            return true
        }
        if hasUnit && (hasFoodWord || words.count <= 7) {
            return true
        }
        return hasFoodWord && words.count <= 8
    }

    private static func looksLikeStep(_ line: String) -> Bool {
        let cleaned = cleanedStepLine(line)
        guard !cleaned.isEmpty else { return false }
        guard !isLikelyNoise(cleaned) else { return false }
        if line.range(of: #"^\s*(\d+[\).\-\s]+|[-•*]\s*)"#, options: .regularExpression) != nil {
            return true
        }

        let normalized = normalizedPhrase(cleaned)
        return stepVerbs.contains { normalized.hasPrefix($0) }
    }

    private static func isLikelyNoise(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        if normalized.isEmpty {
            return true
        }
        if normalized.contains("http") || normalized.contains("www") {
            return true
        }
        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            return true
        }
        if looksLikeSocialHandleLine(line) || looksLikeMusicCredit(line) {
            return true
        }
        return normalized.contains("tiktok") ||
            normalized.contains("instagram") ||
            normalized.contains("pinterest") ||
            normalized.contains("reply to") ||
            normalized.contains("reponse a") ||
            normalized.contains("ajouter un commentaire") ||
            normalized.contains("watch more")
    }

    private static func cleanedSocialLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPhrase(_ line: String) -> String {
        line
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\p{Extended_Pictographic}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^A-Za-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isLikelyRecipeTitle(_ line: String) -> Bool {
        let cleaned = cleanedTitle(line)
        let normalized = normalizedPhrase(cleaned)
        guard !normalized.isEmpty else { return false }
        guard !isLikelyNoise(cleaned) else { return false }
        guard !isSectionHeader(cleaned) else { return false }
        guard !isIngredientSubsectionHeader(cleaned) else { return false }

        let words = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 8 else { return false }

        if words.contains(where: ingredientKeywords.contains(_:)) {
            return true
        }

        return isMostlyUppercased(cleaned) && words.count >= 2 && words.count <= 5
    }

    private static func looksLikeSocialHandleLine(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
            return true
        }

        return normalized.contains("suivre") ||
            normalized.contains("follow") ||
            normalized.contains("abonne toi") ||
            normalized.contains("abonnez vous")
    }

    private static func looksLikeMusicCredit(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        let words = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 6 else { return false }
        guard !words.contains(where: ingredientKeywords.contains(_:)) else { return false }
        return musicKeywords.contains { normalized.contains($0) }
    }

    private static func isMostlyUppercased(_ line: String) -> Bool {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return Double(uppercaseCount) / Double(letters.count) >= 0.7
    }

    private static func parseIngredientLine(_ line: String) -> IngredientDraft {
        let cleaned = cleanedListLine(line)
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return IngredientDraft() }

        if tokens.count == 1 {
            return IngredientDraft(name: cleaned)
        }

        let firstToken = tokens[0]
        let secondToken = tokens.count > 1 ? tokens[1] : ""
        let quantityToken = combinedQuantityToken(first: firstToken, second: secondToken)
        let startsWithQuantity = quantityToken != nil

        if startsWithQuantity {
            let quantity = quantityToken ?? firstToken
            let remainingTokens = Array(tokens.dropFirst(quantity == firstToken ? 1 : 2))
            let unitToken = remainingTokens.first ?? ""

            if remainingTokens.count >= 2 && unitToken.rangeOfCharacter(from: .letters) != nil {
                return IngredientDraft(
                    amount: quantity,
                    unit: unitToken,
                    name: remainingTokens.dropFirst().joined(separator: " ")
                )
            }

            return IngredientDraft(
                amount: quantity,
                unit: "",
                name: remainingTokens.joined(separator: " ")
            )
        }

        return IngredientDraft(name: cleaned)
    }

    private static func combinedQuantityToken(first: String, second: String) -> String? {
        if first.range(of: #"^\d+([,./]\d+)?$"#, options: .regularExpression) != nil {
            if second.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil {
                return "\(first) \(second)"
            }
            return first
        }

        if first.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil {
            return first
        }

        return nil
    }
}
