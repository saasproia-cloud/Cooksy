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
    @State private var showsBookPicker = false
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

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    heroSection

                    if let importNotice = viewModel.importNotice {
                        inlineMessageCard(
                            text: importNotice,
                            tint: CooksyTheme.brandBlueDark,
                            icon: "sparkles"
                        )
                    }

                    quickActionsSection

                    if viewModel.hasContextContent {
                        sourceNotesSection
                    }

                    ingredientsSection
                    instructionsSection

                    if let nutrition = viewModel.nutrition {
                        nutritionSection(nutrition)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 228)
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

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            ImportedRecipeHeroMedia(image: viewModel.heroImage)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.56)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    heroIconButton(systemImage: "chevron.left") {
                        dismiss()
                    }

                    Spacer(minLength: 0)

                    Button("Modifier") {
                        showsEditor = true
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.95))
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
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        if let sourceLabel = viewModel.sourceLabel {
                            heroMetaPill(text: sourceLabel, systemImage: "sparkles")
                        }

                        if let servings = viewModel.heroServingsLabel {
                            heroMetaPill(text: servings, systemImage: "person.2.fill")
                        }
                    }

                    Text(viewModel.title)
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if let calories = viewModel.caloriesSummary {
                            heroSummaryPill(label: "Calories", value: calories)
                        }

                        if let protein = viewModel.proteinSummary {
                            heroSummaryPill(label: "Protéines", value: protein)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            heroInfoChip(
                                title: "\(viewModel.ingredientCount) ingrédients",
                                systemImage: "list.bullet"
                            )
                            heroInfoChip(
                                title: "\(viewModel.instructionCount) étapes",
                                systemImage: "text.justify.left"
                            )

                            if let totalTimeLabel = viewModel.totalTimeLabel {
                                heroInfoChip(
                                    title: totalTimeLabel,
                                    systemImage: "clock"
                                )
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(18)
            }
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 14)
    }

    private var quickActionsSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Actions rapides")

                HStack(spacing: 12) {
                    ImportedQuickActionButton(
                        title: "Livres",
                        systemImage: "books.vertical.fill",
                        action: { showsBookPicker = true }
                    )

                    ImportedQuickActionButton(
                        title: "Plan",
                        systemImage: "calendar.badge.plus",
                        action: { showsPlanSheet = true }
                    )
                    .disabled(!viewModel.canSave)
                    .opacity(viewModel.canSave ? 1 : 0.52)

                    ImportedQuickActionButton(
                        title: "Partager",
                        systemImage: "square.and.arrow.up",
                        action: { showsShareSheet = true }
                    )
                }
            }
        }
    }

    private var sourceNotesSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionEyebrow("Contexte")
                sectionHeader("Source & notes")

                if let sourceURL = viewModel.sourceURL, let sourceButtonTitle = viewModel.sourceButtonTitle {
                    Button(action: { openURL(sourceURL) }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(CooksyTheme.blush)
                                    .frame(width: 40, height: 40)

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sourceButtonTitle)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text(viewModel.sourceHostLabel)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let noteText = viewModel.noteText {
                    Text(noteText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineSpacing(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var ingredientsSection: some View {
        ImportedReviewSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionEyebrow("Préparation")
                        sectionHeader("Ingrédients")

                        Text("Quantités propres, prêtes pour l’enregistrement et l’édition.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: 0)
                }

                HStack(alignment: .center, spacing: 12) {
                    servingsStepper

                    Spacer(minLength: 0)

                    if viewModel.currentServings != viewModel.baseServings {
                        Button(action: viewModel.resetServings) {
                            Label("Base \(viewModel.baseServings)", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.surface)
                            )
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.displayedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                        ImportedIngredientRow(ingredient: ingredient)

                        if index != viewModel.displayedIngredients.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.stroke.opacity(0.9))
                                .padding(.leading, 108)
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionEyebrow("Cuisson")
                        sectionHeader("Instructions")

                        Text("Mode guidé disponible et étapes visibles juste en dessous.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: 0)
                }

                Button(action: { showsStepByStep = true }) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                                .frame(width: 52, height: 52)

                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cuisiner pas à pas")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text("Lancez le mode guidé en cartes plein écran.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText.opacity(0.72))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                                .padding(.leading, 66)
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionEyebrow("Repères")
                        sectionHeader("Nutrition")

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
                                    .fill(CooksyTheme.blush.opacity(0.8))
                            )
                    }
                }

                VStack(spacing: 12) {
                    ImportedNutritionPrimaryCard(
                        title: "Calories",
                        value: nutrition.calories ?? "—",
                        subtitle: viewModel.nutritionServingLabel
                    )

                    HStack(spacing: 12) {
                        ImportedNutritionMetricCard(
                            title: "Protéines",
                            value: nutrition.protein ?? "—",
                            accent: CooksyTheme.ctaOrange
                        )

                        ImportedNutritionMetricCard(
                            title: "Glucides",
                            value: nutrition.carbs ?? "—",
                            accent: CooksyTheme.sparkleYellow
                        )

                        ImportedNutritionMetricCard(
                            title: "Lipides",
                            value: nutrition.fat ?? "—",
                            accent: CooksyTheme.brandBlue
                        )
                    }
                }
            }
        }
    }

    private var saveArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if let reviewNotice = viewModel.reviewNotice {
                    inlineMessageCard(
                        text: reviewNotice,
                        tint: viewModel.canSave ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText,
                        icon: viewModel.canSave ? "checkmark.seal.fill" : "square.and.pencil"
                    )
                }

                HStack(spacing: 12) {
                    Button(action: { showsBookPicker = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)

                            Text(viewModel.selectedBookLabel)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: saveRecipe) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(viewModel.canSave ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.stroke, CooksyTheme.stroke], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 56)

                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(viewModel.canSave ? "Enregistrer" : "Modifier avant d'enregistrer")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving || !viewModel.canSave)
                }

                Button(action: { showsReportAlert = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble")
                        Text("Signaler une erreur d'importation")
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(CooksyTheme.background.opacity(0.9))
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
        }
        .buttonStyle(.plain)
    }

    private func heroMetaPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func heroSummaryPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func heroInfoChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 26, weight: .regular, design: .serif))
            .foregroundStyle(CooksyTheme.primaryText)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.3)
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
    }
}

