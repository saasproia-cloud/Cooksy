import SwiftUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var sessionStore: SessionStore

    private let store: RecipeStore

    @StateObject private var viewModel: RecipeDetailViewModel
    @State private var showsEditRecipe = false

    @State private var showsPlanSheet = false
    @State private var showsShareSheet = false
    @State private var showsAssistant = false
    @State private var showsStepByStep = false
    @State private var showsDeleteConfirmation = false
    @State private var selectedPhotoSource: RecipePhotoSource?
    @State private var showsPhotoOptions = false
    @State private var notice: RecipeDetailNotice?
    @State private var selectedTab: RecipePresentationTab = .ingredients
    @State private var checkedIngredients: Set<UUID> = []
    @State private var showsPaywall = false

    private var isPremium: Bool { sessionStore.isPremium }

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        _viewModel = StateObject(wrappedValue: RecipeDetailViewModel(store: store, recipeID: recipeID))
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F5)
                .ignoresSafeArea()

            if let recipe = viewModel.recipe {
                ScrollView(.vertical, showsIndicators: false) {
                    // Outer VStack pinned to screen width — defends against
                    // any child reporting an intrinsic width larger than
                    // the screen (e.g. a hero placeholder blob, an
                    // unexpected fixed-size chip). Without this clamp, a
                    // single greedy child could inflate the whole
                    // ScrollView content and push cards off both edges.
                    VStack(spacing: 0) {
                        // MARK: – Immersive Hero
                        heroSection(recipe: recipe)

                        // MARK: – Content Body
                        VStack(spacing: 20) {
                            // Title + Quick Stats Card (overlapping hero)
                            titleCard

                            // Quick Actions Row
                            quickActionsRow

                            // Source Link
                            if let sourceButtonTitle = viewModel.sourceButtonTitle, let sourceURL = viewModel.sourceURL {
                                sourceRow(title: sourceButtonTitle, url: sourceURL)
                            }

                            // Tab Selector
                            tabSelector

                            // Tab Content
                            selectedTabContent
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .offset(y: -32)
                    }
                    .frame(maxWidth: .infinity)
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
            if let recipeID = viewModel.recipe?.id {
                RecipeAssistantSheet(store: store, recipeID: recipeID)
            }
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PremiumPaywallView(
                allowsFreeModeDismiss: true,
                onDismissToFreeMode: { showsPaywall = false }
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
            Text("La recette sera définitivement supprimée.")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text("Cooksy"), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Hero Section

    private func heroSection(recipe: Recipe) -> some View {
        ZStack(alignment: .top) {
            // Background image or gradient
            Group {
                if let heroImage = viewModel.heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RecipePresentationHeroPlaceholder(heroStyle: recipe.heroStyle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipped()

            // Gradient overlay for legibility
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

            // Navigation buttons
            HStack {
                heroActionButton(systemImage: "chevron.left") {
                    dismiss()
                }

                Spacer()

                heroActionButton(systemImage: "square.and.arrow.up") {
                    showsShareSheet = true
                }

                Menu {
                    Button("Modifier") { showsEditRecipe = true }
                    Button("Ajouter au plan") { showsPlanSheet = true }
                    Button("Changer la photo") { showsPhotoOptions = true }
                    Button("Supprimer la recette", role: .destructive) { showsDeleteConfirmation = true }
                } label: {
                    heroActionButton(systemImage: "ellipsis")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            // Title overlaying bottom of hero
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                // Badges row
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
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
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
            // Quick stats row
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

            // Servings stepper
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

            // Capsule summary
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
            quickActionButton(icon: "calendar.badge.plus", label: "Plan") {
                showsPlanSheet = true
            }

            quickActionButton(icon: "camera", label: "Photo") {
                showsPhotoOptions = true
            }

            quickActionButton(
                icon: "sparkles",
                label: "Assistant",
                isLocked: !isPremium
            ) {
                if isPremium {
                    showsAssistant = true
                } else {
                    showsPaywall = true
                }
            }

            quickActionButton(icon: "pencil", label: "Modifier") {
                showsEditRecipe = true
            }
        }
    }

    private func quickActionButton(
        icon: String,
        label: String,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLocked
                                     ? CooksyTheme.secondaryText.opacity(0.55)
                                     : CooksyTheme.accentWarm)

                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isLocked
                                     ? CooksyTheme.secondaryText.opacity(0.7)
                                     : CooksyTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isLocked
                          ? Color(hex: 0xF1ECE4)
                          : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    PremiumCrownBadge(isPremium: false, size: 16)
                        .offset(x: 5, y: -5)
                        .allowsHitTesting(false)
                }
            }
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
                checkedIngredients: $checkedIngredients,
                onRevertSwap: { ingredientId in
                    Task { await viewModel.revertSwap(ingredientId: ingredientId) }
                }
            )
        case .steps:
            RecipeStepsTabView(
                steps: viewModel.instructions,
                cookModeIsLocked: !isPremium,
                onCookStepByStep: {
                    if isPremium {
                        showsStepByStep = true
                    } else {
                        showsPaywall = true
                    }
                }
            )
        case .nutrition:
            LockedFeatureOverlay(
                title: "Nutrition réservée à Cooksy Plus",
                subtitle: "Calories, macros et valeurs nutritionnelles complètes pour chaque recette importée.",
                isLocked: !isPremium,
                onUnlockTap: { showsPaywall = true }
            ) {
                RecipeNutritionTabView(
                    perServingNutrition: viewModel.perServingNutritionDisplay,
                    totalNutrition: viewModel.totalNutritionDisplay,
                    isEstimated: viewModel.nutritionIsEstimated,
                    currentServings: viewModel.currentServings
                )
            }
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
}

// MARK: - Ingredients Tab

struct RecipeIngredientsTabView: View {
    let ingredients: [RecipeIngredientPresentation]
    let currentServings: Int
    @Binding var checkedIngredients: Set<UUID>
    var onRevertSwap: ((UUID) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Liste des ingrédients")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("\(checkedIngredients.count)/\(ingredients.count) sélectionnés · \(currentServings) portions")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer()

                if !checkedIngredients.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            checkedIngredients.removeAll()
                        }
                    } label: {
                        Text("Tout décocher")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.accentWarm)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Ingredients list
            if ingredients.isEmpty {
                RecipeEmptyTabState(
                    title: "Aucun ingrédient",
                    subtitle: "Cette recette ne contient pas encore d'ingrédients."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        RecipeIngredientRow(
                            ingredient: ingredient,
                            isChecked: checkedIngredients.contains(ingredient.id),
                            isFirst: index == 0,
                            isLast: index == ingredients.count - 1,
                            onRevertSwap: onRevertSwap
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                if checkedIngredients.contains(ingredient.id) {
                                    checkedIngredients.remove(ingredient.id)
                                } else {
                                    checkedIngredients.insert(ingredient.id)
                                }
                            }
                        }

                        if index < ingredients.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.dividerSubtle)
                                .padding(.leading, 108)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
            }
        }
    }
}

