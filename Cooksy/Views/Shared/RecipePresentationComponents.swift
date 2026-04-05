import SwiftUI

// MARK: - Hero Card

struct RecipePresentationHeroCard<LeadingActions: View, TrailingActions: View>: View {
    let heroImage: UIImage?
    let heroStyle: HeroStyle
    let title: String
    let density: RecipePresentationDensity
    let creatorHandle: String?
    let difficultyLabel: String
    let leadingActions: LeadingActions
    let trailingActions: TrailingActions

    init(
        heroImage: UIImage?,
        heroStyle: HeroStyle,
        title: String,
        density: RecipePresentationDensity = .regular,
        creatorHandle: String?,
        difficultyLabel: String,
        @ViewBuilder leadingActions: () -> LeadingActions,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) {
        self.heroImage = heroImage
        self.heroStyle = heroStyle
        self.title = title
        self.density = density
        self.creatorHandle = creatorHandle
        self.difficultyLabel = difficultyLabel
        self.leadingActions = leadingActions()
        self.trailingActions = trailingActions()
    }

    private var heroHeight: CGFloat { density == .compact ? 220 : 320 }

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
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Top action bar
                HStack(alignment: .top) {
                    leadingActions
                    Spacer(minLength: 0)
                    trailingActions
                }
                .padding(density == .compact ? 12 : 16)

                Spacer(minLength: 0)

                // Bottom overlay: title + badges
                VStack(alignment: .leading, spacing: density == .compact ? 8 : 12) {
                    HStack(spacing: 8) {
                        if let creatorHandle {
                            Text(creatorHandle)
                                .font(.system(size: density == .compact ? 10 : 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, density == .compact ? 8 : 10)
                                .frame(height: density == .compact ? 22 : 24)
                                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.46)))
                        }

                        Spacer(minLength: 0)

                        Text(difficultyLabel)
                            .font(.system(size: density == .compact ? 10 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, density == .compact ? 8 : 10)
                            .frame(height: density == .compact ? 22 : 24)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.18)))
                    }

                    Text(title)
                        .font(.system(size: density == .compact ? 22 : 30, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, density == .compact ? 14 : 20)
                .padding(.bottom, density == .compact ? 14 : 20)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: density == .compact ? 20 : 24,
                bottomTrailingRadius: density == .compact ? 20 : 24,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }
}

// MARK: - Metadata Bar

struct RecipeMetadataBar: View {
    let totalTimeLabel: String?
    let servingsLabel: String
    let density: RecipePresentationDensity

    init(
        totalTimeLabel: String?,
        servingsLabel: String,
        density: RecipePresentationDensity = .regular
    ) {
        self.totalTimeLabel = totalTimeLabel
        self.servingsLabel = servingsLabel
        self.density = density
    }

    var body: some View {
        HStack(spacing: density == .compact ? 14 : 18) {
            if let totalTimeLabel {
                metadataItem(systemImage: "clock", text: totalTimeLabel)
                dotSeparator
            }

            metadataItem(systemImage: "person.2", text: servingsLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, density == .compact ? 10 : 14)
    }

    private func metadataItem(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: density == .compact ? 12 : 13, weight: .semibold))

            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: density == .compact ? 13 : 14, weight: .semibold, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText)
    }

    private var dotSeparator: some View {
        Text("·")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CooksyTheme.dividerSubtle)
    }
}

// MARK: - Summary Card (simplified — no title, no chips)

struct RecipePresentationSummaryCard: View {
    let summaryText: String
    let sourceButtonTitle: String?
    let sourceHostLabel: String
    let sourceAction: (() -> Void)?
    let density: RecipePresentationDensity

