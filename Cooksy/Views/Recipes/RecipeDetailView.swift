import SwiftUI
import UIKit

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
    @State private var selectedContentTab: RecipePresentationTab = .ingredients

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        _viewModel = StateObject(wrappedValue: RecipeDetailViewModel(store: store, recipeID: recipeID))
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            if let recipe = viewModel.recipe {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        detailHeroSection(recipe: recipe)
                        detailSummarySection
                        detailNutritionSection
                        detailContentSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $showsNutritionPrompt) {
            NutritionPortionPromptSheet(initialPortions: max(viewModel.currentServings, 1)) { portionCount in
                _ = viewModel.calculateNutrition(forPortions: portionCount)
                notice = RecipeDetailNotice(message: "Nutrition recalculée pour \(portionCount) portion\(portionCount > 1 ? "s" : "").")
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
    }

    private func detailHeroSection(recipe: Recipe) -> some View {
        RecipePresentationHeroCard(
            heroImage: viewModel.heroImage,
            heroStyle: recipe.heroStyle,
            creatorHandle: viewModel.creatorHandle,
            ratingValue: viewModel.ratingValue,
            ratingCountText: viewModel.ratingCountLabel,
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
                    Button("Modifier") {
                        showsEditRecipe = true
                    }

                    Button("Ajouter au plan") {
                        showsPlanSheet = true
                    }

                    Button("Déplacer dans un livre") {
                        showsBookSheet = true
                    }

                    Button("Changer la photo") {
                        showsPhotoOptions = true
                    }

                    Button("Supprimer la recette", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
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

    private var detailSummarySection: some View {
        RecipePresentationSummaryCard(
            title: viewModel.title,
            summaryText: viewModel.summaryText,
            totalTimeLabel: viewModel.totalTimeLabel,
            totalCaloriesLabel: viewModel.totalCaloriesLabel,
            servingsLabel: viewModel.servingsLabel,
            sourceButtonTitle: viewModel.sourceButtonTitle,
            sourceHostLabel: viewModel.sourceHostLabel,
            sourceAction: viewModel.sourceURL.map { sourceURL in
                { openURL(sourceURL) }
            }
        )
    }

    private var detailNutritionSection: some View {
        RecipePresentationNutritionCard(
            nutrition: viewModel.nutritionDisplay,
            isEstimated: viewModel.nutritionIsEstimated,
            currentServings: viewModel.currentServings,
            baseServings: viewModel.baseServings,
            onDecrease: { viewModel.changeServings(by: -1) },
            onIncrease: { viewModel.changeServings(by: 1) }
        )
    }

    private var detailContentSection: some View {
        RecipePresentationContentCard(
            selectedTab: $selectedContentTab,
            ingredients: viewModel.displayedIngredients,
            steps: viewModel.instructions,
            onCookStepByStep: { showsStepByStep = true }
        )
    }

    private func heroShowcase(recipe: Recipe) -> some View {
        VStack(spacing: 12) {
            topBar

            ZStack(alignment: .bottomLeading) {
                Group {
                    if let heroImage = viewModel.heroImage {
                        Image(uiImage: heroImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RecipeHeroPlaceholder(heroStyle: recipe.heroStyle)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 272)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.06),
                        Color.black.opacity(0.24),
                        Color.black.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        if let sourceLabel = viewModel.sourceLabel {
                            heroTag(text: sourceLabel, systemImage: "sparkles")
                        }

                        Spacer(minLength: 0)

                        if let totalTimeLabel = viewModel.totalTimeLabel {
                            heroTag(text: totalTimeLabel, systemImage: "clock")
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.title)
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                detailPill(systemImage: "bookmark", title: viewModel.selectedBookLabel)
                                detailPill(systemImage: "list.bullet", title: "\(viewModel.ingredientCount) ingrédients")
                                detailPill(systemImage: "list.number", title: "\(viewModel.instructionCount) étapes")

                                if let prepTimeLabel = viewModel.prepTimeLabel {
                                    detailPill(systemImage: "timer", title: prepTimeLabel)
                                }

                                if let cookTimeLabel = viewModel.cookTimeLabel {
                                    detailPill(systemImage: "flame", title: cookTimeLabel)
                                }
                            }
                            .padding(.trailing, 10)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                }
                .padding(18)

                Button(action: { showsPhotoOptions = true }) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "camera")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.46), lineWidth: 1)
            )
            .shadow(color: CooksyTheme.shadow.opacity(0.68), radius: 22, y: 12)
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 20)

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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.97))
                    .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
            )
        }
        .padding(.horizontal, 4)
    }

    private var quickActionsPanel: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    sectionHeader("Accès rapide")
                    Spacer(minLength: 0)
                    Text("Les actions clés restent à portée de main.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    actionTile(title: "Livres", systemImage: "bookmark") {
                        showsBookSheet = true
                    }

                    actionTile(title: "Plan", systemImage: "calendar.badge.plus") {
                        showsPlanSheet = true
                    }

                    actionTile(title: "Nutrition", systemImage: "heart.text.square") {
                        showsNutritionPrompt = true
                    }

                    actionTile(title: "Partager", systemImage: "square.and.arrow.up") {
                        showsShareSheet = true
                    }
                }
            }
        }
    }

    private var contextPanel: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Contexte")

                if let sourceURL = viewModel.sourceURL, let sourceButtonTitle = viewModel.sourceButtonTitle {
                    Link(destination: sourceURL) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(CooksyTheme.surface)
                                    .frame(width: 46, height: 46)

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(CooksyTheme.ctaOrange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceButtonTitle)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text(sourceURL.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? sourceURL.absoluteString)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(CooksyTheme.surface)
                        )
                    }
                }

                if let noteText = viewModel.noteText {
                    Text(noteText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineSpacing(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(CooksyTheme.surface)
                        )
                }
            }
        }
    }

    private var ingredientsPanel: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    sectionHeader("Ingrédients")
                    Spacer(minLength: 0)
                    infoBadge("\(viewModel.ingredientCount)")
                }

                HStack(spacing: 12) {
                    servingsControl

                    Spacer(minLength: 0)

                    Text("Quantités ajustées selon vos portions.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1)
                )

                if viewModel.displayedIngredients.isEmpty {
                    emptyPanel(
                        title: "Aucun ingrédient pour le moment",
                        subtitle: "Cooksy affichera ici la liste complète dès qu’elle sera disponible."
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.displayedIngredients) { ingredient in
                            ingredientRow(ingredient)
                        }
                    }
                }
            }
        }
    }

    private var instructionsPanel: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    sectionHeader("Instructions")
                    Spacer(minLength: 0)
                    infoBadge("\(viewModel.instructionCount) étapes")
                }

                if viewModel.instructions.isEmpty {
                    emptyPanel(
                        title: "Le mode cuisson n’est pas prêt",
                        subtitle: "Il manque encore des étapes assez claires pour démarrer une cuisson guidée."
                    )
                } else {
                    Button(action: { showsStepByStep = true }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(CooksyTheme.ctaOrange.opacity(0.12))
                                    .frame(width: 46, height: 46)

                                Image(systemName: "play.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(CooksyTheme.ctaOrange)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lancer le pas à pas")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text("Suivez la préparation étape par étape en plein écran.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText.opacity(0.7))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CooksyTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.instructions.enumerated()), id: \.element.id) { index, step in
                            stepRow(
                                index: index + 1,
                                step: step,
                                isLast: index == viewModel.instructions.count - 1
                            )
                        }
                    }
                }
            }
        }
    }

    private var nutritionPanel: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    sectionHeader("Nutrition")
                    Spacer(minLength: 0)

                    if viewModel.nutritionIsEstimated {
                        Text("Estimée")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.blush.opacity(0.7))
                            )
                    }
                }

                Text("Pour 1 portion")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                if let nutrition = viewModel.nutrition {
                    RecipeNutritionSummaryView(
                        nutrition: nutrition,
                        isEstimated: viewModel.nutritionIsEstimated
                    )

                    Button(action: { showsNutritionPrompt = true }) {
                        Label("Recalculer les valeurs", systemImage: "wand.and.stars")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.surface)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(CooksyTheme.stroke, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { showsNutritionPrompt = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(CooksyTheme.ctaOrange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Calculer la nutrition")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text("Calories, protéines, glucides et lipides seront estimés pour cette recette.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CooksyTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var servingsControl: some View {
        HStack(spacing: 0) {
            Button(action: { viewModel.changeServings(by: -1) }) {
                Circle()
                    .fill(CooksyTheme.surface)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
            }
            .buttonStyle(.plain)

            Text("\(viewModel.currentServings)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 58)

            Button(action: { viewModel.changeServings(by: 1) }) {
                Circle()
                    .fill(CooksyTheme.surface)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
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
                .stroke(CooksyTheme.stroke, lineWidth: 1.5)
        )
    }

    private var assistantLauncher: some View {
        let collapseProgress = min(1, scrollOffset / 180)

        return Button(action: { showsAssistant = true }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 8)

                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                }

                if collapseProgress < 0.95 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aide cuisson")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Question rapide pendant la recette")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)
                    }
                    .frame(width: max(0, 168 * (1 - collapseProgress)), alignment: .leading)
                    .opacity(1 - collapseProgress)
                }
            }
            .padding(10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 12)
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.22), value: collapseProgress)
    }

    private func actionTile(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.surface)
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .regular, design: .serif))
            .foregroundStyle(CooksyTheme.primaryText)
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: CooksyTheme.softShadow, radius: 12, y: 7)
    }

    private func detailPill(systemImage: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func heroTag(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func infoBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.blush.opacity(0.7))
            )
    }

    private func formattedIngredientText(_ ingredient: RecipeDetailViewModel.DisplayIngredient) -> Text {
        guard let quantityText = ingredient.quantityText else {
            return Text(ingredient.name)
        }

        return Text(quantityText + " ").bold() + Text(ingredient.name)
    }

    private func ingredientRow(_ ingredient: RecipeDetailViewModel.DisplayIngredient) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ingredientGlyph(for: ingredient)

            VStack(alignment: .leading, spacing: 8) {
                if let quantityText = ingredient.quantityText {
                    Text(quantityText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.blush.opacity(0.72))
                        )
                }

                Text(ingredient.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func ingredientGlyph(for ingredient: RecipeDetailViewModel.DisplayIngredient) -> some View {
        IngredientIconBadge(ingredientName: ingredient.name)
    }

    private func stepRow(index: Int, step: RecipeStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.brandBlue.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Text("\(index)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.brandBlueDark)
                }

                if !isLast {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(CooksyTheme.stroke.opacity(0.85))
                        .frame(width: 2, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                Text(step.detail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
        )
    }

    private func emptyPanel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
        )
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
        CooksyTheme.recipeGradient(for: heroStyle)
    }
}

