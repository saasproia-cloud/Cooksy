import Combine
import Foundation
import OSLog
import UIKit

@MainActor
final class RecipeDetailViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "RecipeDetailViewModel")

    typealias DisplayIngredient = RecipeIngredientPresentation

    @Published private(set) var recipe: Recipe?
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var heroImage: UIImage?
    @Published private(set) var currentBook: RecipeBook?
    @Published var currentServings: Int = 1

    // Inline editing state
    @Published var editingIngredientID: RecipeIngredient.ID?
    @Published var editingStepID: RecipeStep.ID?
    @Published var editDraftAmount: String = ""
    @Published var editDraftUnit: String = ""
    @Published var editDraftName: String = ""
    @Published var editDraftStepDetail: String = ""

    private let store: RecipeStore
    private let recipeID: Recipe.ID
    private var cancellables = Set<AnyCancellable>()
    private var hasInitializedServings = false
    private var loadedHeroURL: URL?

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        self.recipeID = recipeID

        store.$recipes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recipes in
                self?.applyRecipe(recipes.first(where: { $0.id == recipeID }))
            }
            .store(in: &cancellables)

        store.$books
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                guard let self else { return }
                self.books = books
                self.currentBook = books.first(where: { $0.id == self.recipe?.bookID })
            }
            .store(in: &cancellables)

        books = store.books
        applyRecipe(store.recipe(withID: recipeID))
    }

    var title: String {
        recipe?.title ?? ""
    }

    var noteText: String? {
        recipe?.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var sourceURL: URL? {
        recipe?.sourceURL
    }

    var sourceButtonTitle: String? {
        RecipePresentationFormatter.sourceButtonTitle(for: sourceURL)
    }

    var sourceLabel: String? {
        RecipePresentationFormatter.sourceLabel(for: sourceURL)
    }

    var sourceHostLabel: String {
        RecipePresentationFormatter.sourceHostLabel(for: sourceURL)
    }

    var creatorHandle: String? {
        RecipePresentationFormatter.creatorHandle(
            explicitHandle: recipe?.creatorHandle,
            sourceURL: sourceURL
        )
    }

    var ratingValue: Double? {
        recipe?.externalRating
    }

    var ratingCountLabel: String? {
        RecipePresentationFormatter.ratingCountText(for: recipe?.externalRatingCount)
    }

    var difficultyLabel: String {
        RecipePresentationFormatter.difficultyLabel(for: recipe)
    }

    var ingredientCount: Int {
        recipe?.ingredients.count ?? 0
    }

    var instructionCount: Int {
        recipe?.steps.count ?? 0
    }

    var selectedBookLabel: String {
        currentBook?.kind == .uncategorized ? "Non catégorisé" : (currentBook?.title ?? "Non catégorisé")
    }

    var baseServings: Int {
        guard let recipe else { return 1 }
        return max(1, RecipeQuantityScaler.baseServings(from: recipe))
    }

    var servingsLabel: String {
        RecipePresentationFormatter.servingsLabel(for: baseServings)
    }

    var prepTimeLabel: String? {
        guard let minutes = recipe?.details.prepTimeMinutes, minutes > 0 else { return nil }
        return "\(minutes) min prep"
    }

    var cookTimeLabel: String? {
        guard let minutes = recipe?.details.cookTimeMinutes, minutes > 0 else { return nil }
        return "\(minutes) min cuisson"
    }

    var totalTimeLabel: String? {
        RecipePresentationFormatter.totalTimeLabel(
            prepMinutes: recipe?.details.prepTimeMinutes,
            cookMinutes: recipe?.details.cookTimeMinutes
        )
    }

    var summaryText: String {
        RecipePresentationFormatter.summaryText(
            noteText: noteText,
            title: title,
            totalTimeLabel: totalTimeLabel,
            baseServings: baseServings
        )
    }

    var totalCaloriesLabel: String? {
        guard let recipe else { return nil }
        return RecipeNutritionDisplayBuilder.totalCaloriesLabel(for: recipe)
    }

    var nutritionDisplay: RecipeNutritionDisplay? {
        guard let recipe else { return nil }
        return RecipeNutritionDisplayBuilder.displayNutrition(
            for: recipe,
            selectedServings: currentServings
        )
    }

    var perServingNutritionDisplay: RecipeNutritionDisplay? {
        guard let recipe else { return nil }
        return RecipeNutritionDisplayBuilder.displayNutrition(for: recipe, selectedServings: 1)
    }

    var totalNutritionDisplay: RecipeNutritionDisplay? {
        nutritionDisplay
    }

    var displayedNutrition: RecipeNutrition? {
        guard let nutritionDisplay else { return nil }
        return RecipeNutrition(
            calories: nutritionDisplay.caloriesText,
            protein: nutritionDisplay.proteinText,
            carbs: nutritionDisplay.carbsText,
            fat: nutritionDisplay.fatText,
            fiber: nutritionDisplay.fiberText,
            sugar: nutritionDisplay.sugarText,
            salt: nutritionDisplay.saltText,
            saturatedFat: nutritionDisplay.saturatedFatText
        )
    }

    var nutritionIsEstimated: Bool {
        guard let recipe else { return false }
        return RecipeNutritionDisplayBuilder.isEstimated(for: recipe)
    }

    var displayedIngredients: [RecipeIngredientPresentation] {
        guard let recipe else { return [] }

        return recipe.ingredients.map { ingredient in
            return RecipeIngredientPresentation(
                id: ingredient.id,
                quantityText: RecipeQuantityScaler.scaledQuantityText(
                    for: ingredient,
                    baseServings: baseServings,
                    targetServings: currentServings
                ),
                rawAmount: ingredient.amount,
                rawUnit: ingredient.unit,
                name: ingredient.name,
                originName: ingredient.originName,
                lastModificationId: ingredient.lastModificationId
            )
        }
    }

    /// Reverts the latest chat-assistant swap that was applied to the
    /// given ingredient. Called from the per-row ↺ chip — fires the
    /// /api/chat/revert endpoint then mirrors the result locally.
    func revertSwap(ingredientId: UUID) async {
        guard
            let recipe,
            let ingredient = recipe.ingredients.first(where: { $0.id == ingredientId }),
            let modificationId = ingredient.lastModificationId
        else { return }

        let payload = CooksyChatService.RecipeContextPayload.from(recipe: recipe)
        do {
            let response = try await CooksyChatService.revertModification(
                recipe: payload,
                modificationId: modificationId
            )
            store.revertAssistantMutation(recipeID: recipe.id, payload: response.recipe)
        } catch {
            logger.error("Revert swap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var instructions: [RecipeStep] {
        guard let recipe else { return [] }
        return RecipeStepDisplayBuilder.cleanedSteps(from: recipe.steps, ingredients: recipe.ingredients)
    }

    var hasNutrition: Bool {
        nutritionDisplay != nil
    }

    var nutrition: RecipeNutrition? {
        displayedNutrition
    }

    func changeServings(by delta: Int) {
        let newValue = max(1, min(24, currentServings + delta))
        currentServings = newValue
    }

    func replaceHeroImage(with data: Data) {
        guard store.replaceRecipeImage(id: recipeID, with: data) != nil else { return }
        heroImage = UIImage(data: data)
    }

    func moveToBook(_ bookID: RecipeBook.ID) {
        guard var recipe else { return }
        recipe.bookID = bookID
        store.updateRecipe(recipe, movingTo: bookID)
    }

    func addToMealPlan(on day: Date) {
        store.addMealPlanRecipe(recipeID: recipeID, for: day)
    }

    // MARK: - Inline Editing

    func beginEditingIngredient(_ ingredient: RecipeIngredient) {
        cancelEdit()
        editingIngredientID = ingredient.id
        editDraftAmount = ingredient.amount ?? ""
        editDraftUnit = ingredient.unit ?? ""
        editDraftName = ingredient.name
    }

    func beginEditingStep(_ step: RecipeStep) {
        cancelEdit()
        editingStepID = step.id
        editDraftStepDetail = step.detail
    }

    func saveIngredientEdit() {
        guard var recipe, let editingID = editingIngredientID,
              let index = recipe.ingredients.firstIndex(where: { $0.id == editingID }) else { return }

        recipe.ingredients[index].amount = editDraftAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : editDraftAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.ingredients[index].unit = editDraftUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : editDraftUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.ingredients[index].name = editDraftName.trimmingCharacters(in: .whitespacesAndNewlines)

        recipe.updatedAt = .now
        store.updateRecipe(recipe, movingTo: recipe.bookID)
        cancelEdit()
    }

    func saveStepEdit() {
        guard var recipe, let editingID = editingStepID,
              let index = recipe.steps.firstIndex(where: { $0.id == editingID }) else { return }

        recipe.steps[index].detail = editDraftStepDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.updatedAt = .now
        store.updateRecipe(recipe, movingTo: recipe.bookID)
        cancelEdit()
    }

    func cancelEdit() {
        editingIngredientID = nil
        editingStepID = nil
        editDraftAmount = ""
        editDraftUnit = ""
        editDraftName = ""
        editDraftStepDetail = ""
    }

    func deleteIngredient(id: RecipeIngredient.ID) {
        guard var recipe else { return }
        recipe.ingredients.removeAll { $0.id == id }
        recipe.updatedAt = .now
        store.updateRecipe(recipe, movingTo: recipe.bookID)
    }

    func deleteStep(id: RecipeStep.ID) {
        guard var recipe else { return }
        recipe.steps.removeAll { $0.id == id }
        recipe.updatedAt = .now
        store.updateRecipe(recipe, movingTo: recipe.bookID)
    }

    func shareText() -> String {
        guard let recipe else { return "Recette Cooksy" }

        var sections: [String] = [recipe.title]

        if !displayedIngredients.isEmpty {
            sections.append(
                (["Ingrédients"] + displayedIngredients.map { "• \($0.fullLine)" })
                    .joined(separator: "\n")
            )
        }

        if !instructions.isEmpty {
            let steps = instructions.enumerated().map { index, step in
                "\(index + 1). \(step.detail)"
            }
            sections.append((["Instructions"] + steps).joined(separator: "\n"))
        }

        if let sourceURL {
            sections.append(sourceURL.absoluteString)
        }

        return sections.joined(separator: "\n\n")
    }

    @discardableResult
    func calculateNutrition(forPortions portionCount: Int) -> RecipeNutritionEstimate? {
        guard var recipe else { return nil }

        let estimate = RecipeNutritionEstimator.estimate(recipe: recipe, forPortions: portionCount)
        recipe.nutrition = estimate.nutrition
        if recipe.details.servings?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            recipe.details.servings = String(portionCount)
        }
        store.updateRecipe(recipe, movingTo: recipe.bookID)
        return estimate
    }

    // Note: the client-side AssistantPreset / regex-matching
    // assistantReply(...) helpers were retired when the Premium chat
    // assistant moved to the backend (`/api/chat/*`). RecipeAssistantSheet
    // + RecipeAssistantViewModel now own the conversation end-to-end.

    private func applyRecipe(_ recipe: Recipe?) {
        self.recipe = recipe
        self.currentBook = books.first(where: { $0.id == recipe?.bookID })

        guard let recipe else { return }

        if !hasInitializedServings {
            currentServings = max(1, RecipeQuantityScaler.baseServings(from: recipe))
            hasInitializedServings = true
        }

        if loadedHeroURL != recipe.heroImageURL {
            loadedHeroURL = recipe.heroImageURL
            loadHeroImage(from: recipe.heroImageURL)
        }
    }

    private func loadHeroImage(from url: URL?) {
        guard let url else {
            heroImage = nil
            return
        }

        if url.isFileURL {
            heroImage = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            return
        }

        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            logger.error("Skipping invalid hero image URL: \(url.absoluteString, privacy: .public)")
            heroImage = nil
            return
        }

        Task {
            logger.debug("Loading hero image from \(url.absoluteString, privacy: .public)")
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard !Task.isCancelled else { return }
            heroImage = UIImage(data: data)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
