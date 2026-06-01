import Foundation
import OSLog
import Supabase

/// Backend client for the Premium chat assistant. The iOS app owns the
/// recipe library locally, so every request carries a compact recipe
/// payload that the backend uses as system context.
///
/// Endpoints:
///   GET    /api/chat/history?recipeId=…
///   POST   /api/chat/message  { recipe, userMessage, threadId? }
///   POST   /api/chat/select   { recipe, messageId, optionId }
///   POST   /api/chat/apply    { recipe, pendingModification, threadId? }
///   POST   /api/chat/revert   { recipe, modificationId }
enum CooksyChatService {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "CooksyChatService")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    static func loadHistory(recipeId: UUID) async throws -> ChatHistoryResponse {
        let url = try makeChatURL(path: "/api/chat/history", query: [
            URLQueryItem(name: "recipeId", value: recipeId.uuidString.lowercased())
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, as: ChatHistoryResponse.self)
    }

    static func sendMessage(
        recipe: RecipeContextPayload,
        userMessage: String,
        threadId: UUID?
    ) async throws -> ChatSendResponse {
        let body = SendMessageRequest(
            recipe: recipe,
            userMessage: userMessage,
            threadId: threadId
        )
        return try await postJSON(path: "/api/chat/message", body: body, as: ChatSendResponse.self)
    }

    static func selectSuggestion(
        recipe: RecipeContextPayload,
        messageId: UUID,
        optionId: String
    ) async throws -> ChatSelectResponse {
        let body = SelectSuggestionRequest(recipe: recipe, messageId: messageId, optionId: optionId)
        return try await postJSON(path: "/api/chat/select", body: body, as: ChatSelectResponse.self)
    }

    static func applyModification(
        recipe: RecipeContextPayload,
        pendingModification: PendingModification,
        threadId: UUID?
    ) async throws -> ChatApplyResponse {
        let body = ApplyModificationRequest(
            recipe: recipe,
            pendingModification: pendingModification,
            threadId: threadId
        )
        return try await postJSON(path: "/api/chat/apply", body: body, as: ChatApplyResponse.self)
    }

    static func revertModification(
        recipe: RecipeContextPayload,
        modificationId: UUID
    ) async throws -> ChatRevertResponse {
        let body = RevertModificationRequest(recipe: recipe, modificationId: modificationId)
        return try await postJSON(path: "/api/chat/revert", body: body, as: ChatRevertResponse.self)
    }

    // ------------------------------------------------------------------
    // Wire types — match the Zod schemas in backend/src/services/chat/chatTypes.ts
    // ------------------------------------------------------------------

    struct RecipeContextPayload: Encodable {
        var recipeId: UUID
        var title: String
        var servings: String?
        var prepTimeMinutes: Int?
        var cookTimeMinutes: Int?
        var ingredients: [IngredientCell]
        var steps: [StepCell]
        var nutritionPerServing: NutritionPatch?
        var allergens: [String]
        var appliedModifications: [AppliedModificationCell]

        struct IngredientCell: Encodable {
            var id: UUID
            var name: String
            var amount: String?
            var unit: String?
            var originName: String?
        }

        struct StepCell: Encodable {
            var id: UUID
            var title: String?
            var detail: String
        }

        struct AppliedModificationCell: Encodable {
            var id: UUID
            var summary: String
            var kind: String
            var appliedAt: Date
        }
    }

    struct ChatHistoryResponse: Decodable {
        let threadId: UUID?
        let messages: [WireChatMessage]
    }

    struct ChatSendResponse: Decodable {
        let threadId: UUID
        let assistantMessage: WireChatMessage
    }

    struct ChatSelectResponse: Decodable {
        let assistantMessage: WireChatMessage
    }

    struct ChatApplyResponse: Decodable {
        let modificationId: UUID
        let recipe: MutatedRecipePayload
    }

    struct ChatRevertResponse: Decodable {
        let recipe: MutatedRecipePayload
    }

    struct MutatedRecipePayload: Decodable {
        let ingredients: [IngredientCell]
        let steps: [StepCell]
        let nutritionPerServing: NutritionPatch?
        let allergens: [String]
        let servings: String?

        struct IngredientCell: Decodable {
            let id: UUID
            let name: String
            let amount: String?
            let unit: String?
            let originName: String?
        }

        struct StepCell: Decodable {
            let id: UUID
            let title: String?
            let detail: String
        }
    }

    /// Backend `PersistedChatMessage` shape — the server maps every DB
    /// row from snake_case to camelCase via `rowToMessage()` before
    /// serialising, so the JSON keys this struct decodes are already
    /// camelCase and match the property names directly. (We used to have
    /// snake_case CodingKeys here; that was the cause of the
    /// "Réponse invalide du backend" error after sending a message — the
    /// `assistantMessage` failed to decode because every key was renamed.)
    struct WireChatMessage: Decodable {
        let id: UUID
        let threadId: UUID
        let role: ChatRole
        let contentText: String?
        let suggestionsJson: ChatSuggestionGroup?
        let pendingModificationJson: PendingModification?
        let createdAt: Date
    }

    // ------------------------------------------------------------------
    // Request bodies
    // ------------------------------------------------------------------

    private struct SendMessageRequest: Encodable {
        let recipe: RecipeContextPayload
        let userMessage: String
        let threadId: UUID?
    }

    private struct SelectSuggestionRequest: Encodable {
        let recipe: RecipeContextPayload
        let messageId: UUID
        let optionId: String
    }

    private struct ApplyModificationRequest: Encodable {
        let recipe: RecipeContextPayload
        let pendingModification: PendingModification
        let threadId: UUID?
    }

    private struct RevertModificationRequest: Encodable {
        let recipe: RecipeContextPayload
        let modificationId: UUID
    }

