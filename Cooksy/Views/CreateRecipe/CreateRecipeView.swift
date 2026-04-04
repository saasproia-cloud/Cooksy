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
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 18)

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
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )

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
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                    .overlay(CooksyTheme.stroke)

                Button {
                    if viewModel.saveRecipe() {
                        onSave?()
                        dismiss()
                    }
                } label: {
                    Text(saveButtonTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule(style: .continuous)
                                .fill(viewModel.canSave ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.stroke], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .disabled(!viewModel.canSave)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                topPillButton(title: "Annuler", tint: CooksyTheme.primaryText) {
                    dismiss()
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ATELIER RECETTE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)

                Text(viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Composer une recette" : viewModel.title)
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)
            }
        }
    }

    private var titleRow: some View {
        TextField("Titre", text: $viewModel.title)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
            .padding(.horizontal, 18)
            .frame(height: 82)
            .background(CooksyTheme.surface)
    }

    private func imageRow(selectedImage: UIImage?) -> some View {
        HStack {
            Text("Image")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer()

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CooksyTheme.elevatedSurface)
                        .frame(width: 80, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CooksyTheme.ctaOrange, lineWidth: 1.5)
                        )

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 96)
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
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                }
            .padding(.horizontal, 18)
            .frame(height: 64)
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
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            rows

            addRow(label: addLabel, action: addAction)
        }
        .background(CooksyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func addRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.5))

                Text(label)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.55))

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 68)
            .background(CooksyTheme.surface)
        }
        .buttonStyle(.plain)
    }

    private func topPillButton(
        title: String,
        tint: Color,
        background: Color = CooksyTheme.elevatedSurface,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
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
        Color.clear
            .frame(height: 18)
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
                    .tint(CooksyTheme.ctaOrange)
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
                    .tint(CooksyTheme.ctaOrange)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}
