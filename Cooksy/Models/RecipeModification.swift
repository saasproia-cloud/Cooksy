import Foundation

/// Local mirror of a `recipe_modifications` row. Used to power the ↺
/// revert chips in the recipe detail view. The full `payload` blob carries
/// enough state to invert the diff atomically.
struct RecipeModification: Identifiable, Codable, Hashable {
    let id: UUID
    var recipeId: UUID
    var threadId: UUID?
    var kind: String
    var summary: String
    var payload: PendingModification
    var appliedAt: Date
    var revertedAt: Date?
}
