import Foundation
import OSLog

enum CooksyBackendError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL(String)
    case invalidRequestURL(String)
    case invalidResponse
    case localBackendOnPhysicalDevice
    case notFood
    case timedOut
    case unreachable
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return AppConfiguration.backendBaseURLValidationError ?? "BACKEND_BASE_URL n'est pas configurée."
        case .invalidBaseURL(let message):
            return message
        case .invalidRequestURL(let message):
            return message
        case .invalidResponse:
            return "Le backend Cooksy a renvoyé une réponse invalide."
        case .localBackendOnPhysicalDevice:
            return "BACKEND_BASE_URL pointe vers localhost. Sur iPhone réel, utilisez l'URL Railway du backend."
        case .notFood:
            return "Ce contenu partagé ne semble pas montrer un plat ou une recette."
        case .timedOut:
            return "Cooksy attend trop longtemps le backend. Vérifiez Railway, votre Wi-Fi ou votre réseau mobile."
        case .unreachable:
            return "Impossible de joindre le backend Cooksy. Vérifiez l'URL Railway et que le serveur est bien démarré."
        case .serverError(let message):
            return message
        }
    }
}

private enum CooksyBackendEndpoint: String {
    case health = "/health"
    case importURL = "/api/import/url"
    case importText = "/api/import/text"
    case importPhoto = "/api/import/photo"
    case shoppingEnrich = "/api/shopping/enrich"
}

