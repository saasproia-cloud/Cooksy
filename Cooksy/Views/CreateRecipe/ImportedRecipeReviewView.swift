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
    @State private var selectedContentTab: RecipePresentationTab = .ingredients

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
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    reviewHeroSection
                    reviewSummarySection

                    if let importNotice = viewModel.importNotice {
                        inlineMessageCard(
                            text: importNotice,
                            tint: CooksyTheme.brandBlueDark,
                            icon: "sparkles"
                        )
                    }

                    if viewModel.showsNutrition {
                        reviewNutritionSection
                    }
                    reviewContentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 176)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadRemoteImageIfNeeded()
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

    private var reviewHeroSection: some View {
        RecipePresentationHeroCard(
            heroImage: viewModel.heroImage,
            heroStyle: .ocean,
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
                        showsEditor = true
                    }

                    if let sourceURL = viewModel.sourceURL {
                        Button("Ouvrir la source") {
                            openURL(sourceURL)
                        }
                    }

                    Button("Signaler une erreur d'importation") {
                        showsReportAlert = true
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

    private var reviewSummarySection: some View {
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

    private var reviewNutritionSection: some View {
        RecipePresentationNutritionCard(
            nutrition: viewModel.nutritionDisplay,
            isEstimated: viewModel.nutritionIsEstimated,
            currentServings: viewModel.currentServings,
            baseServings: viewModel.baseServings,
            onDecrease: { viewModel.changeServings(by: -1) },
            onIncrease: { viewModel.changeServings(by: 1) }
        )
    }

    private var reviewContentSection: some View {
        RecipePresentationContentCard(
            selectedTab: $selectedContentTab,
            ingredients: viewModel.displayedIngredients,
            steps: viewModel.instructions,
            onCookStepByStep: { showsStepByStep = true }
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            heroIconButton(systemImage: "chevron.left") {
                dismiss()
            }

            Spacer(minLength: 0)

            Button("Modifier") {
                showsEditor = true
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .buttonStyle(.plain)

            Menu {
                if let sourceURL = viewModel.sourceURL {
                    Button("Ouvrir la source") {
                        openURL(sourceURL)
                    }
                }

                Button("Signaler une erreur d'importation") {
                    showsReportAlert = true
                }
            } label: {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            ImportedRecipeHeroMedia(image: viewModel.heroImage)
                .frame(height: 212)
                .overlay(alignment: .bottomTrailing) {
                    if viewModel.heroImage != nil {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.96))
                                .frame(width: 34, height: 34)

                            Image(systemName: "camera")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }
                        .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                if let sourceLabel = viewModel.sourceLabel {
                    Text(sourceLabel.uppercased())
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

                Text(viewModel.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        if let calories = viewModel.caloriesSummary {
                            titleSummaryPill(label: "Calories", value: calories)
                        }

                        if let protein = viewModel.proteinSummary {
                            titleSummaryPill(label: "Protéines", value: protein)
                        }

                        if let totalTimeLabel = viewModel.totalTimeLabel {
                            titleSummaryPill(label: "Temps", value: totalTimeLabel)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let calories = viewModel.caloriesSummary {
                            titleSummaryPill(label: "Calories", value: calories)
                        }

                        HStack(spacing: 8) {
                            if let protein = viewModel.proteinSummary {
                                titleSummaryPill(label: "Protéines", value: protein)
                            }

                            if let totalTimeLabel = viewModel.totalTimeLabel {
                                titleSummaryPill(label: "Temps", value: totalTimeLabel)
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        heroInfoBadge(text: "\(viewModel.ingredientCount) ingrédients", systemImage: "list.bullet")
                        heroInfoBadge(text: "\(viewModel.instructionCount) étapes", systemImage: "text.justify.left")

                        if let servings = viewModel.heroServingsLabel {
                            heroInfoBadge(text: servings, systemImage: "person.2")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            heroInfoBadge(text: "\(viewModel.ingredientCount) ingrédients", systemImage: "list.bullet")
                            heroInfoBadge(text: "\(viewModel.instructionCount) étapes", systemImage: "text.justify.left")
                        }

                        if let servings = viewModel.heroServingsLabel {
                            heroInfoBadge(text: servings, systemImage: "person.2")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Divider()
                .overlay(CooksyTheme.stroke.opacity(0.9))

            HStack(spacing: 0) {
                ImportedQuickActionButton(
                    title: "Modifier",
                    systemImage: "square.and.pencil",
                    action: { showsEditor = true }
                )

                Divider()
                    .frame(height: 44)

                ImportedQuickActionButton(
                    title: "Plan",
                    systemImage: "calendar.badge.plus",
                    action: { showsPlanSheet = true }
                )
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1 : 0.45)

                Divider()
                    .frame(height: 44)

                ImportedQuickActionButton(
                    title: "Partager",
                    systemImage: "square.and.arrow.up",
                    action: { showsShareSheet = true }
                )
            }
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 6)
    }

    private var sourceNotesSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionEyebrow("Notes de recette")

                if let sourceURL = viewModel.sourceURL, let sourceButtonTitle = viewModel.sourceButtonTitle {
                    Button(action: { openURL(sourceURL) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sourceButtonTitle)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text(viewModel.sourceHostLabel)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.sourceURL != nil, viewModel.noteText != nil {
                    Divider()
                        .overlay(CooksyTheme.stroke.opacity(0.9))
                }

                if let noteText = viewModel.noteText {
                    Text(noteText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.sourceURL != nil {
                    Text("Aucune note importée pour le moment.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
        }
    }

    private var ingredientsSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Ingrédients")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        servingsStepper
                        Spacer(minLength: 0)
                        servingsHelperPill
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        servingsStepper
                        servingsHelperPill
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.displayedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                        ImportedIngredientRow(ingredient: ingredient)

                        if index != viewModel.displayedIngredients.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.stroke.opacity(0.9))
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
            }
        }
    }

    private var instructionsSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Instructions")

                Button(action: { showsStepByStep = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0xB489D9))
                            .frame(width: 24)

                        Text("Cuisiner pas à pas")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.instructions.isEmpty)
                .opacity(viewModel.instructions.isEmpty ? 0.55 : 1)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.instructions.enumerated()), id: \.element.id) { index, step in
                        ImportedInstructionRow(index: index + 1, step: step)

                        if index != viewModel.instructions.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.stroke.opacity(0.9))
                                .padding(.leading, 28)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
            }
        }
    }

    private func nutritionSection(_ nutrition: RecipeNutrition) -> some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionEyebrow("Nutrition")
                        Text(viewModel.nutritionServingLabel)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Spacer(minLength: 0)

                    if viewModel.nutritionIsEstimated {
                        Text("Estimation Cooksy")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.blush)
                            )
                    }
                }

                ImportedNutritionPanel(
                    nutrition: nutrition,
                    servingLabel: viewModel.nutritionServingLabel
                )
            }
        }
    }

    private var saveArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
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
                            .frame(height: 52)

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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(CooksyTheme.background.opacity(0.96))
    }

    private var servingsStepper: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.changeServings(by: -1) }) {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                Text("\(viewModel.currentServings)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(viewModel.currentServings > 1 ? "portions" : "portion")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .frame(minWidth: 72)

            Button(action: { viewModel.changeServings(by: 1) }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func heroIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var servingsHelperPill: some View {
        Group {
            if viewModel.currentServings != viewModel.baseServings {
                Button(action: viewModel.resetServings) {
                    Label("Base \(viewModel.baseServings)", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
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
            } else {
                Label("Ajustement auto", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
            }
        }
    }

    private func heroInfoBadge(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
    }

    private func titleSummaryPill(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
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

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .black, design: .rounded))
            .tracking(0.9)
            .foregroundStyle(CooksyTheme.brandBlueDark)
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
        previewRecipe.ingredients.count
    }

    var instructionCount: Int {
        previewRecipe.steps.count
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

private struct ImportedReviewSectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: CooksyTheme.softShadow, radius: 10, y: 4)
    }
}

private struct ImportedRecipeHeroMedia: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            CooksyTheme.heroGlowGradient

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 68))
                        .foregroundStyle(Color.white.opacity(0.92))

                    Text("Recette importée")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.86))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct ImportedQuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )

                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct ImportedIngredientRow: View {
    let ingredient: ImportedRecipeReviewViewModel.DisplayIngredient

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IngredientIconBadge(ingredientName: ingredient.name)

            VStack(alignment: .leading, spacing: 4) {
                if let quantityText = ingredient.quantityText {
                    Text(quantityText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                Text(ingredient.name)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ImportedInstructionRow: View {
    let index: Int
    let step: RecipeStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: 18, alignment: .leading)

            Text(step.detail)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ImportedNutritionPanel: View {
    let nutrition: RecipeNutrition
    let servingLabel: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                ImportedNutritionRingView(
                    calories: parsedNumber(from: nutrition.calories),
                    protein: parsedNumber(from: nutrition.protein),
                    carbs: parsedNumber(from: nutrition.carbs),
                    fat: parsedNumber(from: nutrition.fat)
                )

                VStack(alignment: .leading, spacing: 10) {
                    ImportedMacroLegendRow(
                        color: CooksyTheme.ctaOrange,
                        title: "Protéines",
                        value: nutrition.protein ?? "—"
                    )
                    ImportedMacroLegendRow(
                        color: CooksyTheme.sparkleYellow,
                        title: "Glucides",
                        value: nutrition.carbs ?? "—"
                    )
                    ImportedMacroLegendRow(
                        color: CooksyTheme.brandBlue,
                        title: "Lipides",
                        value: nutrition.fat ?? "—"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer(minLength: 0)
                    ImportedNutritionRingView(
                        calories: parsedNumber(from: nutrition.calories),
                        protein: parsedNumber(from: nutrition.protein),
                        carbs: parsedNumber(from: nutrition.carbs),
                        fat: parsedNumber(from: nutrition.fat)
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ImportedMacroLegendRow(
                        color: CooksyTheme.ctaOrange,
                        title: "Protéines",
                        value: nutrition.protein ?? "—"
                    )
                    ImportedMacroLegendRow(
                        color: CooksyTheme.sparkleYellow,
                        title: "Glucides",
                        value: nutrition.carbs ?? "—"
                    )
                    ImportedMacroLegendRow(
                        color: CooksyTheme.brandBlue,
                        title: "Lipides",
                        value: nutrition.fat ?? "—"
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
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

private struct ImportedMacroLegendRow: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct ImportedNutritionRingView: View {
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
                .stroke(CooksyTheme.stroke, lineWidth: 12)

            ImportedNutritionSegment(
                value: fatCalories / totalMacroCalories,
                color: CooksyTheme.brandBlue,
                rotation: -90
            )
            ImportedNutritionSegment(
                value: carbCalories / totalMacroCalories,
                color: CooksyTheme.sparkleYellow,
                rotation: -90 + (fatCalories / totalMacroCalories * 360)
            )
            ImportedNutritionSegment(
                value: proteinCalories / totalMacroCalories,
                color: CooksyTheme.ctaOrange,
                rotation: -90 + ((fatCalories + carbCalories) / totalMacroCalories * 360)
            )

            VStack(spacing: 2) {
                Text(RecipeQuantityScaler.formattedNumber(calories))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("kcal")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
        .frame(width: 112, height: 112)
    }
}

private struct ImportedNutritionSegment: View {
    let value: Double
    let color: Color
    let rotation: Double

    var body: some View {
        Circle()
            .trim(from: 0, to: max(min(value, 1), 0))
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 12, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
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
