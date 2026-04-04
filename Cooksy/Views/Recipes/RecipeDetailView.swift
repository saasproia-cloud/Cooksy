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
    @State private var activeSection: RecipeDetailSection = .ingredients

    init(store: RecipeStore, recipeID: Recipe.ID) {
        self.store = store
        _viewModel = StateObject(wrappedValue: RecipeDetailViewModel(store: store, recipeID: recipeID))
    }

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm
                .ignoresSafeArea()

            if let recipe = viewModel.recipe {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            heroSection(recipe: recipe)

                            VStack(spacing: 16) {
                                metadataBar

                                summarySection

                                stickySegmentedControl(scrollProxy: scrollProxy)

                                ingredientsSection
                                    .id(RecipeDetailSection.ingredients)

                                stepsSection
                                    .id(RecipeDetailSection.steps)

                                nutritionSection
                                    .id(RecipeDetailSection.nutrition)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 120)
                        }
                    }
                }
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

    // MARK: - Hero

    private func heroSection(recipe: Recipe) -> some View {
        RecipePresentationHeroCard(
            heroImage: viewModel.heroImage,
            heroStyle: recipe.heroStyle,
            title: viewModel.title,
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

    // MARK: - Metadata

    private var metadataBar: some View {
        RecipeMetadataBar(
            totalTimeLabel: viewModel.totalTimeLabel,
            servingsLabel: viewModel.servingsLabel,
            difficultyLabel: viewModel.difficultyLabel
        )
    }

    // MARK: - Summary

    private var summarySection: some View {
        RecipePresentationSummaryCard(
            summaryText: viewModel.summaryText,
            sourceButtonTitle: viewModel.sourceButtonTitle,
            sourceHostLabel: viewModel.sourceHostLabel,
            sourceAction: viewModel.sourceURL.map { sourceURL in
                { openURL(sourceURL) }
            }
        )
    }

    // MARK: - Sticky Segmented Control

    private func stickySegmentedControl(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            ForEach(RecipeDetailSection.allCases) { section in
                Button {
                    activeSection = section
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(section, anchor: .top)
                    }
                } label: {
                    Text(section.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(activeSection == section ? .white : CooksyTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(activeSection == section
                                      ? AnyShapeStyle(CooksyTheme.accentGradient)
                                      : AnyShapeStyle(CooksyTheme.backgroundCalm))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        RecipeIngredientListCard(
            ingredients: viewModel.displayedIngredients,
            currentServings: viewModel.currentServings,
            baseServings: viewModel.baseServings,
            onDecrease: { viewModel.changeServings(by: -1) },
            onIncrease: { viewModel.changeServings(by: 1) },
            editingID: viewModel.editingIngredientID,
            onTapRow: { ingredient in
                guard let recipe = viewModel.recipe,
                      let raw = recipe.ingredients.first(where: { $0.id == ingredient.id }) else { return }
                viewModel.beginEditingIngredient(raw)
            },
            editAmount: $viewModel.editDraftAmount,
            editUnit: $viewModel.editDraftUnit,
            editName: $viewModel.editDraftName,
            onSaveEdit: { viewModel.saveIngredientEdit() },
            onCancelEdit: { viewModel.cancelEdit() }
        )
    }

    // MARK: - Steps

    private var stepsSection: some View {
        RecipeStepListCard(
            steps: viewModel.instructions,
            onCookStepByStep: { showsStepByStep = true },
            editingID: viewModel.editingStepID,
            onTapRow: { step in viewModel.beginEditingStep(step) },
            editStepDetail: $viewModel.editDraftStepDetail,
            onSaveEdit: { viewModel.saveStepEdit() },
            onCancelEdit: { viewModel.cancelEdit() }
        )
    }

    // MARK: - Nutrition

    private var nutritionSection: some View {
        RecipePresentationNutritionCard(
            nutrition: viewModel.nutritionDisplay,
            isEstimated: viewModel.nutritionIsEstimated,
            currentServings: viewModel.currentServings,
            baseServings: viewModel.baseServings,
            onDecrease: { viewModel.changeServings(by: -1) },
            onIncrease: { viewModel.changeServings(by: 1) }
        )
    }
}

// MARK: - Section Enum

private enum RecipeDetailSection: String, CaseIterable, Identifiable {
    case ingredients
    case steps
    case nutrition

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ingredients: return "Ingrédients"
        case .steps: return "Étapes"
        case .nutrition: return "Nutrition"
        }
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