    init(
        summaryText: String,
        sourceButtonTitle: String?,
        sourceHostLabel: String,
        sourceAction: (() -> Void)?,
        density: RecipePresentationDensity = .regular
    ) {
        self.summaryText = summaryText
        self.sourceButtonTitle = sourceButtonTitle
        self.sourceHostLabel = sourceHostLabel
        self.sourceAction = sourceAction
        self.density = density
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 14) {
            Text(summaryText)
                .font(.system(size: density == .compact ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(density == .compact ? 2 : 5)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceButtonTitle, let sourceAction {
                Button(action: sourceAction) {
                    HStack(spacing: density == .compact ? 10 : 12) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: density == .compact ? 12 : 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sourceButtonTitle)
                                .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text(sourceHostLabel)
                                .font(.system(size: density == .compact ? 11 : 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: density == .compact ? 11 : 12, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, density == .compact ? 12 : 16)
                    .frame(height: density == .compact ? 48 : 54)
                    .background(
                        RoundedRectangle(cornerRadius: density == .compact ? 14 : 16, style: .continuous)
                            .fill(CooksyTheme.backgroundCalm)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .presentationCard(density: density)
    }
}

// MARK: - Ingredient List Card (flat list, no individual cards)

struct RecipeIngredientListCard: View {
    let ingredients: [RecipeIngredientPresentation]
    let currentServings: Int
    let baseServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    let editingID: UUID?
    let onTapRow: ((RecipeIngredientPresentation) -> Void)?
    let onDelete: ((RecipeIngredientPresentation) -> Void)?
    let density: RecipePresentationDensity

    // Inline edit bindings (only used when editingID != nil)
    var editAmount: Binding<String>?
    var editUnit: Binding<String>?
    var editName: Binding<String>?
    var onSaveEdit: (() -> Void)?
    var onCancelEdit: (() -> Void)?

    init(
        ingredients: [RecipeIngredientPresentation],
        currentServings: Int,
        baseServings: Int,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        editingID: UUID? = nil,
        onTapRow: ((RecipeIngredientPresentation) -> Void)? = nil,
        onDelete: ((RecipeIngredientPresentation) -> Void)? = nil,
        editAmount: Binding<String>? = nil,
        editUnit: Binding<String>? = nil,
        editName: Binding<String>? = nil,
        onSaveEdit: (() -> Void)? = nil,
        onCancelEdit: (() -> Void)? = nil,
        density: RecipePresentationDensity = .regular
    ) {
        self.ingredients = ingredients
        self.currentServings = currentServings
        self.baseServings = baseServings
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.editingID = editingID
        self.onTapRow = onTapRow
        self.onDelete = onDelete
        self.editAmount = editAmount
        self.editUnit = editUnit
        self.editName = editName
        self.onSaveEdit = onSaveEdit
        self.onCancelEdit = onCancelEdit
        self.density = density
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 16) {
            // Header
            HStack {
                RecipeSectionHeader(
                    title: "Ingrédients",
                    count: ingredients.count,
                    density: density
                )

                Spacer(minLength: 0)

                RecipeServingStepper(
                    currentServings: currentServings,
                    onDecrease: onDecrease,
                    onIncrease: onIncrease
                )
            }

            // Ingredient rows
            if !ingredients.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        if editingID == ingredient.id,
                           let editAmount, let editUnit, let editName,
                           let onSaveEdit, let onCancelEdit {
                            InlineIngredientEditRow(
                                amount: editAmount,
                                unit: editUnit,
                                name: editName,
                                onSave: onSaveEdit,
                                onCancel: onCancelEdit,
                                density: density
                            )
                        } else {
                            let display = ingredient.normalizedDisplay

                            IngredientFlatRow(
                                ingredientName: ingredient.name,
                                quantityColumn: display.quantityColumn,
                                nameColumn: display.nameColumn,
                                density: density
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onTapRow?(ingredient) }
                        }

                        if index < ingredients.count - 1 {
                            Divider()
                                .overlay(CooksyTheme.dividerSubtle)
                        }
                    }
                }
            }
        }
        .presentationCard(density: density)
    }

}

// MARK: - Flat Ingredient Row

private struct IngredientFlatRow: View {
    let ingredientName: String
    let quantityColumn: String
    let nameColumn: String
    let density: RecipePresentationDensity

    private var iconSize: CGFloat { density == .compact ? 24 : 28 }
    private var quantityWidth: CGFloat { density == .compact ? 72 : 86 }

    var body: some View {
        HStack(alignment: .center, spacing: density == .compact ? 10 : 14) {
            IngredientLocalIcon(ingredientName: ingredientName, size: iconSize)

            Text(quantityColumn)
                .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.accentWarm)
                .frame(width: quantityWidth, alignment: .trailing)
                .lineLimit(1)

            Text(nameColumn)
                .font(.system(size: density == .compact ? 14 : 15, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, density == .compact ? 10 : 13)
        .padding(.horizontal, density == .compact ? 4 : 8)
    }
}

// MARK: - Inline Ingredient Edit Row

private struct InlineIngredientEditRow: View {
    @Binding var amount: String
    @Binding var unit: String
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let density: RecipePresentationDensity

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Qté", text: $amount)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CooksyTheme.backgroundCalm))

