import PhotosUI
import SwiftUI

@MainActor
struct PasteTextImportView: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (RecipeImportAssessment) -> Void

    @State private var recipeText = ""
    @State private var showsAdvice = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImage: UIImage?
    @State private var isImporting = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                adviceCard
                    .padding(.horizontal, 20)

                textEditor
                    .padding(.top, 28)
            }

            if isImporting {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .tint(CooksyTheme.ctaOrange)
                        .scaleEffect(1.15)

                    Text("Analyse en cours")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("Cooksy structure votre recette et prépare les ingrédients, l'image et les étapes.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 30)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: selectedPhotoItem) {
            guard let selectedPhotoItem else { return }
            if let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                selectedImage = UIImage(data: data)
            }
        }
    }

    private var canImport: Bool {
        !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var topBar: some View {
        let currentImage = selectedImage

        return HStack(spacing: 14) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 92, height: 62)
                    .background(topButtonBackground)
            }
            .buttonStyle(.plain)

            Spacer()

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.07), radius: 22, y: 12)
                        .frame(width: 62, height: 62)

                    if let currentImage {
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: importRecipe) {
                Text("Importer")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(canImport ? CooksyTheme.primaryText : CooksyTheme.secondaryText.opacity(0.7))
                    .frame(width: 164, height: 62)
                    .background(topButtonBackground)
            }
            .buttonStyle(.plain)
            .disabled(!canImport || isImporting)
        }
    }

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: showsAdvice ? 18 : 0) {
            Button(action: { showsAdvice.toggle() }) {
                HStack(alignment: .center, spacing: 12) {
                    Text("✨ Conseils d’importation ✨")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Spacer()

                    Image(systemName: showsAdvice ? "chevron.down" : "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showsAdvice {
                Text("Notre outil d’importation fonctionne mieux si chaque ingrédient et chaque étape sont sur une nouvelle ligne")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.surface)
        )
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $recipeText)
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 20)

            if recipeText.isEmpty {
                Text("Tapez ou collez la recette complète")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.55))
                    .padding(.horizontal, 25)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var topButtonBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.07), radius: 22, y: 12)
    }

    private func importRecipe() {
        guard canImport, !isImporting else { return }
        isImporting = true

        Task {
            let assessment = await RecipeImportPipeline.importTextAssessment(
                recipeText,
                imageData: selectedImageData
            )

            await MainActor.run {
                isImporting = false
                onImport(assessment)
            }
        }
    }
}
