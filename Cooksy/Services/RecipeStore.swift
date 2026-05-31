import Combine
import Foundation

/// Posted by `SessionStore.deleteAccount()` after the server-side row has
/// been deleted. RecipeStore observes this to wipe every local artefact
/// belonging to the deleted account — JSON library, recipe images, share
/// extension's pending imports — so the next signup on the same device
/// doesn't inherit recipes from the previous user.
extension Notification.Name {
    static let cooksyAccountDeleted = Notification.Name("cooksy.account.deleted")
}

@MainActor
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var mealPlanEntries: [MealPlanEntry] = []

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let mealPlanCalendar: Calendar
    private var accountDeletionObserver: NSObjectProtocol?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        var mealPlanCalendar = Calendar(identifier: .gregorian)
        mealPlanCalendar.locale = Locale(identifier: "fr_FR")
        mealPlanCalendar.firstWeekday = 2
        self.mealPlanCalendar = mealPlanCalendar

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()

        // RecipeStore is held for the entire app lifetime, so the
        // observer doesn't need cleanup (a `deinit` would also fight
        // Swift 6's actor-isolation rules around NSObjectProtocol).
        accountDeletionObserver = NotificationCenter.default.addObserver(
            forName: .cooksyAccountDeleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wipeAllForAccountDeletion()
            }
        }
    }

    /// Wipes every locally persisted artefact tied to the previous user:
    /// the library JSON, the cached recipe images directory and the share
    /// extension's pending-imports inbox. Called from the account-deletion
    /// flow via `Notification.Name.cooksyAccountDeleted` so a new signup
    /// on the same device starts from a clean slate.
    func wipeAllForAccountDeletion() {
        recipes = []
        books = []
        mealPlanEntries = []

        let baseCooksyDirectory = storageURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: storageURL)
        let imagesDirectory = baseCooksyDirectory.appendingPathComponent("Images", isDirectory: true)
        try? fileManager.removeItem(at: imagesDirectory)
        let pendingImports = baseCooksyDirectory.appendingPathComponent("PendingImports", isDirectory: true)
        try? fileManager.removeItem(at: pendingImports)

        seedLibrary()
    }

    var uncategorizedBookID: RecipeBook.ID? {
        books.first(where: { $0.kind == .uncategorized })?.id
    }

    func recipe(withID id: Recipe.ID) -> Recipe? {
        recipes.first(where: { $0.id == id })
    }

    func book(withID id: RecipeBook.ID?) -> RecipeBook? {
        guard let id else { return nil }
        return books.first(where: { $0.id == id })
    }

    @discardableResult
    func createBook(title: String) -> RecipeBook? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let book = RecipeBook(title: trimmedTitle, previewStyle: .neutral)
        books.append(book)
        save()
        return book
    }

    func addRecipe(
        _ recipe: Recipe,
        to destinationBookID: RecipeBook.ID? = nil,
        consumesQuota: Bool = true
    ) {
        let destinationID = destinationBookID ?? uncategorizedBookID
        var storedRecipe = recipe
        storedRecipe.bookID = destinationID
        recipes.insert(storedRecipe, at: 0)
        attach(recipeID: storedRecipe.id, to: destinationID)
        save()
        // Counts toward the free-tier weekly quota only when the recipe
        // was produced via an AI-powered import path (text, photo, URL,
        // shared draft). "Depuis zéro" creations and demo-catalogue saves
        // pass `consumesQuota: false` so they don't burn an éclair.
        // Premium users are exempted by ImportQuotaService itself.
        guard consumesQuota else { return }
        Task { @MainActor in
            ImportQuotaService.shared.incrementOnSuccess()
        }

        // Lifetime import counter — drives the one-shot milestone pushes.
        let lifetimeKey = "cooksy.notif.lifetimeImports"
        let lifetimeImports = UserDefaults.standard.integer(forKey: lifetimeKey) + 1
        UserDefaults.standard.set(lifetimeImports, forKey: lifetimeKey)

        // First real (AI-powered) import → schedule the celebration push
        // and retire the onboarding nudges. Latched via the lifetime
        // counter so it fires exactly once per install.
        if lifetimeImports == 1 {
            let recipeID = storedRecipe.id.uuidString
            Task { @MainActor in
                NotificationScheduler.scheduleFirstImportCelebration(recipeID: recipeID)
                // First import is a high-value moment — promote the
                // provisional push grant to a full one so future
                // banners get sound + lock-screen visibility.
                _ = await NotificationsCenter.shared.requestExplicitAuthorization()
            }
        }

        // A5 — 5th lifetime import milestone.
        if lifetimeImports == 5 {
            Task { @MainActor in
                NotificationScheduler.scheduleImportMilestone5()
            }
        }
    }

    func updateRecipe(_ recipe: Recipe, movingTo destinationBookID: RecipeBook.ID? = nil) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else {
            addRecipe(recipe, to: destinationBookID)
            return
        }

        let existingRecipe = recipes[index]
        let destinationID = destinationBookID ?? recipe.bookID ?? uncategorizedBookID

        var updatedRecipe = recipe
        updatedRecipe.bookID = destinationID
        updatedRecipe.createdAt = existingRecipe.createdAt
        updatedRecipe.updatedAt = .now

        recipes[index] = updatedRecipe
        attach(recipeID: updatedRecipe.id, to: destinationID)
        save()
    }

    // ------------------------------------------------------------------
    // Chat-assistant modifications (apply / revert)
    // ------------------------------------------------------------------
    //
    // Both methods take a `MutatedRecipePayload` produced by the backend
    // (which already validated + computed the diff) and project it onto
    // the local `Recipe`. We deliberately keep the ingredient ids intact
    // so the ↺ button keeps working through subsequent edits.
    //
    // The recipe.allergens, recipe.nutrition, recipe.details.servings,
    // and the per-ingredient origin* snapshot are mirrored from the
    // payload so the local store stays the single source of truth.

    @discardableResult
    func applyAssistantMutation(
        recipeID: Recipe.ID,
        payload: CooksyChatService.MutatedRecipePayload,
        modificationId: UUID
    ) -> Recipe? {
        guard let index = recipes.firstIndex(where: { $0.id == recipeID }) else { return nil }
        var updated = recipes[index]
        applyMutation(to: &updated, payload: payload, modificationId: modificationId)
        updated.updatedAt = .now
        recipes[index] = updated
        save()
        return updated
    }

    @discardableResult
    func revertAssistantMutation(
        recipeID: Recipe.ID,
        payload: CooksyChatService.MutatedRecipePayload
    ) -> Recipe? {
        guard let index = recipes.firstIndex(where: { $0.id == recipeID }) else { return nil }
        var updated = recipes[index]
        // Revert clears lastModificationId on the affected ingredients
        // so the ↺ chip disappears.
        applyMutation(to: &updated, payload: payload, modificationId: nil)
        updated.updatedAt = .now
        recipes[index] = updated
        save()
        return updated
    }

    private func applyMutation(
        to recipe: inout Recipe,
        payload: CooksyChatService.MutatedRecipePayload,
        modificationId: UUID?
    ) {
        let mutatedIngredientById = Dictionary(
            uniqueKeysWithValues: payload.ingredients.map { ($0.id, $0) }
        )
        recipe.ingredients = recipe.ingredients.map { existing in
            guard let mutated = mutatedIngredientById[existing.id] else { return existing }
            var copy = existing
            copy.name = mutated.name
            copy.amount = mutated.amount
            copy.unit = mutated.unit
            // The backend nulls originName on revert, sets it on first swap.
            // Mirror that signal locally so the ↺ chip disappears on revert.
            let nameChanged = existing.name != mutated.name
            if let origin = mutated.originName, !origin.isEmpty {
                copy.originIngredientId = existing.originIngredientId ?? existing.id
                copy.originName = origin
                copy.originAmount = copy.originAmount ?? existing.amount
                copy.originUnit = copy.originUnit ?? existing.unit
                if nameChanged, let modId = modificationId {
                    copy.lastModificationId = modId
                }
            } else {
                copy.originIngredientId = nil
                copy.originName = nil
                copy.originAmount = nil
                copy.originUnit = nil
                copy.lastModificationId = nil
            }
            return copy
        }

        let mutatedStepById = Dictionary(
            uniqueKeysWithValues: payload.steps.map { ($0.id, $0) }
        )
        recipe.steps = recipe.steps.map { existing in
            guard let mutated = mutatedStepById[existing.id] else { return existing }
            var copy = existing
            copy.detail = mutated.detail
            return copy
        }

        recipe.allergens = payload.allergens
        if let mutatedNutrition = payload.nutritionPerServing {
            recipe.nutrition = RecipeNutrition(
                calories: mutatedNutrition.calories,
                protein: mutatedNutrition.protein,
                carbs: mutatedNutrition.carbs,
                fat: mutatedNutrition.fat,
                fiber: mutatedNutrition.fiber,
                sugar: mutatedNutrition.sugar,
                salt: mutatedNutrition.salt,
                saturatedFat: mutatedNutrition.saturatedFat
            )
        }
        if let servings = payload.servings {
            recipe.details.servings = servings
        }
    }

    func deleteRecipe(id: Recipe.ID) {
        guard let recipe = recipe(withID: id) else { return }

        if let heroImageURL = recipe.heroImageURL, heroImageURL.isFileURL {
            try? fileManager.removeItem(at: heroImageURL)
        }

        recipes.removeAll { $0.id == id }

        for index in books.indices {
            books[index].recipeIDs.removeAll { $0 == id }
        }

        mealPlanEntries.removeAll { $0.recipeID == id }
        save()
    }

    func storeImageData(_ data: Data, for recipeID: Recipe.ID) -> URL? {
        let imagesDirectory = storageURL.deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true)
        let fileURL = imagesDirectory.appendingPathComponent("\(recipeID.uuidString).jpg")

        do {
            try fileManager.createDirectory(
                at: imagesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            assertionFailure("Unable to store recipe image: \(error)")
            return nil
        }
    }

    @discardableResult
    func replaceRecipeImage(id: Recipe.ID, with data: Data) -> URL? {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return nil }

        if let existingURL = recipes[index].heroImageURL, existingURL.isFileURL {
            try? fileManager.removeItem(at: existingURL)
        }

        guard let fileURL = storeImageData(data, for: id) else { return nil }

        recipes[index].heroImageURL = fileURL
        recipes[index].heroStyle = .ocean
        recipes[index].updatedAt = .now
        save()
        return fileURL
    }

    func recipes(in book: RecipeBook) -> [Recipe] {
        recipes.filter { book.recipeIDs.contains($0.id) }
    }

    func addMealPlanRecipe(recipeID: Recipe.ID, for day: Date, meal mealKind: MealPlanEntry.MealKind? = nil) {
        let normalizedDay = mealPlanCalendar.startOfDay(for: day)
        let targetMeal = mealKind ?? nextAvailableMealKind(on: normalizedDay)

        guard let targetMeal else { return }

        if let existingIndex = mealPlanEntries.firstIndex(where: {
            mealPlanCalendar.isDate($0.dayDate, inSameDayAs: normalizedDay) && $0.resolvedMealKind == targetMeal
        }) {
            guard mealPlanEntries[existingIndex].recipeID != recipeID else { return }
            mealPlanEntries[existingIndex].recipeID = recipeID
            mealPlanEntries[existingIndex].mealKind = targetMeal
            mealPlanEntries[existingIndex].createdAt = .now
        } else {
            mealPlanEntries.append(
                MealPlanEntry(dayDate: normalizedDay, recipeID: recipeID, mealKind: targetMeal)
            )
        }

        save()
    }

    func removeMealPlanRecipe(recipeID: Recipe.ID, from day: Date) {
        let normalizedDay = mealPlanCalendar.startOfDay(for: day)
        mealPlanEntries.removeAll {
            $0.recipeID == recipeID && mealPlanCalendar.isDate($0.dayDate, inSameDayAs: normalizedDay)
        }
        save()
    }

    func removeMealPlanRecipe(from day: Date, meal mealKind: MealPlanEntry.MealKind) {
        let normalizedDay = mealPlanCalendar.startOfDay(for: day)
        mealPlanEntries.removeAll {
            mealPlanCalendar.isDate($0.dayDate, inSameDayAs: normalizedDay) && $0.resolvedMealKind == mealKind
        }
        save()
    }

    func clearMealPlanRecipes(inWeekStartingAt weekStart: Date, calendar: Calendar) {
        let normalizedWeekStart = calendar.startOfDay(for: weekStart)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: normalizedWeekStart) else { return }

        mealPlanEntries.removeAll { entry in
            let day = calendar.startOfDay(for: entry.dayDate)
            return day >= normalizedWeekStart && day <= weekEnd
        }
        save()
    }

    private func attach(recipeID: Recipe.ID, to bookID: RecipeBook.ID?) {
        guard let bookID else { return }

        for index in books.indices {
            books[index].recipeIDs.removeAll { $0 == recipeID }
        }

        guard let destinationIndex = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[destinationIndex].recipeIDs.insert(recipeID, at: 0)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: storageURL),
            let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data)
        else {
            seedLibrary()
            return
        }

        recipes = snapshot.recipes
        books = snapshot.books
        mealPlanEntries = snapshot.mealPlanEntries
        migrateMealPlanEntriesIfNeeded()
        migrateUncategorizedBookTitleIfNeeded()
    }

    private func seedLibrary() {
        let uncategorizedBookID = UUID()

        recipes = []
        // Start with just the "Toutes les recettes" book. Users create
        // their own collections from here — we don't seed fake ones.
        books = [
            RecipeBook(
                id: uncategorizedBookID,
                title: "Toutes les recettes",
                kind: .uncategorized,
                previewStyle: .featured,
                recipeIDs: []
            )
        ]
        mealPlanEntries = []

        save()
    }

    /// Renames the legacy "Non classees" book to the new "Toutes les recettes"
    /// label without creating a second uncategorized row. Runs once per
    /// cold-start for existing users and is a no-op for fresh installs.
    private func migrateUncategorizedBookTitleIfNeeded() {
        guard let index = books.firstIndex(where: { $0.kind == .uncategorized }) else { return }
        let legacyTitles: Set<String> = ["Non classees", "Non classées"]
        guard legacyTitles.contains(books[index].title) else { return }
        books[index].title = "Toutes les recettes"
        save()
    }

    private func save() {
        do {
            let snapshot = LibrarySnapshot(
                recipes: recipes,
                books: books,
                mealPlanEntries: mealPlanEntries
            )
            let data = try encoder.encode(snapshot)

            let directory = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to save library snapshot: \(error)")
        }
    }

    private var storageURL: URL {
        let baseDirectory =
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupID) ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        return baseDirectory
            .appendingPathComponent("Cooksy", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private func nextAvailableMealKind(on day: Date) -> MealPlanEntry.MealKind? {
        let occupiedMeals = Set(
            mealPlanEntries
                .filter { mealPlanCalendar.isDate($0.dayDate, inSameDayAs: day) }
                .map(\.resolvedMealKind)
        )

        return MealPlanEntry.MealKind.allCases.first { !occupiedMeals.contains($0) }
    }

    private func migrateMealPlanEntriesIfNeeded() {
        let groupedEntries = Dictionary(grouping: mealPlanEntries) { entry in
            mealPlanCalendar.startOfDay(for: entry.dayDate)
        }

        var normalizedEntries: [MealPlanEntry] = []
        var didChange = false

        for day in groupedEntries.keys.sorted() {
            let sortedEntries = groupedEntries[day, default: []]
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.createdAt < rhs.createdAt
                }

            var occupiedMeals = Set<MealPlanEntry.MealKind>()

            for var entry in sortedEntries {
                if entry.dayDate != day {
                    entry.dayDate = day
                    didChange = true
                }

                if let mealKind = entry.mealKind, !occupiedMeals.contains(mealKind) {
                    occupiedMeals.insert(mealKind)
                    normalizedEntries.append(entry)
                    continue
                }

                guard let fallbackMeal = MealPlanEntry.MealKind.allCases.first(where: { !occupiedMeals.contains($0) }) else {
                    didChange = true
                    continue
                }

                entry.mealKind = fallbackMeal
                occupiedMeals.insert(fallbackMeal)
                normalizedEntries.append(entry)
                didChange = true
            }
        }

        normalizedEntries.sort { lhs, rhs in
            let leftDay = mealPlanCalendar.startOfDay(for: lhs.dayDate)
            let rightDay = mealPlanCalendar.startOfDay(for: rhs.dayDate)

            if leftDay == rightDay {
                return lhs.resolvedMealKind.sortOrder < rhs.resolvedMealKind.sortOrder
            }

            return leftDay < rightDay
        }

        guard didChange || normalizedEntries != mealPlanEntries else { return }
        mealPlanEntries = normalizedEntries
        save()
    }

}

private struct LibrarySnapshot: Codable {
    var recipes: [Recipe]
    var books: [RecipeBook]
    var mealPlanEntries: [MealPlanEntry]

    init(
        recipes: [Recipe],
        books: [RecipeBook],
        mealPlanEntries: [MealPlanEntry] = []
    ) {
        self.recipes = recipes
        self.books = books
        self.mealPlanEntries = mealPlanEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipes = try container.decode([Recipe].self, forKey: .recipes)
        books = try container.decode([RecipeBook].self, forKey: .books)
        mealPlanEntries = try container.decodeIfPresent([MealPlanEntry].self, forKey: .mealPlanEntries) ?? []
    }
}

private extension MealPlanEntry.MealKind {
    var sortOrder: Int {
        switch self {
        case .breakfast:
            return 0
        case .lunch:
            return 1
        case .dinner:
            return 2
        }
    }
}