struct RecipeIngredientRow: View {
    let ingredient: RecipeIngredientPresentation
    let isChecked: Bool
    let isFirst: Bool
    let isLast: Bool
    var onRevertSwap: ((UUID) -> Void)? = nil
    let onToggle: () -> Void

    private var display: IngredientDisplayRow {
        ingredient.normalizedDisplay
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Checkbox circle
                ZStack {
                    Circle()
                        .stroke(isChecked ? CooksyTheme.accentWarm : CooksyTheme.dividerSubtle, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isChecked {
                        Circle()
                            .fill(CooksyTheme.accentWarm)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                // Icon (no background frame — image sits clean on the card)
                IngredientEmojiIcon(ingredientName: ingredient.name, size: 48)
                    .frame(width: 48, height: 48)
                    .opacity(isChecked ? 0.5 : 1)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.nameColumn)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(isChecked ? CooksyTheme.secondaryText : CooksyTheme.primaryText)
                        .strikethrough(isChecked, color: CooksyTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !display.quantityColumn.isEmpty {
                        Text(display.quantityColumn)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isChecked ? CooksyTheme.secondaryText.opacity(0.6) : CooksyTheme.accentWarm)
                    }

                    if ingredient.isSwapped, let originName = ingredient.originName {
                        Text("Remplace : \(originName)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if ingredient.isSwapped, let revert = onRevertSwap {
                    Button {
                        revert(ingredient.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)
                            .padding(8)
                            .background(
                                Circle().fill(CooksyTheme.accentWarm.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Annuler la modification")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Steps Tab

struct RecipeStepsTabView: View {
    let steps: [RecipeStep]
    var cookModeIsLocked: Bool = false
    let onCookStepByStep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cook mode CTA — gray + crown for free users.
            Button(action: onCookStepByStep) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(cookModeIsLocked
                                  ? AnyShapeStyle(Color(hex: 0xC9C2B7))
                                  : AnyShapeStyle(CooksyTheme.accentWarm))
                            .frame(width: 38, height: 38)

                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode cuisine")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(cookModeIsLocked
                                             ? CooksyTheme.secondaryText
                                             : CooksyTheme.primaryText)

                        Text(cookModeIsLocked
                             ? "Réservé aux membres Cooksy Plus"
                             : "Suivez chaque étape en plein écran")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: cookModeIsLocked ? "lock.fill" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cookModeIsLocked
                              ? Color(hex: 0xF1ECE4)
                              : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(cookModeIsLocked
                                ? Color(hex: 0xC9C2B7).opacity(0.6)
                                : CooksyTheme.accentWarm.opacity(0.3),
                                lineWidth: 1.5)
                )
                .shadow(
                    color: cookModeIsLocked ? .clear : CooksyTheme.accentWarm.opacity(0.08),
                    radius: 12, y: 4
                )
                .overlay(alignment: .topTrailing) {
                    if cookModeIsLocked {
                        PremiumCrownBadge(isPremium: false, size: 22)
                            .offset(x: 8, y: -8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(.plain)

            if steps.isEmpty {
                RecipeEmptyTabState(
                    title: "Aucune étape",
                    subtitle: "Cooksy a besoin d'une liste d'étapes structurée pour cette recette."
                )
            } else {
                // Steps with timeline
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let previousTitle = index > 0 ? steps[index - 1].title : nil
                        let cleanedTitle = step.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isNewSection = cleanedTitle?.isEmpty == false && cleanedTitle != previousTitle

                        if isNewSection, let cleanedTitle {
                            HStack(spacing: 10) {
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.accentWarm)
                                    .frame(width: 3, height: 18)

                                Text(cleanedTitle.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(CooksyTheme.accentWarm)
                            }
                            .padding(.top, index == 0 ? 0 : 16)
                            .padding(.bottom, 8)
                            .padding(.leading, 4)
                        }

                        RecipeStepCard(
                            index: index + 1,
                            step: step,
                            isLast: index == steps.count - 1
                        )
                    }
                }
            }
        }
    }
}

struct RecipeStepCard: View {
    let index: Int
    let step: RecipeStep
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [CooksyTheme.accentWarm, CooksyTheme.accentWarmDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 30, height: 30)

                    Text("\(index)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                if !isLast {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(CooksyTheme.dividerSubtle)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    StepIngredientHighlighter.highlighted(
                        step.detail,
                        ingredientRefs: step.ingredientRefs,
                        fontSize: 14,
                        highlightColor: CooksyTheme.accentWarm
                    )
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
            .padding(.bottom, isLast ? 0 : 6)
        }
    }
}

// MARK: - Nutrition Tab

struct RecipeNutritionTabView: View {
    let perServingNutrition: RecipeNutritionDisplay?
    let totalNutrition: RecipeNutritionDisplay?
    let isEstimated: Bool
    let currentServings: Int

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let perServingNutrition {
                // Calories hero card
                nutritionHeroCard(perServingNutrition)

                // Macro grid
                LazyVGrid(columns: columns, spacing: 10) {
                    RecipeNutritionMetricCard(title: "Protéines", value: perServingNutrition.proteinText, tint: Color(hex: 0x5E7491), icon: "figure.strengthtraining.traditional")
                    RecipeNutritionMetricCard(title: "Glucides", value: perServingNutrition.carbsText, tint: Color(hex: 0xF5B14E), icon: "bolt.fill")
                    RecipeNutritionMetricCard(title: "Lipides", value: perServingNutrition.fatText, tint: Color(hex: 0xEA662A), icon: "drop.fill")
                    RecipeNutritionMetricCard(title: "Fibres", value: perServingNutrition.fiberText, tint: Color(hex: 0x6DAA5E), icon: "leaf.fill")
                }

                // Macro balance
                macroBalanceCard(perServingNutrition)

                // Secondary values
                secondaryMetricsCard(perServingNutrition)

                // Total recipe
                if let totalNutrition {
                    totalRecipeCard(totalNutrition)
                }

                if isEstimated {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text("Valeurs estimées à partir de la liste d'ingrédients.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.horizontal, 4)
                }
            } else {
                RecipeEmptyTabState(
                    title: "Nutrition indisponible",
                    subtitle: "Ajoutez plus de détails aux ingrédients pour débloquer les informations nutritionnelles."
                )
            }
        }
    }

    private func nutritionHeroCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calories")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))

                    Text(nutrition.caloriesText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("par portion")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))

                    Text("\(currentServings) portions")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0xD98C5F), Color(hex: 0xB87345)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .shadow(color: CooksyTheme.accentWarm.opacity(0.3), radius: 16, y: 8)
    }

