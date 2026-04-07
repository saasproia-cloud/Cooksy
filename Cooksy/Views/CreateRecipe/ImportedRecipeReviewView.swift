import Combine
import SwiftUI
import UIKit

@MainActor
struct ImportedRecipeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let store: RecipeStore
    private let onSaved: ((Recipe.ID) -> Void)?
    @StateObject private var viewModel: ImportedRecipeReviewViewModel
    @State private var showsEditor = false
    @State private var showsReportAlert = false
    @State private var showsPlanSheet = false
    @State private var showsShareSheet = false
    @State private var showsStepByStep = false

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

    @State private var selectedTab: RecipePresentationTab = .ingredients
    @State private var checkedIngredients: Set<UUID> = []

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F5)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // MARK: – Immersive Hero
                    heroSection

                    // MARK: – Content Body
                    VStack(spacing: 20) {
                        titleCard

                        quickActionsRow

                        if let sourceButtonTitle = viewModel.sourceButtonTitle, let sourceURL = viewModel.sourceURL {
                            sourceRow(title: sourceButtonTitle, url: sourceURL)
                        }

                        tabSelector

                        selectedTabContent
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                    .offset(y: -32)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadRemoteImageIfNeeded()
            IngredientVisualCatalog.preload()
        }
        .sheet(isPresented: $showsPlanSheet) {
            ImportRecipePlanSelectionSheet { day in
                Task {
                    if let recipeID = await viewModel.saveRecipe(plannedFor: day) {
                        onSaved?(recipeID)
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            RecipeImportActivityShareSheet(activityItems: [viewModel.shareText()])
        }
        .fullScreenCover(isPresented: $showsEditor) {
            CreateRecipeView(store: store, seed: viewModel.seed, preferredBookID: viewModel.selectedBookID) {
                showsEditor = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showsStepByStep) {
            StepByStepCookingView(recipeTitle: viewModel.title, steps: viewModel.instructions)
        }
        .safeAreaInset(edge: .bottom) {
            saveArea
        }
        .alert("Merci pour le signalement", isPresented: $showsReportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On notera cette importation comme a verifier dans la prochaine iteration.")
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack(alignment: .top) {
            Group {
                if let heroImage = viewModel.heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RecipePresentationHeroPlaceholder(heroStyle: .ocean)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipped()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .frame(height: 380)

            HStack {
                heroActionButton(systemImage: "chevron.left") {
                    dismiss()
                }

                Spacer()

                heroActionButton(systemImage: "square.and.arrow.up") {
                    showsShareSheet = true
                }

                Menu {
                    Button("Modifier") { showsEditor = true }

                    if let sourceURL = viewModel.sourceURL {
                        Button("Ouvrir la source") {
                            openURL(sourceURL)
                        }
                    }

                    Button("Signaler une erreur d'importation") {
                        showsReportAlert = true
                    }
                } label: {
                    heroActionButton(systemImage: "ellipsis")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                HStack(spacing: 8) {
                    if let handle = viewModel.creatorHandle {
                        Text(handle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(.ultraThinMaterial.opacity(0.6)))
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.1)))
                    }

                    Spacer()

                    Text(viewModel.difficultyLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(.ultraThinMaterial.opacity(0.5)))
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.1)))
                }

                Text(viewModel.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 380)
    }

    @ViewBuilder
    private func heroActionButton(systemImage: String, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    heroButtonLabel(systemImage: systemImage)
                }
                .buttonStyle(.plain)
            } else {
                heroButtonLabel(systemImage: systemImage)
            }
        }
    }

    private func heroButtonLabel(systemImage: String) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Title Card

    private var titleCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                quickStat(icon: "clock", label: viewModel.totalTimeLabel ?? "—")

                statDivider

                quickStat(icon: "person.2", label: "\(viewModel.currentServings) portions")

                statDivider

                quickStat(icon: "chart.bar", label: viewModel.difficultyLabel)
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0xFAF8F5))
            )

            HStack {
                Text("Portions")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                HStack(spacing: 12) {
                    Button { viewModel.changeServings(by: -1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(hex: 0xFAF8F5)))
                    }
                    .buttonStyle(.plain)

                    Text("\(viewModel.currentServings)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .frame(minWidth: 24)

                    Button { viewModel.changeServings(by: 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(CooksyTheme.accentWarm))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                summaryCapsule(text: "\(viewModel.displayedIngredients.count) ingrédients", icon: "leaf")
                summaryCapsule(text: "\(viewModel.instructions.count) étapes", icon: "list.number")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)
        )
    }

    private func quickStat(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CooksyTheme.accentWarm)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(CooksyTheme.dividerSubtle)
            .frame(width: 1, height: 22)
    }

    private func summaryCapsule(text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CooksyTheme.accentWarm)

            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: 0xFAF8F5))
        )
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickActionButton(icon: "pencil", label: "Modifier") {
                showsEditor = true
            }

            quickActionButton(icon: "calendar.badge.plus", label: "Plan") {
                showsPlanSheet = true
            }

            quickActionButton(icon: "square.and.arrow.up", label: "Partager") {
                showsShareSheet = true
            }
        }
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CooksyTheme.accentWarm)

                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Row

    private func sourceRow(title: String, url: URL) -> some View {
        Button(action: { openURL(url) }) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.accentWarm.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Text(viewModel.sourceHostLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(RecipePresentationTab.allCases) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 12, weight: .bold))

                        Text(tabLabel(for: tab))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))

                        if let count = tabCount(for: tab) {
                            Text(count)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selectedTab == tab ? Color.white.opacity(0.25) : CooksyTheme.dividerSubtle)
                                )
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? .white : CooksyTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selectedTab == tab
                                  ? AnyShapeStyle(LinearGradient(
                                      colors: [Color(hex: 0xD98C5F), Color(hex: 0xC47040)],
                                      startPoint: .topLeading,
                                      endPoint: .bottomTrailing
                                  ))
                                  : AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0xF3F0EC))
        )
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .ingredients:
            RecipeIngredientsTabView(
                ingredients: viewModel.displayedIngredients,
                currentServings: viewModel.currentServings,
                checkedIngredients: $checkedIngredients
            )
        case .steps:
            RecipeStepsTabView(
                steps: viewModel.instructions,
                onCookStepByStep: { showsStepByStep = true }
            )
        case .nutrition:
            RecipeNutritionTabView(
                perServingNutrition: viewModel.perServingNutritionDisplay,
                totalNutrition: viewModel.totalNutritionDisplay,
                isEstimated: viewModel.nutritionIsEstimated,
                currentServings: viewModel.currentServings
            )
        }
    }

    private func tabIcon(for tab: RecipePresentationTab) -> String {
        switch tab {
        case .ingredients: return "leaf"
        case .steps: return "list.number"
        case .nutrition: return "flame"
        }
    }

    private func tabLabel(for tab: RecipePresentationTab) -> String {
        switch tab {
        case .ingredients: return "Ingrédients"
        case .steps: return "Étapes"
        case .nutrition: return "Nutrition"
        }
    }

    private func tabCount(for tab: RecipePresentationTab) -> String? {
        switch tab {
        case .ingredients:
            return "\(viewModel.displayedIngredients.count)"
        case .steps:
            return "\(viewModel.instructions.count)"
        case .nutrition:
            return nil
        }
    }

    // MARK: - Save Area

    private var saveArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let reviewNotice = viewModel.reviewNotice {
                    inlineMessageCard(
                        text: reviewNotice,
                        tint: viewModel.canSave ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText,
                        icon: viewModel.canSave ? "checkmark.seal.fill" : "square.and.pencil"
                    )
                }

                Button(action: primaryAction) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CooksyTheme.accentGradient)
                            .frame(height: 50)

                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(viewModel.primaryActionTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving)

                HStack {
                    Button(action: { showsReportAlert = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble")
                            Text("Signaler")
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 5)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(CooksyTheme.background.opacity(0.96))
    }

    private func inlineMessageCard(text: String, tint: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
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

    private func primaryAction() {
        if viewModel.canSave {
            saveRecipe()
        } else {
            showsEditor = true
        }
    }

}

@MainActor
private final class ImportedRecipeReviewViewModel: ObservableObject {
    typealias DisplayIngredient = RecipeIngredientPresentation

    @Published private(set) var seed: RecipeEditorSeed
    @Published private(set) var books: [RecipeBook] = []
    @Published private(set) var heroImage: UIImage?
    @Published private(set) var isSaving = false
    @Published var selectedBookID: RecipeBook.ID?
    @Published var currentServings: Int

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
        self.currentServings = 1

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

    var title: String {
        let normalizedTitle = seed.normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? "Recette importée" : normalizedTitle
    }

    var sourceURL: URL? {
        seed.sourceURL
    }

    var sourceButtonTitle: String? {
        RecipePresentationFormatter.sourceButtonTitle(for: sourceURL)
    }

    var sourceHostLabel: String {
        RecipePresentationFormatter.sourceHostLabel(for: sourceURL)
    }

    var sourceLabel: String? {
        RecipePresentationFormatter.sourceLabel(for: sourceURL)
    }

    var creatorHandle: String? {
        RecipePresentationFormatter.creatorHandle(
            explicitHandle: seed.creatorHandle,
            sourceURL: sourceURL
        )
    }

    var ratingValue: Double? {
        seed.externalRating
    }

    var ratingCountLabel: String? {
        RecipePresentationFormatter.ratingCountText(for: seed.externalRatingCount)
    }

    var difficultyLabel: String {
        RecipePresentationFormatter.difficultyLabel(for: previewRecipe)
    }

    var noteText: String? {
        nonEmpty(seed.editableNotesText)
    }

    var importNotice: String? {
        seed.importNotice
    }

    var hasContextContent: Bool {
        sourceURL != nil || noteText != nil
    }

    var canSave: Bool {
        validation.canSave
    }

    var primaryActionTitle: String {
        canSave ? "Enregistrer la recette" : "Modifier la recette"
    }

    var reviewNotice: String? {
        validation.reviewNotice
    }

    var showsNutrition: Bool {
        canSave
    }

    var baseServings: Int {
        max(1, RecipeQuantityScaler.baseServings(from: previewRecipe))
    }

    var servingsLabel: String {
        RecipePresentationFormatter.servingsLabel(for: baseServings)
    }

    var heroServingsLabel: String? {
        servingsLabel
    }

    var ingredientCount: Int {
        displayedIngredients.count
    }

    var instructionCount: Int {
        instructions.count
    }

    var totalTimeLabel: String? {
        RecipePresentationFormatter.totalTimeLabel(
            prepMinutes: Int(seed.prepTimeText.trimmingCharacters(in: .whitespacesAndNewlines)),
            cookMinutes: Int(seed.cookTimeText.trimmingCharacters(in: .whitespacesAndNewlines))
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
        guard showsNutrition else { return nil }
        return RecipeNutritionDisplayBuilder.totalCaloriesLabel(for: previewRecipe)
    }

    var nutritionDisplay: RecipeNutritionDisplay? {
        guard showsNutrition else { return nil }
        return RecipeNutritionDisplayBuilder.displayNutrition(
            for: previewRecipe,
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
        guard showsNutrition else { return false }
        return RecipeNutritionDisplayBuilder.isEstimated(for: previewRecipe)
    }

    var perServingNutritionDisplay: RecipeNutritionDisplay? {
        guard showsNutrition else { return nil }
        return RecipeNutritionDisplayBuilder.displayNutrition(for: previewRecipe, selectedServings: 1)
    }

    var totalNutritionDisplay: RecipeNutritionDisplay? {
        nutritionDisplay
    }

    var nutrition: RecipeNutrition? {
        displayedNutrition
    }

    var nutritionServingLabel: String {
        RecipePresentationFormatter.selectedServingsLabel(for: currentServings)
    }

    var caloriesSummary: String? {
        totalCaloriesLabel
    }

    var proteinSummary: String? {
        displayedNutrition?.protein.flatMap(nonEmpty(_:))
    }

    var displayedIngredients: [RecipeIngredientPresentation] {
        previewRecipe.ingredients.map { ingredient in
            let quantityText = RecipeQuantityScaler.scaledQuantityText(
                for: ingredient,
                baseServings: baseServings,
                targetServings: currentServings
            )

            return RecipeIngredientPresentation(
                id: ingredient.id,
                quantityText: quantityText,
                name: ingredient.name
            )
        }
    }

    var instructions: [RecipeStep] {
        previewRecipe.steps
    }

    func changeServings(by delta: Int) {
        currentServings = max(1, min(24, currentServings + delta))
    }

    func resetServings() {
        currentServings = baseServings
    }

    func loadRemoteImageIfNeeded() async {
        guard heroImage == nil, let remoteImageURL = seed.remoteImageURL else { return }
        guard let data = await RecipeWebImportService.downloadImageData(from: remoteImageURL) else { return }

        seed.imageData = data
        heroImage = UIImage(data: data)
    }

    @discardableResult
    func saveRecipe(plannedFor day: Date? = nil) async -> Recipe.ID? {
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

        if let day {
            store.addMealPlanRecipe(recipeID: recipeID, for: day)
        }

        return recipeID
    }

    func shareText() -> String {
        var sections: [String] = [title]

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

    private var previewRecipe: Recipe {
        seed.makeRecipe(bookID: selectedBookID)
    }

    private func applyDefaultBookIfNeeded() {
        guard selectedBookID == nil else { return }
        if let preferredBookID, books.contains(where: { $0.id == preferredBookID }) {
            selectedBookID = preferredBookID
        } else {
            selectedBookID = books.first(where: { $0.kind == .uncategorized })?.id ?? books.first?.id
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private struct ImportRecipePlanSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Date) -> Void

    private let calendar = Calendar(identifier: .gregorian)

    private var dates: [Date] {
        (0..<14).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: .now).map(calendar.startOfDay(for:))
        }
    }

    var body: some View {
        NavigationStack {
            List(dates, id: \.self) { date in
                Button(action: {
                    onSelect(date)
                    dismiss()
                }) {
                    Text(Self.formatter.string(from: date))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.background)
            .navigationTitle("Ajouter au plan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

private struct RecipeImportActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
