import SwiftUI

struct MealPlanView: View {
    @StateObject private var viewModel: MealPlanViewModel
    @State private var pickerContext: MealPickerContext?

    init(store: RecipeStore) {
        _viewModel = StateObject(wrappedValue: MealPlanViewModel(store: store))
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    planningOverviewCard
                    selectedDayHeader
                    mealSections
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 146)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $pickerContext) { context in
            MealPlanRecipePickerSheet(
                title: context.dayTitle,
                mealTitle: context.mealKind.title,
                recipes: viewModel.recipes,
                selectedRecipeID: viewModel.recipe(for: context.date, meal: context.mealKind)?.id,
                onSelect: { recipe in
                    viewModel.addRecipe(recipe, to: context.date, meal: context.mealKind)
                },
                onRemoveSelection: {
                    viewModel.removeRecipe(from: context.date, meal: context.mealKind)
                }
            )
        }
    }

    private var planningOverviewCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            planningHeader
            weekStrip
            objectiveCard
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.shadow, radius: 16, y: 8)
    }

    private var planningHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PLAN DE REPAS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)

                    Text(viewModel.currentMonthLabel)
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Text(viewModel.weekCaptionLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                planningMenuButton
            }

            HStack(spacing: 10) {
                Button(action: { viewModel.showPreviousWeek() }) {
                    PlanningActionButton(systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showCurrentWeek() }) {
                    PlanningActionButton(
                        systemImage: "calendar",
                        label: "Cette semaine",
                        isActive: viewModel.isViewingCurrentWeek
                    )
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showNextWeek() }) {
                    PlanningActionButton(systemImage: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planningMenuButton: some View {
        Menu {
            Button("Revenir à cette semaine") {
                viewModel.showCurrentWeek()
            }

            Button("Vider la semaine", role: .destructive) {
                viewModel.clearCurrentWeek()
            }
        } label: {
            PlanningActionButton(systemImage: "ellipsis")
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.weekPlans) { day in
                Button(action: { viewModel.selectDay(day.date) }) {
                    PlanningDayTile(day: day)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var objectiveCard: some View {
        let summary = viewModel.weekSummary

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CooksyTheme.brandBlue.opacity(0.16))
                    .frame(width: 48, height: 48)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CooksyTheme.brandBlueDark)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SYNTHESE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(CooksyTheme.brandBlueDark.opacity(0.82))

                Text(summary.label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(summary.detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(summary.caloriesText)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrange)

                    Text("KCAL")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CooksyTheme.stroke.opacity(0.85))

                        Capsule()
                            .fill(CooksyTheme.ctaOrange)
                            .frame(width: summary.progress > 0 ? max(18, proxy.size.width * summary.progress) : 0)
                    }
                }
                .frame(width: 104, height: 7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.warmCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var selectedDayHeader: some View {
        let plannedMealsCount = viewModel.selectedDayMeals.filter(\.hasRecipe).count

        return VStack(alignment: .leading, spacing: 4) {
            Text("Repas du jour")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(viewModel.selectedDayTitle)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("\(plannedMealsCount)/3 créneaux remplis")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.brandBlueDark)
        }
        .padding(.horizontal, 4)
    }

    private var mealSections: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.selectedDayMeals) { meal in
                MealPlanMealSection(
                    meal: meal,
                    onSelect: { openPicker(for: meal.kind) },
                    onRemove: { viewModel.removeRecipe(from: viewModel.selectedDayPlan.date, meal: meal.kind) }
                )
            }
        }
    }

    private func openPicker(for kind: MealPlanEntry.MealKind) {
        pickerContext = MealPickerContext(
            date: viewModel.selectedDayPlan.date,
            dayTitle: viewModel.selectedDayTitle,
            mealKind: kind
        )
    }
}

private struct MealPickerContext: Identifiable {
    let date: Date
    let dayTitle: String
    let mealKind: MealPlanEntry.MealKind

    var id: String {
        "\(date.timeIntervalSince1970)-\(mealKind.rawValue)"
    }
}

