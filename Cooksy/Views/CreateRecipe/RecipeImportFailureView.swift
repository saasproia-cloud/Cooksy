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
        source: RecipeImportSourceKind = .url,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCreateManually: @escaping () -> Void
    ) -> OopsContext {
        let reason = seed.importDebug?.failureReason
        let sourceURL = seed.sourceURL

        // Pasted text has its own dedicated copy: the original "screenshot the
        // video" advice is meaningless when the user typed/pasted raw text.
        if source == .text {
            return OopsContext(
                message: "On n'a pas pu reconstruire de recette à partir de ce texte.\n\nPour un meilleur résultat :\n• Sépare bien les ingrédients (avec quantités) des instructions.\n• Mets le titre du plat en haut.\n• Une étape de cuisson par ligne.\n• Évite de coller un article ou des commentaires.",
                primaryLabel: "Réessayer le texte",
                primaryAction: onRetry,
                secondaryLabel: "Créer à la main",
                secondaryAction: onCreateManually
            )
        }

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
    let source: RecipeImportSourceKind
    let context: OopsContext

    @State private var showsCreateRecipe = false
    @State private var didAppear = false

    init(
        store: RecipeStore,
        seed: RecipeEditorSeed,
        preferredBookID: RecipeBook.ID? = nil,
        source: RecipeImportSourceKind = .url,
        context: OopsContext
    ) {
        self.store = store
        self.seed = seed
        self.preferredBookID = preferredBookID
        self.source = source
        self.context = context
    }

    var body: some View {
        Group {
            if source == .text {
                pasteTextFailureBody
            } else {
                mockupFailureBody
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

    private var mockupFailureBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.white
                    .ignoresSafeArea()

                Image("OopsErrorScreen")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width)
                    .frame(maxHeight: .infinity, alignment: .top)

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
    }

    private var pasteTextFailureBody: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(CooksyTheme.elevatedSurface))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 24)

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.ctaOrange.opacity(0.14))
                            .frame(width: 96, height: 96)
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    VStack(spacing: 14) {
                        Text("Aucune recette détectée")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .multilineTextAlignment(.center)

                        Text(context.message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(CooksyTheme.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        OnboardingHaptics.medium()
                        context.primaryAction()
                    }) {
                        Text(context.primaryLabel)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(CooksyTheme.accentGradient)
                            )
                            .shadow(color: CooksyTheme.ctaOrange.opacity(0.35), radius: 16, y: 8)
                    }
                    .buttonStyle(CooksyTheme.pressScale())

                    if let secondaryLabel = context.secondaryLabel,
                       let secondaryAction = context.secondaryAction {
                        Button(action: {
                            OnboardingHaptics.selection()
                            secondaryAction()
                        }) {
                            Text(secondaryLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(CooksyTheme.elevatedSurface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
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
