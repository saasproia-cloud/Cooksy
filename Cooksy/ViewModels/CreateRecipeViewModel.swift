import Combine
import Foundation
import UIKit

@MainActor
final class CreateRecipeViewModel: ObservableObject {
    @Published var title = ""
    @Published var selectedBookID: RecipeBook.ID?
    @Published var prepTimeText = ""
    @Published var cookTimeText = ""
    @Published var servingsText = ""
    @Published var notesText = ""
    @Published var caloriesText = ""
    @Published var proteinText = ""
    @Published var carbsText = ""
    @Published var fatText = ""
    @Published var ingredientDrafts: [IngredientDraft] = []
    @Published var stepDrafts: [StepDraft] = []
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var selectedImage: UIImage?

    private let store: RecipeStore
    private let preferredBookID: RecipeBook.ID?
    private let editingRecipeID: Recipe.ID?
    private let editingCreatedAt: Date?
    private var sourceURL: URL?
    private var remoteImageURL: URL?
    private var selectedImageData: Data?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed? = nil,
        preferredBookID: RecipeBook.ID? = nil,
        editingRecipe: Recipe? = nil
    ) {
        self.store = store
        self.preferredBookID = preferredBookID
        self.editingRecipeID = editingRecipe?.id
        self.editingCreatedAt = editingRecipe?.createdAt

        let effectiveSeed = seed ?? editingRecipe.map {
            RecipeEditorSeed(recipe: $0, imageData: Self.loadImageData(from: $0.heroImageURL))
        }

        store.$books
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                self?.books = books
                self?.applyDefaultBookIfNeeded()
            }
            .store(in: &cancellables)

        books = store.books
        applyDefaultBookIfNeeded()
        apply(seed: effectiveSeed)

        if let editingRecipe {
            selectedBookID = editingRecipe.bookID ?? preferredBookID ?? store.uncategorizedBookID ?? books.first?.id
        }
    }

    var canSave: Bool {
        !currentSeed().normalizedTitle.isEmpty
    }

    var selectedBookLabel: String {
        guard let book = books.first(where: { $0.id == selectedBookID }) else {
            return "Choisir"
        }

        return book.kind == .uncategorized ? "Non catégorisé" : book.title
    }

    var informationSummary: String? {
        let parts = [
            summary(prepTimeText, suffix: "min prep"),
            summary(cookTimeText, suffix: "min cuisson"),
            trimmed(servingsText)
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var nutritionSummary: String? {
        let parts = [
            summary(caloriesText, suffix: "kcal"),
            summary(proteinText, suffix: "prot"),
            summary(carbsText, suffix: "gluc"),
            summary(fatText, suffix: "lip")
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    func setSelectedImageData(_ data: Data?) {
        selectedImageData = data
        guard
            let data,
            let image = UIImage(data: data)
        else {
            selectedImage = nil
            return
        }

        selectedImage = image
    }

    func addIngredient() {
        ingredientDrafts.append(IngredientDraft())
    }

    struct IngredientGroupView: Identifiable {
        let id: String
        let label: String
        let ingredientIDs: [IngredientDraft.ID]
    }

    /// Groups ingredients by their `group` label while preserving the order they
    /// appear in `ingredientDrafts`. Returns a single group with an empty label
    /// when no ingredient carries a group (so the UI can fall back to the
    /// flat rendering).
    var ingredientGroups: [IngredientGroupView] {
        var order: [String] = []
        var buckets: [String: [IngredientDraft.ID]] = [:]
        var seen = Set<String>()
        for draft in ingredientDrafts {
            let label = (draft.group?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if !seen.contains(label) {
                seen.insert(label)
                order.append(label)
            }
            buckets[label, default: []].append(draft.id)
        }
        let hasAnyGroup = order.contains(where: { !$0.isEmpty })
        if !hasAnyGroup {
            return [IngredientGroupView(id: "__flat__", label: "", ingredientIDs: ingredientDrafts.map(\.id))]
        }
        return order.map { label in
            IngredientGroupView(id: label.isEmpty ? "__default__" : label, label: label, ingredientIDs: buckets[label] ?? [])
        }
    }

    func removeIngredient(id: IngredientDraft.ID) {
        ingredientDrafts.removeAll { $0.id == id }
    }

    func addStep() {
        stepDrafts.append(StepDraft())
    }

    func removeStep(id: StepDraft.ID) {
        stepDrafts.removeAll { $0.id == id }
    }

    func selectBook(_ bookID: RecipeBook.ID) {
        selectedBookID = bookID
    }

    @discardableResult
    func saveRecipe() -> Bool {
        let seed = currentSeed()
        guard !seed.normalizedTitle.isEmpty else { return false }

        if let editingRecipeID {
            let existingRecipe = store.recipe(withID: editingRecipeID)
            let imageURL = seed.imageData
                .flatMap { persistImage(data: $0, recipeID: editingRecipeID) }
                ?? existingRecipe?.heroImageURL

            var updatedRecipe = seed.makeRecipe(
                id: editingRecipeID,
                bookID: selectedBookID,
                imageURL: imageURL
            )
            updatedRecipe.createdAt = editingCreatedAt ?? existingRecipe?.createdAt ?? .now
            updatedRecipe.updatedAt = .now
            updatedRecipe.heroStyle = imageURL == nil ? (existingRecipe?.heroStyle ?? .warmCocoa) : .ocean

            store.updateRecipe(updatedRecipe, movingTo: selectedBookID)
        } else {
            let recipeID = UUID()
            let imageURL = persistImage(data: seed.imageData, recipeID: recipeID)
            let recipe = seed.makeRecipe(id: recipeID, bookID: selectedBookID, imageURL: imageURL)
            store.addRecipe(recipe, to: selectedBookID)
        }

        return true
    }

    func currentSeed() -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: title,
            sourceURL: sourceURL,
            ingredientDrafts: ingredientDrafts,
            stepDrafts: stepDrafts,
            notesText: notesText,
            prepTimeText: prepTimeText,
            cookTimeText: cookTimeText,
            servingsText: servingsText,
            caloriesText: caloriesText,
            proteinText: proteinText,
            carbsText: carbsText,
            fatText: fatText,
            imageData: selectedImageData,
            remoteImageURL: remoteImageURL
        )
    }

    private func applyDefaultBookIfNeeded() {
        guard selectedBookID == nil else { return }
        if let preferredBookID, books.contains(where: { $0.id == preferredBookID }) {
            selectedBookID = preferredBookID
        } else {
            selectedBookID = books.first(where: { $0.kind == .uncategorized })?.id ?? books.first?.id
        }
    }

    private func apply(seed: RecipeEditorSeed?) {
        guard let seed else { return }
        title = seed.title
        sourceURL = seed.sourceURL
        remoteImageURL = seed.remoteImageURL
        ingredientDrafts = seed.ingredientDrafts
        stepDrafts = seed.stepDrafts
        notesText = seed.editableNotesText
        prepTimeText = seed.prepTimeText
        cookTimeText = seed.cookTimeText
        servingsText = seed.servingsText
        caloriesText = seed.caloriesText
        proteinText = seed.proteinText
        carbsText = seed.carbsText
        fatText = seed.fatText
        setSelectedImageData(seed.imageData)
    }

    private func persistImage(data: Data?, recipeID: Recipe.ID) -> URL? {
        guard let data else { return nil }
        return store.storeImageData(data, for: recipeID)
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func summary(_ text: String, suffix: String) -> String? {
        guard let value = trimmed(text) else { return nil }
        let lowercased = value.lowercased()
        if lowercased.contains(suffix.lowercased()) || lowercased.hasSuffix(" g") || lowercased.hasSuffix(" kcal") || lowercased.hasSuffix(" min") {
            return value
        }
        return "\(value) \(suffix)"
    }

    private static func loadImageData(from url: URL?) -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}
