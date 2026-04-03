import SwiftUI

struct RecipePresentationHeroCard<LeadingActions: View, TrailingActions: View>: View {
    let heroImage: UIImage?
    let heroStyle: HeroStyle
    let density: RecipePresentationDensity
    let creatorHandle: String?
    let ratingValue: Double?
    let ratingCountText: String?
    let difficultyLabel: String
    let leadingActions: LeadingActions
    let trailingActions: TrailingActions

    init(
        heroImage: UIImage?,
        heroStyle: HeroStyle,
        density: RecipePresentationDensity = .regular,
        creatorHandle: String?,
        ratingValue: Double?,
        ratingCountText: String?,
        difficultyLabel: String,
        @ViewBuilder leadingActions: () -> LeadingActions,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) {
        self.heroImage = heroImage
        self.heroStyle = heroStyle
        self.density = density
        self.creatorHandle = creatorHandle
        self.ratingValue = ratingValue
        self.ratingCountText = ratingCountText
        self.difficultyLabel = difficultyLabel
        self.leadingActions = leadingActions()
        self.trailingActions = trailingActions()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RecipePresentationHeroPlaceholder(heroStyle: heroStyle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: density == .compact ? 212 : 296)
            .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    leadingActions
                    Spacer(minLength: 0)
                    trailingActions
                }
                .padding(density == .compact ? 12 : 16)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    if let creatorHandle {
                        Text(creatorHandle)
                            .font(.system(size: density == .compact ? 10 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, density == .compact ? 8 : 10)
                            .frame(height: density == .compact ? 22 : 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.46))
                            )
                    }

                    HStack(alignment: .center) {
                        if let ratingValue {
                            RecipePresentationRatingView(
                                ratingValue: ratingValue,
                                ratingCountText: ratingCountText
                            )
                        }

                        Spacer(minLength: 0)

                        Text(difficultyLabel)
                            .font(.system(size: density == .compact ? 10 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, density == .compact ? 8 : 10)
                            .frame(height: density == .compact ? 22 : 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                            )
                    }
                }
                .padding(density == .compact ? 14 : 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: density == .compact ? 22 : 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 22 : 28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: CooksyTheme.shadow.opacity(0.7), radius: density == .compact ? 10 : 16, y: density == .compact ? 4 : 8)
    }
}

struct RecipePresentationSummaryCard: View {
    let title: String
    let summaryText: String
    let totalTimeLabel: String?
    let totalCaloriesLabel: String?
    let servingsLabel: String
    let sourceButtonTitle: String?
    let sourceHostLabel: String
    let sourceAction: (() -> Void)?
    let density: RecipePresentationDensity

