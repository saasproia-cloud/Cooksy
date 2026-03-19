import Foundation

struct ParsedShoppingItem: Hashable {
    let article: String
    let quantity: String?
    let category: ShoppingCategory
}

enum ShoppingCatalog {
    static func parseItems(from rawText: String) -> [ParsedShoppingItem] {
        let lines = normalizedLines(from: rawText)

        return lines.compactMap { line in
            parseItem(from: line)
        }
    }

    static func parseItem(from line: String) -> ParsedShoppingItem? {
        let trimmedLine = cleanup(line)
        guard !trimmedLine.isEmpty else { return nil }

        let components = extractQuantityAndArticle(from: trimmedLine)
        let article = displayArticle(for: components.article)
        guard !article.isEmpty else { return nil }

        let category = suggestedCategory(for: article)
        return ParsedShoppingItem(article: article, quantity: components.quantity, category: category)
    }

    static func displayArticle(for rawArticle: String) -> String {
        let collapsed = cleanup(rawArticle)
        guard !collapsed.isEmpty else { return "" }

        let withoutDeterminer = removeLeadingDeterminer(from: collapsed)
        let normalized = withoutDeterminer.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !normalized.isEmpty else { return "" }

        if normalized == normalized.uppercased(), normalized.count > 1 {
            return normalized.localizedLowercase
        }

        let first = normalized.prefix(1).localizedLowercase
        return first + normalized.dropFirst()
    }

    static func suggestedCategory(for article: String) -> ShoppingCategory {
        let normalized = normalizedSearchText(for: article)

        if matchesAnyKeyword(in: normalized, keywords: freshProduceKeywords) {
            return .freshProduce
        }

        if matchesAnyKeyword(in: normalized, keywords: dairyKeywords) {
            return .dairyAndEggs
        }

        if matchesAnyKeyword(in: normalized, keywords: bakeryKeywords) {
            return .bakery
        }

        if matchesAnyKeyword(in: normalized, keywords: meatKeywords) {
            return .meatAndSeafood
        }

        if matchesAnyKeyword(in: normalized, keywords: frozenKeywords) {
            return .frozen
        }

        if matchesAnyKeyword(in: normalized, keywords: beverageKeywords) {
            return .beverages
        }

        if matchesAnyKeyword(in: normalized, keywords: householdKeywords) {
            return .household
        }

        return .pantry
    }

    static func emoji(for article: String, category: ShoppingCategory) -> String {
        let normalized = normalizedSearchText(for: article)

        for entry in emojiMappings {
            if matchesAnyKeyword(in: normalized, keywords: entry.keywords) {
                return entry.emoji
            }
        }

        switch category {
        case .freshProduce:
            return "🥬"
        case .dairyAndEggs:
            return "🥛"
        case .bakery:
            return "🥖"
        case .pantry:
            return "🥫"
        case .meatAndSeafood:
            return "🥩"
        case .frozen:
            return "🧊"
        case .beverages:
            return "🥤"
        case .household:
            return "🧽"
        }
    }

