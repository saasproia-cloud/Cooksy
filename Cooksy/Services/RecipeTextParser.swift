import Foundation

enum RecipeTextParser {
    static func parse(_ input: String, imageData: Data? = nil) -> RecipeEditorSeed {
        let lines = normalizedLines(from: input)
        guard !lines.isEmpty else {
            return RecipeEditorSeed(imageData: imageData)
        }

        var title = explicitTitle(in: lines) ?? fallbackTitle(in: lines)
        var ingredientLines: [String] = []
        var stepLines: [String] = []
        var noteLines: [String] = []

        enum Section {
            case header
            case ingredients
            case steps
            case notes
        }

        var currentSection: Section = .header

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

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

            if currentSection == .header, title.isEmpty {
                title = cleanedTitle(line)
                continue
            }

            switch currentSection {
            case .ingredients:
                ingredientLines.append(cleanedListLine(line))
            case .steps:
                stepLines.append(cleanedStepLine(line))
            case .notes:
                noteLines.append(line)
            case .header:
                noteLines.append(line)
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

            ingredientLines = candidateLines.filter(looksLikeIngredient)
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
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanedSocialLine(_:))
            .filter { !$0.isEmpty }
    }

    private static func explicitTitle(in lines: [String]) -> String? {
        for line in lines {
            let lowercased = line.lowercased()
            guard lowercased.hasPrefix("titre:") || lowercased.hasPrefix("title:") else { continue }
            let raw = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let cleaned = cleanedTitle(raw)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private static func fallbackTitle(in lines: [String]) -> String {
        for line in lines where !isSectionHeader(line) {
            let cleaned = cleanedTitle(line)
            if !cleaned.isEmpty {
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

    private static func matches(_ line: String, against patterns: [String]) -> Bool {
        let normalized = line
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ": -•"))
        return patterns.contains(normalized)
    }

    private static func cleanedTitle(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^(titre|title)\s*:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedListLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*[-•*]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[🟠🔸▪️◦]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedStepLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*(\d+[\).\-\s]+|[-•*]\s*)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        let cleaned = cleanedListLine(line)
        guard !cleaned.isEmpty else { return false }
        if cleaned.range(of: #"^\d+([,./]\d+)?"#, options: .regularExpression) != nil {
            return true
        }
        let lowercased = cleaned.lowercased()
        let knownUnits = ["g", "kg", "ml", "l", "càc", "cac", "cas", "cuillère", "cuillere", "tasse", "verre", "pincée", "pincee"]
        if knownUnits.contains(where: lowercased.contains) {
            return true
        }
        return cleaned.split(separator: " ").count <= 6
    }

    private static func looksLikeStep(_ line: String) -> Bool {
        let cleaned = cleanedStepLine(line)
        guard !cleaned.isEmpty else { return false }
        if line.range(of: #"^\s*(\d+[\).\-\s]+|[-•*]\s*)"#, options: .regularExpression) != nil {
            return true
        }

        let lowercased = cleaned.lowercased()
        let commonVerbs = [
            "mélanger", "melanger", "ajouter", "faire", "cuire", "verser", "laisser",
            "chauffer", "former", "mettre", "fouetter", "mixer", "découper", "decouper",
            "rôtir", "rotir", "servir", "préchauffer", "prechauffer", "remuer", "incorporer"
        ]

        return commonVerbs.contains { lowercased.hasPrefix($0) }
    }

    private static func isLikelyNoise(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if lowercased.contains("http://") || lowercased.contains("https://") {
            return true
        }
        if lowercased.hasPrefix("#") {
            return true
        }
        if lowercased.contains("tiktok") || lowercased.contains("instagram") {
            return true
        }
        return false
    }

    private static func cleanedSocialLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
