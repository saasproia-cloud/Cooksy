import Combine
import Foundation

@MainActor
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var mealPlanEntries: [MealPlanEntry] = []

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let mealPlanCalendar: Calendar

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

    func addRecipe(_ recipe: Recipe, to destinationBookID: RecipeBook.ID? = nil) {
        let destinationID = destinationBookID ?? uncategorizedBookID
        var storedRecipe = recipe
        storedRecipe.bookID = destinationID
        recipes.insert(storedRecipe, at: 0)
        attach(recipeID: storedRecipe.id, to: destinationID)
        save()
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
    }

    private func seedLibrary() {
        let uncategorizedBookID = UUID()

        recipes = []
        books = [
            RecipeBook(
                id: uncategorizedBookID,
                title: "Non classees",
                kind: .uncategorized,
                previewStyle: .featured,
                recipeIDs: []
            ),
            RecipeBook(
                title: "Diner",
                kind: .collection,
                previewStyle: .neutral,
                recipeIDs: []
            )
        ]
        mealPlanEntries = []

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