private struct PlanningActionButton: View {
    let systemImage: String
    var label: String? = nil
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))

            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .foregroundStyle(isActive ? CooksyTheme.ctaOrange : CooksyTheme.primaryText)
        .padding(.horizontal, label == nil ? 0 : 12)
        .frame(minWidth: label == nil ? 42 : 96, minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? CooksyTheme.blush.opacity(0.82) : CooksyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? CooksyTheme.ctaOrange.opacity(0.32) : CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct PlanningDayTile: View {
    let day: MealPlanViewModel.DayPlan

    var body: some View {
        VStack(spacing: 8) {
            Text(day.shortWeekdayTitle.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(day.dayNumberText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(numberColor)

            Spacer(minLength: 0)

            if day.completedMealsCount > 0 {
                Text("\(day.completedMealsCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(markerTextColor)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(markerBackgroundColor)
                    )
            } else {
                Circle()
                    .fill(markerBackgroundColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(tileBackground)
        .overlay(tileBorder)
        .shadow(color: shadowColor, radius: 6, y: 3)
    }

    private var tileBackground: some ShapeStyle {
        if day.isSelected {
            return AnyShapeStyle(CooksyTheme.accentGradient)
        }

        if day.isToday {
            return AnyShapeStyle(CooksyTheme.softCloud)
        }

        return AnyShapeStyle(CooksyTheme.surface.opacity(0.96))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(day.isSelected ? Color.clear : borderColor, lineWidth: 1.2)
    }

    private var labelColor: Color {
        day.isSelected ? Color.white.opacity(0.84) : CooksyTheme.secondaryText
    }

    private var numberColor: Color {
        day.isSelected ? .white : CooksyTheme.primaryText
    }

    private var markerBackgroundColor: Color {
        day.isSelected ? Color.white.opacity(0.24) : (day.hasRecipes ? CooksyTheme.ctaOrange : CooksyTheme.stroke)
    }

    private var markerTextColor: Color {
        day.isSelected ? .white : .white
    }

    private var borderColor: Color {
        day.isToday ? CooksyTheme.brandBlue.opacity(0.5) : CooksyTheme.stroke
    }

    private var shadowColor: Color {
        day.isSelected ? CooksyTheme.ctaOrange.opacity(0.22) : CooksyTheme.softShadow
    }
}

private struct MealPlanMealSection: View {
    let meal: MealPlanViewModel.MealSection
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(meal.hasRecipe ? CooksyTheme.ctaOrange.opacity(0.14) : CooksyTheme.softCloud)
                        .frame(width: 32, height: 32)

                    Image(systemName: meal.iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(meal.hasRecipe ? CooksyTheme.ctaOrangeDark : CooksyTheme.brandBlueDark)
                }

                Text(meal.title.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(CooksyTheme.secondaryText)

                Spacer(minLength: 0)

                Text(meal.timeLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(meal.hasRecipe ? CooksyTheme.ctaOrangeDark : CooksyTheme.brandBlueDark)
                    .padding(.horizontal, meal.hasRecipe ? 10 : 0)
                    .frame(height: meal.hasRecipe ? 26 : nil)
                    .background(
                        Capsule(style: .continuous)
                            .fill(meal.hasRecipe ? CooksyTheme.blush.opacity(0.65) : CooksyTheme.softCloud.opacity(0.7))
                    )
            }

            if let recipe = meal.recipe {
                MealPlanRecipeCard(recipe: recipe)

                HStack(spacing: 10) {
                    Button(action: onSelect) {
                        Text("Changer")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.brandBlueDark)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.softCloud.opacity(0.8))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(CooksyTheme.brandBlue.opacity(0.38), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        Text("Retirer")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.warmCard.opacity(0.75))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(CooksyTheme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: onSelect) {
                    EmptyMealPlanCard()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 6)
    }
}

private struct MealPlanRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            MealPlanRecipeThumbnail(recipe: recipe, size: 70, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let calories = recipe.nutrition?.calories, !calories.isEmpty {
                        Label("\(calories) kcal", systemImage: "flame.fill")
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }

                    if let minutes = recipe.totalMinutes {
                        Text("•")
                            .foregroundStyle(CooksyTheme.stroke)

                        Label("\(minutes) min", systemImage: "clock.fill")
                            .foregroundStyle(CooksyTheme.brandBlueDark)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.background.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct MealPlanRecipeThumbnail: View {
    let recipe: Recipe
    var size: CGFloat = 64
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackThumbnail
                        }
                    }
                }
            } else {
                fallbackThumbnail
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackThumbnail: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(thumbnailGradient)
            .overlay {
                Image(systemName: thumbnailIcon)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }

    private var thumbnailGradient: LinearGradient {
        CooksyTheme.recipeGradient(for: recipe.heroStyle)
    }

    private var thumbnailIcon: String {
        switch recipe.heroStyle {
        case .warmCocoa:
            return "fork.knife"
        case .citrus:
            return "sun.max.fill"
        case .ocean:
            return "drop.fill"
        case .meadow:
            return "leaf.fill"
        }
    }
}

private struct EmptyMealPlanCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(CooksyTheme.ctaOrange.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Ajouter au planning")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Choisissez une recette pour ce créneau.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                .foregroundStyle(CooksyTheme.ctaOrange.opacity(0.42))
        )
    }
}

private struct MealPlanRecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let mealTitle: String
    let recipes: [Recipe]
    let selectedRecipeID: Recipe.ID?
    let onSelect: (Recipe) -> Void
    let onRemoveSelection: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CooksyTheme.ambientGradient
                    .ignoresSafeArea()

                if recipes.isEmpty {
                    VStack(spacing: 18) {
                        Text("Aucune recette enregistrée")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Ajoute d’abord des recettes dans l’onglet Recettes pour pouvoir les planifier ici.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            if selectedRecipeID != nil {
                                Button(role: .destructive) {
                                    onRemoveSelection()
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Retirer la recette de ce créneau")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                        Spacer()
                                    }
                                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .fill(CooksyTheme.blush.opacity(0.58))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(recipes) { recipe in
                                MealPlanRecipePickerRow(
                                    recipe: recipe,
                                    isSelected: selectedRecipeID == recipe.id,
                                    onTap: {
                                        onSelect(recipe)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(mealTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text(title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

private struct MealPlanRecipePickerRow: View {
    let recipe: Recipe
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                MealPlanRecipeThumbnail(recipe: recipe, size: 78, cornerRadius: 18)

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.leading)

                    Text(detailText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.brandBlueDark)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(isSelected ? CooksyTheme.ctaOrange.opacity(0.45) : Color.clear, lineWidth: 1.5)
                    )
                    .shadow(color: CooksyTheme.shadow, radius: 14, y: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailText: String {
        let calories = recipe.nutrition?.calories ?? "Calories à estimer"
        if let totalMinutes = recipe.totalMinutes {
            return "\(calories) • \(totalMinutes) min"
        }
        return calories
    }
}

private extension MealPlanEntry.MealKind {
    var title: String {
        switch self {
        case .breakfast:
            return "Petit déjeuner"
        case .lunch:
            return "Déjeuner"
        case .dinner:
            return "Dîner"
        }
    }
}

private extension Recipe {
    var totalMinutes: Int? {
        let prep = details.prepTimeMinutes ?? 0
        let cook = details.cookTimeMinutes ?? 0
        let total = prep + cook
        return total > 0 ? total : nil
    }
}
