import SwiftUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let store: RecipeStore

    @StateObject private var viewModel: RecipeDetailViewModel
    @State private var showsEditRecipe = false
    @State private var showsBookSheet = false
    @State private var showsPlanSheet = false
    @State private var showsShareSheet = false
    @State private var showsAssistant = false
    @State private var showsStepByStep = false
    @State private var showsDeleteConfirmation = false
    @State private var selectedPhotoSource: RecipePhotoSource?
    @State private var showsPhotoOptions = false
    @State private var notice: RecipeDetailNotice?
    @State private var selectedTab: RecipePresentationTab = .ingredients

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        _viewModel = StateObject(wrappedValue: RecipeDetailViewModel(store: store, recipeID: recipeID))
    }

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm
                .ignoresSafeArea()

            if let recipe = viewModel.recipe {
                VStack(spacing: 0) {
                    heroSection(recipe: recipe)

                    VStack(spacing: 14) {
                        overviewPanel
                            .offset(y: -26)
                            .padding(.bottom, -18)

                        tabBar

                        selectedTabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.recipe == nil) { _, hasNoRecipe in
            if hasNoRecipe { dismiss() }
        }
        .confirmationDialog("Changer la photo", isPresented: $showsPhotoOptions, titleVisibility: .visible) {
            Button("Choisir dans la galerie") { selectedPhotoSource = .photoLibrary }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo") { selectedPhotoSource = .camera }
            }
            Button("Annuler", role: .cancel) {}
        }
        .fullScreenCover(item: $selectedPhotoSource) { source in
            SystemImagePicker(sourceType: source.uiKitSourceType) { data in
                if let data { viewModel.replaceHeroImage(with: data) }
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
                    let title = viewModel.books.first(where: { $0.id == bookID })?.title ?? "ce livre"
                    notice = RecipeDetailNotice(message: "Recette déplacée dans \(title).")
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
        .alert("Supprimer la recette ?", isPresented: $showsDeleteConfirmation) {
            Button("Supprimer", role: .destructive) {
                if let recipeID = viewModel.recipe?.id { store.deleteRecipe(id: recipeID) }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La recette sera retirée de vos livres et de votre plan de repas.")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text("Cooksy"), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private func heroSection(recipe: Recipe) -> some View {
        RecipePresentationHeroCard(
            heroImage: viewModel.heroImage,
            heroStyle: recipe.heroStyle,
            title: viewModel.title,
            density: .compact,
            creatorHandle: viewModel.creatorHandle,
            difficultyLabel: viewModel.difficultyLabel
        ) {
            RecipePresentationActionIconButton(systemImage: "chevron.left") {
                dismiss()
            }
        } trailingActions: {
            HStack(spacing: 8) {
                RecipePresentationActionIconButton(systemImage: "square.and.arrow.up") {
                    showsShareSheet = true
                }

                Menu {
                    Button("Modifier") { showsEditRecipe = true }
                    Button("Ajouter au plan") { showsPlanSheet = true }
                    Button("Déplacer dans un livre") { showsBookSheet = true }
                    Button("Changer la photo") { showsPhotoOptions = true }
                    Button("Supprimer la recette", role: .destructive) { showsDeleteConfirmation = true }
                } label: {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RecipeDetailInfoTile(
                    systemImage: "clock",
                    title: "Total Time",
                    value: viewModel.totalTimeLabel ?? "Flexible"
                )

                RecipeDetailScaleTile(
                    currentServings: viewModel.currentServings,
                    baseServings: viewModel.baseServings,
                    onDecrease: { viewModel.changeServings(by: -1) },
                    onIncrease: { viewModel.changeServings(by: 1) }
                )
            }

            HStack(spacing: 8) {
                RecipeDetailCapsuleLabel(text: "\(viewModel.displayedIngredients.count) ingredients")
                RecipeDetailCapsuleLabel(text: "\(viewModel.instructions.count) steps")
            }

            if let sourceButtonTitle = viewModel.sourceButtonTitle, let sourceURL = viewModel.sourceURL {
                Button(action: { openURL(sourceURL) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sourceButtonTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text(viewModel.sourceHostLabel)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CooksyTheme.backgroundCalm)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(RecipePresentationTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? .white : CooksyTheme.primaryText)

                        if let count = tabCount(for: tab) {
                            Text(count)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(selectedTab == tab ? Color.white.opacity(0.82) : CooksyTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedTab == tab ? AnyShapeStyle(CooksyTheme.accentGradient) : AnyShapeStyle(Color.white))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selectedTab == tab ? Color.clear : CooksyTheme.dividerSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .ingredients:
            RecipeIngredientsTabView(
                ingredients: viewModel.displayedIngredients,
                currentServings: viewModel.currentServings,
                baseServings: viewModel.baseServings
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
}

private struct RecipeDetailInfoTile: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.accentWarm)

            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.backgroundCalm)
        )
    }
}

private struct RecipeDetailScaleTile: View {
    let currentServings: Int
    let baseServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scale")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text("\(currentServings) servings")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            HStack(spacing: 8) {
                stepperButton(systemImage: "minus", action: onDecrease)
                stepperButton(systemImage: "plus", action: onIncrease)
            }

            Text("Base recipe: \(baseServings)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.backgroundCalm)
        )
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeDetailCapsuleLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.backgroundCalm)
            )
    }
}

private struct RecipeIngredientsTabView: View {
    let ingredients: [RecipeIngredientPresentation]
    let currentServings: Int
    let baseServings: Int

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ingredients")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("Strict 3-column layout scaled for \(currentServings) servings.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Items")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)

                        Spacer()

                        Text("Base \(baseServings)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider()
                        .overlay(CooksyTheme.dividerSubtle)

                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        RecipeIngredientColumnRow(ingredient: ingredient)

                        if index < ingredients.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.dividerSubtle)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
                )
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
}