enum CooksyBackendService {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "CooksyBackendService")

    static var isAvailable: Bool {
        AppConfiguration.backendBaseURL != nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    static func healthCheck() async throws -> BackendHealthEnvelope {
        let request = try makeRequest(
            endpoint: .health,
            method: "GET",
            contentType: nil,
            timeoutInterval: 20
        )
        return try await send(request, as: BackendHealthEnvelope.self)
    }

    static func importURL(
        _ url: URL,
        sharedText: String? = nil,
        previewMode: Bool = false,
        sharedMode: Bool = false
    ) async throws -> RecipeEditorSeed {
        let requestBody = URLImportRequest(
            url: encodedAbsoluteString(for: url),
            sharedText: nonEmpty(sharedText),
            previewMode: previewMode,
            sharedMode: sharedMode
        )

        let envelope: URLImportEnvelope = try await sendJSON(
            endpoint: .importURL,
            requestBody: requestBody,
            timeoutInterval: importRequestTimeout(previewMode: previewMode, sharedMode: sharedMode)
        )
        guard envelope.success, let seed = envelope.asSeed() else {
            throw CooksyBackendError.serverError(envelope.error ?? "Impossible de générer la recette")
        }

        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        return seed
    }

    static func importText(
        _ text: String,
        imageData: Data? = nil,
        previewMode: Bool = false,
        sharedMode: Bool = false
    ) async throws -> RecipeEditorSeed {
        let requestBody = TextImportRequest(
            text: text,
            imageBase64: imageData?.base64EncodedString(),
            previewMode: previewMode,
            sharedMode: sharedMode
        )

        let envelope: RecipeImportEnvelope = try await sendJSON(
            endpoint: .importText,
            requestBody: requestBody,
            timeoutInterval: importRequestTimeout(previewMode: previewMode, sharedMode: sharedMode)
        )
        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        return envelope.recipe.asSeed(debug: debug)
    }

    static func importPhoto(_ imageData: Data) async throws -> RecipeEditorSeed {
        let boundary = "CooksyBoundary-\(UUID().uuidString)"
        let request = try makeRequest(
            endpoint: .importPhoto,
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeoutInterval: 90
        )

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")

        var uploadRequest = request
        uploadRequest.httpBody = body

        let envelope: RecipeImportEnvelope = try await send(uploadRequest, as: RecipeImportEnvelope.self)
        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        var seed = envelope.recipe.asSeed(debug: debug)
        seed.imageData = seed.imageData ?? imageData
        return seed
    }

    static func enrichIngredientPhotos(
        _ items: [IngredientPhotoEnrichmentRequestItem]
    ) async throws -> [IngredientPhotoEnrichmentResponseItem] {
        guard !items.isEmpty else { return [] }

        let requestBody = ShoppingEnrichRequest(
            items: items.map { item in
                ShoppingEnrichRequest.Item(
                    id: item.id,
                    article: item.article,
                    category: item.category
                )
            }
        )

        let response: ShoppingEnrichResponse = try await sendJSON(
            endpoint: .shoppingEnrich,
            requestBody: requestBody,
            timeoutInterval: 20
        )

        return response.items.map { item in
            IngredientPhotoEnrichmentResponseItem(
                id: item.id,
                imageURL: urlIfPresent(item.imageUrl ?? ""),
                sourcePageURL: urlIfPresent(item.sourcePageUrl ?? "")
            )
        }
    }

    private static func sendJSON<Request: Encodable, Response: Decodable>(
        endpoint: CooksyBackendEndpoint,
        requestBody: Request,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        var request = try makeRequest(endpoint: endpoint, timeoutInterval: timeoutInterval)
        request.httpBody = try JSONEncoder().encode(requestBody)
        return try await send(request, as: Response.self)
    }

    private static func send<Response: Decodable>(
        _ request: URLRequest,
        as _: Response.Type
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            let requestStartedAt = Date()
            if let urlString = request.url?.absoluteString {
                logger.debug(
                    "Backend request start t=\(requestStartedAt.timeIntervalSince1970, privacy: .public) url=\(urlString, privacy: .public)"
                )
            } else {
                logger.error("Attempted backend request with nil URL.")
            }
            (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            logger.debug("Backend response received in \(durationMs)ms")
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw CooksyBackendError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw CooksyBackendError.unreachable
            case .badURL, .unsupportedURL:
                let urlString = request.url?.absoluteString ?? "(nil)"
                throw CooksyBackendError.invalidRequestURL("L'URL finale du backend est invalide: \(urlString)")
            default:
                throw CooksyBackendError.serverError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CooksyBackendError.invalidResponse
        }

        let responseURLString = httpResponse.url?.absoluteString ?? request.url?.absoluteString ?? "(nil)"
        logger.debug(
            "Backend response \(httpResponse.statusCode) from \(responseURLString, privacy: .public)"
        )

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if !data.isEmpty {
                let responseBody = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                logger.error(
                    "Backend error payload for \(responseURLString, privacy: .public): \(String(responseBody.prefix(500)), privacy: .public)"
                )
            }

            if
                let backendError = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data),
                backendError.error == "not_food",
                backendError.reason == "no_food_detected"
            {
                throw CooksyBackendError.notFood
            }

            if
                let backendError = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data),
                let message = nonEmpty(backendError.message) ?? nonEmpty(backendError.error)
            {
                throw CooksyBackendError.serverError(message)
            }

            throw CooksyBackendError.serverError("Le backend Cooksy a échoué (\(httpResponse.statusCode)).")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CooksyBackendError.invalidResponse
        }
    }

    private static func makeRequest(
        endpoint: CooksyBackendEndpoint,
        method: String = "POST",
        contentType: String? = "application/json",
        timeoutInterval: TimeInterval? = nil
    ) throws -> URLRequest {
        guard let baseURL = AppConfiguration.backendBaseURL else {
            throw CooksyBackendError.invalidBaseURL(
                AppConfiguration.backendBaseURLValidationError ?? "BACKEND_BASE_URL n'est pas configurée."
            )
        }

        if isRunningOnPhysicalDevice, isLocalDevelopmentHost(baseURL.host) {
            throw CooksyBackendError.localBackendOnPhysicalDevice
        }

        let url = try buildURL(baseURL: baseURL, endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func importRequestTimeout(
        previewMode: Bool,
        sharedMode: Bool
    ) -> TimeInterval {
        if sharedMode {
            return 110
        }

        if previewMode {
            return 45
        }

        return 90
    }

    private static func buildURL(baseURL: URL, endpoint: CooksyBackendEndpoint) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CooksyBackendError.invalidBaseURL(
                "BACKEND_BASE_URL est mal formée: \(AppConfiguration.backendBaseURLDebugValue ?? baseURL.absoluteString)"
            )
        }

        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            throw CooksyBackendError.invalidBaseURL("BACKEND_BASE_URL doit inclure un schéma valide.")
        }

        if isRunningOnPhysicalDevice, scheme != "https" {
            throw CooksyBackendError.invalidBaseURL("BACKEND_BASE_URL doit commencer par https:// sur iPhone réel.")
        }

        let basePath = components.percentEncodedPath
        components.percentEncodedPath = joinedPath(basePath: basePath, endpointPath: endpoint.rawValue)

        guard let url = components.url else {
            throw CooksyBackendError.invalidRequestURL(
                "Impossible de construire une URL valide pour \(endpoint.rawValue) depuis \(baseURL.absoluteString)"
            )
        }

        return url
    }

    private static func joinedPath(basePath: String, endpointPath: String) -> String {
        let trimmedBasePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedEndpointPath = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmedBasePath.isEmpty {
            return "/\(trimmedEndpointPath)"
        }

        return "/\(trimmedBasePath)/\(trimmedEndpointPath)"
    }

    private static func encodedAbsoluteString(for url: URL) -> String {
        if let normalizedURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url {
            return normalizedURL.absoluteString
        }

        return url.absoluteString
    }

    private static func logBackendDebug(_ debug: RecipeImportDebugInfo?) {
        guard let debug else { return }
        let missing = debug.missing.joined(separator: ",")
        let failureReason = debug.failureReason ?? "none"
        let message = [
            "Backend import debug",
            "strategy=\(debug.strategy)",
            "ingredients=\(debug.ingredientsCount)",
            "steps=\(debug.stepsCount)",
            "duration=\(debug.durationMs)ms",
            "valid=\(debug.isLikelyValid)",
            "missing=\(missing)",
            "failureReason=\(failureReason)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }
}

private struct URLImportRequest: Encodable {
    let url: String
    let sharedText: String?
    let previewMode: Bool?
    let sharedMode: Bool?
}

private struct TextImportRequest: Encodable {
    let text: String
    let imageBase64: String?
    let previewMode: Bool?
    let sharedMode: Bool?
}

struct IngredientPhotoEnrichmentRequestItem: Hashable {
    let id: String
    let article: String
    let category: String?
}

struct IngredientPhotoEnrichmentResponseItem: Hashable {
    let id: String
    let imageURL: URL?
    let sourcePageURL: URL?
}

private struct ShoppingEnrichRequest: Encodable {
    let items: [Item]

    struct Item: Encodable {
        let id: String
        let article: String
        let category: String?
    }
}

private struct ShoppingEnrichResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let imageUrl: String?
        let sourcePageUrl: String?
    }
}