    private func macroBalanceCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        let total = max(nutrition.protein + nutrition.carbs + nutrition.fat, 1)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Répartition des macros")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            GeometryReader { proxy in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: 0x5E7491))
                        .frame(width: max(8, proxy.size.width * CGFloat(nutrition.protein / total)))

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: 0xF5B14E))
                        .frame(width: max(8, proxy.size.width * CGFloat(nutrition.carbs / total)))

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: 0xEA662A))
                        .frame(width: max(8, proxy.size.width * CGFloat(nutrition.fat / total)))
                }
            }
            .frame(height: 10)

            VStack(spacing: 10) {
                RecipeNutritionLegendRow(title: "Protéines", value: nutrition.proteinText, tint: Color(hex: 0x5E7491))
                RecipeNutritionLegendRow(title: "Glucides", value: nutrition.carbsText, tint: Color(hex: 0xF5B14E))
                RecipeNutritionLegendRow(title: "Lipides", value: nutrition.fatText, tint: Color(hex: 0xEA662A))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func secondaryMetricsCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Valeurs secondaires")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            VStack(spacing: 14) {
                RecipeNutritionSecondaryRow(title: "Fibres", value: nutrition.fiberText, tint: Color(hex: 0x6DAA5E), fraction: metricFraction(nutrition.fiber, reference: 12))
                RecipeNutritionSecondaryRow(title: "Sucres", value: nutrition.sugarText, tint: Color(hex: 0xF5B14E), fraction: metricFraction(nutrition.sugar, reference: 25))
                RecipeNutritionSecondaryRow(title: "Sel", value: nutrition.saltText, tint: Color(hex: 0xEA662A), fraction: metricFraction(nutrition.salt, reference: 6))
                RecipeNutritionSecondaryRow(title: "Graisses sat.", value: nutrition.saturatedFatText, tint: CooksyTheme.primaryAccentStrong, fraction: metricFraction(nutrition.saturatedFat, reference: 20))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func totalRecipeCard(_ nutrition: RecipeNutritionDisplay) -> some View {
        let totalColumns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Recette complète")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("Pour \(currentServings) portions")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            LazyVGrid(columns: totalColumns, spacing: 10) {
                RecipeNutritionTotalPill(title: "Calories", value: nutrition.caloriesText)
                RecipeNutritionTotalPill(title: "Protéines", value: nutrition.proteinText)
                RecipeNutritionTotalPill(title: "Glucides", value: nutrition.carbsText)
                RecipeNutritionTotalPill(title: "Lipides", value: nutrition.fatText)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }

    private func metricFraction(_ value: Double, reference: Double) -> Double {
        min(max(value, 0) / max(reference, 1), 1)
    }
}

// MARK: - Nutrition Sub-components

struct RecipeNutritionMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)

                Spacer()
            }

            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }
}

struct RecipeNutritionLegendRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
    }
}

struct RecipeNutritionSecondaryRow: View {
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tint)
                            .frame(width: max(6, proxy.size.width * fraction))
                    }
            }
            .frame(height: 6)
        }
    }
}

struct RecipeNutritionTotalPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xFAF8F5))
        )
    }
}

// MARK: - Empty State

struct RecipeEmptyTabState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CooksyTheme.dividerSubtle)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
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

// NOTE: The old client-side CooksyAssistantView (hardcoded preset
// matcher, no LLM, no history) has been retired in favor of
// `RecipeAssistantSheet` + `RecipeAssistantViewModel`, which talk to
// `/api/chat/*` and persist the conversation in Supabase.


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
