import SwiftUI

struct RecipeLibraryScreen: View {
    @ObservedObject private var store: RecipeStore

    private let openImportSheet: () -> Void

    @State private var searchText = ""
    /// `nil` = "Toutes les recettes" (no filter).
    @State private var selectedBookID: RecipeBook.ID? = nil
    @State private var showsCreateBookSheet = false

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
                    bookPickerStrip

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
        .sheet(isPresented: $showsCreateBookSheet) {
            CreateRecipeBookSheet { title in
                if let book = store.createBook(title: title) {
                    selectedBookID = book.id
                }
            }
        }
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

    private var bookPickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                bookPill(
                    title: "Toutes les recettes",
                    systemImage: "books.vertical.fill",
                    isSelected: selectedBookID == nil
                ) {
                    selectedBookID = nil
                }

                ForEach(userBooks) { book in
                    bookPill(
                        title: book.title,
                        systemImage: "book.closed.fill",
                        isSelected: selectedBookID == book.id
                    ) {
                        selectedBookID = book.id
                    }
                }

                bookPill(
                    title: "Nouveau",
                    systemImage: "plus",
                    isSelected: false,
                    isAccent: true
                ) {
                    showsCreateBookSheet = true
                }
            }
        }
    }

    private func bookPill(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isAccent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(pillForeground(isSelected: isSelected, isAccent: isAccent))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(pillBackground(isSelected: isSelected, isAccent: isAccent))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(pillStroke(isSelected: isSelected, isAccent: isAccent), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func pillForeground(isSelected: Bool, isAccent: Bool) -> Color {
        if isSelected { return .white }
        if isAccent { return CooksyTheme.ctaOrange }
        return CooksyTheme.secondaryText
    }

    private func pillBackground(isSelected: Bool, isAccent: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(CooksyTheme.accentGradient) }
        return AnyShapeStyle(Color.white)
    }

    private func pillStroke(isSelected: Bool, isAccent: Bool) -> Color {
        if isSelected { return .clear }
        if isAccent { return CooksyTheme.ctaOrange.opacity(0.6) }
        return CooksyTheme.stroke
    }

    private var userBooks: [RecipeBook] {
        store.books
            .filter { $0.kind == .collection }
            .sorted { $0.createdAt < $1.createdAt }
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
                matchesSearch(recipe) && matchesBook(recipe)
            }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.recipes.isEmpty ? "Aucune recette pour le moment" : "Aucune recette dans ce livre")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(store.recipes.isEmpty
                 ? "Importe ta première recette : elle apparaîtra ici, prête à cuisiner."
                 : "Essaie un autre terme de recherche ou change de livre pour voir plus de recettes.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            if store.recipes.isEmpty {
                Button(action: openImportSheet) {
                    Text("Importer une recette")
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
                Button("Réinitialiser les filtres") {
                    searchText = ""
                    selectedBookID = nil
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

    private func matchesBook(_ recipe: Recipe) -> Bool {
        guard let selectedBookID else { return true }
        return recipe.bookID == selectedBookID
    }
}

private struct LibraryFeaturedRecipeCard: View {
    let recipe: Recipe

    /// Locked card height — applied to BOTH the artwork frame and the
    /// outer ZStack so a tall portrait-orientation TikTok still can't
    /// stretch the card past it. Without the second `.frame(height:)`
    /// on the ZStack, the artwork would be 248pt but the ZStack would
    /// resize itself based on the image's natural aspect ratio,
    /// blowing the card up to ~1200pt and pushing the title overlay
    /// into the middle of nowhere.
    private static let cardHeight: CGFloat = 248

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LibraryRecipeArtwork(recipe: recipe, cornerRadius: 24)
                .frame(height: Self.cardHeight)

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
        // Lock the outer card height too — the inner artwork already
        // does this, but tall portrait imports can still stretch the
        // ZStack via its other children if we don't re-clamp here.
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                LibraryRecipeArtwork(recipe: recipe, cornerRadius: 18, contentAlignment: .top)
                    .frame(maxWidth: .infinity)
                    .frame(height: 122)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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
    /// Bias for center-cropping. Grid thumbnails use `.top` so portrait
    /// (9:16) photos from TikTok/Reels keep the subject in frame instead
    /// of showing the background. Featured hero keeps the default `.center`.
    var contentAlignment: Alignment = .center

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    croppedImage(Image(uiImage: uiImage))
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            croppedImage(image)
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        // Force the artwork to take the full proposed width and never
        // exceed it, regardless of the image's intrinsic aspect ratio.
        // Without this, a tall portrait import (9:16 TikTok still) can
        // push the parent layout to its natural height — overflowing
        // the rest of the card. Combined with the per-image .clipped()
        // inside `croppedImage`, this makes the artwork render at the
        // exact size the call site requested.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func croppedImage(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            .clipped()
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
