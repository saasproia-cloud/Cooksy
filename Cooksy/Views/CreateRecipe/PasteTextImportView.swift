import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct PasteTextImportView: View {
    @Environment(\.dismiss) private var dismiss

    let initialText: String
    let onImport: (String, RecipeImportAssessment) -> Void

    @State private var recipeText: String
    @State private var showsAdvice = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImage: UIImage?
    @State private var isImporting = false
    @State private var pasteboardHasText = false
    @FocusState private var isEditorFocused: Bool

    init(
        initialText: String = "",
        onImport: @escaping (String, RecipeImportAssessment) -> Void
    ) {
        self.initialText = initialText
        self.onImport = onImport
        _recipeText = State(initialValue: initialText)
    }

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
                RecipeImportLoadingView(
                    source: .text,
                    title: "Analyse de l'import"
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if pasteboardHasText && recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Coller")
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

                Spacer()

                Button("Terminé") {
                    isEditorFocused = false
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: selectedPhotoItem) {
            guard let selectedPhotoItem else { return }
            if let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                selectedImage = UIImage(data: data)
            }
        }
        .onAppear {
            refreshPasteboardState()
            // Land the user directly on the keyboard so the first tap
            // they want to make ("Coller" / typing) just works.
            if recipeText.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isEditorFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshPasteboardState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPasteboardState()
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
                    .frame(width: 62, height: 62)
                    .background(topButtonBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")

            Spacer()

            ZStack(alignment: .topTrailing) {
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
                .accessibilityLabel(currentImage == nil
                    ? "Ajouter une photo"
                    : "Photo attachée — toucher pour la remplacer")

                if currentImage != nil {
                    Button(action: clearAttachedPhoto) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Retirer la photo")
                }
            }

            Button(action: importRecipe) {
                ZStack {
                    topButtonBackground
                    HStack(spacing: 8) {
                        Text("Importer")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))

                        HStack(spacing: 2) {
                            Text("–1")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundStyle(canImport ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText.opacity(0.6))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill((canImport ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText).opacity(0.12))
                        )
                    }
                    .foregroundStyle(canImport ? CooksyTheme.primaryText : CooksyTheme.secondaryText.opacity(0.7))
                }
                .frame(width: 164, height: 62)
            }
            .buttonStyle(.plain)
            .disabled(!canImport || isImporting)
            .accessibilityHint("Lance l'analyse IA. Consomme 1 éclair d'import sur le plan gratuit.")
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
                .focused($isEditorFocused)

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
        // Dismiss the keyboard so the loading overlay isn't visually
        // cropped by it while the AI works.
        isEditorFocused = false
        isImporting = true

        Task {
            let assessment = await RecipeImportPipeline.importTextAssessment(
                recipeText,
                imageData: selectedImageData
            )

            await MainActor.run {
                isImporting = false
                onImport(recipeText, assessment)
            }
        }
    }

    /// Reads from `UIPasteboard.general` and injects whatever string the
    /// system holds — silently no-ops if there's no text. Triggers the
    /// pasteboard permission prompt the first time on iOS 16+.
    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipeText = pasted
        } else {
            recipeText.append("\n\(pasted)")
        }
    }

    /// Cheap pre-check that doesn't trigger the pasteboard permission
    /// prompt — uses `hasStrings` rather than reading the content. Lets
    /// us decide whether to surface the inline "Coller" shortcut.
    private func refreshPasteboardState() {
        pasteboardHasText = UIPasteboard.general.hasStrings
    }

    private func clearAttachedPhoto() {
        selectedPhotoItem = nil
        selectedImageData = nil
        selectedImage = nil
    }
}