    private static func normalizedLines(from rawText: String) -> [String] {
        rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanup)
            .filter { !$0.isEmpty }
    }

    private static func cleanup(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[•\\-–—·\\s]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
    }

    private static func extractQuantityAndArticle(from line: String) -> (quantity: String?, article: String) {
        let patterns = [
            #"^((?:\d+(?:[.,]\d+)?)\s*(?:kg|g|mg|l|cl|ml|x|pcs?|pi[eè]ces?|tranches?|c\.?\s*a\.?\s*s\.?|c\.?\s*a\.?\s*c\.?)?)\s+(.+)$"#,
            #"^((?:un|une|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|quelques))\s+(.+)$"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: line,
                    options: [],
                    range: NSRange(location: 0, length: line.utf16.count)
                ),
                match.numberOfRanges == 3,
                let quantityRange = Range(match.range(at: 1), in: line),
                let articleRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            let quantity = cleanup(String(line[quantityRange]))
            let article = cleanup(String(line[articleRange]))
            return (quantity.isEmpty ? nil : quantity, article)
        }

        return (nil, line)
    }

    private static func removeLeadingDeterminer(from string: String) -> String {
        let determiners = [
            "des ", "du ", "de la ", "de l'", "de ", "le ", "la ", "les ", "un ", "une ", "d'"
        ]

        let lowercase = string.localizedLowercase
        for determiner in determiners {
            if lowercase.hasPrefix(determiner) {
                return String(string.dropFirst(determiner.count))
            }
        }

        return string
    }

    private static func normalizedSearchText(for string: String) -> String {
        string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesAnyKeyword(in text: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            text.contains(keyword)
        }
    }

    private static let freshProduceKeywords = [
        "tomate", "tomates", "salade", "laitue", "concombre", "carotte", "courgette", "zucchini",
        "aubergine", "poivron", "oignon", "echalote", "ail", "pomme de terre", "pomme",
        "banane", "orange", "citron", "lime", "avocat", "champignon", "epinard", "basilic",
        "persil", "coriandre", "fraise", "framboise", "myrtille", "brocoli", "chou", "raisin"
    ]

    private static let dairyKeywords = [
        "lait", "beurre", "creme", "yaourt", "yogurt", "fromage", "mozzarella", "parmesan",
        "cheddar", "feta", "oeuf", "oeufs", "egg", "ricotta", "mascarpone"
    ]

    private static let bakeryKeywords = [
        "pain", "baguette", "brioche", "croissant", "bun", "tortilla", "wrap", "pita", "toast"
    ]

    private static let meatKeywords = [
        "poulet", "dinde", "boeuf", "steak", "viande", "jambon", "lardon", "saumon",
        "thon", "poisson", "crevette", "shrimp", "truite", "porc", "bacon"
    ]

    private static let frozenKeywords = [
        "surgele", "glace", "ice cream", "frozen", "nuggets", "pizza surgele"
    ]

    private static let beverageKeywords = [
        "eau", "jus", "soda", "cola", "cafe", "the", "biere", "vin", "lait d amande", "smoothie"
    ]

    private static let householdKeywords = [
        "sopalin", "essuie tout", "papier toilette", "eponges", "eponge", "savon", "lessive",
        "liquide vaisselle", "sac poubelle", "mouchoirs", "nettoyant"
    ]

    private static let emojiMappings: [(keywords: [String], emoji: String)] = [
        (["tomate"], "🍅"),
        (["salade", "laitue"], "🥬"),
        (["concombre"], "🥒"),
        (["carotte"], "🥕"),
        (["courgette", "zucchini"], "🥒"),
        (["aubergine"], "🍆"),
        (["poivron"], "🫑"),
        (["oignon"], "🧅"),
        (["ail"], "🧄"),
        (["champignon"], "🍄"),
        (["avocat"], "🥑"),
        (["citron", "lime"], "🍋"),
        (["pomme"], "🍎"),
        (["banane"], "🍌"),
        (["orange"], "🍊"),
        (["fraise"], "🍓"),
        (["framboise", "myrtille", "raisin"], "🫐"),
        (["brocoli"], "🥦"),
        (["oeuf", "egg"], "🥚"),
        (["lait"], "🥛"),
        (["beurre"], "🧈"),
        (["fromage", "mozzarella", "parmesan", "cheddar", "feta", "ricotta"], "🧀"),
        (["yaourt", "yogurt"], "🥣"),
        (["pain", "baguette", "brioche", "croissant", "bun", "pita"], "🥖"),
        (["tortilla", "wrap"], "🌯"),
        (["riz"], "🍚"),
        (["pates", "pasta", "spaghetti"], "🍝"),
        (["farine"], "🌾"),
        (["sucre"], "🍚"),
        (["sel"], "🧂"),
        (["poivre", "epice", "paprika", "curry"], "🧂"),
        (["huile"], "🫒"),
        (["vinaigre"], "🍶"),
        (["chocolat"], "🍫"),
        (["poulet", "dinde"], "🍗"),
        (["boeuf", "steak", "viande", "porc", "bacon"], "🥩"),
        (["saumon", "thon", "poisson", "truite"], "🐟"),
        (["crevette", "shrimp"], "🦐"),
        (["glace", "ice cream"], "🍨"),
        (["eau"], "💧"),
        (["jus", "smoothie"], "🧃"),
        (["soda", "cola"], "🥤"),
        (["cafe"], "☕"),
        (["the"], "🫖"),
        (["vin", "biere"], "🍷"),
        (["sopalin", "essuie tout", "papier toilette", "mouchoirs"], "🧻"),
        (["savon", "liquide vaisselle", "nettoyant"], "🧼"),
        (["lessive"], "🧴"),
        (["eponge", "eponges"], "🧽"),
        (["sac poubelle"], "🗑️")
    ]
}
