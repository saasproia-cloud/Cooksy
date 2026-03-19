import Foundation

enum CooksyBackendError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case localBackendOnPhysicalDevice
    case timedOut
    case unreachable
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "BACKEND_BASE_URL n'est pas configurée."
        case .invalidResponse:
            return "Le backend Cooksy a renvoyé une réponse invalide."
        case .localBackendOnPhysicalDevice:
            return "BACKEND_BASE_URL pointe vers localhost. Sur iPhone réel, utilisez l'URL Railway du backend."
        case .timedOut:
            return "Cooksy attend trop longtemps le backend. Vérifiez Railway, votre Wi-Fi ou votre réseau mobile."
        case .unreachable:
            return "Impossible de joindre le backend Cooksy. Vérifiez l'URL Railway et que le serveur est bien démarré."
        case .serverError(let message):
            return message
        }
    }
}

enum CooksyBackendService {
    static var isAvailable: Bool {
        AppConfiguration.backendBaseURL != nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        return URLSession(configuration: configuration)
    }()

    static func importURL(_ url: URL, sharedText: String? = nil) async throws -> RecipeEditorSeed {
        let requestBody = URLImportRequest(
            url: url.absoluteString,
            sharedText: nonEmpty(sharedText)
        )

        let envelope: RecipeImportEnvelope = try await sendJSON(
            path: "/api/import/url",
            requestBody: requestBody
        )
        return envelope.recipe.asSeed()
    }

    static func importText(_ text: String, imageData: Data? = nil) async throws -> RecipeEditorSeed {
        let requestBody = TextImportRequest(
            text: text,
            imageBase64: imageData?.base64EncodedString()
        )

        let envelope: RecipeImportEnvelope = try await sendJSON(
            path: "/api/import/text",
            requestBody: requestBody
        )
        return envelope.recipe.asSeed()
    }

    static func importPhoto(_ imageData: Data) async throws -> RecipeEditorSeed {
        let boundary = "CooksyBoundary-\(UUID().uuidString)"
        let request = try makeRequest(
            path: "/api/import/photo",
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)"
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
        var seed = envelope.recipe.asSeed()
        seed.imageData = seed.imageData ?? imageData
        return seed
    }

    static func enrichShoppingItems(_ items: [ShoppingItem]) async throws -> [ShoppingItem.ID: URL] {
        let payload = ShoppingImageRequestEnvelope(
            items: items.map { item in
                ShoppingImageRequest(
                    id: item.id.uuidString,
                    article: item.article,
                    category: item.category.rawValue
                )
            }
        )

        let response: ShoppingImageResponseEnvelope = try await sendJSON(
            path: "/api/shopping/enrich",
            requestBody: payload
        )

        return Dictionary(
            uniqueKeysWithValues: response.items.compactMap { item in
                guard
                    let id = UUID(uuidString: item.id),
                    let imageURL = item.imageURL
                else {
                    return nil
                }

                return (id, imageURL)
            }
        )
    }

    private static func sendJSON<Request: Encodable, Response: Decodable>(
        path: String,
        requestBody: Request
    ) async throws -> Response {
        var request = try makeRequest(path: path)
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
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw CooksyBackendError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw CooksyBackendError.unreachable
            default:
                throw CooksyBackendError.serverError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CooksyBackendError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
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
        path: String,
        method: String = "POST",
        contentType: String = "application/json"
    ) throws -> URLRequest {
        guard let baseURL = AppConfiguration.backendBaseURL else {
            throw CooksyBackendError.missingBaseURL
        }

        if isRunningOnPhysicalDevice, isLocalDevelopmentHost(baseURL.host) {
            throw CooksyBackendError.localBackendOnPhysicalDevice
        }

        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: normalizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

private struct URLImportRequest: Encodable {
    let url: String
    let sharedText: String?
}

private struct TextImportRequest: Encodable {
    let text: String
    let imageBase64: String?
}

private struct ShoppingImageRequestEnvelope: Encodable {
    let items: [ShoppingImageRequest]
}

private struct ShoppingImageRequest: Encodable {
    let id: String
    let article: String
    let category: String
}

private struct RecipeImportEnvelope: Decodable {
    let recipe: BackendRecipeSeed
}

private struct BackendRecipeSeed: Decodable {
    let title: String
    let sourceUrl: String
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

    func asSeed() -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: title,
            sourceURL: urlIfPresent(sourceUrl),
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
            remoteImageURL: urlIfPresent(remoteImageUrl)
        )
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

private struct ShoppingImageResponseEnvelope: Decodable {
    let items: [ShoppingImageResponseItem]
}

private struct ShoppingImageResponseItem: Decodable {
    let id: String
    let imageUrl: String?

    var imageURL: URL? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        return URL(string: imageUrl)
    }
}

private struct BackendErrorEnvelope: Decodable {
    let error: String?
    let message: String?
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
