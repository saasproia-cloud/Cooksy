import Combine
import SwiftUI
import UIKit

@MainActor
struct ImportedRecipeReviewView: View {
    @Environment(\.dismiss) private var dismiss

    private let store: RecipeStore
    private let onSaved: ((Recipe.ID) -> Void)?
    @StateObject private var viewModel: ImportedRecipeReviewViewModel
    @State private var showsBookPicker = false
    @State private var showsEditor = false
    @State private var showsReportAlert = false

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed,
        validation: RecipeValidationResult,
        preferredBookID: RecipeBook.ID? = nil,
        onSaved: ((Recipe.ID) -> Void)? = nil
    ) {
        self.store = store
        self.onSaved = onSaved
        _viewModel = StateObject(
            wrappedValue: ImportedRecipeReviewViewModel(
                store: store,
                seed: seed,
                validation: validation,
                preferredBookID: preferredBookID
            )
        )
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 22)

                    headerSection
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)

                    if let importNotice = viewModel.importNotice {
                        importNoticeSection(importNotice)
                    }

                    sectionDivider

                    ingredientsSection

                    if !viewModel.seed.normalizedSteps.isEmpty {
                        sectionDivider
                        instructionsSection
                    }
                }
                .padding(.bottom, 230)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadRemoteImageIfNeeded()
        }
        .sheet(isPresented: $showsBookPicker) {
            ImportBookPickerSheet(
                books: viewModel.books,
                selectedBookID: viewModel.selectedBookID,
                onSelect: { bookID in
                    viewModel.selectBook(bookID)
                    showsBookPicker = false
                }
            )
        }
        .fullScreenCover(isPresented: $showsEditor) {
            CreateRecipeView(store: store, seed: viewModel.seed, preferredBookID: viewModel.selectedBookID) {
                showsEditor = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Merci pour le signalement", isPresented: $showsReportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On notera cette importation comme a verifier dans la prochaine iteration.")
        }
    }

    private var topBar: some View {
        HStack {
            topPillButton(title: "Annuler", tint: CooksyTheme.primaryText) {
                dismiss()
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.84))
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.72), lineWidth: 1.2)
                    )
                    .shadow(color: CooksyTheme.shadow, radius: 16, y: 10)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            RecipeImportHeroImage(image: viewModel.heroImage)

            VStack(alignment: .leading, spacing: 14) {
                Text("Recette reconstruite par Cooksy")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.85))
                    )

                Text(viewModel.seed.normalizedTitle)
                    .font(.system(size: titleFontSize, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let sourceLabel = viewModel.sourceLabel {
                    Text(sourceLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

                Button(action: { showsEditor = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrange)

                        Text("Modifier la recette")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("INGRÉDIENTS")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.brandBlueDark)
                .tracking(1.2)
                .padding(.horizontal, 22)
                .padding(.top, 18)

            VStack(spacing: 18) {
                ForEach(viewModel.seed.normalizedIngredients) { ingredient in
                    HStack(alignment: .top, spacing: 16) {
                        ingredientIcon(for: ingredient.name)

                        formattedIngredientText(for: ingredient)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("INSTRUCTIONS")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.brandBlueDark)
                .tracking(1.2)
                .padding(.horizontal, 22)
                .padding(.top, 18)

            VStack(spacing: 18) {
                ForEach(Array(viewModel.seed.normalizedSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(CooksyTheme.brandBlueDark)
                            )

                        Text(step.detail)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func importNoticeSection(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CooksyTheme.brandBlueDark)
                .padding(.top, 2)

            Text(notice)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let reviewNotice = viewModel.reviewNotice {
                Text(reviewNotice)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(viewModel.canSave ? CooksyTheme.ctaOrangeDark : Color.red.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button(action: { showsBookPicker = true }) {
                HStack(spacing: 14) {
                    Text(viewModel.selectedBookLabel)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .padding(.horizontal, 20)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    Rectangle()
                        .stroke(CooksyTheme.stroke, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Button(action: saveRecipe) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(viewModel.canSave ? CooksyTheme.ctaOrange : CooksyTheme.stroke.opacity(0.55))
                        .frame(height: 66)

                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(viewModel.canSave ? "Enregistrer" : "Modifier avant d'enregistrer")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving || !viewModel.canSave)

            Button(action: { showsReportAlert = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                    Text("Signaler une erreur d'importation")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 20, y: -6)
        )
    }

    private func saveRecipe() {
        Task {
            if let recipeID = await viewModel.saveRecipe() {
                onSaved?(recipeID)
                dismiss()
            }
        }
    }

    private func topPillButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 26)
                .frame(height: 62)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
                )
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(CooksyTheme.warmCard.opacity(0.8))
            .frame(height: 16)
    }

    private func formattedIngredientText(for ingredient: RecipeIngredient) -> Text {
        let prefix = [ingredient.amount, ingredient.unit]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if prefix.isEmpty {
            return Text(ingredient.name)
        }

        return Text(prefix + " ").bold() + Text(ingredient.name)
    }

    @ViewBuilder
    private func ingredientIcon(for ingredientName: String) -> some View {
        if let emoji = ShoppingCatalog.specificEmoji(for: ingredientName) {
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 38)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.surface)
                    .frame(width: 38, height: 38)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 38)
        }
    }

    private var titleFontSize: CGFloat {
        let count = viewModel.seed.normalizedTitle.count
        switch count {
        case ..<28:
            return 31
        case ..<46:
            return 27
        case ..<72:
            return 24
        default:
            return 22
        }
    }
}

@MainActor
private final class ImportedRecipeReviewViewModel: ObservableObject {
    @Published private(set) var seed: RecipeEditorSeed
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var heroImage: UIImage?
    @Published private(set) var isSaving = false
    @Published var selectedBookID: RecipeBook.ID?

    private let store: RecipeStore
    private let validation: RecipeValidationResult
    private let preferredBookID: RecipeBook.ID?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed,
        validation: RecipeValidationResult,
        preferredBookID: RecipeBook.ID? = nil
    ) {
        self.store = store
        self.validation = validation
        self.preferredBookID = preferredBookID
        self.seed = seed
        self.heroImage = seed.imageData.flatMap(UIImage.init(data:))

        store.$books
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                self?.books = books
                self?.applyDefaultBookIfNeeded()
            }
            .store(in: &cancellables)

        books = store.books
        applyDefaultBookIfNeeded()
    }

    var selectedBookLabel: String {
        guard let book = books.first(where: { $0.id == selectedBookID }) else {
            return "Sélectionnez un livre de recettes"
        }

        return book.kind == .uncategorized ? "Non catégorisé" : book.title
    }

    var sourceLabel: String? {
        let trimmedNotes = seed.notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = trimmedNotes.components(separatedBy: "\n").first,
           firstLine.hasPrefix("Source demo : ") {
            return firstLine
        }

        guard let host = seed.sourceURL?.host(percentEncoded: false), !host.isEmpty else {
            return nil
        }

        let loweredHost = host.lowercased()
        if loweredHost.contains("tiktok") { return "TikTok" }
        if loweredHost.contains("instagram") { return "Instagram" }
        if loweredHost.contains("youtube") { return "YouTube" }
        if loweredHost.contains("pinterest") { return "Pinterest" }

        return host
    }

    var canSave: Bool {
        validation.canSave
    }

    var importNotice: String? {
        seed.importNotice
    }

    var reviewNotice: String? {
        validation.reviewNotice
    }

    func selectBook(_ bookID: RecipeBook.ID) {
        selectedBookID = bookID
    }

    func loadRemoteImageIfNeeded() async {
        guard heroImage == nil, let remoteImageURL = seed.remoteImageURL else { return }
        guard let data = await RecipeWebImportService.downloadImageData(from: remoteImageURL) else { return }

        seed.imageData = data
        heroImage = UIImage(data: data)
    }

    @discardableResult
    func saveRecipe() async -> Recipe.ID? {
        guard !isSaving, canSave else { return nil }
        isSaving = true
        defer { isSaving = false }

        if seed.imageData == nil {
            await loadRemoteImageIfNeeded()
        }

        let recipeID = UUID()
        let imageURL = seed.imageData.flatMap { store.storeImageData($0, for: recipeID) }
        let recipe = seed.makeRecipe(id: recipeID, bookID: selectedBookID, imageURL: imageURL)
        store.addRecipe(recipe, to: selectedBookID)
        return recipeID
    }

    private func applyDefaultBookIfNeeded() {
        guard selectedBookID == nil else { return }
        if let preferredBookID, books.contains(where: { $0.id == preferredBookID }) {
            selectedBookID = preferredBookID
        } else {
            selectedBookID = books.first(where: { $0.kind == .uncategorized })?.id ?? books.first?.id
        }
    }
}

private struct RecipeImportHeroImage: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.warmCard)
                .frame(width: 110, height: 110)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(CooksyTheme.brandBlueDark.opacity(0.8))
            }
        }
    }
}

private struct ImportBookPickerSheet: View {
    let books: [RecipeBook]
    let selectedBookID: RecipeBook.ID?
    let onSelect: (RecipeBook.ID) -> Void

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button(action: { onSelect(book.id) }) {
                    HStack {
                        Text(book.kind == .uncategorized ? "Non catégorisé" : book.title)
                            .foregroundStyle(CooksyTheme.primaryText)
                        Spacer()
                        if selectedBookID == book.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(CooksyTheme.ctaOrange)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.background)
            .navigationTitle("Livre")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