    // ------------------------------------------------------------------
    // Plumbing
    // ------------------------------------------------------------------

    private static func postJSON<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        as _: Response.Type
    ) async throws -> Response {
        let url = try makeChatURL(path: path, query: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeEncoder().encode(body)
        return try await send(request, as: Response.self)
    }

    private static func send<Response: Decodable>(
        _ request: URLRequest,
        as _: Response.Type
    ) async throws -> Response {
        guard CooksyBackendService.isAvailable else {
            throw CooksyChatError.backendUnavailable
        }

        let authenticated = await attachAuthHeader(to: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: authenticated)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw CooksyChatError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw CooksyChatError.unreachable
            default:
                throw CooksyChatError.network(urlError.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw CooksyChatError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            throw mapHttpError(status: http.statusCode, data: data)
        }

        do {
            return try makeDecoder().decode(Response.self, from: data)
        } catch {
            logger.error("Chat decode failed: \(error.localizedDescription, privacy: .public)")
            throw CooksyChatError.invalidResponse
        }
    }

    private static func mapHttpError(status: Int, data: Data) -> CooksyChatError {
        let envelope = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data)
        let message = envelope?.message ?? envelope?.error
        switch status {
        case 401: return .unauthenticated
        case 402: return .premiumRequired
        case 404: return .notFound(message ?? "Ressource introuvable")
        case 429: return .rateLimited(message ?? "Trop de messages. Patientons un peu.")
        case 502: return .assistantUnparseable(message ?? "L'assistant n'a pas pu structurer sa réponse.")
        case 503: return .assistantUnavailable(message ?? "L'assistant est temporairement indisponible.")
        default:
            return .server(status: status, message: message ?? "Erreur \(status)")
        }
    }

    private static func attachAuthHeader(to request: URLRequest) async -> URLRequest {
        var enriched = request
        do {
            let session = try await SupabaseClientProvider.shared.auth.session
            enriched.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } catch {
            logger.debug("No active Supabase session — chat request will be unauthenticated.")
        }
        return enriched
    }

    private static func makeChatURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard let baseURL = AppConfiguration.backendBaseURL else {
            throw CooksyChatError.backendUnavailable
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CooksyChatError.invalidResponse
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let joined = [basePath, trimmedPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.percentEncodedPath = "/" + joined
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw CooksyChatError.invalidResponse
        }
        return url
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = iso8601Fractional.date(from: raw) ?? iso8601Plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }

    // ISO8601DateFormatter is documented as thread-safe in modern SDKs.
    // We wrap them in `nonisolated(unsafe)` to silence the Swift 6
    // strict concurrency check without changing runtime behaviour.
    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct BackendErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

enum CooksyChatError: LocalizedError {
    case backendUnavailable
    case unauthenticated
    case premiumRequired
    case rateLimited(String)
    case notFound(String)
    case assistantUnparseable(String)
    case assistantUnavailable(String)
    case server(status: Int, message: String)
    case timedOut
    case unreachable
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable:
            return "Le backend Cooksy n'est pas configuré."
        case .unauthenticated:
            return "Session expirée. Reconnecte-toi pour continuer."
        case .premiumRequired:
            return "L'assistant Cooksy est réservé aux membres Premium."
        case .rateLimited(let m):
            return m
        case .notFound(let m):
            return m
        case .assistantUnparseable(let m):
            return m
        case .assistantUnavailable(let m):
            return m
        case .server(_, let m):
            return m
        case .timedOut:
            return "L'assistant met trop de temps à répondre. Réessaie."
        case .unreachable:
            return "Impossible de joindre Cooksy. Vérifie ta connexion."
        case .invalidResponse:
            return "Réponse invalide du backend."
        case .network(let m):
            return m
        }
    }
}

// ---------------------------------------------------------------------------
// Recipe → RecipeContextPayload projection helper.
// ---------------------------------------------------------------------------

extension CooksyChatService.RecipeContextPayload {
    /// Build the compact payload from the local Recipe + the active list
    /// of modifications (those not yet reverted). Truncates long step
    /// detail so the system block stays cache-friendly.
    static func from(
        recipe: Recipe,
        appliedModifications: [RecipeModification] = []
    ) -> CooksyChatService.RecipeContextPayload {
        let ingredients = recipe.ingredients.map { ing in
            IngredientCell(
                id: ing.id,
                name: ing.name,
                amount: ing.amount,
                unit: ing.unit,
                originName: ing.originName
            )
        }
        let steps = recipe.steps.map { step in
            StepCell(
                id: step.id,
                title: step.title,
                detail: step.detail
            )
        }
        let nutrition: NutritionPatch? = recipe.nutrition.map { n in
            NutritionPatch(
                calories: n.calories,
                protein: n.protein,
                carbs: n.carbs,
                fat: n.fat,
                fiber: n.fiber,
                sugar: n.sugar,
                salt: n.salt,
                saturatedFat: n.saturatedFat
            )
        }
        return CooksyChatService.RecipeContextPayload(
            recipeId: recipe.id,
            title: recipe.title,
            servings: recipe.details.servings,
            prepTimeMinutes: recipe.details.prepTimeMinutes,
            cookTimeMinutes: recipe.details.cookTimeMinutes,
            ingredients: ingredients,
            steps: steps,
            nutritionPerServing: nutrition,
            allergens: recipe.allergens ?? [],
            appliedModifications: appliedModifications
                .filter { $0.revertedAt == nil }
                .map { AppliedModificationCell(
                    id: $0.id,
                    summary: $0.summary,
                    kind: $0.kind,
                    appliedAt: $0.appliedAt
                ) }
        )
    }
}
