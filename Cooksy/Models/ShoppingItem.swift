import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    let id: UUID
    var article: String
    var quantity: String?
    var category: ShoppingCategory
    var remoteImageURLString: String?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        article: String,
        quantity: String? = nil,
        category: ShoppingCategory,
        remoteImageURLString: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.article = article
        self.quantity = quantity
        self.category = category
        self.remoteImageURLString = remoteImageURLString
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayQuantity: String? {
        let trimmed = quantity?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var emoji: String {
        ShoppingCatalog.emoji(for: article, category: category)
    }

    var remoteImageURL: URL? {
        guard let remoteImageURLString else { return nil }
        return URL(string: remoteImageURLString)
    }
}

enum ShoppingCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case freshProduce
    case dairyAndEggs
    case bakery
    case pantry
    case meatAndSeafood
    case frozen
    case beverages
    case household

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freshProduce:
            return "Produits frais"
        case .dairyAndEggs:
            return "Produits laitiers"
        case .bakery:
            return "Boulangerie"
        case .pantry:
            return "Epicerie"
        case .meatAndSeafood:
            return "Boucherie & poissonnerie"
        case .frozen:
            return "Surgeles"
        case .beverages:
            return "Boissons"
        case .household:
            return "Maison"
        }
    }

    var sectionTitle: String {
        title.uppercased()
    }

    var sortOrder: Int {
        switch self {
        case .freshProduce:
            return 0
        case .dairyAndEggs:
            return 1
        case .bakery:
            return 2
        case .pantry:
            return 3
        case .meatAndSeafood:
            return 4
        case .frozen:
            return 5
        case .beverages:
            return 6
        case .household:
            return 7
        }
    }
}