                TextField("Unité", text: $unit)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .frame(width: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CooksyTheme.backgroundCalm))

                TextField("Ingrédient", text: $name)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CooksyTheme.backgroundCalm))
            }

            HStack(spacing: 12) {
                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CooksyTheme.backgroundCalm))
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CooksyTheme.accentWarm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, density == .compact ? 4 : 8)
    }
}

// MARK: - Step List Card

struct RecipeStepListCard: View {
    let steps: [RecipeStep]
    let onCookStepByStep: () -> Void
    let editingID: UUID?
    let onTapRow: ((RecipeStep) -> Void)?
    let onDelete: ((RecipeStep) -> Void)?
    let editStepDetail: Binding<String>?
    let onSaveEdit: (() -> Void)?
    let onCancelEdit: (() -> Void)?
    let density: RecipePresentationDensity

    init(
        steps: [RecipeStep],
        onCookStepByStep: @escaping () -> Void,
        editingID: UUID? = nil,
        onTapRow: ((RecipeStep) -> Void)? = nil,
        onDelete: ((RecipeStep) -> Void)? = nil,
        editStepDetail: Binding<String>? = nil,
        onSaveEdit: (() -> Void)? = nil,
        onCancelEdit: (() -> Void)? = nil,
        density: RecipePresentationDensity = .regular
    ) {
        self.steps = steps
        self.onCookStepByStep = onCookStepByStep
        self.editingID = editingID
        self.onTapRow = onTapRow
        self.onDelete = onDelete
        self.editStepDetail = editStepDetail
        self.onSaveEdit = onSaveEdit
        self.onCancelEdit = onCancelEdit
        self.density = density
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 10 : 16) {
            HStack {
                RecipeSectionHeader(
                    title: "Étapes",
                    count: steps.count,
                    density: density
                )
                Spacer(minLength: 0)
            }

            // Step-by-step button
            if !steps.isEmpty {
                Button(action: onCookStepByStep) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: density == .compact ? 12 : 13, weight: .bold))
                            .foregroundStyle(CooksyTheme.accentWarm)

                        Text("Cuisiner pas à pas")
                            .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .padding(.horizontal, density == .compact ? 12 : 16)
                    .frame(height: density == .compact ? 42 : 48)
                    .background(
                        RoundedRectangle(cornerRadius: density == .compact ? 12 : 14, style: .continuous)
                            .fill(CooksyTheme.backgroundCalm)
                    )
                }
                .buttonStyle(.plain)
            }

            // Steps
            if !steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let previousTitle = index > 0 ? steps[index - 1].title : nil
                        let isNewSection = step.title != nil
                            && !step.title!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && step.title != previousTitle

                        if isNewSection {
                            if index > 0 {
                                Divider()
                                    .overlay(CooksyTheme.dividerSubtle)
                                    .padding(.vertical, density == .compact ? 4 : 6)
                            }

                            Text(step.title!)
                                .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.accentWarm)
                                .padding(.horizontal, density == .compact ? 4 : 8)
                                .padding(.top, index > 0 ? (density == .compact ? 6 : 10) : 0)
                                .padding(.bottom, density == .compact ? 2 : 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if editingID == step.id,
                           let editStepDetail, let onSaveEdit, let onCancelEdit {
                            InlineStepEditRow(
                                index: index + 1,
                                detail: editStepDetail,
                                onSave: onSaveEdit,
                                onCancel: onCancelEdit,
                                density: density
                            )
                        } else {
                            StepFlatRow(
                                index: index + 1,
                                step: step,
                                density: density
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onTapRow?(step) }
                        }

                        if index < steps.count - 1 && !isNewSection {
                            Divider()
                                .overlay(CooksyTheme.dividerSubtle)
                        }
                    }
                }
            }
        }
        .presentationCard(density: density)
    }
}

// MARK: - Flat Step Row

private struct StepFlatRow: View {
    let index: Int
    let step: RecipeStep
    let density: RecipePresentationDensity

