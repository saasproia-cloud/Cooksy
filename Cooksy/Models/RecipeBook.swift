import Foundation

struct RecipeBook: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var kind: Kind
    var previewStyle: PreviewStyle
    var recipeIDs: [Recipe.ID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: Kind = .collection,
        previewStyle: PreviewStyle = .neutral,
        recipeIDs: [Recipe.ID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.previewStyle = previewStyle
        self.recipeIDs = recipeIDs
        self.createdAt = createdAt
    }

    var recipeCount: Int {
        recipeIDs.count
    }

    enum Kind: String, Codable, Hashable {
        case collection
        case uncategorized
    }

    enum PreviewStyle: String, Codable, Hashable {
        case neutral
        case featured
        case softBlue
    }
}

