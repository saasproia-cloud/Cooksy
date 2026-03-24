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
        specificEmoji(for: article) ?? fallbackEmoji(for: category)
    }

    static func specificEmoji(for article: String) -> String? {
        let normalized = normalizedSearchText(for: article)

        return matchedEmoji(forNormalizedArticle: normalized)
    }

    private static func fallbackEmoji(for category: ShoppingCategory) -> String {
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

    private static func matchedEmoji(forNormalizedArticle normalized: String) -> String? {
        guard !normalized.isEmpty else { return nil }

        for entry in emojiMappings {
            if matchesAnyKeyword(in: normalized, keywords: entry.keywords) {
                return entry.emoji
            }
        }

        return nil
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
        "persil", "coriandre", "ciboulette", "menthe", "aneth", "romarin", "origan",
        "fraise", "framboise", "myrtille", "brocoli", "chou", "raisin", "cornichon", "pickle",
        "jalapeno", "piment", "patate", "frite", "fries"
    ]

    private static let dairyKeywords = [
        "lait", "beurre", "creme", "yaourt", "yogurt", "fromage", "mozzarella", "parmesan",
        "cheddar", "feta", "oeuf", "oeufs", "egg", "ricotta", "mascarpone", "emmental",
        "gruyere", "comte", "gouda", "raclette", "mozzarella", "kiri", "boursin", "mayo", "mayonnaise"
    ]

    private static let bakeryKeywords = [
        "pain", "baguette", "brioche", "croissant", "bun", "tortilla", "wrap", "pita", "toast",
        "pain burger", "pain brioche", "burger bun", "burger buns", "naan"
    ]

    private static let meatKeywords = [
        "poulet", "dinde", "boeuf", "steak", "viande", "jambon", "lardon", "saumon",
        "thon", "poisson", "crevette", "shrimp", "truite", "porc", "bacon", "cabillaud",
        "colin", "merlu", "hach", "ground beef", "beef mince", "beef patty"
    ]

    private static let frozenKeywords = [
        "surgele", "glace", "ice cream", "frozen", "nuggets", "pizza surgele"
    ]

    private static let beverageKeywords = [
        "eau", "jus", "soda", "cola", "cafe", "the", "biere", "vin", "lait d amande", "smoothie",
        "sirop", "syrup"
    ]

    private static let householdKeywords = [
        "sopalin", "essuie tout", "papier toilette", "eponges", "eponge", "savon", "lessive",
        "liquide vaisselle", "sac poubelle", "mouchoirs", "nettoyant"
    ]

    private static let emojiMappings: [(keywords: [String], emoji: String)] = [
        (["animal fries", "fries", "frites"], "🍟"),
        (["pomme de terre", "pommes de terre", "patate", "patates", "potato", "potatoes"], "🥔"),
        (["tomate"], "🍅"),
        (["salade", "laitue"], "🥬"),
        (["concombre"], "🥒"),
        (["carotte"], "🥕"),
        (["courgette", "zucchini"], "🥒"),
        (["aubergine"], "🍆"),
        (["poivron"], "🫑"),
        (["oignon"], "🧅"),
        (["ail"], "🧄"),
        (["ciboulette", "persil", "coriandre", "cilantro", "basilic", "menthe", "aneth", "thym", "romarin", "origan"], "🌿"),
        (["cornichon", "pickle"], "🥒"),
        (["champignon"], "🍄"),
        (["avocat"], "🥑"),
        (["jalapeno", "piment", "chili", "chilli", "piment d espelette"], "🌶️"),
        (["citron", "lime"], "🍋"),
        (["pomme"], "🍎"),
        (["banane"], "🍌"),
        (["orange"], "🍊"),
        (["fraise"], "🍓"),
        (["framboise", "myrtille", "raisin"], "🫐"),
        (["brocoli"], "🥦"),
        (["oeuf", "egg"], "🥚"),
        (["lait"], "🥛"),
        (["creme", "crème", "creme fraiche", "sour cream"], "🥛"),
        (["beurre"], "🧈"),
        (["fromage", "mozzarella", "parmesan", "cheddar", "feta", "ricotta", "emmental", "gruyere", "comte", "gouda", "raclette", "camembert", "reblochon", "boursin", "kiri"], "🧀"),
        (["yaourt", "yogurt"], "🥣"),
        (["pain burger", "pain brioche", "burger bun", "burger buns", "bun", "buns"], "🍞"),
        (["pain", "baguette", "brioche", "croissant", "pita", "naan", "toast"], "🥖"),
        (["tortilla", "wrap"], "🌯"),
        (["frites", "fries"], "🍟"),
        (["riz"], "🍚"),
        (["pates", "pasta", "spaghetti"], "🍝"),
        (["farine"], "🌾"),
        (["sucre"], "🍚"),
        (["miel", "honey"], "🍯"),
        (["sirop d erable", "maple syrup"], "🍁"),
        (["sirop"], "🍯"),
        (["sel"], "🧂"),
        (["poivre", "epice", "épice", "paprika", "curry", "curcuma", "cumin", "cajun", "garam masala", "cayenne", "epices cajun"], "🧂"),
        (["huile d olive", "olive oil", "huile"], "🫒"),
        (["vinaigre"], "🍶"),
        (["chocolat"], "🍫"),
        (["poulet", "dinde"], "🍗"),
        (["boeuf hache", "viande hache", "bœuf hache", "ground beef", "beef mince", "steak hache", "steak hach", "boeuf", "steak", "viande", "porc", "bacon", "lardon"], "🥩"),
        (["saumon", "thon", "poisson", "truite", "cabillaud", "cod", "colin", "merlu"], "🐟"),
        (["crevette", "shrimp"], "🦐"),
        (["glace", "ice cream"], "🍨"),
        (["eau"], "💧"),
        (["jus", "smoothie"], "🧃"),
        (["soda", "cola"], "🥤"),
        (["cafe"], "☕"),
        (["the"], "🫖"),
        (["vin", "biere"], "🍷"),
        (["ketchup", "moutarde", "mustard", "mayonnaise", "mayo", "aioli", "sauce burger", "sauce algérienne", "sauce algerienne", "sauce blanche", "worcester", "worcestershire", "sauce soja", "soy sauce", "teriyaki", "barbecue", "bbq"], "🫙"),
        (["sauce piquante", "hot sauce", "sriracha", "harissa", "tabasco"], "🌶️"),
        (["sopalin", "essuie tout", "papier toilette", "mouchoirs"], "🧻"),
        (["savon", "liquide vaisselle", "nettoyant"], "🧼"),
        (["lessive"], "🧴"),
        (["eponge", "eponges"], "🧽"),
        (["sac poubelle"], "🗑️")
    ]
}
