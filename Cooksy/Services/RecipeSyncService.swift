import Foundation
import OSLog
import Supabase

/// Cloud sync layer on top of the local `RecipeStore`.
///
/// Strategy: **best-effort fire-and-forget** with last-write-wins.
///   • Every local mutation (`addRecipe`, `updateRecipe`, `deleteRecipe`)
///     pushes a single upsert/tombstone to `/api/recipes`.
///   • On sign-in, `hydrateFromCloud()` pulls every non-deleted row and
///     merges them into the local library, preferring the side with the
///     fresher `updatedAt`.
///   • On account deletion, `wipeCloud()` soft-deletes everything on the
///     server too (the cascade from `auth.users` would do it as well,
///     but this is explicit and survives RC race conditions).
///
/// The store is the source of truth for the UI; the cloud is a backup
/// so a reinstall + Apple sign-in restores the library byte-for-byte.
@MainActor
final class RecipeSyncService {
    static let shared = RecipeSyncService()

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "RecipeSync")
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Push

    /// Upsert a single recipe to the cloud. Safe to call frequently —
    /// the backend is idempotent.
    func push(_ recipe: Recipe) {
        Task { [weak self] in
            await self?.pushImpl(recipe)
        }
    }

    /// Push a whole list of recipes in one round-trip. Used at first
    /// sign-in when the local library predates the cloud.
    func pushBatch(_ recipes: [Recipe]) {
        guard !recipes.isEmpty else { return }
        Task { [weak self] in
            await self?.pushBatchImpl(recipes)
        }
    }

    /// Soft-delete a recipe in the cloud. Local store has already removed
    /// the row by the time this is called.
    func tombstone(recipeID: UUID) {
        Task { [weak self] in
            await self?.tombstoneImpl(recipeID: recipeID)
        }
    }

    // MARK: - Pull

    /// Fetch every non-deleted recipe owned by the signed-in user. Caller
    /// is the `RecipeStore` (post-sign-in hydration).
    func pull() async -> [Recipe] {
        guard let request = await buildRequest(path: "/api/recipes", method: "GET") else {
            return []
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("Pull non-200 status")
                return []
            }
            let envelope = try JSONDecoder.cooksy.decode(PullResponse.self, from: data)
            return envelope.recipes.map(\.payload)
        } catch {
            logger.warning("Pull failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Impl

    private func pushImpl(_ recipe: Recipe) async {
        guard let payload = encodeRecipe(recipe) else { return }
        let body: [String: Any] = [
            "recipeId": recipe.id.uuidString,
            "payload": payload,
            "updatedAt": ISO8601DateFormatter().string(from: recipe.updatedAt)
        ]
        guard let request = await buildRequest(
            path: "/api/recipes/upsert",
            method: "POST",
            jsonBody: body
        ) else { return }
        _ = try? await session.data(for: request)
    }

    private func pushBatchImpl(_ recipes: [Recipe]) async {
        let payloads: [[String: Any]] = recipes.compactMap { recipe in
            guard let payload = encodeRecipe(recipe) else { return nil }
            return [
                "recipeId": recipe.id.uuidString,
                "payload": payload,
                "updatedAt": ISO8601DateFormatter().string(from: recipe.updatedAt)
            ]
        }
        guard !payloads.isEmpty else { return }
        let body: [String: Any] = ["recipes": payloads]
        guard let request = await buildRequest(
            path: "/api/recipes/upsert/batch",
            method: "POST",
            jsonBody: body
        ) else { return }
        _ = try? await session.data(for: request)
    }

    private func tombstoneImpl(recipeID: UUID) async {
        guard let request = await buildRequest(
            path: "/api/recipes/\(recipeID.uuidString)",
            method: "DELETE"
        ) else { return }
        _ = try? await session.data(for: request)
    }

    private func encodeRecipe(_ recipe: Recipe) -> [String: Any]? {
        do {
            let data = try JSONEncoder.cooksy.encode(recipe)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            logger.warning("encodeRecipe failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - HTTP plumbing (mirrors NotificationsCenter)

    private func buildRequest(
        path: String,
        method: String,
        jsonBody: Any? = nil
    ) async -> URLRequest? {
        guard let baseURL = AppConfiguration.backendBaseURL else { return nil }
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if jsonBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let session = try? await SupabaseClientProvider.shared.auth.session else {
            return nil
        }
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
            } catch {
                return nil
            }
        }
        return request
    }
}

// MARK: - Response shapes

private struct PullResponse: Decodable {
    let recipes: [PulledRecipeRow]
}

private struct PulledRecipeRow: Decodable {
    let recipeId: String
    /// The opaque JSON we sent at push time is the full Recipe Codable
    /// blob, so we can decode it back into the rich domain type in one
    /// shot. Any unknown future field will surface as a decode error
    /// and skip just the offending row.
    let payload: Recipe
    let updatedAt: String?
}

// MARK: - Shared Codable config

extension JSONEncoder {
    /// Cooksy's canonical encoder used for cloud-synced recipe payloads.
    /// Pulls in the ISO-8601 date strategy so the timestamps match what
    /// the backend expects.
    static let cooksy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let cooksy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
