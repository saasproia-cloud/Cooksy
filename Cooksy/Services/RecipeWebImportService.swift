import Foundation
import OSLog

enum RecipeWebImportError: LocalizedError {
    case invalidPageSnapshot
    case noRecipeFound

    var errorDescription: String? {
        switch self {
        case .invalidPageSnapshot:
            return "La page n'a pas pu etre lue correctement."
        case .noRecipeFound:
            return "Aucune recette exploitable n'a ete detectee sur cette page."
        }
    }
}

enum RecipeWebImportService {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "RecipeWebImportService")

    static let pageExtractionJavaScript = #"""
    (() => {
      const clean = value => (value || "").toString().replace(/\s+/g, " ").trim();
      const metaContent = selector => document.querySelector(selector)?.content || "";
      const textArray = nodes => Array.from(nodes)
        .map(node => clean(node.innerText || node.textContent || ""))
        .filter(Boolean);
      const collectSectionLines = patterns => {
        const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, [role="heading"]'));

        for (const heading of headings) {
          const headingText = clean(heading.innerText || heading.textContent || "");
          if (!headingText || !patterns.some(pattern => pattern.test(headingText))) {
            continue;
          }

          const containers = [
            heading.closest('section'),
            heading.closest('article'),
            heading.parentElement,
            heading.parentElement?.parentElement,
            heading.closest('div'),
            document.querySelector('main'),
            document.body
          ].filter(Boolean);

          for (const container of containers) {
            const lines = textArray(container.querySelectorAll('li, p'))
              .filter(line => line !== headingText);

            if (lines.length > 0) {
              return lines;
            }
          }
        }

        return [];
      };

      const instructionRoots = Array.from(document.querySelectorAll('[itemprop="recipeInstructions"]'));
      const microInstructions = instructionRoots.flatMap(node => {
        const detailed = textArray(node.querySelectorAll('li, p, [itemprop="text"]'));
        if (detailed.length > 0) {
          return detailed;
        }
        const ownText = clean(node.innerText || node.textContent || "");
        return ownText ? [ownText] : [];
      });

      const payload = {
        url: document.location.href || "",
        title: clean(document.title || ""),
        h1Title: clean(document.querySelector('h1')?.innerText || document.querySelector('h1')?.textContent || ""),
        ogTitle: clean(metaContent('meta[property="og:title"]')),
        ogImage: clean(metaContent('meta[property="og:image"]')),
        description: clean(metaContent('meta[name="description"]')),
        socialTitle: clean(metaContent('meta[name="twitter:title"]') || metaContent('meta[property="twitter:title"]')),
        socialDescription: clean(metaContent('meta[name="twitter:description"]') || metaContent('meta[property="twitter:description"]') || metaContent('meta[property="og:description"]')),
        socialImage: clean(metaContent('meta[name="twitter:image"]') || metaContent('meta[property="twitter:image"]')),
        jsonLD: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
          .map(node => node.textContent || "")
          .filter(Boolean),
        microIngredients: textArray(document.querySelectorAll('[itemprop="recipeIngredient"]')),
        microInstructions,
        sectionIngredients: collectSectionLines([/ingredients?/i, /ingr[ée]dients?/i]),
        sectionInstructions: collectSectionLines([/instructions?/i, /directions?/i, /method/i, /preparation/i, /pr[ée]paration/i, /steps?/i, /etapes?/i, /[ée]tapes?/i])
      };

      return JSON.stringify(payload);
    })();
    """#

    static func canImportRecipe(from snapshotJSON: String) -> Bool {
        guard let seed = try? importRecipe(from: snapshotJSON) else {
            return false
        }

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)
        return !assessment.validation.isRejected
    }

    static func importRecipe(from snapshotJSON: String) throws -> RecipeEditorSeed {
        let extractedContent = try extractRecipeContent(from: snapshotJSON)

        guard !extractedContent.ingredientLines.isEmpty || !extractedContent.stepLines.isEmpty else {
            throw RecipeWebImportError.noRecipeFound
        }

        let snapshot = extractedContent.snapshot
        let structuredRecipe = extractedContent.structuredRecipe
        let ingredientLines = extractedContent.ingredientLines
        let stepLines = extractedContent.stepLines

        let sourceURL = URL(string: snapshot.url)
        let remoteImageSource = [
            structuredRecipe?.imageURLString,
            cleanedText(snapshot.ogImage),
            cleanedText(snapshot.socialImage)
        ]
        .compactMap { $0 }
        .first

        let remoteImageURL = remoteImageSource.flatMap(URL.init(string:))
        let notes = [structuredRecipe?.description, snapshot.description, snapshot.socialDescription]
            .compactMap(cleanedText)
            .first ?? ""

        return RecipeEditorSeed(
            title: cleanedText(structuredRecipe?.title) ??
                cleanedText(snapshot.h1Title) ??
                cleanedText(snapshot.ogTitle) ??
                cleanedText(snapshot.title) ??
                "Recette importee",
            sourceURL: sourceURL,
            ingredientDrafts: ingredientLines.map(parseIngredientLine(_:)),
            stepDrafts: stepLines.map { StepDraft(detail: cleanInstructionLine($0)) },
            notesText: notes,
            prepTimeText: structuredRecipe?.prepTimeMinutes.map(String.init) ?? "",
            cookTimeText: structuredRecipe?.cookTimeMinutes.map(String.init) ?? "",
            servingsText: cleanedText(structuredRecipe?.yieldText) ?? "",
            caloriesText: cleanedText(structuredRecipe?.nutrition?.calories) ?? "",
            proteinText: cleanedText(structuredRecipe?.nutrition?.protein) ?? "",
            carbsText: cleanedText(structuredRecipe?.nutrition?.carbs) ?? "",
            fatText: cleanedText(structuredRecipe?.nutrition?.fat) ?? "",
            remoteImageURL: remoteImageURL
        )
    }

    static func downloadImageData(from url: URL) async -> Data? {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }

        do {
            logger.debug("Downloading remote image from \(url.absoluteString, privacy: .public)")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let httpResponse = response as? HTTPURLResponse,
                200 ..< 300 ~= httpResponse.statusCode
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    static func importRecipe(from url: URL) async throws -> RecipeEditorSeed {
        let summary = try await fetchPageSummary(from: url)
        return try importRecipe(from: summary)
    }

    static func importRecipe(from summary: RecipePageSummary) throws -> RecipeEditorSeed {
        let snapshot = summary.snapshot

        if let snapshotData = try? JSONEncoder().encode(snapshot),
           let snapshotJSON = String(data: snapshotData, encoding: .utf8),
           let structuredSeed = try? importRecipe(from: snapshotJSON) {
            var enrichedSeed = structuredSeed
            enrichedSeed.sourceURL = summary.url
            if enrichedSeed.remoteImageURL == nil {
                enrichedSeed.remoteImageURL = summary.imageURL
            }
            if enrichedSeed.notesText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty,
               let description = summary.description {
                enrichedSeed.notesText = description
            }
            return enrichedSeed
        }

        if let fallbackSeed = conservativeFallbackSeed(from: summary) {
            return fallbackSeed
        }

        throw RecipeWebImportError.noRecipeFound
    }

    static func fallbackReconstructionText(from summary: RecipePageSummary) -> String? {
        let ingredientLines = filteredIngredientLines(summary.snapshot.sectionIngredients)
        let stepLines = filteredInstructionLines(summary.snapshot.sectionInstructions)

        var sections: [String] = []
        if !ingredientLines.isEmpty {
            sections.append("Ingredients\n" + ingredientLines.joined(separator: "\n"))
        }
        if !stepLines.isEmpty {
            sections.append("Instructions\n" + stepLines.joined(separator: "\n"))
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    static func safeFallbackNotes(from summary: RecipePageSummary) -> String? {
        guard let description = cleanedText(summary.description) else { return nil }
        guard !looksLikeArticleParagraph(description) else { return nil }
        return String(description.prefix(220))
    }

    static func fetchPageSummary(from url: URL) async throws -> RecipePageSummary {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw RecipeWebImportError.invalidPageSnapshot
        }

        logger.debug("Fetching page summary from \(url.absoluteString, privacy: .public)")
        let page = try await fetchHTMLPage(from: url)
        let snapshot = buildSnapshot(fromHTML: page.html, url: page.url)

        return RecipePageSummary(
            url: page.url,
            title: cleanedText(snapshot.h1Title) ??
                cleanedText(snapshot.ogTitle) ??
                cleanedText(snapshot.socialTitle) ??
                cleanedText(snapshot.title),
            description: cleanedText(snapshot.description) ??
                cleanedText(snapshot.socialDescription),
            imageURL: [cleanedText(snapshot.ogImage), cleanedText(snapshot.socialImage)]
                .compactMap { $0 }
                .first
                .flatMap(URL.init(string:)),
            textContent: page.textContent,
            snapshot: snapshot
        )
    }

    private static func extractRecipeContent(from snapshotJSON: String) throws -> ExtractedRecipeContent {
        let snapshot = try decodeSnapshot(from: snapshotJSON)

        let structuredRecipe = snapshot.jsonLD
            .compactMap(extractStructuredRecipe(from:))
            .first

        let ingredientLines = preferredIngredientLines(from: snapshot, structuredRecipe: structuredRecipe)
        let stepLines = preferredStepLines(from: snapshot, structuredRecipe: structuredRecipe)

        guard !ingredientLines.isEmpty || !stepLines.isEmpty else {
            throw RecipeWebImportError.noRecipeFound
        }

        return ExtractedRecipeContent(
            snapshot: snapshot,
            structuredRecipe: structuredRecipe,
            ingredientLines: ingredientLines,
            stepLines: stepLines
        )
    }

    private static func decodeSnapshot(from json: String) throws -> WebRecipeImportSnapshot {
        guard let data = json.data(using: .utf8) else {
            throw RecipeWebImportError.invalidPageSnapshot
        }

        do {
            return try JSONDecoder().decode(WebRecipeImportSnapshot.self, from: data)
        } catch {
            throw RecipeWebImportError.invalidPageSnapshot
        }
    }

    private static func fetchHTMLPage(from url: URL) async throws -> FetchedHTMLPage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("fr-FR,fr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            logger.debug("Requesting HTML page at \(url.absoluteString, privacy: .public)")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .badURL || error.code == .unsupportedURL {
            logger.error("Invalid page URL requested: \(url.absoluteString, privacy: .public)")
            throw RecipeWebImportError.invalidPageSnapshot
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 400).contains(httpResponse.statusCode) {
            throw RecipeWebImportError.invalidPageSnapshot
        }

        let finalURL = response.url ?? url
        let html = decodedHTML(from: data)
        let textContent = plainText(fromHTML: html)

        return FetchedHTMLPage(
            url: finalURL,
            html: html,
            textContent: textContent
        )
    }

    private static func decodedHTML(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let isoLatin = String(data: data, encoding: .isoLatin1) {
            return isoLatin
        }

        return String(decoding: data, as: UTF8.self)
    }

    private static func buildSnapshot(fromHTML html: String, url: URL) -> WebRecipeImportSnapshot {
        let textContent = plainText(fromHTML: html)

        return WebRecipeImportSnapshot(
            url: url.absoluteString,
            title: firstTagText("title", in: html) ?? "",
            h1Title: firstTagText("h1", in: html) ?? "",
            ogTitle: metaContent(for: "og:title", in: html) ?? metaContent(for: "twitter:title", in: html) ?? "",
            ogImage: metaContent(for: "og:image", in: html) ?? metaContent(for: "twitter:image", in: html) ?? "",
            description: metaContent(for: "description", in: html) ??
                metaContent(for: "og:description", in: html) ??
                metaContent(for: "twitter:description", in: html) ?? "",
            socialTitle: metaContent(for: "twitter:title", in: html) ??
                metaContent(for: "og:title", in: html) ?? "",
            socialDescription: metaContent(for: "twitter:description", in: html) ??
                metaContent(for: "og:description", in: html) ?? "",
            socialImage: metaContent(for: "twitter:image", in: html) ??
                metaContent(for: "og:image", in: html) ?? "",
            jsonLD: jsonLDScripts(in: html),
            microIngredients: itempropValues(named: "recipeIngredient", in: html),
            microInstructions: itempropValues(named: "recipeInstructions", in: html),
            sectionIngredients: collectSectionLines(
                in: textContent,
                headings: ["ingredients", "ingrédients", "ingredient", "liste des ingrédients", "ingredients list"]
            ),
            sectionInstructions: collectSectionLines(
                in: textContent,
                headings: [
                    "instructions", "préparation", "preparation", "étapes", "etapes", "method",
                    "directions", "steps", "methodes", "méthodes", "marche a suivre"
                ]
            )
        )
    }

    private static func metaContent(for key: String, in html: String) -> String? {
        for tag in matches(
            pattern: #"<meta\b[^>]*>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let property = attributeValue(named: "property", in: tag) ??
                attributeValue(named: "name", in: tag)

            guard property?.caseInsensitiveCompare(key) == .orderedSame else { continue }
            if let content = cleanedText(attributeValue(named: "content", in: tag)) {
                return content
            }
        }

        return nil
    }

    private static func jsonLDScripts(in html: String) -> [String] {
        matches(
            pattern: #"<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators],
            captureGroup: 1
        )
        .compactMap(cleanJSONLD(_:))
    }

    private static func itempropValues(named name: String, in html: String) -> [String] {
        let directContentPattern = #"<[^>]*itemprop=["']\#(name)["'][^>]*content=["']([^"']+)["'][^>]*>"#
        let nodeTextPattern = #"<[^>]*itemprop=["']\#(name)["'][^>]*>(.*?)</[^>]+>"#

        let directValues = matches(
            pattern: directContentPattern,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators],
            captureGroup: 1
        )

        let textValues = matches(
            pattern: nodeTextPattern,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators],
            captureGroup: 1
        )
        .map(stripHTMLTags(_:))

        return Array(Set((directValues + textValues).compactMap(cleanedText))).sorted()
    }

    private static func firstTagText(_ tag: String, in html: String) -> String? {
        matches(
            pattern: #"<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators],
            captureGroup: 1
        )
        .map(stripHTMLTags(_:))
        .compactMap(cleanedText)
        .first
    }

    private static func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8) else {
            return stripHTMLTags(html)
        }

        if let attributedString = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributedString.string
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return stripHTMLTags(html)
    }

    private static func stripHTMLTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<script\b[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collectSectionLines(in text: String, headings: [String]) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for (index, line) in lines.enumerated() {
            guard matchesHeading(line, in: headings) else { continue }

            var collected: [String] = []
            for candidate in lines.dropFirst(index + 1) {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if !collected.isEmpty { break }
                    continue
                }

                if isLikelySectionHeader(trimmed), !collected.isEmpty {
                    break
                }

                collected.append(trimmed)
                if collected.count >= 24 {
                    break
                }
            }

            let cleanedLines = collected
                .map { value in
                    value.replacingOccurrences(of: #"^\s*[-•*]\s*"#, with: "", options: .regularExpression)
                }
                .filter { !$0.isEmpty }

            if !cleanedLines.isEmpty {
                return cleanedLines
            }
        }

        return []
    }

    private static func matchesHeading(_ line: String, in headings: [String]) -> Bool {
        let normalizedLine = line
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: CharacterSet(charactersIn: ": -•"))

        return headings.contains {
            normalizedLine == $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }
    }

    private static func isLikelySectionHeader(_ line: String) -> Bool {
        let normalizedLine = line
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: CharacterSet(charactersIn: ": -•"))

        let knownHeadings = [
            "ingredients", "ingredient", "instructions", "preparation", "etapes", "etape",
            "method", "directions", "nutrition", "notes", "astuces", "tips", "servings"
        ]

        guard knownHeadings.contains(normalizedLine) else { return false }
        return true
    }

    private static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        captureGroup: Int? = nil
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            let targetRange = captureGroup.map { match.range(at: $0) } ?? match.range
            guard targetRange.location != NSNotFound,
                  let swiftRange = Range(targetRange, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }

    private static func attributeValue(named attribute: String, in tag: String) -> String? {
        matches(
            pattern: #"\#(attribute)\s*=\s*["']([^"']+)["']"#,
            in: tag,
            options: [.caseInsensitive],
            captureGroup: 1
        )
        .compactMap(cleanedText(_:))
        .first
    }

    private static func preferredIngredientLines(
        from snapshot: WebRecipeImportSnapshot,
        structuredRecipe: StructuredRecipeCandidate?
    ) -> [String] {
        let lineSets = nonEmptyLineSets(
            structuredRecipe?.ingredients,
            snapshot.microIngredients,
            snapshot.sectionIngredients
        )
        return firstRecipeLikeLineSet(
            lineSets,
            minimumCount: 3,
            transform: cleanIngredientLine(_:),
            validator: looksLikeIngredientCandidate(_:),
            paragraphValidator: looksLikeArticleParagraph(_:),
            maxLineLength: 120
        )
    }

    private static func preferredStepLines(
        from snapshot: WebRecipeImportSnapshot,
        structuredRecipe: StructuredRecipeCandidate?
    ) -> [String] {
        let lineSets = nonEmptyLineSets(
            structuredRecipe?.instructions,
            snapshot.microInstructions,
            snapshot.sectionInstructions
        )
        return firstRecipeLikeLineSet(
            lineSets,
            minimumCount: 2,
            transform: cleanInstructionLine(_:),
            validator: looksLikeInstructionCandidate(_:),
            paragraphValidator: looksLikeArticleParagraph(_:),
            maxLineLength: 240
        )
    }

    private static func extractStructuredRecipe(from rawJSONString: String) -> StructuredRecipeCandidate? {
        guard
            let cleaned = cleanJSONLD(rawJSONString),
            let data = cleaned.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        guard let recipeObject = findRecipeObject(in: object) else {
            return nil
        }

        return StructuredRecipeCandidate(
            title: stringValue(recipeObject["name"]),
            description: stringValue(recipeObject["description"]),
            imageURLString: imageURL(from: recipeObject["image"]),
            yieldText: firstString(from: recipeObject["recipeYield"]),
            prepTimeMinutes: durationInMinutes(from: stringValue(recipeObject["prepTime"])),
            cookTimeMinutes: durationInMinutes(from: stringValue(recipeObject["cookTime"])),
            ingredients: stringArray(from: recipeObject["recipeIngredient"]),
            instructions: instructions(from: recipeObject["recipeInstructions"]),
            nutrition: nutrition(from: recipeObject["nutrition"])
        )
    }

    private static func cleanJSONLD(_ raw: String) -> String? {
        let trimmed = raw
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }

    private static func findRecipeObject(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if isRecipeType(dictionary["@type"]) {
                return dictionary
            }

            if let graph = dictionary["@graph"] as? [Any] {
                for child in graph {
                    if let recipe = findRecipeObject(in: child) {
                        return recipe
                    }
                }
            }

            for value in dictionary.values {
                if let recipe = findRecipeObject(in: value) {
                    return recipe
                }
            }
        }

        if let array = object as? [Any] {
            for item in array {
                if let recipe = findRecipeObject(in: item) {
                    return recipe
                }
            }
        }

        return nil
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let type = value as? String {
            return type.caseInsensitiveCompare("Recipe") == .orderedSame
        }

        if let types = value as? [String] {
            return types.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
        }

        if let types = value as? [Any] {
            return types.compactMap { $0 as? String }
                .contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
        }

        return false
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return cleanedText(string)
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            return stringValue(dictionary["value"]) ??
                stringValue(dictionary["text"]) ??
                stringValue(dictionary["name"])
        case let array as [Any]:
            return array.compactMap(stringValue(_:)).first
        default:
            return nil
        }
    }

    private static func firstString(from value: Any?) -> String? {
        stringValue(value)
    }

    private static func stringArray(from value: Any?) -> [String] {
        switch value {
        case let array as [Any]:
            return array.compactMap(stringValue(_:))
        case let string as String:
            return [string]
        default:
            return []
        }
    }

    private static func imageURL(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return cleanedText(string)
        case let array as [Any]:
            for item in array {
                if let url = imageURL(from: item) {
                    return url
                }
            }
        case let dictionary as [String: Any]:
            return stringValue(dictionary["url"]) ??
                stringValue(dictionary["contentUrl"]) ??
                stringValue(dictionary["thumbnailUrl"])
        default:
            break
        }

        return nil
    }

    private static func instructions(from value: Any?) -> [String] {
        switch value {
        case let string as String:
            return [cleanInstructionLine(string)].filter { !$0.isEmpty }
        case let array as [Any]:
            return array.flatMap(instructions(from:))
        case let dictionary as [String: Any]:
            if let text = stringValue(dictionary["text"]) {
                return [cleanInstructionLine(text)].filter { !$0.isEmpty }
            }

            if let nested = dictionary["itemListElement"] {
                return instructions(from: nested)
            }

            if let name = stringValue(dictionary["name"]) {
                return [cleanInstructionLine(name)].filter { !$0.isEmpty }
            }

            return []
        default:
            return []
        }
    }

    private static func nutrition(from value: Any?) -> StructuredNutrition? {
        guard let dictionary = value as? [String: Any] else { return nil }

        return StructuredNutrition(
            calories: stringValue(dictionary["calories"]),
            protein: stringValue(dictionary["proteinContent"]),
            carbs: stringValue(dictionary["carbohydrateContent"]),
            fat: stringValue(dictionary["fatContent"])
        )
    }

    private static func durationInMinutes(from value: String?) -> Int? {
        guard let value = cleanedText(value)?.uppercased() else { return nil }
        let pattern = #"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?"#

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: value,
                range: NSRange(location: 0, length: value.utf16.count)
            )
        else {
            return nil
        }

        func intValue(at index: Int) -> Int {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return 0 }
            return Int(value[swiftRange]) ?? 0
        }

        let days = intValue(at: 1)
        let hours = intValue(at: 2)
        let minutes = intValue(at: 3)
        let total = (days * 24 * 60) + (hours * 60) + minutes
        return total == 0 ? nil : total
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanIngredientLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*[-•*]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanInstructionLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*(\d+[\).\-\s]+|[-•*]\s*)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseIngredientLine(_ line: String) -> IngredientDraft {
        let cleaned = cleanIngredientLine(line)
        let tokens = cleaned.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return IngredientDraft() }

        if tokens.count == 1 {
            return IngredientDraft(name: cleaned)
        }

        let firstToken = tokens[0]
        let secondToken = tokens.count > 1 ? tokens[1] : ""
        let startsWithQuantity = firstToken.rangeOfCharacter(from: .decimalDigits) != nil

        if startsWithQuantity {
            if tokens.count >= 3 && secondToken.rangeOfCharacter(from: .letters) != nil {
                return IngredientDraft(
                    amount: firstToken,
                    unit: secondToken,
                    name: tokens.dropFirst(2).joined(separator: " ")
                )
            }

            return IngredientDraft(
                amount: firstToken,
                unit: "",
                name: tokens.dropFirst().joined(separator: " ")
            )
        }

        return IngredientDraft(name: cleaned)
    }

    private static func nonEmptyLineSets(_ candidates: [String]?...) -> [[String]] {
        candidates.compactMap { candidate in
            guard let candidate else { return nil }
            let cleaned = candidate
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private static func firstRecipeLikeLineSet(
        _ lineSets: [[String]],
        minimumCount: Int,
        transform: (String) -> String,
        validator: (String) -> Bool,
        paragraphValidator: (String) -> Bool,
        maxLineLength: Int
    ) -> [String] {
        for lineSet in lineSets {
            let cleaned = lineSet
                .map(transform)
                .map(cleanedText(_:))
                .compactMap { $0 }
                .filter { !isNoiseLine($0) }

            let filtered = cleaned.filter { line in
                line.count <= maxLineLength &&
                    !paragraphValidator(line) &&
                    validator(line)
            }

            if filtered.count >= minimumCount {
                return filtered
            }

            if !filtered.isEmpty && filtered.count == cleaned.count {
                return filtered
            }
        }

        return []
    }

    private static func filteredIngredientLines(_ lines: [String]) -> [String] {
        firstRecipeLikeLineSet(
            [lines],
            minimumCount: 3,
            transform: cleanIngredientLine(_:),
            validator: looksLikeIngredientCandidate(_:),
            paragraphValidator: looksLikeArticleParagraph(_:),
            maxLineLength: 120
        )
    }

    private static func filteredInstructionLines(_ lines: [String]) -> [String] {
        firstRecipeLikeLineSet(
            [lines],
            minimumCount: 2,
            transform: cleanInstructionLine(_:),
            validator: looksLikeInstructionCandidate(_:),
            paragraphValidator: looksLikeArticleParagraph(_:),
            maxLineLength: 240
        )
    }

    private static func conservativeFallbackSeed(from summary: RecipePageSummary) -> RecipeEditorSeed? {
        let ingredientLines = filteredIngredientLines(summary.snapshot.sectionIngredients)
        let stepLines = filteredInstructionLines(summary.snapshot.sectionInstructions)

        guard !ingredientLines.isEmpty || !stepLines.isEmpty else {
            return nil
        }

        return RecipeEditorSeed(
            title: summary.title ?? "Recette importee",
            sourceURL: summary.url,
            ingredientDrafts: ingredientLines.map(parseIngredientLine(_:)),
            stepDrafts: stepLines.map { StepDraft(detail: $0) },
            notesText: safeFallbackNotes(from: summary) ?? "",
            remoteImageURL: summary.imageURL
        )
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        let noise = [
            "read more",
            "view post",
            "continue reading",
            "voir plus",
            "newsletter",
            "subscribe",
            "jump to recipe"
        ]

        return noise.contains(normalized)
    }

    private static func looksLikeIngredientCandidate(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }
        guard !normalized.contains("read more"), !normalized.contains("view post") else { return false }

        let tokens = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let quantityRegex = try? NSRegularExpression(pattern: #"(^|\s)(\d+([\/.,]\d+)?|[¼½¾⅓⅔⅛])(\s|$)"#)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let hasQuantity = quantityRegex?.firstMatch(in: normalized, range: range) != nil
        let hasUnit = tokens.contains { token in
            ["g", "kg", "ml", "l", "cup", "cups", "tbsp", "tsp", "cas", "cac", "cl"].contains(token)
        }
        let hasFood = tokens.contains { token in
            [
                "egg", "eggs", "flour", "milk", "sugar", "salt", "butter", "cheese", "chicken",
                "tomato", "tomatoes", "garlic", "onion", "rice", "pasta", "oil", "cream",
                "oeuf", "oeufs", "œuf", "œufs", "farine", "sucre", "sel", "beurre", "fromage",
                "poulet", "tomate", "tomates", "ail", "oignon", "riz", "huile", "creme", "crème"
            ].contains(token)
        }

        return (hasQuantity && (hasUnit || hasFood)) || (hasUnit && hasFood) || (hasFood && tokens.count <= 6)
    }

    private static func looksLikeInstructionCandidate(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        guard !normalized.isEmpty else { return false }
        guard !normalized.contains("read more"), !normalized.contains("view post") else { return false }

        let tokens = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard tokens.count >= 3, tokens.count <= 32 else { return false }

        let verbs: Set<String> = [
            "add", "bake", "blend", "boil", "bring", "chop", "combine", "cook", "heat", "melt",
            "mix", "place", "pour", "preheat", "roast", "season", "serve", "simmer", "stir",
            "toss", "whisk",
            "ajoutez", "chauffez", "coupez", "cuisez", "enfournez", "fouettez", "melangez",
            "mélangez", "placez", "prechauffez", "préchauffez", "servez", "versez"
        ]

        return Array(tokens.prefix(8)).contains(where: verbs.contains(_:)) ||
            tokens.contains(where: verbs.contains(_:))
    }

    private static func looksLikeArticleParagraph(_ line: String) -> Bool {
        let normalized = normalizedPhrase(line)
        let words = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        return words > 24 ||
            line.count > 180 ||
            normalized.contains("celebrity") ||
            normalized.contains("fashion") ||
            normalized.contains("travel") ||
            normalized.contains("newsletter")
    }

    private static func normalizedPhrase(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WebRecipeImportSnapshot: Codable {
    var url: String
    var title: String
    var h1Title: String
    var ogTitle: String
    var ogImage: String
    var description: String
    var socialTitle: String
    var socialDescription: String
    var socialImage: String
    var jsonLD: [String]
    var microIngredients: [String]
    var microInstructions: [String]
    var sectionIngredients: [String]
    var sectionInstructions: [String]

    init(
        url: String,
        title: String,
        h1Title: String,
        ogTitle: String,
        ogImage: String,
        description: String,
        socialTitle: String,
        socialDescription: String,
        socialImage: String,
        jsonLD: [String],
        microIngredients: [String],
        microInstructions: [String],
        sectionIngredients: [String],
        sectionInstructions: [String]
    ) {
        self.url = url
        self.title = title
        self.h1Title = h1Title
        self.ogTitle = ogTitle
        self.ogImage = ogImage
        self.description = description
        self.socialTitle = socialTitle
        self.socialDescription = socialDescription
        self.socialImage = socialImage
        self.jsonLD = jsonLD
        self.microIngredients = microIngredients
        self.microInstructions = microInstructions
        self.sectionIngredients = sectionIngredients
        self.sectionInstructions = sectionInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        h1Title = try container.decode(String.self, forKey: .h1Title)
        ogTitle = try container.decode(String.self, forKey: .ogTitle)
        ogImage = try container.decode(String.self, forKey: .ogImage)
        description = try container.decode(String.self, forKey: .description)
        socialTitle = try container.decodeIfPresent(String.self, forKey: .socialTitle) ?? ""
        socialDescription = try container.decodeIfPresent(String.self, forKey: .socialDescription) ?? ""
        socialImage = try container.decodeIfPresent(String.self, forKey: .socialImage) ?? ""
        jsonLD = try container.decode([String].self, forKey: .jsonLD)
        microIngredients = try container.decode([String].self, forKey: .microIngredients)
        microInstructions = try container.decode([String].self, forKey: .microInstructions)
        sectionIngredients = try container.decode([String].self, forKey: .sectionIngredients)
        sectionInstructions = try container.decode([String].self, forKey: .sectionInstructions)
    }
}

private struct StructuredRecipeCandidate {
    var title: String?
    var description: String?
    var imageURLString: String?
    var yieldText: String?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var ingredients: [String]
    var instructions: [String]
    var nutrition: StructuredNutrition?
}

private struct StructuredNutrition {
    var calories: String?
    var protein: String?
    var carbs: String?
    var fat: String?
}

private struct ExtractedRecipeContent {
    var snapshot: WebRecipeImportSnapshot
    var structuredRecipe: StructuredRecipeCandidate?
    var ingredientLines: [String]
    var stepLines: [String]
}

struct RecipePageSummary {
    var url: URL
    var title: String?
    var description: String?
    var imageURL: URL?
    var textContent: String
    fileprivate var snapshot: WebRecipeImportSnapshot
}

private struct FetchedHTMLPage {
    var url: URL
    var html: String
    var textContent: String
}
