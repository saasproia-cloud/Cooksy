import SwiftUI

struct RecipePresentationHeroCard<LeadingActions: View, TrailingActions: View>: View {
    let heroImage: UIImage?
    let heroStyle: HeroStyle
    let creatorHandle: String?
    let ratingValue: Double?
    let ratingCountText: String?
    let difficultyLabel: String
    let leadingActions: LeadingActions
    let trailingActions: TrailingActions

    init(
        heroImage: UIImage?,
        heroStyle: HeroStyle,
        creatorHandle: String?,
        ratingValue: Double?,
        ratingCountText: String?,
        difficultyLabel: String,
        @ViewBuilder leadingActions: () -> LeadingActions,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) {
        self.heroImage = heroImage
        self.heroStyle = heroStyle
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
            .frame(height: 296)
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
                .padding(16)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    if let creatorHandle {
                        Text(creatorHandle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                            )
                    }
                }
                .padding(18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: CooksyTheme.shadow.opacity(0.7), radius: 16, y: 8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if let totalTimeLabel {
                        RecipeSummaryChip(systemImage: "clock", text: totalTimeLabel)
                    }

                    RecipeSummaryChip(systemImage: "person.2", text: servingsLabel)

                    if let totalCaloriesLabel {
                        RecipeSummaryChip(systemImage: "flame.fill", text: totalCaloriesLabel)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let totalTimeLabel {
                            RecipeSummaryChip(systemImage: "clock", text: totalTimeLabel)
                        }
                        RecipeSummaryChip(systemImage: "person.2", text: servingsLabel)
                    }

                    if let totalCaloriesLabel {
                        RecipeSummaryChip(systemImage: "flame.fill", text: totalCaloriesLabel)
                    }
                }
            }

            if let sourceButtonTitle, let sourceAction {
                Button(action: sourceAction) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(CooksyTheme.blush.opacity(0.9))
                                .frame(width: 42, height: 42)

                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sourceButtonTitle)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text(sourceHostLabel)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }
}

struct RecipePresentationNutritionCard: View {
    let nutrition: RecipeNutritionDisplay?
    let isEstimated: Bool
    let currentServings: Int
    let baseServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)

                        Text("Nutrition")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }

                    Text(RecipePresentationFormatter.baseServingsCaption(for: baseServings))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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

                HStack(spacing: 10) {
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.ctaOrange,
                        title: "Protein",
                        value: nutrition.proteinText
                    )
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.sparkleYellow,
                        title: "Carbs",
                        value: nutrition.carbsText
                    )
                    RecipeMacroMetricCard(
                        tint: CooksyTheme.brandBlue,
                        title: "Fats",
                        value: nutrition.fatText
                    )
                }

                HStack {
                    Text(RecipePresentationFormatter.selectedServingsLabel(for: currentServings))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)

                    Spacer(minLength: 0)

                    Text(nutrition.caloriesText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                if isEstimated {
                    Text("Estimated from ingredients.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            } else {
                RecipePresentationEmptyState(
                    title: "Nutrition unavailable",
                    subtitle: "Cooksy will show calories and macros here when enough ingredient data is available."
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }
}

struct RecipePresentationContentCard: View {
    @Binding var selectedTab: RecipePresentationTab
    let ingredients: [RecipeIngredientPresentation]
    let steps: [RecipeStep]
    let onCookStepByStep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(RecipePresentationTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tabTitle(for: tab))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? .white : CooksyTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                            title: "No ingredients yet",
                            subtitle: "Cooksy will list them here as soon as the recipe is structured."
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(ingredients) { ingredient in
                                RecipeIngredientRow(ingredient: ingredient)
                            }
                        }
                    }

                case .steps:
                    VStack(alignment: .leading, spacing: 12) {
                        if !steps.isEmpty {
                            Button(action: onCookStepByStep) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(CooksyTheme.blush)
                                            .frame(width: 38, height: 38)

                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                                    }

                                    Text("Cook Step-by-Step")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if steps.isEmpty {
                            RecipePresentationEmptyState(
                                title: "No steps yet",
                                subtitle: "Cooksy needs a few clear instructions before step-by-step cooking can start."
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                    RecipeInstructionRow(index: index + 1, step: step)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }

    private func tabTitle(for tab: RecipePresentationTab) -> String {
        switch tab {
        case .ingredients:
            return "Ingredients (\(ingredients.count))"
        case .steps:
            return "Steps (\(steps.count))"
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))

            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 34)
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
                .frame(minWidth: 68)

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

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct RecipeIngredientRow: View {
    let ingredient: RecipeIngredientPresentation

    var body: some View {
        HStack(spacing: 12) {
            IngredientIconBadge(ingredientName: ingredient.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let quantityText = ingredient.quantityText {
                    Text(quantityText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CooksyTheme.stroke)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

private struct RecipeInstructionRow: View {
    let index: Int
    let step: RecipeStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.ctaOrange)
                    .frame(width: 24, height: 24)

                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(step.detail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    private var kind: IngredientIconKind {
        IngredientIconCatalog.kind(for: ingredientName)
    }

    private var tint: Color {
        switch kind {
        case .fish:
            return Color(hex: 0x4D86A8)
        case .produce:
            return Color(hex: 0xD96A3A)
        case .herb:
            return CooksyTheme.brandBlueDark
        case .bulb:
            return Color(hex: 0xA27B5D)
        case .dairy:
            return Color(hex: 0x90A8C3)
        case .cheese:
            return Color(hex: 0xE2A23A)
        case .grain:
            return Color(hex: 0xB88945)
        case .bread:
            return Color(hex: 0xBF8243)
        case .egg:
            return Color(hex: 0xDDAF63)
        case .protein:
            return Color(hex: 0xB25B46)
        case .sauce:
            return Color(hex: 0xC45A3A)
        case .spice:
            return Color(hex: 0xC84A2E)
        case .sweet:
            return Color(hex: 0xA3606D)
        case .logo:
            return CooksyTheme.ctaOrangeDark
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .frame(width: 42, height: 42)

            if kind == .logo {
                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                IngredientGlyph(kind: kind, tint: tint)
                    .frame(width: 24, height: 24)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct IngredientGlyph: View {
    let kind: IngredientIconKind
    let tint: Color

    var body: some View {
        ZStack {
            switch kind {
            case .fish:
                FishGlyph().fill(tint)
            case .produce:
                ProduceGlyph().fill(tint)
            case .herb:
                HerbGlyph().fill(tint)
            case .bulb:
                BulbGlyph().fill(tint)
            case .dairy:
                DairyGlyph().fill(tint)
            case .cheese:
                CheeseGlyph().fill(tint)
            case .grain:
                GrainGlyph().fill(tint)
            case .bread:
                BreadGlyph().fill(tint)
            case .egg:
                EggGlyph().fill(tint)
            case .protein:
                ProteinGlyph().fill(tint)
            case .sauce:
                SauceGlyph().fill(tint)
            case .spice:
                SpiceGlyph().fill(tint)
            case .sweet:
                SweetGlyph().fill(tint)
            case .logo:
                EmptyView()
            }
        }
    }
}

private struct FishGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyRect = CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.25, width: rect.width * 0.56, height: rect.height * 0.5)
        path.addEllipse(in: bodyRect)
        path.move(to: CGPoint(x: bodyRect.maxX - 1, y: rect.midY))
        path.addLines([
            CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + rect.height * 0.18),
            CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY - rect.height * 0.18)
        ])
        path.closeSubpath()
        return path
    }
}

private struct ProduceGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.26, width: rect.width * 0.72, height: rect.height * 0.62))
        path.addEllipse(in: CGRect(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.06, width: rect.width * 0.24, height: rect.height * 0.16))
        return path
    }
}

private struct HerbGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18, width: rect.width * 0.34, height: rect.height * 0.58))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.08, width: rect.width * 0.34, height: rect.height * 0.58))
        path.addRect(CGRect(x: rect.midX - rect.width * 0.03, y: rect.minY + rect.height * 0.52, width: rect.width * 0.06, height: rect.height * 0.32))
        return path
    }
}

