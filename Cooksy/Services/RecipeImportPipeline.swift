import Foundation

enum RecipeImportPipelineError: LocalizedError {
    case emptyImport
    case noUsableRecipe

    var errorDescription: String? {
        switch self {
        case .emptyImport:
            return "Cooksy n'a rien recu a importer."
        case .noUsableRecipe:
            return "Cooksy n'a pas pu reconstituer une recette exploitable a partir de ce contenu."
        }
    }
}

enum RecipeImportPipeline {
    static func importPhoto(from imageData: Data) async -> RecipeEditorSeed {
        if let backendSeed = try? await CooksyBackendService.importPhoto(imageData),
           shouldUseImportedSeed(backendSeed, sourceKind: .photo) {
            var seed = backendSeed
            seed.imageData = seed.imageData ?? imageData
            return seed
        }

        async let recognizedTextTask = RecipeOCRService.recognizeText(from: imageData)
        async let detectedIngredientsTask = IngredientPhotoClassifierService.classifyIngredients(from: imageData)

        let recognizedText = (try? await recognizedTextTask) ?? ""
        let detectedIngredients = await detectedIngredientsTask
        var seed = RecipeTextParser.parse(recognizedText, imageData: imageData)

        if seed.normalizedTitle.isEmpty {
            seed.title = detectedIngredients.first.map { "Recette à base de \($0)" } ?? "Recette depuis une photo"
        }

        if !isMeaningful(seed) {
            seed.notesText = recognizedText
        }

        mergeDetectedIngredients(detectedIngredients, into: &seed)
        seed.imageData = imageData
        return seed
    }

    static func importText(_ text: String, imageData: Data? = nil) async -> RecipeEditorSeed {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedText.isEmpty,
           let backendSeed = try? await CooksyBackendService.importText(trimmedText, imageData: imageData),
           shouldUseImportedSeed(backendSeed, sourceKind: .text) {
            var seed = backendSeed
            seed.imageData = seed.imageData ?? imageData
            return seed
        }

        var seed = RecipeTextParser.parse(trimmedText, imageData: imageData)

        if seed.normalizedTitle.isEmpty {
            seed.title = "Recette importée"
        }

        if !isMeaningful(seed), let imageData {
            let imageSeed = await importPhoto(from: imageData)
            seed = chooseBetterSeed(imageSeed, over: seed)
            if seed.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                seed.notesText = trimmedText
            }
        }