@MainActor
private final class ImportedRecipeReviewViewModel: ObservableObject {
    struct DisplayIngredient: Identifiable, Hashable {
        let id: RecipeIngredient.ID
        let quantityText: String?
        let name: String
        let emoji: String?
        let fullLine: String
    }

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
        self.currentServings = max(1, RecipeQuantityScaler.baseServings(from: seed.makeRecipe()))

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
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "Ouvrez TikTok" }
        if host.contains("instagram") { return "Ouvrez Instagram" }
        if host.contains("youtube") { return "Ouvrez YouTube" }
        if host.contains("pinterest") { return "Ouvrez Pinterest" }
        return "Ouvrez la source"
    }

    var sourceHostLabel: String {
        sourceURL?.host(percentEncoded: false)?
            .replacingOccurrences(of: "www.", with: "") ?? "Source"
    }

    var sourceLabel: String? {
        guard let host = sourceURL?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("instagram") { return "Instagram" }
        if host.contains("youtube") { return "YouTube" }
        if host.contains("pinterest") { return "Pinterest" }
        return host.replacingOccurrences(of: "www.", with: "").capitalized
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

    var selectedBookLabel: String {
        guard let book = books.first(where: { $0.id == selectedBookID }) else {
            return "Sélectionnez un livre"
        }

        return book.kind == .uncategorized ? "Non catégorisé" : book.title
    }

    var canSave: Bool {
        validation.canSave
    }

    var reviewNotice: String? {
        validation.reviewNotice
    }

    var baseServings: Int {
        max(1, RecipeQuantityScaler.baseServings(from: previewRecipe))
    }

    var heroServingsLabel: String? {
        let value = baseServings
        guard value > 0 else { return nil }
        return value > 1 ? "\(value) portions" : "1 portion"
    }

    var ingredientCount: Int {
        previewRecipe.ingredients.count
    }

    var instructionCount: Int {
        previewRecipe.steps.count
    }

    var totalTimeLabel: String? {
        let prep = Int(seed.prepTimeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let cook = Int(seed.cookTimeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let total = prep + cook
        return total > 0 ? "\(total) min" : nil
    }

    var nutrition: RecipeNutrition? {
        seed.nutrition
    }

    var nutritionIsEstimated: Bool {
        false
    }

    var nutritionServingLabel: String {
        let value = baseServings
        return value > 1 ? "Par portion · \(value) portions" : "Par portion"
    }

    var caloriesSummary: String? {
        nutrition?.calories.flatMap(nonEmpty(_:))
    }

    var proteinSummary: String? {
        nutrition?.protein.flatMap(nonEmpty(_:))
    }

    var displayedIngredients: [DisplayIngredient] {
        previewRecipe.ingredients.map { ingredient in
            let quantityText = RecipeQuantityScaler.scaledQuantityText(
                for: ingredient,
                baseServings: baseServings,
                targetServings: currentServings
            )

            return DisplayIngredient(
                id: ingredient.id,
                quantityText: quantityText,
                name: ingredient.name,
                emoji: IngredientVisualCatalog.specificEmoji(for: ingredient.name),
                fullLine: [quantityText, nonEmpty(ingredient.name)].compactMap { $0 }.joined(separator: " ")
            )
        }
    }

    var instructions: [RecipeStep] {
        previewRecipe.steps
    }

    func selectBook(_ bookID: RecipeBook.ID) {
        selectedBookID = bookID
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CooksyTheme.elevatedSurface,
                                Color.white.opacity(0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: CooksyTheme.softShadow, radius: 16, y: 8)
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
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.blush)
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ImportedIngredientRow: View {
    let ingredient: ImportedRecipeReviewViewModel.DisplayIngredient

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(ingredient.quantityText ?? "À ajuster")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ingredient.quantityText == nil ? CooksyTheme.secondaryText : CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.9))
                    )

                if let emoji = ingredient.emoji {
                    Text(emoji)
                        .font(.system(size: 18))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.88))
                        )
                }
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Quantité ajustée pour \(ingredient.quantityText == nil ? "la recette" : "vos portions")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

private struct ImportedInstructionRow: View {
    let index: Int
    let step: RecipeStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.blush)
                    .frame(width: 36, height: 36)

                Text("\(index)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Étape \(index)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)

                Text(step.detail)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

private struct ImportedNutritionPrimaryCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(CooksyTheme.blush)
                    .frame(width: 70, height: 70)

                Image(systemName: "flame.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
        }
        .padding(18)
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

private struct ImportedNutritionMetricCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 28, height: 6)

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
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
