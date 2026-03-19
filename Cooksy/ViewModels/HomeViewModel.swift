import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var totalRecipeCount = 0
    @Published private(set) var pendingImport: SharedImportDraft?

    private let store: RecipeStore
    private let sharedLinkInbox: SharedLinkInbox
    private var cancellables = Set<AnyCancellable>()

    init(store: RecipeStore, sharedLinkInbox: SharedLinkInbox) {
        self.store = store
        self.sharedLinkInbox = sharedLinkInbox

        store.$books
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                self?.books = books
            }
            .store(in: &cancellables)

        store.$recipes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recipes in
                self?.totalRecipeCount = recipes.count
            }
            .store(in: &cancellables)

        refreshPendingImport()
    }

    var uncategorizedBook: RecipeBook? {
        books.first(where: { $0.kind == .uncategorized })
    }

    var customBooks: [RecipeBook] {
        books
            .filter { $0.kind == .collection }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var displayedBookCount: Int {
        (uncategorizedBook == nil ? 0 : 1) + customBooks.count
    }

    var headerSubtitle: String {
        if totalRecipeCount == 0 {
            return "Importez une premiere recette depuis TikTok ou Instagram."
        }

        let suffix = totalRecipeCount > 1 ? "s" : ""
        return "\(totalRecipeCount) recette\(suffix) deja prete\(suffix.isEmpty ? "" : "s") a retrouver."
    }

    var bannerTitle: String {
        pendingImport == nil ? "Guides d'importation par plateforme" : "Lien partage pret a etre transforme"
    }

    var bannerSubtitle: String {
        pendingImport?.hostLabel ?? "TikTok, Instagram, Safari et Chrome"
    }

    func refreshPendingImport() {
        pendingImport = sharedLinkInbox.peek()
    }

    func createBook(title: String) {
        store.createBook(title: title)
    }
}
