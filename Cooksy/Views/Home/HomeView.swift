import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var recipeStore: RecipeStore

    @StateObject private var viewModel: HomeViewModel
    @State private var showsCreateBookSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    init(store: RecipeStore, sharedLinkInbox: SharedLinkInbox) {
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(store: store, sharedLinkInbox: sharedLinkInbox)
        )
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    HomeWordmarkHeader()

                    ImportGuideBanner(
                        title: viewModel.bannerTitle
                    )

                    VStack(alignment: .leading, spacing: 22) {
                        recipeBooksHeader

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            CreateRecipeBookCard {
                                showsCreateBookSheet = true
                            }

                            if let uncategorizedBook = viewModel.uncategorizedBook {
                                NavigationLink {
                                    RecipeBookDetailView(bookID: uncategorizedBook.id)
                                } label: {
                                    RecipeBookCard(
                                        book: uncategorizedBook,
                                        recipes: recipeStore.recipes(in: uncategorizedBook)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(viewModel.customBooks) { book in
                                NavigationLink {
                                    RecipeBookDetailView(bookID: book.id)
                                } label: {
                                    RecipeBookCard(
                                        book: book,
                                        recipes: recipeStore.recipes(in: book)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .padding(.bottom, 148)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.refreshPendingImport()
        }
        .sheet(isPresented: $showsCreateBookSheet) {
            CreateRecipeBookSheet { title in
                recipeStore.createBook(title: title)
            }
        }
    }

    private var recipeBooksHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                Text("Livres de recettes")
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Button(action: {}) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 21, weight: .semibold))

                    Text("Trier")
                        .font(.system(size: 18, weight: .medium, design: .rounded))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(hex: 0xD7CCBB), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeWordmarkHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Text("Cooksy")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(CooksyTheme.brandBlueDark.opacity(0.22))
                        .offset(x: 0, y: 4)

                    Text("Cooksy")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: 0x8FC5FF), Color(hex: 0x2E7DDE)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(CooksyTheme.sparkleYellow, Color(hex: 0xF6A300))
                    .shadow(color: CooksyTheme.sparkleYellow.opacity(0.45), radius: 8, y: 2)
                    .offset(x: 12, y: -6)
            }
            .frame(width: 220, height: 74, alignment: .leading)

            Spacer(minLength: 0)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.top, 2)
    }
}

#Preview {
    let store = RecipeStore()
    NavigationStack {
        HomeView(store: store, sharedLinkInbox: SharedLinkInbox())
            .environmentObject(store)
    }
}
