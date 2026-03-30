import SwiftUI
import UIKit

struct HomeView: View {
    private let store: RecipeStore
    private let openRecipesTab: () -> Void
    private let openPlanTab: () -> Void
    private let openImportSheet: () -> Void

    @StateObject private var viewModel: HomeViewModel

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openRecipesTab: @escaping () -> Void = {},
        openPlanTab: @escaping () -> Void = {},
        openImportSheet: @escaping () -> Void = {}
    ) {
        self.store = store
        self.openRecipesTab = openRecipesTab
        self.openPlanTab = openPlanTab
        self.openImportSheet = openImportSheet
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(store: store, sharedLinkInbox: sharedLinkInbox)
        )
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HomeWordmarkHeader()
                    editorialHero
                    snapshotSection
                    libraryBridgeSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 116)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.refreshPendingImport()
        }
    }

    private var editorialHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(CooksyTheme.heroGlowGradient.opacity(0.82))
                        .blur(radius: 14)
                        .padding(20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
                .shadow(color: CooksyTheme.shadow, radius: 16, y: 9)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AUJOURD'HUI")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)

                        Text(viewModel.welcomeHeadline)
                            .font(.system(size: 27, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text(viewModel.pendingImport == nil ? "Plan, recettes et import sous la main." : "Un import vous attend.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)
                    }
                }

                heroStatLine

                HStack(spacing: 12) {
                    HomePrimaryActionButton(
                        title: viewModel.pendingImport == nil ? "Importer une recette" : "Reprendre l’import"
                    ) {
                        openImportSheet()
                    }

                    HomeSecondaryActionButton(
                        title: "Ouvrir le plan"
                    ) {
                        openPlanTab()
                    }
                }

                Button(action: openRecipesTab) {
                    HStack(spacing: 8) {
                        Text("Ouvrir les recettes")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(CooksyTheme.primaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    private var heroStatLine: some View {
        HStack(spacing: 10) {
            heroStatColumn(title: "Recettes", value: "\(viewModel.totalRecipeCount)")
            heroStatColumn(title: "Livres", value: "\(viewModel.displayedBookCount)")
            heroStatColumn(title: "Plan", value: "\(viewModel.weekPlannedCount)")
        }
    }

    private func heroStatColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.surface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.9), lineWidth: 1)
        )
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("L'ESSENTIEL")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(CooksyTheme.secondaryText)

                    Text("Tout tenir sur un écran")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                Spacer(minLength: 0)

                Button(action: openRecipesTab) {
                    Text("Recettes")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12, alignment: .top),
                    GridItem(.flexible(), spacing: 12, alignment: .top)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                planSnapshotCard
                recipeSnapshotCard
            }
        }
    }

    private var planSnapshotCard: some View {
        Button(action: openPlanTab) {
            VStack(alignment: .leading, spacing: 12) {
                snapshotEyebrow(
                    title: "PLAN"
                )

                if let meal = viewModel.upcomingMeals.first {
                    Text(meal.recipe.title)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)

                    Text("\(meal.dayLabel) • \(meal.mealLabel)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Text("\(viewModel.weekPlannedCount) repas cette semaine")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                } else {
                    Text("Semaine vide")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("Ajoutez un repas pour démarrer.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Text("Ouvrir le plan")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .padding(16)
            .background(homePanelBackground)
        }
        .buttonStyle(.plain)
    }

    private var recipeSnapshotCard: some View {
        Group {
            if let featuredRecipe = viewModel.featuredRecipe {
                NavigationLink {
                    RecipeDetailView(store: store, recipeID: featuredRecipe.id)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        snapshotEyebrow(
                            title: "RECETTE"
                        )

                        RecipeThumbnail(recipe: featuredRecipe)
                            .frame(height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text(featuredRecipe.title)
                            .font(.system(size: 21, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text("\(featuredRecipe.ingredients.count) ingrédients • \(featuredRecipe.steps.count) étapes")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                    .padding(16)
                    .background(homePanelBackground)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: openImportSheet) {
                    VStack(alignment: .leading, spacing: 12) {
                        snapshotEyebrow(
                            title: "RECETTE"
                        )

                        Text("Aucune recette")
                            .font(.system(size: 21, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Importez-en une pour remplir l’accueil.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        Text("Importer")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                    .padding(16)
                    .background(homePanelBackground)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var libraryBridgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIVRES")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(CooksyTheme.secondaryText)

                    Text("Vos rangements")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                Spacer(minLength: 0)

                Button(action: openRecipesTab) {
                    Text("Voir tout")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .buttonStyle(.plain)
            }

            if viewModel.highlightedBooks.isEmpty {
                Button(action: openRecipesTab) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Créer un premier livre")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text("Vos recettes seront rangées ici.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(homePanelBackground)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.highlightedBooks) { book in
                            Button(action: openRecipesTab) {
                                CompactBookBridgeChip(
                                    book: book,
                                    recipes: store.recipes(in: book)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private func snapshotEyebrow(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
    }

    private var homePanelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(CooksyTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
    }
}

struct RecipeLibraryView: View {
    @ObservedObject private var store: RecipeStore

    private let sharedLinkInbox: SharedLinkInbox
    private let openImportSheet: () -> Void

    @State private var showsCreateBookSheet = false
    @State private var pendingImportHostLabel: String?

    private let columns = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openImportSheet: @escaping () -> Void = {}
    ) {
        self.store = store
        self.sharedLinkInbox = sharedLinkInbox
        self.openImportSheet = openImportSheet
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    libraryHeader
                    libraryOverview
                    ImportGuideBanner(
                        title: pendingImportHostLabel == nil ? "Importer une recette depuis un lien ou une vidéo" : "Lien partagé depuis \(pendingImportHostLabel ?? "une app")",
                        action: openImportSheet
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Vos livres")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("\(displayedBookCount) livres pour \(store.recipes.count) recettes.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        CreateRecipeBookCard {
                            showsCreateBookSheet = true
                        }

                        if let uncategorizedBook {
                            NavigationLink {
                                RecipeBookDetailView(bookID: uncategorizedBook.id)
                            } label: {
                                RecipeBookCard(
                                    book: uncategorizedBook,
                                    recipes: store.recipes(in: uncategorizedBook)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(customBooks) { book in
                            NavigationLink {
                                RecipeBookDetailView(bookID: book.id)
                            } label: {
                                RecipeBookCard(
                                    book: book,
                                    recipes: store.recipes(in: book)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 146)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            pendingImportHostLabel = sharedLinkInbox.peek()?.hostLabel
        }
        .sheet(isPresented: $showsCreateBookSheet) {
            CreateRecipeBookSheet { title in
                store.createBook(title: title)
            }
        }
    }

    private var uncategorizedBook: RecipeBook? {
        store.books.first(where: { $0.kind == .uncategorized })
    }

    private var customBooks: [RecipeBook] {
        store.books
            .filter { $0.kind == .collection }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var displayedBookCount: Int {
        (uncategorizedBook == nil ? 0 : 1) + customBooks.count
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECETTES")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text("Votre bibliothèque")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("Tous les livres et toutes les recettes vivent ici, sans encombrer l’accueil.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }

    private var libraryOverview: some View {
        HStack(spacing: 14) {
            libraryMetric(title: "Recettes", value: "\(store.recipes.count)")
            libraryMetric(title: "Livres", value: "\(displayedBookCount)")
            libraryMetric(title: "Semaine", value: "\(store.mealPlanEntries.count)")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func libraryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomePrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            .foregroundStyle(CooksyTheme.primaryText)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactBookBridgeChip: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 10) {
            BookPreviewStrip(recipes: recipes)
                .frame(width: 72, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)

                Text("\(book.recipeCount) recette\(book.recipeCount > 1 ? "s" : "")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct CompactRecentRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumbnail(recipe: recipe)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)

                Text("\(recipe.ingredients.count) ingrédients • \(recipe.steps.count) étapes")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.vertical, 14)
    }
}

private struct MiniBookBridgeCard: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookPreviewStrip(recipes: recipes)
                .frame(width: 208, height: 86)

            Text(book.title)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(2)

            Text("\(book.recipeCount) recette\(book.recipeCount > 1 ? "s" : "")")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(14)
        .frame(width: 228, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct BookPreviewStrip: View {
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(recipes.prefix(3).enumerated()), id: \.offset) { _, recipe in
                RecipeThumbnail(recipe: recipe)
                    .frame(maxWidth: .infinity)
            }

            if recipes.isEmpty {
                placeholderTile
            } else if recipes.count == 1 {
                placeholderTile
                placeholderTile
            } else if recipes.count == 2 {
                placeholderTile
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.warmCard.opacity(0.72))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CooksyTheme.elevatedSurface.opacity(0.88))
    }
}

private struct RecipeFeatureArtwork: View {
    let recipe: Recipe

    var body: some View {
        RecipeThumbnail(recipe: recipe)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(CooksyTheme.stroke.opacity(0.82), lineWidth: 1)
            )
    }
}

private struct RecipeThumbnail: View {
    let recipe: Recipe

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
        .clipped()
    }

    private var fallback: some View {
        LinearGradient(
            colors: fallbackColors,
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var fallbackColors: [Color] {
        CooksyTheme.recipeGradientColors(for: recipe.heroStyle)
    }
}

private struct HomeWordmarkHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            Text("Cooksy")
                .font(.custom("AvenirNext-HeavyItalic", size: 38))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cooksy")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
