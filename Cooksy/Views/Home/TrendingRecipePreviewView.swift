import SwiftUI

struct TrendingRecipePreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let scenario: DemoRecipeScenario
    let store: RecipeStore

    @State private var saved = false

    private var previewRecipe: Recipe {
        HomeViewModel.previewRecipe(from: scenario)
    }

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    metadataBar
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    VStack(spacing: 24) {
                        ingredientsCard
                        stepsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: scenario.hero.topColorHex),
                        Color(hex: scenario.hero.bottomColorHex)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 140, height: 140)
                    .offset(x: 60, y: -40)

                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .offset(x: -50, y: 40)

                Text(scenario.hero.emoji)
                    .font(.system(size: 72))
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )

            // Gradient overlay for title
            VStack {
                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
            .frame(height: 280)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )

            // Back button + title overlay
            VStack(alignment: .leading) {
                Button(action: { dismiss() }) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 54)

                Spacer()

                Text(scenario.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .frame(height: 280)
        }
    }

    // MARK: - Metadata

    private var metadataBar: some View {
        HStack(spacing: 16) {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(scenario.prepMinutes + scenario.cookMinutes) min")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.secondaryText)

            Text("·")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.dividerSubtle)

            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(scenario.servings) portions")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.secondaryText)

            Spacer()
        }
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecipeSectionHeader(
                title: "Ingrédients",
                count: scenario.ingredients.count,
                density: .regular
            )

            VStack(spacing: 0) {
                ForEach(Array(scenario.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    let display = IngredientDisplayNormalizer.displayRow(
                        amount: ingredient.amount.isEmpty ? nil : ingredient.amount,
                        unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                        name: ingredient.name
                    )

                    IngredientLocalIcon_PreviewRow(
                        ingredientName: ingredient.name,
                        quantityColumn: display.quantityColumn,
                        nameColumn: display.nameColumn
                    )

                    if index < scenario.ingredients.count - 1 {
                        Divider()
                            .overlay(CooksyTheme.dividerSubtle)
                    }
                }
            }
        }
        .presentationCard(density: .regular)
    }

    // MARK: - Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecipeSectionHeader(
                title: "Étapes",
                count: scenario.steps.count,
                density: .regular
            )

            VStack(spacing: 0) {
                ForEach(Array(scenario.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(CooksyTheme.accentWarm)
                            )

                        Text(step)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 13)
                    .padding(.horizontal, 8)

                    if index < scenario.steps.count - 1 {
                        Divider()
                            .overlay(CooksyTheme.dividerSubtle)
                    }
                }
            }
        }
        .presentationCard(density: .regular)
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CooksyTheme.dividerSubtle)

            HStack(spacing: 14) {
                if saved {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Enregistrée")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                } else {
                    Button(action: saveToLibrary) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Enregistrer")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(CooksyTheme.backgroundCalm.opacity(0.95))
        }
    }

    private func saveToLibrary() {
        let recipe = previewRecipe
        // Demo / trending recipes are baked-in content — they don't run
        // through the AI import pipeline, so they shouldn't consume a
        // free-plan éclair.
        store.addRecipe(recipe, consumesQuota: false)
        withAnimation(.easeInOut(duration: 0.3)) {
            saved = true
        }
    }
}

// MARK: - Preview Ingredient Row (uses local icons, no editing)

private struct IngredientLocalIcon_PreviewRow: View {
    let ingredientName: String
    let quantityColumn: String
    let nameColumn: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IngredientLocalIcon(ingredientName: ingredientName, size: 28)

            Text(quantityColumn)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.accentWarm)
                .frame(width: 86, alignment: .trailing)
                .lineLimit(1)

            Text(nameColumn)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 8)
    }
}
