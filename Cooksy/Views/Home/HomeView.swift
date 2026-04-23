import SwiftUI
import UIKit

struct HomeView: View {
    private let store: RecipeStore
    private let openRecipesTab: () -> Void
    private let openPlanTab: () -> Void
    private let openImportSheet: () -> Void
    private let openProfileTab: () -> Void

    @StateObject private var viewModel: HomeViewModel

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openRecipesTab: @escaping () -> Void = {},
        openPlanTab: @escaping () -> Void = {},
        openImportSheet: @escaping () -> Void = {},
        openProfileTab: @escaping () -> Void = {}
    ) {
        self.store = store
        self.openRecipesTab = openRecipesTab
        self.openPlanTab = openPlanTab
        self.openImportSheet = openImportSheet
        self.openProfileTab = openProfileTab
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(store: store, sharedLinkInbox: sharedLinkInbox)
        )
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    topBar
                    welcomeBlock
                    importGuideCard
                    recentImportsSection
                    trendingTodaySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.refreshPendingImport()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            Spacer()

            HomeCircleIconButton(systemName: "bell") {
                openProfileTab()
            }

            Button(action: openProfileTab) {
                HomeAvatarBadge(text: viewModel.profileBadgeText)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(viewModel.greetingLine)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CooksyTheme.sparkleYellow)
            }

            Text(viewModel.homeHeadline)
                .font(.system(size: 35, weight: .bold, design: .serif))
                .tracking(-0.8)
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importGuideCard: some View {
        Button(action: openImportSheet) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: 0xFFF2E4))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: viewModel.pendingImport == nil ? "square.and.arrow.down" : "arrow.trianglehead.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.importGuideTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Text(viewModel.importGuideSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("Import")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFF2E4))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var recentImportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Imports")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                if viewModel.hasRecentImports {
                    Button(action: openRecipesTab) {
                        Text("See all")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.hasRecentImports {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.recentImportCards) { card in
                            recentImportDestination(for: card)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 4)
                }
            } else {
                HomeRecentImportsEmptyState(onImport: openImportSheet)
            }
        }
    }

    private var trendingTodaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trending Today")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))

                    Text("Hot")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CooksyTheme.ctaOrange)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.trendingTodayItems) { item in
                    trendingDestination(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func recentImportDestination(for card: HomeViewModel.RecentImportCard) -> some View {
        if let recipeID = card.destinationRecipeID {
            NavigationLink {
                RecipeDetailView(store: store, recipeID: recipeID)
            } label: {
                HomeRecentImportCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: openImportSheet) {
                HomeRecentImportCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    private func trendingDestination(for item: HomeViewModel.TrendingRecipe) -> some View {
        NavigationLink {
            TrendingRecipePreviewView(
                scenario: item.scenario,
                store: store
            )
        } label: {
            HomeTrendingRecipeRow(item: item)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeCircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.98))
                )
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeAvatarBadge: View {
    let text: String

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xD9B596), Color(hex: 0xB77850)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 34)
            .overlay {
                Text(text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct HomeRecentImportCardView: View {
    let card: HomeViewModel.RecentImportCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                HomeArtworkSurface(artwork: card.artwork, emojiSize: 42)
                    .frame(width: 208, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(alignment: .top) {
                    Text(card.sourceLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        )

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .bold))

                        Text(card.ratingLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                }
                .padding(10)
            }

            Text(card.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            HStack(spacing: 10) {
                HomeMetaLabel(systemName: "clock", text: card.durationLabel)
                HomeMetaLabel(systemName: "flame.fill", text: card.caloriesLabel)
            }
        }
        .frame(width: 208, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }
}

private struct HomeTrendingRecipeRow: View {
    let item: HomeViewModel.TrendingRecipe

    var body: some View {
        HStack(spacing: 12) {
            Text("\(item.rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .frame(width: 16)

            TrendingArtworkSurface(
                style: TrendingArtworkStyle.forScenarioID(item.scenario.id),
                symbolSize: 20
            )
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(item.handle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)

                    Text("•")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CooksyTheme.stroke)

                    Text(item.durationLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))

                Text(item.ratingLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }
}

private struct HomeRecentImportsEmptyState: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.5))

            VStack(spacing: 6) {
                Text("No recipes yet")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Import your first recipe from TikTok, Instagram or any link")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onImport) {
                Text("Import a recipe")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFF2E4))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct HomeMetaLabel: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(CooksyTheme.secondaryText)
    }
}

private struct HomeArtworkSurface: View {
    let artwork: HomeViewModel.Artwork
    let emojiSize: CGFloat

    var body: some View {
        Group {
            switch artwork {
            case .recipe(let recipe):
                if recipe.heroImageURL == nil,
                   let previewSeed = DemoRecipeMatcherService.match(sharedText: recipe.title),
                   let imageData = previewSeed.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RecipeThumbnail(recipe: recipe)
                }
            case .demo(let scenario):
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hex: scenario.hero.topColorHex),
                            Color(hex: scenario.hero.bottomColorHex)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 92, height: 92)
                        .offset(x: 38, y: -28)

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 74, height: 74)
                        .offset(x: -34, y: 30)

                    Text(scenario.hero.emoji)
                        .font(.system(size: emojiSize))
                }
            }
        }
        .clipped()
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