    init(
        title: String,
        summaryText: String,
        totalTimeLabel: String?,
        totalCaloriesLabel: String?,
        servingsLabel: String,
        sourceButtonTitle: String?,
        sourceHostLabel: String,
        sourceAction: (() -> Void)?,
        density: RecipePresentationDensity = .regular
    ) {
        self.title = title
        self.summaryText = summaryText
        self.totalTimeLabel = totalTimeLabel
        self.totalCaloriesLabel = totalCaloriesLabel
        self.servingsLabel = servingsLabel
        self.sourceButtonTitle = sourceButtonTitle
        self.sourceHostLabel = sourceHostLabel
        self.sourceAction = sourceAction
        self.density = density
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 18) {
            Text(title)
                .font(.system(size: density == .compact ? 24 : 32, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryText)
                .font(.system(size: density == .compact ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(density == .compact ? 2 : 6)
                .lineLimit(density == .compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: density == .compact ? 6 : 8) {
                    if let totalTimeLabel {
                        RecipeSummaryChip(systemImage: "clock", text: totalTimeLabel, density: density)
                    }

                    RecipeSummaryChip(systemImage: "person.2", text: servingsLabel, density: density)

                    if let totalCaloriesLabel {
                        RecipeSummaryChip(systemImage: "flame.fill", text: totalCaloriesLabel, density: density)
                    }
                }

                VStack(alignment: .leading, spacing: density == .compact ? 6 : 8) {
                    HStack(spacing: density == .compact ? 6 : 8) {
                        if let totalTimeLabel {
                            RecipeSummaryChip(systemImage: "clock", text: totalTimeLabel, density: density)
                        }
                        RecipeSummaryChip(systemImage: "person.2", text: servingsLabel, density: density)
                    }

                    if let totalCaloriesLabel {
                        RecipeSummaryChip(systemImage: "flame.fill", text: totalCaloriesLabel, density: density)
                    }
                }
            }

            if let sourceButtonTitle, let sourceAction {
                Button(action: sourceAction) {
                    HStack(spacing: density == .compact ? 10 : 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: density == .compact ? 12 : 14, style: .continuous)
                                .fill(CooksyTheme.blush.opacity(0.9))
                                .frame(width: density == .compact ? 38 : 42, height: density == .compact ? 38 : 42)

                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: density == .compact ? 14 : 16, weight: .bold))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sourceButtonTitle)
                                .font(.system(size: density == .compact ? 14 : 15, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text(sourceHostLabel)
                                .font(.system(size: density == .compact ? 11 : 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: density == .compact ? 12 : 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, density == .compact ? 12 : 14)
                    .frame(height: density == .compact ? 50 : 58)
                    .background(
                        RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(density == .compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: density == .compact ? 8 : 12, y: density == .compact ? 4 : 6)
    }
}

struct RecipePresentationNutritionCard: View {
    let nutrition: RecipeNutritionDisplay?
    let isEstimated: Bool
    let currentServings: Int
    let baseServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    let density: RecipePresentationDensity

    init(
        nutrition: RecipeNutritionDisplay?,
        isEstimated: Bool,
        currentServings: Int,
        baseServings: Int,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        density: RecipePresentationDensity = .regular
    ) {
        self.nutrition = nutrition
        self.isEstimated = isEstimated
        self.currentServings = currentServings
        self.baseServings = baseServings
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.density = density
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 12 : 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: density == .compact ? 11 : 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)

                        Text("Nutrition")
                            .font(.system(size: density == .compact ? 15 : 16, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }

                    Text(RecipePresentationFormatter.baseServingsCaption(for: baseServings))
                        .font(.system(size: density == .compact ? 11 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                    RecipeServingStepper(
                        currentServings: currentServings,
                        onDecrease: onDecrease,
                        onIncrease: onIncrease
                    )
            }

            if let nutrition {
                RecipeNutritionMacroBar(nutrition: nutrition)

                HStack(spacing: density == .compact ? 8 : 10) {
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.ctaOrange,
                        title: "Protéines",
                        value: nutrition.proteinText,
                        density: density
                    )
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.sparkleYellow,
                        title: "Glucides",
                        value: nutrition.carbsText,
                        density: density
                    )
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.brandBlue,
                        title: "Lipides",
                        value: nutrition.fatText,
                        density: density
                    )
                }

                HStack {
                    Text(RecipePresentationFormatter.selectedServingsLabel(for: currentServings))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)

                    Spacer(minLength: 0)

                    Text(nutrition.caloriesText)
                        .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                if isEstimated {
                    Text("Estimation calculée à partir des ingrédients.")
                        .font(.system(size: density == .compact ? 10 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            } else {
                RecipePresentationEmptyState(
                    title: "Nutrition indisponible",
                    subtitle: "Cooksy affichera les calories et macros ici dès que les ingrédients seront assez précis."
                )
            }
        }
        .padding(density == .compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: density == .compact ? 8 : 12, y: density == .compact ? 4 : 6)
    }
}

struct RecipePresentationContentCard: View {
    @Binding var selectedTab: RecipePresentationTab
    let ingredients: [RecipeIngredientPresentation]
    let steps: [RecipeStep]
    let onCookStepByStep: () -> Void
    let density: RecipePresentationDensity

    init(
        selectedTab: Binding<RecipePresentationTab>,
        ingredients: [RecipeIngredientPresentation],
        steps: [RecipeStep],
        onCookStepByStep: @escaping () -> Void,
        density: RecipePresentationDensity = .regular
    ) {
        self._selectedTab = selectedTab
        self.ingredients = ingredients
        self.steps = steps
        self.onCookStepByStep = onCookStepByStep
        self.density = density
    }

    private var ingredientPhotoTaskKey: String {
        ingredients.map(\.name).joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
            HStack(spacing: density == .compact ? 6 : 8) {
                ForEach(RecipePresentationTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tabTitle(for: tab))
                            .font(.system(size: density == .compact ? 12 : 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? .white : CooksyTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: density == .compact ? 34 : 38)
                            .background(
                                RoundedRectangle(cornerRadius: density == .compact ? 10 : 12, style: .continuous)
                                    .fill(selectedTab == tab ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.surface, CooksyTheme.surface], startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                switch selectedTab {
                case .ingredients:
                    if ingredients.isEmpty {
                        RecipePresentationEmptyState(
                            title: "Pas encore d'ingrédients",
                            subtitle: "Cooksy affichera les ingrédients ici dès que la recette sera bien structurée."
                        )
                    } else {
                        VStack(spacing: density == .compact ? 8 : 12) {
                            ForEach(ingredients) { ingredient in
                                RecipeIngredientRow(ingredient: ingredient, density: density)
                            }
                        }
                    }

                case .steps:
                    VStack(alignment: .leading, spacing: density == .compact ? 8 : 12) {
                        if !steps.isEmpty {
                            Button(action: onCookStepByStep) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(CooksyTheme.blush)
                                            .frame(width: density == .compact ? 34 : 38, height: density == .compact ? 34 : 38)

                                        Image(systemName: "play.fill")
                                            .font(.system(size: density == .compact ? 13 : 14, weight: .bold))
                                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                                    }

                                    Text("Cuisiner pas à pas")
                                        .font(.system(size: density == .compact ? 14 : 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, density == .compact ? 10 : 12)
                                .frame(height: density == .compact ? 44 : 50)
                                .background(
                                    RoundedRectangle(cornerRadius: density == .compact ? 14 : 16, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: density == .compact ? 14 : 16, style: .continuous)
                                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if steps.isEmpty {
                            RecipePresentationEmptyState(
                                title: "Pas encore d'étapes",
                                subtitle: "Cooksy a besoin de quelques instructions claires avant de lancer le pas-à-pas."
                            )
                        } else {
                            VStack(spacing: density == .compact ? 8 : 12) {
                                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                    RecipeInstructionRow(index: index + 1, step: step, density: density)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(density == .compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 18 : 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: density == .compact ? 8 : 12, y: density == .compact ? 4 : 6)
        .task(id: ingredientPhotoTaskKey) {
            await IngredientPhotoStore.shared.preload(for: ingredients.map(\.name))
        }
    }

    private func tabTitle(for tab: RecipePresentationTab) -> String {
        switch tab {
        case .ingredients:
            return "Ingrédients (\(ingredients.count))"
        case .steps:
            return "Étapes (\(steps.count))"
        }
    }
}

struct RecipePresentationActionIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct RecipePresentationHeroPlaceholder: View {
    let heroStyle: HeroStyle

    var body: some View {
        ZStack {
            CooksyTheme.recipeGradient(for: heroStyle)

            Image(systemName: "fork.knife")
                .font(.system(size: 70, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }
}

private struct RecipePresentationRatingView: View {
    let ratingValue: Double
    let ratingCountText: String?

    private var filledStars: Int {
        max(1, min(5, Int(ratingValue.rounded())))
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: index < filledStars ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CooksyTheme.sparkleYellow)
                }
            }

            Text(RecipePresentationFormatter.ratingText(for: ratingValue) ?? "")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let ratingCountText {
                Text(ratingCountText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }
}

private struct RecipeSummaryChip: View {
    let systemImage: String
    let text: String
    let density: RecipePresentationDensity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: density == .compact ? 10 : 11, weight: .bold))

            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: density == .compact ? 11 : 12, weight: .bold, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText)
        .padding(.horizontal, density == .compact ? 8 : 10)
        .frame(height: density == .compact ? 30 : 34)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct RecipeServingStepper: View {
    let currentServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Text(RecipePresentationFormatter.selectedServingsLabel(for: currentServings))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(minWidth: 84)

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct RecipeNutritionMacroBar: View {
    let nutrition: RecipeNutritionDisplay

    private var proteinCalories: Double { max(nutrition.protein, 0) * 4 }
    private var carbCalories: Double { max(nutrition.carbs, 0) * 4 }
    private var fatCalories: Double { max(nutrition.fat, 0) * 9 }
    private var total: Double { max(proteinCalories + carbCalories + fatCalories, 1) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CooksyTheme.ctaOrange)
                    .frame(width: max(18, proxy.size.width * proteinCalories / total))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CooksyTheme.sparkleYellow)
                    .frame(width: max(18, proxy.size.width * carbCalories / total))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CooksyTheme.brandBlue)
                    .frame(width: max(18, proxy.size.width * fatCalories / total))
            }
        }
        .frame(height: 8)
    }
}

private struct RecipeMacroMetricCard: View {
    let tint: Color
    let title: String
    let value: String
    let density: RecipePresentationDensity

    var body: some View {
        VStack(spacing: density == .compact ? 4 : 6) {
            Circle()
                .fill(tint)
                .frame(width: density == .compact ? 5 : 6, height: density == .compact ? 5 : 6)

            Text(value)
                .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(title)
                .font(.system(size: density == .compact ? 10 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, density == .compact ? 9 : 12)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 16, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct RecipeIngredientRow: View {
    let ingredient: RecipeIngredientPresentation
    let density: RecipePresentationDensity

    var body: some View {
        HStack(spacing: density == .compact ? 10 : 14) {
            IngredientIconBadge(
                ingredientName: ingredient.name,
                size: density == .compact ? 38 : 46
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.system(size: density == .compact ? 14 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let quantityText = ingredient.quantityText {
                    Text(quantityText)
                        .font(.system(size: density == .compact ? 11 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if density == .regular {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.stroke)
            }
        }
        .padding(.horizontal, density == .compact ? 12 : 16)
        .padding(.vertical, density == .compact ? 9 : 14)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: density == .regular ? 4 : 0, y: density == .regular ? 2 : 0)
    }
}

private struct RecipeInstructionRow: View {
    let index: Int
    let step: RecipeStep
    let density: RecipePresentationDensity

    var body: some View {
        HStack(alignment: .top, spacing: density == .compact ? 10 : 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.ctaOrange)
                    .frame(width: density == .compact ? 22 : 28, height: density == .compact ? 22 : 28)

                Text("\(index)")
                    .font(.system(size: density == .compact ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(step.detail)
                    .font(.system(size: density == .compact ? 14 : 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(density == .compact ? 2 : 5)
                    .fixedSize(horizontal: false, vertical: true)

                if let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Text(title)
                        .font(.system(size: density == .compact ? 11 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, density == .compact ? 12 : 16)
        .padding(.vertical, density == .compact ? 10 : 16)
        .background(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .compact ? 14 : 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: density == .regular ? 4 : 0, y: density == .regular ? 2 : 0)
    }
}

private struct RecipePresentationEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

struct IngredientIconBadge: View {
    let ingredientName: String
    let size: CGFloat
    @State private var image: UIImage?

    init(ingredientName: String, size: CGFloat = 42) {
        self.ingredientName = ingredientName
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
                .fill(Color.white)
                .frame(width: size, height: size)

            imageView
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.38, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .task(id: ingredientName) {
            image = await IngredientPhotoStore.shared.image(for: ingredientName)
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            IngredientPhotoPlaceholder(ingredientName: ingredientName)
        }
    }
}

private struct IngredientPhotoPlaceholder: View {
    let ingredientName: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xFFF6EA),
                    Color(hex: 0xEBCB9C)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 24, height: 24)
                .offset(x: -8, y: -7)

            Circle()
                .fill(Color(hex: 0xD9A15D).opacity(0.26))
                .frame(width: 18, height: 18)
                .offset(x: 9, y: 9)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 18, height: 12)
                .rotationEffect(.degrees(-18))
                .offset(x: 6, y: -6)
        }
    }
}
