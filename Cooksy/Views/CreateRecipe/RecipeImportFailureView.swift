import SwiftUI
import UIKit

// MARK: - Oops context

/// Copy + CTA + action for the Oops error screen, derived from the failure
/// reason. Every error path the app can surface (import timeout, not_food,
/// weak metadata, invalid result, …) maps to a tailored `OopsContext` so the
/// screen reads naturally instead of showing a generic "something went wrong".
struct OopsContext {
    let message: String
    let primaryLabel: String
    let primaryAction: () -> Void
    let secondaryLabel: String?
    let secondaryAction: (() -> Void)?

    init(
        message: String,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
    }

    /// Build the contextual copy from a seed's debug info + failure reason.
    /// Callers pass the already-wired dismissal/retry/manual callbacks; this
    /// factory decides which of them the primary CTA should trigger.
    static func from(
        seed: RecipeEditorSeed,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCreateManually: @escaping () -> Void
    ) -> OopsContext {
        let reason = seed.importDebug?.failureReason
        let sourceURL = seed.sourceURL

        switch reason {
        case "not_food",
             "not_enough_ingredients",
             "not_enough_steps",
             "no_recipe_detected",
             "weak_tiktok_metadata":
            // The video doesn't carry enough structured info. The user's best
            // recovery path is to screenshot the TikTok themselves and import
            // the stills — so the primary CTA just opens the original video.
            return OopsContext(
                message: "Cette vidéo ne contient pas suffisamment d'informations pour créer une recette. Essayez avec un autre contenu, vous pouvez prendre des captures d'écran et importer les photos à la place",
                primaryLabel: "Prendre des captures d'écran",
                primaryAction: {
                    if let url = sourceURL {
                        UIApplication.shared.open(url)
                    }
                    // Dismiss the error so the user lands back in a clean state
                    // when they come back to the app after screenshoting.
                    onCancel()
                }
            )

        case "import_too_slow":
            return OopsContext(
                message: "L'import a pris trop de temps. Vérifie ta connexion et réessaie.",
                primaryLabel: "Réessayer",
                primaryAction: onRetry,
                secondaryLabel: "Annuler",
                secondaryAction: onCancel
            )

        case "invalid_recipe_result":
            return OopsContext(
                message: "On n'a pas pu traiter cette vidéo. Réessaie ou crée la recette à la main.",
                primaryLabel: "Réessayer",
                primaryAction: onRetry,
                secondaryLabel: "Créer manuellement",
                secondaryAction: onCreateManually
            )

        default:
            return OopsContext(
                message: "On n'a pas réussi à transformer ce contenu en recette. Essaie avec un autre lien ou crée la recette à la main.",
                primaryLabel: "Créer manuellement",
                primaryAction: onCreateManually,
                secondaryLabel: "Annuler",
                secondaryAction: onCancel
            )
        }
    }
}

// MARK: - Oops screen

/// Screen shown whenever a recipe import fails. Replaces the v2 serif/magnifier
/// card with the "OOPS..." calligraphy + fruit row mockup.
///
/// Callsites pass the `RecipeEditorSeed` (carries the source URL and debug
/// info) and a pre-built `OopsContext`. The view itself is stateless apart
/// from the "create manually" sheet.
@MainActor
struct RecipeImportFailureView: View {
    @Environment(\.dismiss) private var dismiss

    let store: RecipeStore
    let seed: RecipeEditorSeed
    let preferredBookID: RecipeBook.ID?
    let context: OopsContext

    @State private var showsCreateRecipe = false
    @State private var didAppear = false

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed,
        preferredBookID: RecipeBook.ID? = nil,
        context: OopsContext
    ) {
        self.store = store
        self.seed = seed
        self.preferredBookID = preferredBookID
        self.context = context
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.white
                    .ignoresSafeArea()

                // Full-screen mockup image — pixel-perfect match to the design.
                Image("OopsErrorScreen")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width)
                    .frame(maxHeight: .infinity, alignment: .top)

                // Invisible tappable area positioned over the orange CTA
                // inside the image. Coordinates are derived from the original
                // 2245×3179 mockup: the button sits at y≈1995–2225 (≈62.8%
                // → ≈70% of the canvas) and spans ≈12% to ≈88% horizontally.
                Button(action: {
                    OnboardingHaptics.medium()
                    context.primaryAction()
                }) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(CooksyTheme.pressScale())
                .frame(
                    width: proxy.size.width * 0.76,
                    height: proxy.size.width * (230.0 / 2245.0) * 1.4
                )
                .position(
                    x: proxy.size.width / 2,
                    y: imageHeight(in: proxy) * (2110.0 / 3179.0)
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
        .fullScreenCover(isPresented: $showsCreateRecipe) {
            CreateRecipeView(
                store: store,
                seed: seed,
                preferredBookID: preferredBookID
            ) {
                showsCreateRecipe = false
                dismiss()
            }
        }
    }

    /// Computed height of the image when scaled to fit the screen width,
    /// keeping the original 2245×3179 aspect ratio. Used to position the
    /// invisible button overlay relative to the rendered image.
    private func imageHeight(in proxy: GeometryProxy) -> CGFloat {
        let aspect: CGFloat = 3179.0 / 2245.0
        return min(proxy.size.height, proxy.size.width * aspect)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Oops — not enough info") {
    RecipeImportFailureView(
        store: RecipeStore(),
        seed: RecipeEditorSeed(
            sourceURL: URL(string: "https://www.tiktok.com/@chef/video/123"),
            importDebug: RecipeImportDebugInfo(
                ingredientsCount: 0,
                stepsCount: 0,
                strategy: "tiktok",
                durationMs: 1200,
                isLikelyValid: false,
                missing: ["ingredients", "steps"],
                failureReason: "not_food",
                needsReview: false
            )
        ),
        context: OopsContext.from(
            seed: RecipeEditorSeed(
                sourceURL: URL(string: "https://www.tiktok.com/@chef/video/123"),
                importDebug: RecipeImportDebugInfo(
                    ingredientsCount: 0,
                    stepsCount: 0,
                    strategy: "tiktok",
                    durationMs: 1200,
                    isLikelyValid: false,
                    missing: ["ingredients", "steps"],
                    failureReason: "not_food",
                    needsReview: false
                )
            ),
            onRetry: {},
            onCancel: {},
            onCreateManually: {}
        )
    )
}
#endif
