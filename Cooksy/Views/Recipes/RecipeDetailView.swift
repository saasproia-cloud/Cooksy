import SwiftUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss

    private let store: RecipeStore

    @StateObject private var viewModel: RecipeDetailViewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var showsEditRecipe = false
    @State private var showsBookSheet = false
    @State private var showsPlanSheet = false
    @State private var showsShareSheet = false
    @State private var showsAssistant = false
    @State private var showsStepByStep = false
    @State private var showsNutritionPrompt = false
    @State private var showsDeleteConfirmation = false
    @State private var selectedPhotoSource: RecipePhotoSource?
    @State private var showsPhotoOptions = false
    @State private var notice: RecipeDetailNotice?

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        _viewModel = StateObject(wrappedValue: RecipeDetailViewModel(store: store, recipeID: recipeID))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CooksyTheme.background
                .ignoresSafeArea()

            if let recipe = viewModel.recipe {
                ScrollView(.vertical, showsIndicators: false) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: RecipeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("recipeScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    VStack(spacing: 0) {
                        topBar
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 18)

                        heroSection

                        VStack(alignment: .leading, spacing: 0) {
                            titleAndActionsSection

                            if recipe.sourceURL != nil || viewModel.noteText != nil {
                                sectionDivider
                                notesSection
                            }

                            sectionDivider
                            ingredientsSection

                            sectionDivider
                            instructionsSection

                            sectionDivider
                            nutritionSection
                        }
                        .background(Color.white)
                    }
                    .padding(.bottom, 160)
                }
                .coordinateSpace(name: "recipeScroll")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(RecipeScrollOffsetKey.self) { value in
            scrollOffset = max(0, -value)
        }
        .onChange(of: viewModel.recipe == nil) { _, hasNoRecipe in
            if hasNoRecipe {
                dismiss()
            }
        }
        .confirmationDialog("Changer la photo", isPresented: $showsPhotoOptions, titleVisibility: .visible) {
            Button("Choisir dans la galerie") {
                selectedPhotoSource = .photoLibrary
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo") {
                    selectedPhotoSource = .camera
                }
            }

            Button("Annuler", role: .cancel) {}
        }
        .fullScreenCover(item: $selectedPhotoSource) { source in
            SystemImagePicker(sourceType: source.uiKitSourceType) { data in
                if let data {
                    viewModel.replaceHeroImage(with: data)
                }
                selectedPhotoSource = nil
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showsEditRecipe) {
            if let recipe = viewModel.recipe {
                CreateRecipeView(store: store, editingRecipe: recipe)
            }
        }
        .fullScreenCover(isPresented: $showsStepByStep) {
            StepByStepCookingView(recipeTitle: viewModel.title, steps: viewModel.instructions)
        }
        .fullScreenCover(isPresented: $showsAssistant) {
            CooksyAssistantView(
                recipeTitle: viewModel.title,
                responseForPreset: { viewModel.assistantReply(for: $0) },
                responseForQuestion: { viewModel.assistantReply(for: $0) }
            )
        }
        .sheet(isPresented: $showsBookSheet) {
            RecipeBookSelectionSheet(
                books: viewModel.books,
                selectedBookID: viewModel.recipe?.bookID,
                onSelect: { bookID in
                    viewModel.moveToBook(bookID)
                    notice = RecipeDetailNotice(message: "Recette déplacée dans \(viewModel.books.first(where: { $0.id == bookID })?.title ?? "ce livre").")
                    showsBookSheet = false
                }
            )
        }
        .sheet(isPresented: $showsPlanSheet) {
            RecipePlanSelectionSheet { day in
                viewModel.addToMealPlan(on: day)
                notice = RecipeDetailNotice(message: "Recette ajoutée au plan de repas.")
                showsPlanSheet = false
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            RecipeActivityShareSheet(activityItems: [viewModel.shareText()])
        }
        .sheet(isPresented: $showsNutritionPrompt) {
            NutritionPortionPromptSheet(initialPortions: max(viewModel.currentServings, 1)) { portionCount in
                _ = viewModel.calculateNutrition(forPortions: portionCount)
                notice = RecipeDetailNotice(message: "Nutrition calculée pour 1 portion.")
                showsNutritionPrompt = false
            }
        }
        .alert("Supprimer la recette ?", isPresented: $showsDeleteConfirmation) {
            Button("Supprimer", role: .destructive) {
                if let recipeID = viewModel.recipe?.id {
                    store.deleteRecipe(id: recipeID)
                }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La recette sera retirée de vos livres et de votre plan de repas.")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text("Cooksy"), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.recipe != nil {
                askCooksyButton
                    .padding(.trailing, 22)
                    .padding(.bottom, 30)
            }
        }
    }

    private var topBar: some View {
        HStack {
            circleButton(systemImage: "chevron.left") {
                dismiss()
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button("Modifier") {
                    showsEditRecipe = true
                }
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 24)

                Menu {
                    Button("Partager") {
                        showsShareSheet = true
                    }

                    Button("Changer la photo") {
                        showsPhotoOptions = true
                    }

                    Button("Supprimer la recette", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .frame(height: 60)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
            )
        }
        .background(Color.white)
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let heroImage = viewModel.heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else if let recipe = viewModel.recipe {
                    RecipeHeroPlaceholder(heroStyle: recipe.heroStyle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .clipped()

            Button(action: { showsPhotoOptions = true }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 62, height: 62)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
            .padding(.bottom, 18)
        }
    }

    private var titleAndActionsSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(viewModel.title)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                actionButton(title: "Livres", systemImage: "bookmark") {
                    showsBookSheet = true
                }

                actionButton(title: "Plan", systemImage: "calendar.badge.plus") {
                    showsPlanSheet = true
                }

                actionButton(title: "Courses", systemImage: "cart.badge.plus") {
                    let count = viewModel.addDisplayedIngredientsToShoppingList()
                    notice = RecipeDetailNotice(message: "\(count) ingrédient\(count > 1 ? "s" : "") ajouté\(count > 1 ? "s" : "") aux courses.")
                }

                actionButton(title: "Partager", systemImage: "square.and.arrow.up") {
                    showsShareSheet = true
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 28)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("NOTES DE RECETTE")

            if let sourceURL = viewModel.sourceURL, let sourceButtonTitle = viewModel.sourceButtonTitle {
                Link(destination: sourceURL) {
                    HStack(spacing: 10) {
                        Text(sourceButtonTitle)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                }
            }

            if let noteText = viewModel.noteText {
                Text(noteText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("INGRÉDIENTS")

            HStack(spacing: 16) {
                servingsStepper

                Text("portions")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(viewModel.displayedIngredients) { ingredient in
                    HStack(alignment: .top, spacing: 16) {
                        Text(ingredient.emoji)
                            .font(.system(size: 32))
                            .frame(width: 40)

                        formattedIngredientText(ingredient)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(action: {
                let count = viewModel.addDisplayedIngredientsToShoppingList()
                notice = RecipeDetailNotice(message: "\(count) ingrédient\(count > 1 ? "s" : "") ajouté\(count > 1 ? "s" : "") aux courses.")
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrange)

                    Text("Ajouter aux courses")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 78)
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

            sectionTitle("INSTRUCTIONS")

            Button(action: { showsStepByStep = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrange)

                    Text("Cuisiner pas à pas")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 78)
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

            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(viewModel.instructions.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 16) {
                        Text("\(index + 1)")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText.opacity(0.75))
                            .frame(width: 34, alignment: .leading)

                        Text(step.detail)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("NUTRITION")

            Text("Pour 1 portion")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            if let nutrition = viewModel.nutrition {
                RecipeNutritionSummaryView(nutrition: nutrition)
            } else {
                Button(action: { showsNutritionPrompt = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrange)

                        Text("Calculer la nutrition")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
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

            if viewModel.hasNutrition {
                Button(action: { showsNutritionPrompt = true }) {
                    Text("Recalculer")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.surface)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 140)
    }

    private var servingsStepper: some View {
        HStack(spacing: 0) {
            Button(action: { viewModel.changeServings(by: -1) }) {
                Circle()
                    .fill(CooksyTheme.surface)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "minus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
            }
            .buttonStyle(.plain)

            Text("\(viewModel.currentServings)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 84)

            Button(action: { viewModel.changeServings(by: 1) }) {
                Circle()
                    .fill(CooksyTheme.surface)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 2)
        )
    }

    private var askCooksyButton: some View {
        let collapseProgress = min(1, scrollOffset / 180)

        return Button(action: { showsAssistant = true }) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrange)
                    .frame(width: 22)

                Text("Demandez à Cooksy")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .opacity(1 - collapseProgress)
                    .frame(width: max(0, 172 * (1 - collapseProgress)), alignment: .leading)
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.22), value: collapseProgress)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 66, height: 66)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                    .overlay(
                        Circle()
                            .stroke(CooksyTheme.stroke, lineWidth: 2)
                    )

                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.white)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(CooksyTheme.brandBlueDark)
            .tracking(1.2)
    }

    private func formattedIngredientText(_ ingredient: RecipeDetailViewModel.DisplayIngredient) -> Text {
        guard let quantityText = ingredient.quantityText else {
            return Text(ingredient.name)
        }

        return Text(quantityText + " ").bold() + Text(ingredient.name)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(CooksyTheme.warmCard.opacity(0.8))
            .frame(height: 16)
    }
}

private struct RecipeHeroPlaceholder: View {
    let heroStyle: HeroStyle

    var body: some View {
        ZStack {
            gradient

            Image(systemName: "fork.knife")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private var gradient: LinearGradient {
        switch heroStyle {
        case .warmCocoa:
            return LinearGradient(
                colors: [Color(hex: 0x7A4C36), Color(hex: 0xDDA177)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .citrus:
            return LinearGradient(
                colors: [Color(hex: 0xF8B34D), Color(hex: 0xFFDD78)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .ocean:
            return LinearGradient(
                colors: [CooksyTheme.brandBlueDark, CooksyTheme.brandBlue],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .meadow:
            return LinearGradient(
                colors: [Color(hex: 0x79A962), Color(hex: 0xB5D86E)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }
}

private struct RecipeNutritionSummaryView: View {
    let nutrition: RecipeNutrition

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            NutritionRingView(
                calories: parsedNumber(from: nutrition.calories),
                protein: parsedNumber(from: nutrition.protein),
                carbs: parsedNumber(from: nutrition.carbs),
                fat: parsedNumber(from: nutrition.fat)
            )

            VStack(alignment: .leading, spacing: 22) {
                nutritionRow(emoji: "🍗", title: "Protéine", value: nutrition.protein ?? "—")
                nutritionRow(emoji: "🌾", title: "Glucides", value: nutrition.carbs ?? "—")
                nutritionRow(emoji: "🥑", title: "Lipides", value: nutrition.fat ?? "—")
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CooksyTheme.surface)
        )
    }

    private func nutritionRow(emoji: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 24))

            Text("\(title): \(value)")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
    }

    private func parsedNumber(from text: String?) -> Double {
        let digits = text?
            .replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined()

        return Double(digits ?? "") ?? 0
    }
}

private struct NutritionRingView: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    private var proteinCalories: Double { max(protein, 0) * 4 }
    private var carbCalories: Double { max(carbs, 0) * 4 }
    private var fatCalories: Double { max(fat, 0) * 9 }
    private var totalMacroCalories: Double { max(proteinCalories + carbCalories + fatCalories, 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(CooksyTheme.warmCardMuted, lineWidth: 14)

            segmentedArc(value: fatCalories / totalMacroCalories, color: Color(hex: 0x8ED552), rotation: -90)
            segmentedArc(
                value: carbCalories / totalMacroCalories,
                color: Color(hex: 0xFFD62D),
                rotation: -90 + (fatCalories / totalMacroCalories * 360)
            )
            segmentedArc(
                value: proteinCalories / totalMacroCalories,
                color: Color(hex: 0xA34ED8),
                rotation: -90 + ((fatCalories + carbCalories) / totalMacroCalories * 360)
            )

            VStack(spacing: 4) {
                Text(RecipeQuantityScaler.formattedNumber(calories))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Calories")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
        }
        .frame(width: 164, height: 164)
    }

    private func segmentedArc(value: Double, color: Color, rotation: Double) -> some View {
        Circle()
            .trim(from: 0, to: max(0.03, value))
            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            .rotationEffect(.degrees(rotation))
    }
}

private struct RecipeBookSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let books: [RecipeBook]
    let selectedBookID: RecipeBook.ID?
    let onSelect: (RecipeBook.ID) -> Void

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button(action: {
                    onSelect(book.id)
                    dismiss()
                }) {
                    HStack {
                        Text(book.kind == .uncategorized ? "Non classées" : book.title)
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
            .navigationTitle("Choisir un livre")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct RecipePlanSelectionSheet: View {
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

private struct NutritionPortionPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var portionCount: Int
    let onConfirm: (Int) -> Void

    init(initialPortions: Int, onConfirm: @escaping (Int) -> Void) {
        _portionCount = State(initialValue: max(initialPortions, 1))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Combien de portions souhaitez-vous utiliser pour le calcul ?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                HStack(spacing: 18) {
                    Button(action: { portionCount = max(1, portionCount - 1) }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                    .buttonStyle(.plain)

                    Text("\(portionCount) portion\(portionCount > 1 ? "s" : "")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Button(action: { portionCount = min(24, portionCount + 1) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)

                Spacer()

                Button(action: {
                    onConfirm(portionCount)
                    dismiss()
                }) {
                    Text("Calculer")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(CooksyTheme.ctaOrange)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(CooksyTheme.background)
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

private struct CooksyAssistantView: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let responseForPreset: (RecipeDetailViewModel.AssistantPreset) -> String
    let responseForQuestion: (String) -> String

    @State private var messages: [String] = []
    @State private var draft = ""

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(CooksyTheme.surface)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)

                    Text(recipeTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.7))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Bonjour !")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Souhaitez-vous modifier votre recette ? Cooksy peut vous aider.")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        assistantOption(title: "Remplacer un ingrédient", emoji: "🔁") {
                            messages.append(responseForPreset(.replaceIngredient))
                        }

                        assistantOption(title: "Simplifiez-la", emoji: "👌") {
                            messages.append(responseForPreset(.simplify))
                        }

                        assistantOption(title: "Rendez-la plus saine", emoji: "🥗") {
                            messages.append(responseForPreset(.healthier))
                        }

                        if !messages.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                                    Text(message)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(CooksyTheme.surface)
                                        )
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 150)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                TextField("Posez une question", text: $draft)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 2)
                    )

                Button(action: submitQuestion) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CooksyTheme.secondaryText : CooksyTheme.ctaOrange)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(CooksyTheme.surface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(Color.white)
        }
    }

    private func assistantOption(title: String, emoji: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(emoji)
                    .font(.system(size: 28))

                Text(title)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryText.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .frame(height: 86)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CooksyTheme.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private func submitQuestion() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        messages.append(responseForQuestion(question))
        draft = ""
    }
}

private struct RecipeActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum RecipePhotoSource: Identifiable {
    case camera
    case photoLibrary

    var id: String {
        switch self {
        case .camera:
            return "camera"
        case .photoLibrary:
            return "photoLibrary"
        }
    }

    var uiKitSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }
}

private struct RecipeDetailNotice: Identifiable {
    let id = UUID()
    let message: String
}

private struct RecipeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
