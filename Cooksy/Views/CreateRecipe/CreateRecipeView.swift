import PhotosUI
import SwiftUI

@MainActor
struct CreateRecipeView: View {
    @Environment(\.dismiss) private var dismiss

    private let onSave: (() -> Void)?
    private let saveButtonTitle: String
    @StateObject private var viewModel: CreateRecipeViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showsBookPicker = false
    @State private var showsInformationEditor = false
    @State private var showsNutritionEditor = false

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed? = nil,
        preferredBookID: RecipeBook.ID? = nil,
        editingRecipe: Recipe? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.onSave = onSave
        self.saveButtonTitle = editingRecipe == nil ? "Enregistrer" : "Mettre à jour"
        _viewModel = StateObject(
            wrappedValue: CreateRecipeViewModel(
                store: store,
                seed: seed,
                preferredBookID: preferredBookID,
                editingRecipe: editingRecipe
            )
        )
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 16)

                    sectionDivider

                    VStack(spacing: 0) {
                        titleRow
                        rowDivider
                        imageRow(selectedImage: viewModel.selectedImage)
                        rowDivider
                        selectionRow(
                            title: "Livres de recettes",
                            value: viewModel.selectedBookLabel,
                            action: { showsBookPicker = true }
                        )
                        rowDivider
                        selectionRow(
                            title: "Informations",
                            value: viewModel.informationSummary,
                            action: { showsInformationEditor = true }
                        )
                        rowDivider
                        selectionRow(
                            title: "Nutrition",
                            value: viewModel.nutritionSummary,
                            action: { showsNutritionEditor = true }
                        )
                    }
                    .background(CooksyTheme.surface)

                    sectionDivider

                    editorSection(
                        title: "INGRÉDIENTS",
                        addLabel: "Ajouter un ingrédient",
                        rows: ingredientRows,
                        addAction: viewModel.addIngredient
                    )

                    sectionDivider

                    editorSection(
                        title: "INSTRUCTIONS",
                        addLabel: "Ajouter une étape",
                        rows: stepRows,
                        addAction: viewModel.addStep
                    )
                }
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsBookPicker) {
            RecipeBookPickerSheet(
                books: viewModel.books,
                selectedBookID: viewModel.selectedBookID,
                onSelect: { bookID in
                    viewModel.selectBook(bookID)
                    showsBookPicker = false
                }
            )
        }
        .sheet(isPresented: $showsInformationEditor) {
            InformationEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsNutritionEditor) {
            NutritionEditorSheet(viewModel: viewModel)
        }
        .task(id: selectedPhotoItem) {
            guard let selectedPhotoItem else { return }
            if let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) {
                viewModel.setSelectedImageData(data)
            }
        }
    }

    private var topBar: some View {
        HStack {
            topPillButton(title: "Annuler", tint: CooksyTheme.primaryText) {
                dismiss()
            }

            Spacer()

            topPillButton(
                title: saveButtonTitle,
                tint: viewModel.canSave ? CooksyTheme.ctaOrange : CooksyTheme.secondaryText.opacity(0.55)
            ) {
                if viewModel.saveRecipe() {
                    onSave?()
                    dismiss()
                }
            }
            .disabled(!viewModel.canSave)
        }
    }

    private var titleRow: some View {
        TextField("Titre", text: $viewModel.title)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
            .padding(.horizontal, 22)
            .frame(height: 96)
            .background(CooksyTheme.surface)
    }

    private func imageRow(selectedImage: UIImage?) -> some View {
        HStack {
            Text("Image")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer()

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CooksyTheme.surface)
                        .frame(width: 86, height: 86)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CooksyTheme.ctaOrange, lineWidth: 2)
                        )

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 116)
        .background(CooksyTheme.surface)
    }

    private var ingredientRows: some View {
        VStack(spacing: 0) {
            ForEach($viewModel.ingredientDrafts) { $draft in
                IngredientDraftRow(
                    draft: $draft,
                    onDelete: { viewModel.removeIngredient(id: draft.id) }
                )
                if draft.id != viewModel.ingredientDrafts.last?.id {
                    rowDivider
                }
            }
        }
    }

    private var stepRows: some View {
        VStack(spacing: 0) {
            ForEach($viewModel.stepDrafts) { $draft in
                StepDraftRow(
                    draft: $draft,
                    onDelete: { viewModel.removeStep(id: draft.id) }
                )
                if draft.id != viewModel.stepDrafts.last?.id {
                    rowDivider
                }
            }
        }
    }

    private func selectionRow(title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrange)
            }
            .padding(.horizontal, 22)
            .frame(height: 76)
            .background(CooksyTheme.surface)
        }
        .buttonStyle(.plain)
    }

    private func editorSection<Rows: View>(
        title: String,
        addLabel: String,
        rows: Rows,
        addAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.brandBlueDark)
                .tracking(1.2)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            rows

            addRow(label: addLabel, action: addAction)
        }
        .background(CooksyTheme.surface)
    }

    private func addRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.5))

                Text(label)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.55))

                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 82)
            .background(CooksyTheme.surface)
        }
        .buttonStyle(.plain)
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
                        .fill(CooksyTheme.surface)
                        .shadow(color: Color.black.opacity(0.05), radius: 18, y: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(CooksyTheme.stroke.opacity(0.7))
            .frame(height: 1)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(CooksyTheme.warmCard.opacity(0.7))
            .frame(height: 14)
    }
}

private struct IngredientDraftRow: View {
    @Binding var draft: IngredientDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Qté", text: $draft.amount)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .frame(width: 58)

                TextField("Unité", text: $draft.unit)
                    .textInputAutocapitalization(.never)
                    .frame(width: 70)

                TextField("Ingrédient", text: $draft.name)

                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.red.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(CooksyTheme.surface)
    }
}

private struct StepDraftRow: View {
    @Binding var draft: StepDraft
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("Décrivez l'étape", text: $draft.detail, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(CooksyTheme.surface)
    }
}

private struct RecipeBookPickerSheet: View {
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

private struct InformationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CreateRecipeViewModel

    var body: some View {
        NavigationStack {
            List {
                TextField("Temps de préparation (min)", text: $viewModel.prepTimeText)
                    .keyboardType(.numberPad)
                TextField("Temps de cuisson (min)", text: $viewModel.cookTimeText)
                    .keyboardType(.numberPad)
                TextField("Portions", text: $viewModel.servingsText)
                TextField("Notes", text: $viewModel.notesText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.background)
            .navigationTitle("Informations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminé") {
                        dismiss()
                    }
                    .tint(UIColor(hex: 0xFF7A12).swiftUIColor)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct NutritionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CreateRecipeViewModel

    var body: some View {
        NavigationStack {
            List {
                TextField("Calories", text: $viewModel.caloriesText)
                TextField("Protéines", text: $viewModel.proteinText)
                TextField("Glucides", text: $viewModel.carbsText)
                TextField("Lipides", text: $viewModel.fatText)
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.background)
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminé") {
                        dismiss()
                    }
                    .tint(UIColor(hex: 0xFF7A12).swiftUIColor)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}
