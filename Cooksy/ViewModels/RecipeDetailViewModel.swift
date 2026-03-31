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

    typealias DisplayIngredient = RecipeIngredientPresentation

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

    var displayedNutrition: RecipeNutrition? {
        guard let nutritionDisplay else { return nil }
        return RecipeNutrition(
            calories: nutritionDisplay.caloriesText,
            protein: nutritionDisplay.proteinText,
            carbs: nutritionDisplay.carbsText,
            fat: nutritionDisplay.fatText
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
                name: ingredient.name
            )
        }
    }

    var instructions: [RecipeStep] {
        recipe?.steps ?? []
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

        if normalized.contains("nutrition") || normalized.contains("calorie") || normalized.contains("proteine") || normalized.contains("glucide") || normalized.contains("lipide") {
            if let nutrition = displayedNutrition {
                return "Par portion: \(nutrition.calories ?? "—"), protéines \(nutrition.protein ?? "—"), glucides \(nutrition.carbs ?? "—"), lipides \(nutrition.fat ?? "—")."
            }

            return "Je n’ai pas encore les valeurs nutritionnelles exactes. Utilisez le bouton nutrition sur la fiche pour les calculer."
        }

        if normalized.contains("combien") && normalized.contains("temps") {
            let prep = recipe?.details.prepTimeMinutes.map { "\($0) min de préparation" }
            let cook = recipe?.details.cookTimeMinutes.map { "\($0) min de cuisson" }
            return [prep, cook].compactMap { $0 }.joined(separator: " • ").nilIfEmpty
                ?? "Je n’ai pas encore le temps exact pour cette recette."
        }

        if normalized.contains("liste") || normalized.contains("ingredient") || normalized.contains("ingrédient") {
            let list = displayedIngredients.prefix(6).map(\.fullLine).joined(separator: ", ")
            return "Voici les ingrédients principaux : \(list)."
        }

        if normalized.contains("temperature") || normalized.contains("température") || normalized.contains("four") || normalized.contains("cuisson") {
            let temperatureSteps = recipe?.steps
                .map(\.detail)
                .filter { $0.contains("°") || $0.localizedCaseInsensitiveContains("four") || $0.localizedCaseInsensitiveContains("cuisson") } ?? []

            if let first = temperatureSteps.first {
                return first
            }

            return "Je n’ai pas trouvé de température précise dans cette recette. Vérifiez les étapes ou adaptez selon votre matériel."
        }

        if normalized.contains("etape") || normalized.contains("étape") {
            if let requestedStepIndex = requestedStepIndex(in: normalized),
               instructions.indices.contains(requestedStepIndex) {
                return "Étape \(requestedStepIndex + 1): \(instructions[requestedStepIndex].detail)"
            }

            let compactSteps = instructions.prefix(3).enumerated().map { index, step in
                "Étape \(index + 1): \(step.detail)"
            }
            return compactSteps.isEmpty
                ? "Je n’ai pas encore assez d’étapes structurées pour vous guider."
                : compactSteps.joined(separator: "\n\n")
        }

        if normalized.contains("ensuite") || normalized.contains("apres") || normalized.contains("après") || normalized.contains("prochaine") || normalized.contains("prochain") {
            guard let first = instructions.first else {
                return "Je n’ai pas encore assez d’étapes structurées pour vous guider."
            }
            return "Commencez par ceci: \(first.detail)"
        }

        if normalized.contains("simpl") {
            return assistantReply(for: .simplify)
        }

        if normalized.contains("sain") || normalized.contains("light") {
            return assistantReply(for: .healthier)
        }

        return "Je peux vous aider sur les ingrédients, les étapes, les temps, la nutrition, ou proposer des remplacements."
    }

    private func applyRecipe(_ recipe: Recipe?) {
        self.recipe = recipe
        self.currentBook = books.first(where: { $0.id == recipe?.bookID })

        guard let recipe else { return }

        if !hasInitializedServings {
            currentServings = 1
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

    private func requestedStepIndex(in question: String) -> Int? {
        let digits = question.compactMap { $0.isNumber ? String($0) : nil }.joined()
        guard let value = Int(digits), value > 0 else { return nil }
        return value - 1
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
