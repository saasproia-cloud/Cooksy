import SwiftUI
import UIKit

private enum QuickImportPhotoSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var pickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }
}

private struct RecipeImportFlowHost: ViewModifier {
    @EnvironmentObject private var recipeStore: RecipeStore

    @Binding var isPresented: Bool
    let preferredBookID: RecipeBook.ID?

    @State private var showsCreateRecipe = false
    @State private var showsPasteTextImport = false
    @State private var showsBrowserImport = false
    @State private var showsImportReview = false
    @State private var showsPhotoSourceDialog = false
    @State private var showsCameraUnavailableAlert = false
    @State private var showsPhotoImportError = false
    @State private var activePhotoImportSource: QuickImportPhotoSource?
    @State private var photoImportErrorMessage = ""
    @State private var isProcessingPhotoImport = false
    @State private var createRecipeSeed: RecipeEditorSeed?
    @State private var importReviewSeed: RecipeEditorSeed?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                QuickImportSheetView(
                    onCreateFromScratch: {
                        createRecipeSeed = nil
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsCreateRecipe = true
                        }
                    },
                    onBrowserImport: {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsBrowserImport = true
                        }
                    },
                    onCameraImport: {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsPhotoSourceDialog = true
                        }
                    },
                    onPasteText: {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsPasteTextImport = true
                        }
                    }
                )
            }
            .confirmationDialog(
                "Importer une image",
                isPresented: $showsPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Prendre une photo") {
                    presentPhotoImport(for: .camera)
                }

                Button("Choisir dans la galerie") {
                    presentPhotoImport(for: .photoLibrary)
                }

                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Choisissez votre source pour démarrer une recette à partir d'une photo.")
            }
            .alert("Appareil photo indisponible", isPresented: $showsCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("La caméra n'est pas disponible sur cet appareil. Vous pouvez choisir une image depuis la galerie.")
            }
            .alert("Import photo incomplet", isPresented: $showsPhotoImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoImportErrorMessage)
            }
            .sheet(item: $activePhotoImportSource) { source in
                SystemImagePicker(sourceType: source.pickerSourceType) { data in
                    handleImportedImage(data)
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showsBrowserImport) {
                BrowserImportView { seed in
                    importReviewSeed = seed
                    showsBrowserImport = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showsImportReview = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showsPasteTextImport) {
                PasteTextImportView { seed in
                    importReviewSeed = seed
                    showsPasteTextImport = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showsImportReview = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showsImportReview, onDismiss: {
                importReviewSeed = nil
            }) {
                if let importReviewSeed {
                    ImportedRecipeReviewView(
                        store: recipeStore,
                        seed: importReviewSeed,
                        preferredBookID: preferredBookID
                    )
                }
            }
            .fullScreenCover(isPresented: $showsCreateRecipe, onDismiss: {
                createRecipeSeed = nil
            }) {
                CreateRecipeView(
                    store: recipeStore,
                    seed: createRecipeSeed,
                    preferredBookID: preferredBookID
                )
            }
            .overlay {
                if isProcessingPhotoImport {
                    RecipeImportProcessingOverlay(
                        title: "Analyse de la photo",
                        message: "Cooksy lit votre image pour retrouver les ingredients et les etapes."
                    )
                }
            }
    }

    private func presentPhotoImport(for source: QuickImportPhotoSource) {
        guard source != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showsCameraUnavailableAlert = true
            return
        }

        activePhotoImportSource = source
    }

    private func handleImportedImage(_ data: Data?) {
        activePhotoImportSource = nil

        guard let data else { return }

        isProcessingPhotoImport = true

        Task {
            let seed = await RecipeImportPipeline.importPhoto(from: data)

            await MainActor.run {
                isProcessingPhotoImport = false

                if seed.normalizedIngredients.isEmpty && seed.normalizedSteps.isEmpty {
                    photoImportErrorMessage = "Cooksy n'a pas trouve de recette complete dans cette image. Vous pouvez continuer manuellement."
                    showsPhotoImportError = true
                    createRecipeSeed = seed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showsCreateRecipe = true
                    }
                } else {
                    importReviewSeed = seed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showsImportReview = true
                    }
                }
            }
        }
    }
}

private struct RecipeImportProcessingOverlay: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(CooksyTheme.ctaOrange)
                    .scaleEffect(1.15)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(message)
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
}

extension View {
    func recipeImportFlow(
        isPresented: Binding<Bool>,
        preferredBookID: RecipeBook.ID? = nil
    ) -> some View {
        modifier(RecipeImportFlowHost(isPresented: isPresented, preferredBookID: preferredBookID))
    }
}