private struct BulbGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.24, width: rect.width * 0.64, height: rect.height * 0.58))
        path.addRoundedRect(in: CGRect(x: rect.midX - rect.width * 0.1, y: rect.minY + rect.height * 0.06, width: rect.width * 0.2, height: rect.height * 0.24), cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}

private struct DairyGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.18, width: rect.width * 0.44, height: rect.height * 0.64), cornerSize: CGSize(width: 4, height: 4))
        path.addRect(CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.08, width: rect.width * 0.14, height: rect.height * 0.14))
        return path
    }
}

private struct CheeseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.18))
        path.addLines([
            CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.18),
            CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.18)
        ])
        path.closeSubpath()
        return path
    }
}

private struct GrainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.54, width: rect.width * 0.64, height: rect.height * 0.18), cornerSize: CGSize(width: 6, height: 6))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.26, width: rect.width * 0.16, height: rect.height * 0.18))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.2, width: rect.width * 0.16, height: rect.height * 0.2))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.26, width: rect.width * 0.16, height: rect.height * 0.18))
        return path
    }
}

private struct BreadGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.26, width: rect.width * 0.72, height: rect.height * 0.48), cornerSize: CGSize(width: 9, height: 9))
        return path
    }
}

private struct EggGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.14, width: rect.width * 0.44, height: rect.height * 0.68))
    }
}

private struct ProteinGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.26, width: rect.width * 0.38, height: rect.height * 0.38))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.22, width: rect.width * 0.38, height: rect.height * 0.42), cornerSize: CGSize(width: 7, height: 7))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.28, width: rect.width * 0.1, height: rect.height * 0.12), cornerSize: CGSize(width: 2, height: 2))
        return path
    }
}

private struct SauceGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.22, width: rect.width * 0.44, height: rect.height * 0.5), cornerSize: CGSize(width: 6, height: 6))
        path.addRect(CGRect(x: rect.midX - rect.width * 0.08, y: rect.minY + rect.height * 0.08, width: rect.width * 0.16, height: rect.height * 0.12))
        return path
    }
}

private struct SpiceGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.12),
            control: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.42)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.36),
            control: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08),
            control: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.08)
        )
        return path
    }
}

private struct SweetGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.22, width: rect.width * 0.6, height: rect.height * 0.5), cornerSize: CGSize(width: 6, height: 6))
        path.addRect(CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.12, width: rect.width * 0.1, height: rect.height * 0.1))
        path.addRect(CGRect(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.12, width: rect.width * 0.1, height: rect.height * 0.1))
        path.addRect(CGRect(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.12, width: rect.width * 0.1, height: rect.height * 0.1))
        return path
    }
}
