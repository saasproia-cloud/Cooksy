import Combine
import Foundation

@MainActor
final class ShoppingListViewModel: ObservableObject {
    enum SortMode: String, CaseIterable, Identifiable {
        case aisle
        case alphabetical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aisle:
                return "Allée"
            case .alphabetical:
                return "A-Z"
            }
        }
    }

    struct Section: Identifiable, Hashable {
        let id: String
        let title: String
        let items: [ShoppingItem]
    }

    @Published private(set) var items: [ShoppingItem] = []
    @Published var sortMode: SortMode = .aisle

    private let store: RecipeStore
    private var cancellables = Set<AnyCancellable>()

    init(store: RecipeStore) {
        self.store = store

        store.$shoppingItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.items = items
            }
            .store(in: &cancellables)
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    var totalCountLabel: String {
        let suffix = items.count == 1 ? "" : "s"
        return "\(items.count) article\(suffix)"
    }

    var checkedCount: Int {
        items.filter(\.isCompleted).count
    }

    var sections: [Section] {
        switch sortMode {
        case .aisle:
            let grouped = Dictionary(grouping: items) { $0.category }
            return ShoppingCategory.allCases.compactMap { category in
                guard let categoryItems = grouped[category], !categoryItems.isEmpty else { return nil }
                return Section(
                    id: category.rawValue,
                    title: category.sectionTitle,
                    items: sortItems(categoryItems)
                )
            }
        case .alphabetical:
            guard !items.isEmpty else { return [] }
            return [
                Section(
                    id: "alphabetical",
                    title: "A-Z",
                    items: sortItems(items)
                )
            ]
        }
    }

    var shareText: String {
        guard !items.isEmpty else { return "Liste de courses Cooksy" }

        return sections
            .map { section in
                let lines = section.items.map { item in
                    if let quantity = item.displayQuantity {
                        return "• \(quantity) \(item.article)"
                    }

                    return "• \(item.article)"
                }
                return ([section.title] + lines).joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    @discardableResult
    func addItems(from rawText: String) -> Int {
        store.addShoppingItems(from: rawText).count
    }

    func toggleCompletion(for item: ShoppingItem) {
        store.toggleShoppingItemCompletion(id: item.id)
    }

    func update(_ item: ShoppingItem, article: String, quantity: String, category: ShoppingCategory) {
        store.updateShoppingItem(
            id: item.id,
            article: article,
            quantity: quantity,
            category: category
        )
    }

    func delete(_ item: ShoppingItem) {
        store.deleteShoppingItem(id: item.id)
    }

    func clearCompleted() {
        store.clearCompletedShoppingItems()
    }

    func clearAll() {
        store.clearShoppingItems()
    }

    private func sortItems(_ items: [ShoppingItem]) -> [ShoppingItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }

            let lhsArticle = lhs.article.localizedLowercase
            let rhsArticle = rhs.article.localizedLowercase
            if lhsArticle != rhsArticle {
                return lhsArticle < rhsArticle
            }

            return lhs.createdAt < rhs.createdAt
        }
    }
}