private struct RecipeImportEnvelope: Decodable {
    let recipe: BackendRecipeSeed
    let debug: BackendRecipeImportDebug?
}

private struct URLImportEnvelope: Decodable {
    let success: Bool
    let data: BackendStableRecipeSeed?
    let debug: BackendRecipeImportDebug?
    let error: String?
    let legacyRecipe: BackendRecipeSeed?

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case debug
        case error
        case recipe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.success) {
            success = try container.decode(Bool.self, forKey: .success)
            data = try container.decodeIfPresent(BackendStableRecipeSeed.self, forKey: .data)
            debug = try container.decodeIfPresent(BackendRecipeImportDebug.self, forKey: .debug)
            error = try container.decodeIfPresent(String.self, forKey: .error)
            legacyRecipe = nil
            return
        }

        success = true
        data = nil
        debug = try container.decodeIfPresent(BackendRecipeImportDebug.self, forKey: .debug)
        error = nil
        legacyRecipe = try container.decode(BackendRecipeSeed.self, forKey: .recipe)
    }

    func asSeed() -> RecipeEditorSeed? {
        if let data {
            return data.asSeed()
        }

        if let legacyRecipe {
            return legacyRecipe.asSeed(debug: debug?.asImportDebug())
        }

        return nil
    }
}

private struct BackendRecipeSeed: Decodable {
    let title: String
    let sourceUrl: String
    let creatorHandle: String?
    let externalRating: Double?
    let externalRatingCount: Int?
    let remoteImageUrl: String
    let ingredientDrafts: [BackendIngredientDraft]
    let stepDrafts: [BackendStepDraft]
    let notesText: String
    let prepTimeText: String
    let cookTimeText: String
    let servingsText: String
    let caloriesText: String
    let proteinText: String
    let carbsText: String
    let fatText: String