        seed.imageData = seed.imageData ?? imageData
        return seed
    }

    static func importSharedDraft(_ draft: SharedImportDraft) async throws -> RecipeEditorSeed {
        guard draft.hasPayload else {
            throw RecipeImportPipelineError.emptyImport
        }

        let sharedImageData = SharedLinkInbox().imageData(for: draft.sharedImageFilename)

        if let url = draft.url {
            var seed = try await importURL(url, sharedText: draft.sharedText)
            if seed.imageData == nil {
                seed.imageData = sharedImageData
            }
            return seed
        }

        if let sharedText = draft.sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), !sharedText.isEmpty {
            return await importText(sharedText, imageData: sharedImageData)
        }

        if let sharedImageData {
            return await importPhoto(from: sharedImageData)
        }

        throw RecipeImportPipelineError.emptyImport
    }

    static func importURL(_ url: URL?, sharedText: String? = nil) async throws -> RecipeEditorSeed {
        let isSocialImport = url.map(isSocialImportURL) ?? false
        var backendError: Error?

        if let url {
            do {
                let backendSeed = try await CooksyBackendService.importURL(url, sharedText: sharedText)
                if shouldUseImportedSeed(backendSeed, sourceKind: .url) {
                    return backendSeed
                }
            } catch {
                backendError = error
            }
        }

        var pageSummary: RecipePageSummary?
        var bestSeed: RecipeEditorSeed?

        if let url {
            pageSummary = try? await RecipeWebImportService.fetchPageSummary(from: url)
            bestSeed = try? await RecipeWebImportService.importRecipe(from: url)
        }

        if let parsedTextSeed = parsedTextSeed(sharedText: sharedText, pageSummary: pageSummary) {
            bestSeed = chooseBetterSeed(parsedTextSeed, over: bestSeed)
        }

        if let strongSeed = bestSeed, isMeaningful(strongSeed) {
            return merged(strongSeed, pageSummary: pageSummary, sharedText: sharedText)
        }

        if let query = bestSearchQuery(sharedText: sharedText, pageSummary: pageSummary, seed: bestSeed) {
            for candidateURL in (try? await RecipeSearchFallbackService.search(query: query)) ?? [] {
                if let importedSeed = try? await RecipeWebImportService.importRecipe(from: candidateURL) {
                    return merged(importedSeed, pageSummary: pageSummary, sharedText: sharedText)
                }
            }
        }

        if let bestSeed, shouldUseImportedSeed(bestSeed, sourceKind: .url) {
            return merged(bestSeed, pageSummary: pageSummary, sharedText: sharedText)
        }

        if isSocialImport, let backendError {
            throw backendError
        }

        if isSocialImport {
            throw RecipeImportPipelineError.noUsableRecipe
        }

        if let pageSummary {
            return fallbackSeed(from: pageSummary, sharedText: sharedText)
        }

        if let sharedText, !sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let seed = RecipeTextParser.parse(sharedText)
            if isMeaningful(seed) || !seed.normalizedTitle.isEmpty {
                return seed
            }
        }

        throw RecipeImportPipelineError.noUsableRecipe
    }

    private static func parsedTextSeed(sharedText: String?, pageSummary: RecipePageSummary?) -> RecipeEditorSeed? {
        let textBlob = [
            sharedText?.trimmingCharacters(in: .whitespacesAndNewlines),
            pageSummary?.description,
            pageSummary?.textContent
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n\n")

        guard !textBlob.isEmpty else { return nil }

        var seed = RecipeTextParser.parse(textBlob)
        if seed.normalizedTitle.isEmpty {
            seed.title = pageSummary?.title ?? ""
        }
        seed.sourceURL = pageSummary?.url
        seed.remoteImageURL = pageSummary?.imageURL
        return seed
    }

    private static func merged(
        _ seed: RecipeEditorSeed,
        pageSummary: RecipePageSummary?,
        sharedText: String?
    ) -> RecipeEditorSeed {
        var mergedSeed = seed

        if mergedSeed.normalizedTitle.isEmpty {
            mergedSeed.title = pageSummary?.title ?? "Recette importee"
        }

        if mergedSeed.sourceURL == nil {
            mergedSeed.sourceURL = pageSummary?.url
        }

        if mergedSeed.remoteImageURL == nil {
            mergedSeed.remoteImageURL = pageSummary?.imageURL
        }

        if mergedSeed.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergedSeed.notesText = [
                sharedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                pageSummary?.description
            ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")
        }

        return mergedSeed
    }

    private static func fallbackSeed(from summary: RecipePageSummary, sharedText: String?) -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: summary.title ?? "Recette importee",
            sourceURL: summary.url,
            notesText: [
                sharedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                summary.description,
                summary.textContent
            ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return String(value.prefix(1800))
            }
            .joined(separator: "\n\n"),
            remoteImageURL: summary.imageURL
        )
    }

    private static func chooseBetterSeed(_ lhs: RecipeEditorSeed, over rhs: RecipeEditorSeed?) -> RecipeEditorSeed {
        guard let rhs else { return lhs }
        return score(lhs) >= score(rhs) ? lhs : rhs
    }

    private static func bestSearchQuery(
        sharedText: String?,
        pageSummary: RecipePageSummary?,
        seed: RecipeEditorSeed?
    ) -> String? {
        let titleCandidate = [
            seed?.normalizedTitle.nilIfEmpty,
            socialFriendlySearchCandidate(from: sharedText),
            socialFriendlySearchCandidate(from: pageSummary?.description),
            socialFriendlySearchCandidate(from: pageSummary?.title),
            cleanedSearchCandidate(from: sharedText)
        ]
        .compactMap { $0 }
        .first

        guard let titleCandidate, !titleCandidate.isEmpty else { return nil }
        return "\(titleCandidate) recette"
    }

    private static func cleanedSearchCandidate(from text: String?) -> String? {
        guard let text else { return nil }

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("http://") || lowercased.contains("https://") { continue }
            if lowercased.hasPrefix("#") { continue }
            if lowercased.contains("tiktok") || lowercased.contains("instagram") { continue }
            return String(line.prefix(120))
        }

        return nil
    }

    private static func socialFriendlySearchCandidate(from text: String?) -> String? {
        guard let text else { return nil }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: "#[\\p{L}0-9_]+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "@[\\p{L}0-9_\\.]+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lowercased = line.lowercased()
                return !lowercased.contains("original sound") &&
                    !lowercased.contains("watch more") &&
                    !lowercased.contains("instagram") &&
                    !lowercased.contains("tiktok")
            }

        for line in normalized {
            if RecipeTextParser.parse(line).normalizedTitle.isEmpty == false {
                return String(line.prefix(110))
            }
        }

        return normalized.first.map { String($0.prefix(110)) }
    }

    private static func score(_ seed: RecipeEditorSeed) -> Int {
        let titleScore = seed.normalizedTitle.isEmpty ? 0 : 3
        let ingredientScore = min(seed.normalizedIngredients.count, 12) * 4
        let stepScore = min(seed.normalizedSteps.count, 12) * 5
        let noteScore = seed.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        return titleScore + ingredientScore + stepScore + noteScore
    }

    private static func isMeaningful(_ seed: RecipeEditorSeed) -> Bool {
        let ingredientCount = seed.normalizedIngredients.count
        let stepCount = seed.normalizedSteps.count
        return ingredientCount >= 2 || stepCount >= 2 || (ingredientCount >= 1 && stepCount >= 1)
    }

    private enum ImportedSeedSourceKind {
        case url
        case text
        case photo
    }

    private static func shouldUseImportedSeed(
        _ seed: RecipeEditorSeed,
        sourceKind: ImportedSeedSourceKind
    ) -> Bool {
        if isMeaningful(seed) {
            return true
        }

        let hasPartialRecipe = !seed.normalizedIngredients.isEmpty || !seed.normalizedSteps.isEmpty
        if hasPartialRecipe {
            return true
        }

        switch sourceKind {
        case .url, .photo:
            return false
        case .text:
            return !seed.normalizedTitle.isEmpty && seed.imageData != nil
        }
    }

    private static func isSocialImportURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("tiktok") || host.contains("instagram") || host.contains("pinterest") || host.contains("pin.it")
    }

    private static func mergeDetectedIngredients(_ detectedIngredients: [String], into seed: inout RecipeEditorSeed) {
        guard !detectedIngredients.isEmpty else { return }

        let existingNames = Set(
            seed.normalizedIngredients.map {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            }
        )

        let missingIngredients = detectedIngredients.filter { candidate in
            let normalized = candidate.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return !existingNames.contains(normalized)
        }

        guard !missingIngredients.isEmpty else { return }

        seed.ingredientDrafts.append(contentsOf: missingIngredients.map { IngredientDraft(name: $0) })

        if seed.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            seed.notesText = "Ingrédients détectés visuellement depuis la photo."
        }
    }
}

private enum RecipeSearchFallbackService {
    static func search(query: String) async throws -> [URL] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encodedQuery)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("fr-FR,fr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 400).contains(httpResponse.statusCode) {
            return []
        }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let hrefs = matches(
            pattern: #"<a[^>]+class="result__a"[^>]+href="([^"]+)""#,
            in: html,
            options: [.caseInsensitive]
        )

        var urls: [URL] = []
        var seen = Set<String>()

        for href in hrefs {
            guard let resolvedURL = resolvedSearchURL(from: href) else { continue }
            let key = resolvedURL.absoluteString
            if seen.insert(key).inserted {
                urls.append(resolvedURL)
            }
            if urls.count == 5 {
                break
            }
        }

        return urls
    }

    private static func resolvedSearchURL(from href: String) -> URL? {
        let normalizedHref = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let components = URLComponents(string: normalizedHref),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let directURL = URL(string: uddg) {
            return directURL
        }

        return URL(string: normalizedHref)
    }

    private static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return String(text[swiftRange])
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
