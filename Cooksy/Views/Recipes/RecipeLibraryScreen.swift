import SwiftUI

struct RecipeLibraryScreen: View {
    private enum LibraryCategory: String, CaseIterable {
        case all = "All"
        case italian = "Italian"
        case asian = "Asian"
        case healthy = "Healthy"
        case mexican = "Mexican"
        case other = "Other"
    }

    @ObservedObject private var store: RecipeStore

    private let openImportSheet: () -> Void

    @State private var searchText = ""
    @State private var selectedCategory: LibraryCategory = .all

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openImportSheet: @escaping () -> Void = {}
    ) {
        self.store = store
        self.openImportSheet = openImportSheet
        _ = sharedLinkInbox
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerRow
                    searchField
                    categoryStrip

                    if let featuredRecipe {
                        Text("FEATURED")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(CooksyTheme.secondaryText.opacity(0.82))

                        NavigationLink {
                            RecipeDetailView(store: store, recipeID: featuredRecipe.id)
                        } label: {
                            LibraryFeaturedRecipeCard(recipe: featuredRecipe)
                        }
                        .buttonStyle(.plain)

                        if !gridRecipes.isEmpty {
                            Text("ALL RECIPES")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .tracking(1.0)
                                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.82))

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(gridRecipes) { recipe in
                                    NavigationLink {
                                        RecipeDetailView(store: store, recipeID: recipe.id)
                                    } label: {
                                        LibraryRecipeGridCard(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        emptyStateCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 150)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            Text("Recipe Library")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("\(store.recipes.count) recipes")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.ctaOrange)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CooksyTheme.secondaryText)

            TextField("Search recipes...", text: $searchText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableCategories, id: \.rawValue) { category in
                    Button(action: { selectedCategory = category }) {
                        Text(category.rawValue)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedCategory == category ? .white : CooksyTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedCategory == category ? AnyShapeStyle(CooksyTheme.accentGradient) : AnyShapeStyle(Color.white))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(selectedCategory == category ? Color.clear : CooksyTheme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var featuredRecipe: Recipe? {
        filteredRecipes.first
    }

    private var gridRecipes: [Recipe] {
        Array(filteredRecipes.dropFirst())
    }

    private var filteredRecipes: [Recipe] {
        store.recipes
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .filter { recipe in
                matchesSearch(recipe) && matchesCategory(recipe)
            }
    }

    private var availableCategories: [LibraryCategory] {
        var categories: [LibraryCategory] = [.all, .italian, .asian, .healthy, .mexican]
        let hasOtherRecipes = store.recipes.contains { inferredCategory(for: $0) == .other }
        if hasOtherRecipes {
            categories.append(.other)
        }
        return categories
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.recipes.isEmpty ? "No recipes yet" : "No recipes match this filter")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(store.recipes.isEmpty
                 ? "Import your first recipe and it will appear here with search and category filters."
                 : "Try another search term or switch category to see more recipes.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            if store.recipes.isEmpty {
                Button(action: openImportSheet) {
                    Text("Import a recipe")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button("Reset filters") {
                    searchText = ""
                    selectedCategory = .all
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func matchesSearch(_ recipe: Recipe) -> Bool {
        let query = RecipePresentationFormatter.normalizedSearchText(for: searchText)
        guard !query.isEmpty else { return true }

        let haystack = RecipePresentationFormatter.normalizedSearchText(
            for: [
                recipe.title,
                recipe.ingredients.map(\.name).joined(separator: " "),
                recipe.notes ?? ""
            ].joined(separator: " ")
        )

        return haystack.contains(query)
    }

    private func matchesCategory(_ recipe: Recipe) -> Bool {
        selectedCategory == .all || inferredCategory(for: recipe) == selectedCategory
    }

    private func inferredCategory(for recipe: Recipe) -> LibraryCategory {
        let text = RecipePresentationFormatter.normalizedSearchText(
            for: [
                recipe.title,
                recipe.ingredients.map(\.name).joined(separator: " "),
                recipe.notes ?? ""
            ].joined(separator: " ")
        )

        if containsAny(text, keywords: ["pasta", "risotto", "lasagna", "parmesan", "italian", "gnocchi", "tiramisu"]) {
            return .italian
        }

        if containsAny(text, keywords: ["ramen", "miso", "ginger", "soy", "teriyaki", "asian", "noodle", "kimchi", "curry"]) {
            return .asian
        }

        if containsAny(text, keywords: ["healthy", "protein", "salad", "oats", "avocado", "quinoa", "yogurt", "spinach"]) {
            return .healthy
        }

        if containsAny(text, keywords: ["taco", "quesadilla", "mexican", "salsa", "burrito", "birria", "guacamole"]) {
            return .mexican
        }

        return .other
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains(where: text.contains)
    }
}

private struct LibraryFeaturedRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LibraryRecipeArtwork(recipe: recipe, cornerRadius: 24)
                .frame(height: 248)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let sourceLabel = RecipePresentationFormatter.sourceLabel(for: recipe.sourceURL) {
                        Text(sourceLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.ctaOrange.opacity(0.95))
                            )
                    }

                    Spacer(minLength: 0)

                    if let rating = RecipePresentationFormatter.ratingText(for: recipe.externalRating) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(rating)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(CooksyTheme.primaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.94))
                        )
                    }
                }

                Text(recipe.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let timeLabel = libraryTimeLabel(for: recipe) {
                        LibraryMetaText(text: timeLabel)
                    }

                    if let caloriesLabel = libraryCaloriesLabel(for: recipe) {
                        LibraryMetaText(text: caloriesLabel)
                    }

                    LibraryMetaText(text: RecipePresentationFormatter.difficultyLabel(for: recipe))
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct LibraryRecipeGridCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                LibraryRecipeArtwork(recipe: recipe, cornerRadius: 18)
                    .frame(height: 122)

                HStack {
                    if let sourceLabel = RecipePresentationFormatter.sourceLabel(for: recipe.sourceURL) {
                        Text(sourceLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.65))
                            )
                    }

                    Spacer(minLength: 0)

                    if let rating = RecipePresentationFormatter.ratingText(for: recipe.externalRating) {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(rating)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(CooksyTheme.primaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.95))
                        )
                    }
                }
                .padding(8)
            }

            Text(recipe.title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                if let timeLabel = libraryTimeLabel(for: recipe) {
                    LibraryGridMetaLabel(systemImage: "clock.fill", text: timeLabel)
                }

                if let caloriesLabel = libraryCaloriesLabel(for: recipe) {
                    LibraryGridMetaLabel(systemImage: "flame.fill", text: caloriesLabel)
                }

                LibraryGridMetaLabel(
                    systemImage: "bolt.fill",
                    text: RecipePresentationFormatter.difficultyLabel(for: recipe)
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct LibraryRecipeArtwork: View {
    let recipe: Recipe
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CooksyTheme.recipeGradient(for: recipe.heroStyle))
    }
}

private struct LibraryMetaText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
    }
}

private struct LibraryGridMetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CooksyTheme.ctaOrange)

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

private func libraryTimeLabel(for recipe: Recipe) -> String? {
    let minutes = (recipe.details.prepTimeMinutes ?? 0) + (recipe.details.cookTimeMinutes ?? 0)
    guard minutes > 0 else { return nil }
    return "\(minutes) min"
}

private func libraryCaloriesLabel(for recipe: Recipe) -> String? {
    guard let calories = RecipePresentationFormatter.parseNumber(from: recipe.nutrition?.calories),
          calories > 0 else {
        return nil
    }

    return "\(Int(calories.rounded())) kcal"
}