private struct RecipeIngredientColumnRow: View {
    let ingredient: RecipeIngredientPresentation

    private let iconColumnWidth: CGFloat = 42
    private let quantityColumnWidth: CGFloat = 82
    private let rowHeight: CGFloat = 58

    private var display: IngredientDisplayRow {
        ingredient.normalizedDisplay
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.backgroundCalm)

                IngredientLocalIcon(ingredientName: ingredient.name, size: 24)
            }
            .frame(width: 34, height: 34)
            .frame(width: iconColumnWidth, alignment: .leading)

            Text(display.quantityColumn.isEmpty ? " " : display.quantityColumn)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.accentWarm)
                .frame(width: quantityColumnWidth, alignment: .leading)
                .lineLimit(1)

            Text(display.nameColumn)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

private struct RecipeStepsTabView: View {
    let steps: [RecipeStep]
    let onCookStepByStep: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onCookStepByStep) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)

                        Text("Start cook mode")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
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

                if steps.isEmpty {
                    RecipeEmptyTabState(
                        title: "No steps available",
                        subtitle: "Cooksy needs a structured step list for this recipe."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            let previousTitle = index > 0 ? steps[index - 1].title : nil
                            let cleanedTitle = step.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let isNewSection = cleanedTitle?.isEmpty == false && cleanedTitle != previousTitle

                            if isNewSection, let cleanedTitle {
                                Text(cleanedTitle.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(0.7)
                                    .foregroundStyle(CooksyTheme.brandBlueDark)
                                    .padding(.top, index == 0 ? 2 : 10)
                            }

                            RecipeStepCard(index: index + 1, step: step)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
}

private struct RecipeStepCard: View {
    let index: Int
    let step: RecipeStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 34, height: 34)

                Text("\(index)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(
                StepIngredientHighlighter.highlighted(
                    step.detail,
                    ingredientRefs: step.ingredientRefs,
                    fontSize: 14,
                    highlightColor: CooksyTheme.brandBlueDark
                )
            )
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
            .lineSpacing(3)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }
}

private struct RecipeNutritionTabView: View {
    let perServingNutrition: RecipeNutritionDisplay?
    let totalNutrition: RecipeNutritionDisplay?
    let isEstimated: Bool
    let currentServings: Int

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if let perServingNutrition {
                    nutritionOverviewCard(perServingNutrition)

                    LazyVGrid(columns: columns, spacing: 12) {
                        RecipeNutritionMetricCard(title: "Calories", value: perServingNutrition.caloriesText, tint: CooksyTheme.accentWarm)
                        RecipeNutritionMetricCard(title: "Protein", value: perServingNutrition.proteinText, tint: CooksyTheme.brandBlueDark)
                        RecipeNutritionMetricCard(title: "Carbs", value: perServingNutrition.carbsText, tint: CooksyTheme.sparkleYellow)
                        RecipeNutritionMetricCard(title: "Fat", value: perServingNutrition.fatText, tint: CooksyTheme.secondaryAccentStrong)
                    }

                    macroBalanceCard(perServingNutrition)
                    secondaryMetricsCard(perServingNutrition)

                    if let totalNutrition {
                        totalRecipeCard(totalNutrition)
                    }

                    if isEstimated {
                        Text("Estimated from the ingredient list.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 2)
                    }
                } else {
                    RecipeEmptyTabState(
                        title: "Nutrition unavailable",
                        subtitle: "Add more ingredient detail to unlock richer nutrition insights."
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    private func nutritionOverviewCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutrition")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))

            Text(nutrition.caloriesText)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(.white)

            Text("Per serving")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))

            Text("Recipe scaled to \(currentServings) servings.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.accentGradient)
        )
    }