    var body: some View {
        HStack(alignment: .top, spacing: density == .compact ? 10 : 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentWarm)
                    .frame(width: density == .compact ? 22 : 26, height: density == .compact ? 22 : 26)

                Text("\(index)")
                    .font(.system(size: density == .compact ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(StepIngredientHighlighter.highlighted(step.detail, ingredientRefs: step.ingredientRefs))
                    .font(.system(size: density == .compact ? 14 : 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineSpacing(density == .compact ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, density == .compact ? 10 : 14)
        .padding(.horizontal, density == .compact ? 4 : 8)
    }
}

// MARK: - Inline Step Edit Row

private struct InlineStepEditRow: View {
    let index: Int
    @Binding var detail: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let density: RecipePresentationDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.accentWarm)
                        .frame(width: 26, height: 26)

                    Text("\(index)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)

                TextEditor(text: $detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CooksyTheme.backgroundCalm))
            }

            HStack(spacing: 12) {
                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CooksyTheme.backgroundCalm))
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CooksyTheme.accentWarm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, density == .compact ? 4 : 8)
    }
}

// MARK: - Nutrition Card

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
            HStack {
                RecipeSectionHeader(title: "Nutrition", count: nil, density: density)
                Spacer(minLength: 0)
                RecipeServingStepper(
                    currentServings: currentServings,
                    onDecrease: onDecrease,
                    onIncrease: onIncrease
                )
            }

            if let nutrition {
                VStack(spacing: 0) {
                    NutritionRow(
                        label: "Calories",
                        value: nutrition.caloriesText,
                        tint: CooksyTheme.accentWarm,
                        fraction: 1.0,
                        density: density
                    )
                    Divider().overlay(CooksyTheme.dividerSubtle)
                    NutritionRow(
                        label: "Protéines",
                        value: nutrition.proteinText,
                        tint: CooksyTheme.ctaOrange,
                        fraction: macroFraction(nutrition.protein, total: macroTotal(nutrition)),
                        density: density
                    )
                    Divider().overlay(CooksyTheme.dividerSubtle)
                    NutritionRow(
                        label: "Glucides",
                        value: nutrition.carbsText,
                        tint: CooksyTheme.sparkleYellow,
                        fraction: macroFraction(nutrition.carbs, total: macroTotal(nutrition)),
                        density: density
                    )
                    Divider().overlay(CooksyTheme.dividerSubtle)
                    NutritionRow(
                        label: "Lipides",
                        value: nutrition.fatText,
                        tint: CooksyTheme.secondaryAccent,
                        fraction: macroFraction(nutrition.fat, total: macroTotal(nutrition)),
                        density: density
                    )
                }

                if isEstimated {
                    Text("Valeurs estimées")
                        .font(.system(size: density == .compact ? 10 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .padding(.top, 2)
                }
            }
        }
        .presentationCard(density: density)
    }

    private func macroTotal(_ n: RecipeNutritionDisplay) -> Double {
        max(n.protein + n.carbs + n.fat, 1)
    }

    private func macroFraction(_ value: Double, total: Double) -> Double {
        max(value, 0) / total
    }
}

// MARK: - Nutrition Row

private struct NutritionRow: View {
    let label: String
    let value: String
    let tint: Color
    let fraction: Double
    let density: RecipePresentationDensity

    var body: some View {
        HStack(spacing: density == .compact ? 10 : 14) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: density == .compact ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: density == .compact ? 72 : 80, alignment: .leading)

            // Subtle bar
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint)
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
            }
            .frame(height: 6)

            Text(value)
                .font(.system(size: density == .compact ? 13 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: density == .compact ? 64 : 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, density == .compact ? 10 : 13)
        .padding(.horizontal, density == .compact ? 4 : 8)
    }
}

// MARK: - Shared Sub-components

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

struct RecipeSectionHeader: View {
    let title: String
    let count: Int?
    let density: RecipePresentationDensity

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: density == .compact ? 16 : 18, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            if let count {
                Text("\(count)")
                    .font(.system(size: density == .compact ? 11 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.accentWarm.opacity(0.12))
                    )
            }
        }
    }
}

private struct RecipeServingStepper: View {
    let currentServings: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Text(RecipePresentationFormatter.selectedServingsLabel(for: currentServings))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(minWidth: 72)

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.backgroundCalm)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Hero Placeholder

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

// MARK: - Card Modifier

extension View {
    func presentationCard(density: RecipePresentationDensity) -> some View {
        self
            .padding(density == .compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: density == .compact ? 18 : 22, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: density == .compact ? 18 : 22, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Ingredient Local Icon

struct IngredientLocalIcon: View {
    let ingredientName: String
    var size: CGFloat = 28

    var body: some View {
        Image(resolvedAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private var resolvedAssetName: String {
        IngredientVisualCatalog.assetName(for: ingredientName) ?? "IngredientIconGeneric"
    }
}
