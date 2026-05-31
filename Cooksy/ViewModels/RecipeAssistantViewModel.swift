import Foundation
import SwiftUI

/// Drives the Premium recipe-assistant sheet. Owns:
///   - the message timeline (with optimistic local echo + states)
///   - the active thread id and the per-recipe history rehydration
///   - the network calls into CooksyChatService
///   - the "Cooksy réfléchit…" typing indicator
///   - applying / reverting modifications through RecipeStore
@MainActor
final class RecipeAssistantViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var initialLoadFailed = false
    @Published var draft: String = ""
    @Published var errorMessage: String?

    private let store: RecipeStore
    private let recipeID: Recipe.ID
    private var threadId: UUID?
    private var hasLoadedHistory = false

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        self.recipeID = recipeID
    }

    var recipe: Recipe? {
        store.recipe(withID: recipeID)
    }

    var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    /// Called once when the sheet appears. Hydrates the conversation
    /// from the backend so the user picks up exactly where they left off.
    func loadIfNeeded() async {
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true
        do {
            let response = try await CooksyChatService.loadHistory(recipeId: recipeID)
            self.threadId = response.threadId
            self.messages = response.messages.map { wire in
                ChatMessage(
                    id: wire.id,
                    threadId: wire.threadId,
                    role: wire.role,
                    text: wire.contentText ?? "",
                    suggestions: wire.suggestionsJson,
                    pendingModification: wire.pendingModificationJson,
                    createdAt: wire.createdAt
                )
            }
            self.initialLoadFailed = false
        } catch let error as CooksyChatError {
            // A 404 / no thread is fine — the user just hasn't chatted
            // about this recipe yet. Other errors surface as a banner.
            switch error {
            case .notFound:
                self.messages = []
            default:
                self.initialLoadFailed = true
                self.errorMessage = error.errorDescription
            }
        } catch {
            self.initialLoadFailed = true
            self.errorMessage = error.localizedDescription
        }
    }

    // ------------------------------------------------------------------
    // Send / select / apply / revert
    // ------------------------------------------------------------------

    func submitDraft() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        await sendUserMessage(text: trimmed)
    }

    func send(presetQuickQuestion text: String) async {
        guard !isStreaming else { return }
        await sendUserMessage(text: text)
    }

    private func sendUserMessage(text: String) async {
        guard let recipe = recipe else { return }

        // Optimistic echo — user sees their message instantly.
        let localUserMessage = ChatMessage(
            role: .user,
            text: text,
            state: .sending
        )
        messages.append(localUserMessage)
        draft = ""
        isStreaming = true
        errorMessage = nil

        let payload = CooksyChatService.RecipeContextPayload.from(recipe: recipe)

        do {
            let response = try await CooksyChatService.sendMessage(
                recipe: payload,
                userMessage: text,
                threadId: threadId
            )
            threadId = response.threadId

            // Mark the local echo as sent and append the assistant reply.
            markLastUserMessage(state: .sent)
            appendWireMessage(response.assistantMessage)
        } catch {
            markLastUserMessage(state: .failed(reason: error.localizedDescription))
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }

    func selectSuggestion(_ option: ChatSuggestionOption, in message: ChatMessage) async {
        guard !isStreaming, let recipe = recipe else { return }
        // Optimistic echo: render the user's "selected" intent as a
        // user message so the conversation reads naturally.
        let echo = ChatMessage(
            role: .user,
            text: option.label,
            state: .sending
        )
        messages.append(echo)
        isStreaming = true
        errorMessage = nil

        let payload = CooksyChatService.RecipeContextPayload.from(recipe: recipe)
        do {
            let response = try await CooksyChatService.selectSuggestion(
                recipe: payload,
                messageId: message.id,
                optionId: option.id
            )
            markLastUserMessage(state: .sent)
            appendWireMessage(response.assistantMessage)
        } catch {
            markLastUserMessage(state: .failed(reason: error.localizedDescription))
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }

    func confirmModification(_ pending: PendingModification) async {
        guard let recipe = recipe else { return }
        isStreaming = true
        errorMessage = nil
        let payload = CooksyChatService.RecipeContextPayload.from(recipe: recipe)
        do {
            let response = try await CooksyChatService.applyModification(
                recipe: payload,
                pendingModification: pending,
                threadId: threadId
            )
            store.applyAssistantMutation(
                recipeID: recipeID,
                payload: response.recipe,
                modificationId: response.modificationId
            )
            // Replace the pending card with a confirmation bubble so the
            // user gets a visible "modifiée" feedback in the timeline.
            replacePendingModification(
                modificationId: pending.modificationId,
                with: ChatMessage(
                    role: .assistant,
                    text: "Recette modifiée — \(pending.summary). Tu peux annuler à tout moment depuis la ligne d'ingrédient (↺).",
                    state: .sent
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }

    /// Triggered by the ↺ icon next to a swapped ingredient. Walks back
    /// to the latest active modification for that ingredient and reverts.
    func revertSwap(for ingredientId: UUID) async {
        guard let recipe = recipe else { return }
        // We don't persist a local list of modifications — we always
        // surface the ↺ via the ingredient.origin* fields. The actual
        // modification id needed for /chat/revert is the most recent one
        // touching this ingredient. We look it up server-side via a
        // best-effort: send the modification id from the last assistant
        // pending_modification message for this ingredient.
        let candidate = lastAppliedModification(forIngredientId: ingredientId)
        guard let pending = candidate else {
            errorMessage = "Modification introuvable pour annulation."
            return
        }
        let payload = CooksyChatService.RecipeContextPayload.from(recipe: recipe)
        do {
            let response = try await CooksyChatService.revertModification(
                recipe: payload,
                modificationId: pending.modificationId
            )
            store.revertAssistantMutation(recipeID: recipeID, payload: response.recipe)
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Annulation — la recette est revenue à : \(pending.diff.beforeSummary).",
                    state: .sent
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private func appendWireMessage(_ wire: CooksyChatService.WireChatMessage) {
        let message = ChatMessage(
            id: wire.id,
            threadId: wire.threadId,
            role: wire.role,
            text: wire.contentText ?? "",
            suggestions: wire.suggestionsJson,
            pendingModification: wire.pendingModificationJson,
            createdAt: wire.createdAt
        )
        messages.append(message)
    }

    private func markLastUserMessage(state: ChatMessageState) {
        guard let index = messages.lastIndex(where: { $0.role == .user }) else { return }
        messages[index].state = state
    }

    private func replacePendingModification(modificationId: UUID, with replacement: ChatMessage) {
        if let index = messages.lastIndex(where: { $0.pendingModification?.modificationId == modificationId }) {
            messages[index] = replacement
        } else {
            messages.append(replacement)
        }
    }

    private func lastAppliedModification(forIngredientId ingredientId: UUID) -> PendingModification? {
        for message in messages.reversed() {
            guard let pending = message.pendingModification else { continue }
            if case let .ingredientSwap(diff) = pending.diff, diff.ingredientId == ingredientId {
                return pending
            }
        }
        return nil
    }
}

private extension RecipeDiff {
    var beforeSummary: String {
        switch self {
        case .ingredientSwap(let diff):
            let qty = [diff.before.amount, diff.before.unit].compactMap { $0 }.joined(separator: " ")
            return qty.isEmpty ? diff.before.name : "\(qty) \(diff.before.name)"
        case .scalePortions(let diff):
            return diff.before.servings ?? "portions d'origine"
        }
    }
}