    private func macroBalanceCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        let total = max(nutrition.protein + nutrition.carbs + nutrition.fat, 1)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Macro balance")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            GeometryReader { proxy in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CooksyTheme.brandBlueDark)
                        .frame(width: proxy.size.width * CGFloat(nutrition.protein / total))

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CooksyTheme.sparkleYellow)
                        .frame(width: proxy.size.width * CGFloat(nutrition.carbs / total))

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CooksyTheme.secondaryAccentStrong)
                        .frame(width: proxy.size.width * CGFloat(nutrition.fat / total))
                }
            }
            .frame(height: 12)

            VStack(spacing: 10) {
                RecipeNutritionLegendRow(title: "Protein", value: nutrition.proteinText, tint: CooksyTheme.brandBlueDark)
                RecipeNutritionLegendRow(title: "Carbs", value: nutrition.carbsText, tint: CooksyTheme.sparkleYellow)
                RecipeNutritionLegendRow(title: "Fat", value: nutrition.fatText, tint: CooksyTheme.secondaryAccentStrong)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func secondaryMetricsCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Secondary values")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            VStack(spacing: 12) {
                RecipeNutritionSecondaryRow(title: "Fiber", value: nutrition.fiberText, tint: CooksyTheme.brandBlueDark.opacity(0.65), fraction: metricFraction(nutrition.fiber, reference: 12))
                RecipeNutritionSecondaryRow(title: "Sugar", value: nutrition.sugarText, tint: CooksyTheme.accentWarm, fraction: metricFraction(nutrition.sugar, reference: 25))
                RecipeNutritionSecondaryRow(title: "Salt", value: nutrition.saltText, tint: CooksyTheme.secondaryAccentStrong, fraction: metricFraction(nutrition.salt, reference: 6))
                RecipeNutritionSecondaryRow(title: "Saturated fat", value: nutrition.saturatedFatText, tint: CooksyTheme.primaryAccentStrong, fraction: metricFraction(nutrition.saturatedFat, reference: 20))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func totalRecipeCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        let totalColumns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Total recipe")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("For \(currentServings) servings")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            LazyVGrid(columns: totalColumns, spacing: 12) {
                RecipeNutritionTotalPill(title: "Calories", value: nutrition.caloriesText)
                RecipeNutritionTotalPill(title: "Protein", value: nutrition.proteinText)
                RecipeNutritionTotalPill(title: "Carbs", value: nutrition.carbsText)
                RecipeNutritionTotalPill(title: "Fat", value: nutrition.fatText)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func metricFraction(_ value: Double, reference: Double) -> Double {
        min(max(value, 0) / max(reference, 1), 1)
    }
}

private struct RecipeNutritionMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }
}

private struct RecipeNutritionLegendRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
    }
}

private struct RecipeNutritionSecondaryRow: View {
    let title: String
    let value: String
    let tint: Color
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Spacer(minLength: 0)

                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint)
                            .frame(width: max(8, proxy.size.width * fraction))
                    }
            }
            .frame(height: 8)
        }
    }
}

private struct RecipeNutritionTotalPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.backgroundCalm)
        )
    }
}

private struct RecipeEmptyTabState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Supporting Sheets

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
                                .foregroundStyle(CooksyTheme.accentWarm)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.backgroundCalm)
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
            .background(CooksyTheme.backgroundCalm)
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

private struct CooksyAssistantView: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let responseForPreset: (RecipeDetailViewModel.AssistantPreset) -> String
    let responseForQuestion: (String) -> String

    @State private var messages: [String] = []
    @State private var draft = ""

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)

                    Text(recipeTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

                Divider().overlay(CooksyTheme.dividerSubtle)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Besoin d'un coup de main ?")
                            .font(.system(size: 26, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        assistantOption(title: "Remplacer un ingrédient", systemImage: "arrow.triangle.2.circlepath") {
                            messages.append(responseForPreset(.replaceIngredient))
                        }
                        assistantOption(title: "Simplifier", systemImage: "slider.horizontal.3") {
                            messages.append(responseForPreset(.simplify))
                        }
                        assistantOption(title: "Rendre plus saine", systemImage: "leaf") {
                            messages.append(responseForPreset(.healthier))
                        }

                        if !messages.isEmpty {
                            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                                Text(message)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Posez une question", text: $draft)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Capsule(style: .continuous).fill(Color.white))
                    .overlay(Capsule(style: .continuous).stroke(CooksyTheme.dividerSubtle, lineWidth: 1))

                Button(action: submitQuestion) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(CooksyTheme.accentWarm)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CooksyTheme.backgroundCalm.opacity(0.95))
        }
    }

    private func assistantOption(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
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

// MARK: - Utility Types

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
        case .camera: return "camera"
        case .photoLibrary: return "photoLibrary"
        }
    }

    var uiKitSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera: return .camera
        case .photoLibrary: return .photoLibrary
        }
    }
}

private struct RecipeDetailNotice: Identifiable {
    let id = UUID()
    let message: String
}
