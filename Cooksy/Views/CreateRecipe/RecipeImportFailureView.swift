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
                },
                secondaryLabel: "Créer manuellement",
                secondaryAction: onCreateManually
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
        ZStack {
            // Mockup is on strict white — skip the ambient gradient used
            // elsewhere so the fruit row's flat tones read clean.
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top-left chef hat
                HStack {
                    OopsChefHat()
                        .frame(width: 54, height: 54)
                        .padding(.leading, 24)
                        .padding(.top, 12)
                    Spacer()
                }
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : -10)
                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05), value: didAppear)

                // Calligraphy OOPS title. SnellRoundhand-Bold is a system font
                // on iOS, so we can use `.custom` without bundling a ttf.
                Text("OOPS...")
                    .font(.custom("SnellRoundhand-Bold", size: 120))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.top, 24)
                    .opacity(didAppear ? 1 : 0)
                    .scaleEffect(didAppear ? 1 : 0.85)
                    .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.12), value: didAppear)

                Spacer(minLength: 24)

                Text(context.message)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.2), value: didAppear)

                Spacer(minLength: 32)

                VStack(spacing: 14) {
                    primaryButton(
                        title: context.primaryLabel,
                        action: {
                            OnboardingHaptics.medium()
                            context.primaryAction()
                            // If the primary action didn't swap out the view
                            // (e.g. "Créer manuellement" doesn't open anything
                            // of its own), we dismiss so the user gets back
                            // to a known state.
                            if context.primaryLabel == "Créer manuellement" {
                                showsCreateRecipe = true
                            }
                        }
                    )

                    if let secondaryLabel = context.secondaryLabel,
                       let secondaryAction = context.secondaryAction {
                        Button(action: {
                            OnboardingHaptics.selection()
                            secondaryAction()
                            if secondaryLabel == "Créer manuellement" {
                                showsCreateRecipe = true
                            }
                        }) {
                            Text(secondaryLabel)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 30)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 12)
                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.28), value: didAppear)

                Spacer(minLength: 36)

                OopsFruitRow()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 16)
                    .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.35), value: didAppear)
            }
            .padding(.bottom, 0)
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

    private func primaryButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.ctaOrange)
                )
        }
        .buttonStyle(CooksyTheme.pressScale())
    }
}

// MARK: - Chef hat

/// Tiny decorative chef hat drawn with SwiftUI paths, matching the orange
/// line-art style in the mockup. Using a Path keeps us asset-free while the
/// bitmap asset catches up.
private struct OopsChefHat: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let stroke = max(2.5, w * 0.055)

            ZStack {
                // Three puffy top blobs (the iconic chef toque)
                Path { path in
                    // Left blob
                    path.addEllipse(in: CGRect(
                        x: w * 0.06, y: h * 0.10,
                        width: w * 0.42, height: h * 0.45
                    ))
                    // Right blob
                    path.addEllipse(in: CGRect(
                        x: w * 0.52, y: h * 0.10,
                        width: w * 0.42, height: h * 0.45
                    ))
                    // Top centre blob (sits above the other two)
                    path.addEllipse(in: CGRect(
                        x: w * 0.28, y: h * 0.00,
                        width: w * 0.44, height: h * 0.42
                    ))
                }
                .stroke(CooksyTheme.ctaOrangeDark, lineWidth: stroke)

                // The band of the hat (rounded rectangle base)
                RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                    .stroke(CooksyTheme.ctaOrangeDark, lineWidth: stroke)
                    .frame(width: w * 0.78, height: h * 0.32)
                    .offset(y: h * 0.30)
            }
        }
    }
}

// MARK: - Fruit row

/// Colourful row of fruits across the bottom. Uses SF Symbols (iOS 17+
/// fruit glyphs) when available, with emoji as the cross-version fallback.
/// A single HStack keeps spacing predictable on every screen width.
private struct OopsFruitRow: View {
    // Emoji fallback — rendered by Apple's native emoji font so they come out
    // as colourful flat glyphs on every iPhone. If the user later drops a
    // PNG asset named `OopsFruitRow`, we swap to it transparently.
    private let fruits: [String] = ["🍎", "🍐", "🥕", "🍓", "🥑", "🍆"]

    var body: some View {
        Group {
            if UIImage(named: "OopsFruitRow") != nil {
                Image("OopsFruitRow")
                    .resizable()
                    .scaledToFit()
            } else {
                HStack(spacing: 12) {
                    ForEach(fruits, id: \.self) { fruit in
                        Text(fruit)
                            .font(.system(size: 52))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
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
