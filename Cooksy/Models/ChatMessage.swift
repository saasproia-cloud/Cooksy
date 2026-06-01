import Foundation

// Mirror of the backend AssistantReply / PendingModification schemas. The
// wire format is JSON; these Codable types map 1:1 onto the backend's
// Zod definitions so a contract drift surfaces as a decode error rather
// than silent wrong behavior.

enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

enum ChatMessageState: Hashable {
    case sending      // optimistic local echo before the network round-trip
    case sent
    case failed(reason: String)
}

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    var threadId: UUID?
    var role: ChatRole
    var text: String
    var suggestions: ChatSuggestionGroup?
    var pendingModification: PendingModification?
    var createdAt: Date
    var state: ChatMessageState

    init(
        id: UUID = UUID(),
        threadId: UUID? = nil,
        role: ChatRole,
        text: String,
        suggestions: ChatSuggestionGroup? = nil,
        pendingModification: PendingModification? = nil,
        createdAt: Date = .now,
        state: ChatMessageState = .sent
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.text = text
        self.suggestions = suggestions
        self.pendingModification = pendingModification
        self.createdAt = createdAt
        self.state = state
    }
}

// ---------------------------------------------------------------------------
// Suggestion buttons
// ---------------------------------------------------------------------------

enum ChatSuggestionKind: String, Codable, Hashable {
    case ingredientSwap = "ingredient_swap"
    case scalePortions = "scale_portions"
}

struct ChatSuggestionTarget: Codable, Hashable {
    var ingredientId: UUID?
    var ingredientName: String?
    var stepId: UUID?
}

struct ChatSuggestionOption: Identifiable, Codable, Hashable {
    var id: String
    var label: String
    var shortImpact: String
}

struct ChatSuggestionGroup: Codable, Hashable {
    var kind: ChatSuggestionKind
    var target: ChatSuggestionTarget?
    var options: [ChatSuggestionOption]
}

// ---------------------------------------------------------------------------
// Pending modification (after user taps a suggestion)
// ---------------------------------------------------------------------------

struct NutritionPatch: Codable, Hashable {
    var calories: String?
    var protein: String?
    var carbs: String?
    var fat: String?
    var fiber: String?
    var sugar: String?
    var salt: String?
    var saturatedFat: String?
}

struct IngredientPatch: Codable, Hashable {
    var name: String
    var amount: String?
    var unit: String?
}

struct StepRewrite: Codable, Hashable {
    var stepId: UUID
    var beforeDetail: String
    var afterDetail: String
}

struct IngredientScalePatch: Codable, Hashable {
    var ingredientId: UUID
    var before: IngredientPatch
    var after: IngredientPatch
}

enum RecipeDiff: Codable, Hashable {
    case ingredientSwap(IngredientSwapDiff)
    case scalePortions(ScalePortionsDiff)
    case addComponents(AddComponentsDiff)

    private enum CodingKeys: String, CodingKey { case kind }
    private enum Kind: String, Codable {
        case ingredientSwap = "ingredient_swap"
        case scalePortions = "scale_portions"
        case addComponents = "add_components"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let single = try decoder.singleValueContainer()
        switch kind {
        case .ingredientSwap:
            self = .ingredientSwap(try single.decode(IngredientSwapDiff.self))
        case .scalePortions:
            self = .scalePortions(try single.decode(ScalePortionsDiff.self))
        case .addComponents:
            self = .addComponents(try single.decode(AddComponentsDiff.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .ingredientSwap(let payload): try single.encode(payload)
        case .scalePortions(let payload): try single.encode(payload)
        case .addComponents(let payload): try single.encode(payload)
        }
    }
}

// New ingredient injected via the chat (e.g. "ajoute une sauce maison").
struct AddedIngredientPayload: Codable, Hashable {
    var id: UUID
    var name: String
    var amount: String?
    var unit: String?
}

// New cooking step injected via the chat.
struct AddedStepPayload: Codable, Hashable {
    var id: UUID
    var title: String?
    var detail: String
}

struct AddComponentsDiff: Codable, Hashable {
    var kind: String = "add_components"
    /// Short label rendered on the assistant card (e.g. "Sauce maison").
    var label: String
    var addedIngredients: [AddedIngredientPayload]
    var addedSteps: [AddedStepPayload]
    /// Nutrition delta applied additively when the modification is
    /// accepted. `nil` when the assistant chose not to estimate one.
    var nutritionDelta: NutritionPatch?
    /// New allergens introduced by the addition.
    var allergensAdded: [String]
}

struct IngredientSwapDiff: Codable, Hashable {
    var kind: String = "ingredient_swap"
    var ingredientId: UUID
    var before: IngredientPatch
    var after: IngredientPatch
    var stepRewrites: [StepRewrite]
    var nutritionBefore: NutritionPatch?
    var nutritionAfter: NutritionPatch?
    var allergensBefore: [String]?
    var allergensAfter: [String]?
}

struct ScalePortionsDiff: Codable, Hashable {
    var kind: String = "scale_portions"
    var factor: Double
    var before: ScalePortionsServings
    var after: ScalePortionsServings
    var ingredientPatches: [IngredientScalePatch]

    struct ScalePortionsServings: Codable, Hashable {
        var servings: String?
    }
}

struct PendingModification: Codable, Hashable {
    var modificationId: UUID
    var summary: String
    var diff: RecipeDiff
    var confirmLabel: String
}