private struct RecipeNutritionSummaryView: View {
    let nutrition: RecipeNutrition
    let isEstimated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    nutritionRing
                    metricsColumn
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 0)
                        nutritionRing
                        Spacer(minLength: 0)
                    }
                    metricsColumn
                }
            }

            if isEstimated {
                Text("Ces valeurs sont estimées automatiquement par Cooksy à partir des ingrédients et des portions.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineSpacing(2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
        )
    }

    private var nutritionRing: some View {
        NutritionRingView(
            calories: parsedNumber(from: nutrition.calories),
            protein: parsedNumber(from: nutrition.protein),
            carbs: parsedNumber(from: nutrition.carbs),
            fat: parsedNumber(from: nutrition.fat)
        )
    }

    private var metricsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricCard(
                color: CooksyTheme.ctaOrange,
                emoji: "🍗",
                title: "Protéines",
                value: nutrition.protein ?? "—"
            )
            metricCard(
                color: CooksyTheme.sparkleYellow,
                emoji: "🌾",
                title: "Glucides",
                value: nutrition.carbs ?? "—"
            )
            metricCard(
                color: CooksyTheme.brandBlue,
                emoji: "🥑",
                title: "Lipides",
                value: nutrition.fat ?? "—"
            )
        }
    }

    private func metricCard(color: Color, emoji: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)

                Text(emoji)
                    .font(.system(size: 17))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
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

            segmentedArc(value: fatCalories / totalMacroCalories, color: CooksyTheme.brandBlue, rotation: -90)
            segmentedArc(
                value: carbCalories / totalMacroCalories,
                color: CooksyTheme.sparkleYellow,
                rotation: -90 + (fatCalories / totalMacroCalories * 360)
            )
            segmentedArc(
                value: proteinCalories / totalMacroCalories,
                color: CooksyTheme.ctaOrange,
                rotation: -90 + ((fatCalories + carbCalories) / totalMacroCalories * 360)
            )

            VStack(spacing: 4) {
                Text(RecipeQuantityScaler.formattedNumber(calories))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Calories")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
        }
        .frame(width: 132, height: 132)
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
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { dismiss() }) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CooksyTheme.elevatedSurface)
                            .frame(width: 50, height: 50)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)

                    Text(recipeTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.7))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ASSISTANT CUISSON")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.7)
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)

                        Text("Besoin d’un coup de main ?")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Besoin d’un coup de main pour préparer, simplifier ou adapter cette recette ?")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)

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
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(CooksyTheme.elevatedSurface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 140)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                TextField("Posez une question", text: $draft)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.elevatedSurface)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )

                Button(action: submitQuestion) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1))
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CooksyTheme.warmCardMuted : CooksyTheme.ctaOrange)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(CooksyTheme.background.opacity(0.95))
        }
    }

    private func assistantOption(title: String, emoji: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(emoji)
                    .font(.system(size: 24))

                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryText.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
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