    func asSeed(debug: RecipeImportDebugInfo?) -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: title,
            sourceURL: urlIfPresent(sourceUrl),
            creatorHandle: nonEmpty(creatorHandle),
            externalRating: externalRating,
            externalRatingCount: externalRatingCount,
            ingredientDrafts: ingredientDrafts.map { $0.asDraft() },
            stepDrafts: stepDrafts.map { $0.asDraft() },
            notesText: notesText,
            prepTimeText: prepTimeText,
            cookTimeText: cookTimeText,
            servingsText: servingsText,
            caloriesText: caloriesText,
            proteinText: proteinText,
            carbsText: carbsText,
            fatText: fatText,
            remoteImageURL: urlIfPresent(remoteImageUrl),
            importDebug: debug
        )
    }
}

private struct BackendStableRecipeSeed: Decodable {
    let title: String
    let ingredients: [BackendStableIngredient]
    let steps: [BackendStableStep]
    let nutrition: BackendStableNutrition
    let image: String
    let sourceUrl: String
    let creatorHandle: String?
    let externalRating: Double?
    let externalRatingCount: Int?

    func asSeed() -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: title,
            sourceURL: urlIfPresent(sourceUrl),
            creatorHandle: nonEmpty(creatorHandle),
            externalRating: externalRating,
            externalRatingCount: externalRatingCount,
            ingredientDrafts: ingredients.map { $0.asDraft() },
            stepDrafts: steps.map { $0.asDraft() },
            notesText: "",
            prepTimeText: "",
            cookTimeText: "",
            servingsText: "",
            caloriesText: BackendStableNutrition.formatCalories(nutrition.calories),
            proteinText: BackendStableNutrition.formatMacro(nutrition.protein),
            carbsText: BackendStableNutrition.formatMacro(nutrition.carbs),
            fatText: BackendStableNutrition.formatMacro(nutrition.fat),
            remoteImageURL: urlIfPresent(image),
            importDebug: nil
        )
    }
}

private struct BackendRecipeImportDebug: Decodable {
    let ingredientsCount: Int
    let stepsCount: Int
    let strategy: String
    let durationMs: Int
    let isLikelyValid: Bool
    let missing: [String]
    let failureReason: String?

    func asImportDebug() -> RecipeImportDebugInfo {
        RecipeImportDebugInfo(
            ingredientsCount: ingredientsCount,
            stepsCount: stepsCount,
            strategy: strategy,
            durationMs: durationMs,
            isLikelyValid: isLikelyValid,
            missing: missing,
            failureReason: failureReason
        )
    }
}

private struct BackendStableIngredient: Decodable {
    let name: String
    let quantity: String
    let unit: String

    func asDraft() -> IngredientDraft {
        IngredientDraft(amount: quantity, unit: unit, name: name)
    }
}

private struct BackendStableStep: Decodable {
    let stepNumber: Int
    let description: String

    func asDraft() -> StepDraft {
        StepDraft(detail: description)
    }
}

private struct BackendStableNutrition: Decodable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    static func formatCalories(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    static func formatMacro(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) g"
        }

        return "\(rounded.formatted(.number.precision(.fractionLength(1)))) g"
    }
}

private struct BackendIngredientDraft: Decodable {
    let amount: String
    let unit: String
    let name: String

    func asDraft() -> IngredientDraft {
        IngredientDraft(amount: amount, unit: unit, name: name)
    }
}

private struct BackendStepDraft: Decodable {
    let detail: String

    func asDraft() -> StepDraft {
        StepDraft(detail: detail)
    }
}

struct BackendHealthEnvelope: Decodable {
    let status: String
    let env: String?
}

private struct BackendErrorEnvelope: Decodable {
    let error: String?
    let message: String?
    let reason: String?
}

private func urlIfPresent(_ string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(string: trimmed)
}

private func nonEmpty(_ string: String?) -> String? {
    guard let string else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private var isRunningOnPhysicalDevice: Bool {
#if targetEnvironment(simulator)
    false
#else
    true
#endif
}

private func isLocalDevelopmentHost(_ host: String?) -> Bool {
    guard let host else { return false }
    let normalized = host.lowercased()
    return normalized == "localhost" ||
        normalized == "127.0.0.1" ||
        normalized == "0.0.0.0"
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
