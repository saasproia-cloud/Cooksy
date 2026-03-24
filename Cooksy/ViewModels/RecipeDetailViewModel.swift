import Combine
import Foundation
import OSLog
import UIKit

@MainActor
final class RecipeDetailViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "RecipeDetailViewModel")

    enum AssistantPreset {
        case replaceIngredient
        case simplify
        case healthier
    }

    struct DisplayIngredient: Identifiable, Hashable {
        let id: RecipeIngredient.ID
        let emoji: String?
        let quantityText: String?
        let name: String

        var fullLine: String {
            [quantityText, name].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
        }
    }

    @Published private(set) var recipe: Recipe?
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var heroImage: UIImage?
    @Published private(set) var currentBook: RecipeBook?
    @Published var currentServings: Int = 1

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
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "Ouvrez TikTok" }
        if host.contains("instagram") { return "Ouvrez Instagram" }
        if host.contains("youtube") { return "Ouvrez YouTube" }
        if host.contains("cooksy.app"), sourceURL?.path(percentEncoded: false).contains("/demo/") == true {
            return "Voir la source demo"
        }
        return "Ouvrez la source"
    }

    var displayedIngredients: [DisplayIngredient] {
        guard let recipe else { return [] }

        let baseServings = RecipeQuantityScaler.baseServings(from: recipe)
        return recipe.ingredients.map { ingredient in
            return DisplayIngredient(
                id: ingredient.id,
                emoji: ShoppingCatalog.specificEmoji(for: ingredient.name),
                quantityText: RecipeQuantityScaler.scaledQuantityText(
                    for: ingredient,
                    baseServings: baseServings,
                    targetServings: currentServings
                ),
                name: ingredient.name
            )
        }
    }

    var instructions: [RecipeStep] {
        recipe?.steps ?? []
    }

    var hasNutrition: Bool {
        recipe?.nutrition != nil
    }

    var nutrition: RecipeNutrition? {
        recipe?.nutrition
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

    @discardableResult
    func addDisplayedIngredientsToShoppingList() -> Int {
        store.addShoppingItems(from: displayedIngredients.map(\.fullLine)).count
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

    func assistantReply(for preset: AssistantPreset) -> String {
        guard let recipe else { return "Je n’ai pas encore assez d’informations sur cette recette." }

        switch preset {
        case .replaceIngredient:
            let suggestions = recipe.ingredients.prefix(3).map(\.name).joined(separator: ", ")
            return "Je peux vous aider à remplacer \(suggestions). Dites-moi l’ingrédient à changer et par quoi vous voulez le remplacer."
        case .simplify:
            let compactSteps = recipe.steps.prefix(3).enumerated().map { index, step in
                "\(index + 1). \(step.detail.split(separator: ".").first.map(String.init) ?? step.detail)"
            }
            return compactSteps.joined(separator: "\n")
        case .healthier:
            let healthyTips = healthierSuggestions(for: recipe)
            return healthyTips.isEmpty
                ? "Je garderais surtout les portions sous contrôle et j’ajouterais un accompagnement plus léger."
                : healthyTips.joined(separator: "\n")
        }
    }

    func assistantReply(for customQuestion: String) -> String {
        let normalized = customQuestion
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "Posez-moi une question sur les ingrédients, les étapes ou l’organisation de cette recette."
        }

        if normalized.contains("combien") && normalized.contains("temps") {
            let prep = recipe?.details.prepTimeMinutes.map { "\($0) min de préparation" }
            let cook = recipe?.details.cookTimeMinutes.map { "\($0) min de cuisson" }
            return [prep, cook].compactMap { $0 }.joined(separator: " • ").nilIfEmpty
                ?? "Je n’ai pas encore le temps exact pour cette recette."
        }

        if normalized.contains("ingredient") || normalized.contains("ingrédient") {
            let list = displayedIngredients.prefix(6).map(\.fullLine).joined(separator: ", ")
            return "Voici les ingrédients principaux : \(list)."
        }

        if normalized.contains("simpl") {
            return assistantReply(for: .simplify)
        }

        if normalized.contains("sain") || normalized.contains("light") {
            return assistantReply(for: .healthier)
        }

        return "Je peux vous aider à simplifier la recette, proposer des remplacements d’ingrédients, ou vous résumer les étapes."
    }

    private func applyRecipe(_ recipe: Recipe?) {
        self.recipe = recipe
        self.currentBook = books.first(where: { $0.id == recipe?.bookID })

        guard let recipe else { return }

        if !hasInitializedServings {
            currentServings = RecipeQuantityScaler.baseServings(from: recipe)
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

    private func healthierSuggestions(for recipe: Recipe) -> [String] {
        var suggestions: [String] = []
        let names = recipe.ingredients.map { $0.name.localizedLowercase }

        if names.contains(where: { $0.contains("sucre") || $0.contains("miel") }) {
            suggestions.append("• Réduisez légèrement le sucre ou le miel pour alléger la recette.")
        }

        if names.contains(where: { $0.contains("beurre") || $0.contains("crème") || $0.contains("creme") }) {
            suggestions.append("• Remplacez une partie du beurre ou de la crème par un yaourt grec ou une compote.")
        }

        if names.contains(where: { $0.contains("chocolat") }) {
            suggestions.append("• Utilisez un chocolat noir plus corsé pour garder le goût avec un peu moins de sucre.")
        }

        return suggestions
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
