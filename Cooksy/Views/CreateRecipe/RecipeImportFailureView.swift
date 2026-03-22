import SwiftUI

@MainActor
struct RecipeImportFailureView: View {
    @Environment(\.dismiss) private var dismiss

    private let store: RecipeStore
    private let onRetry: () -> Void
    private let onCancel: () -> Void
    private let onManualSaved: (() -> Void)?

    let seed: RecipeEditorSeed
    let preferredBookID: RecipeBook.ID?

    @State private var showsCreateRecipe = false

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed,
        preferredBookID: RecipeBook.ID? = nil,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onManualSaved: (() -> Void)? = nil
    ) {
        self.store = store
        self.seed = seed
        self.preferredBookID = preferredBookID
        self.onRetry = onRetry
        self.onCancel = onCancel
        self.onManualSaved = onManualSaved
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.94))
                            .frame(width: 110, height: 110)

                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    VStack(spacing: 12) {
                        Text("Impossible d’importer cette recette")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .multilineTextAlignment(.center)

                        Text("Le contenu partagé ne contient pas une recette exploitable")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 34)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
                )
                .padding(.horizontal, 24)

                VStack(spacing: 14) {
                    primaryButton(title: "Réessayer", fill: CooksyTheme.ctaOrange, textColor: .white) {
                        dismiss()
                        onRetry()
                    }

                    primaryButton(title: "Créer manuellement", fill: .white, textColor: CooksyTheme.primaryText) {
                        showsCreateRecipe = true
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1.6)
                    )

                    Button("Annuler") {
                        dismiss()
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCreateRecipe) {
            CreateRecipeView(
                store: store,
                seed: seed,
                preferredBookID: preferredBookID
            ) {
                showsCreateRecipe = false
                onManualSaved?()
                dismiss()
            }
        }
    }

    private func primaryButton(
        title: String,
        fill: Color,
        textColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fill)
                )
        }
        .buttonStyle(.plain)
    }
}
