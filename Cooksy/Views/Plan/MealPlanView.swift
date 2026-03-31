import SwiftUI

struct MealPlanView: View {
    @StateObject private var viewModel: MealPlanViewModel
    @State private var pickerContext: MealPickerContext?
    @State private var showsReplacementDialog = false

    init(store: RecipeStore) {
        _viewModel = StateObject(wrappedValue: MealPlanViewModel(store: store))
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    weekStripSection
                    dailyProgressCard
                    mealSections
                    weeklyOverviewCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 150)
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
        .confirmationDialog("Choose a meal to replace", isPresented: $showsReplacementDialog, titleVisibility: .visible) {
            ForEach(MealPlanEntry.MealKind.allCases, id: \.self) { kind in
                Button(kind.title) {
                    openPicker(for: kind)
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Week")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Text("Meal Planner")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(viewModel.weekLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Button(action: handleQuickAdd) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: CooksyTheme.shadow.opacity(0.12), radius: 10, y: 6)

                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var weekStripSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.weekDays) { day in
                    Button(action: { viewModel.selectDay(day.date) }) {
                        PlannerDayCard(day: day)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width <= -40 {
                        viewModel.showNextWeek()
                    } else if value.translation.width >= 40 {
                        viewModel.showPreviousWeek()
                    }
                }
        )
    }

    private var dailyProgressCard: some View {
        let summary = viewModel.dailySummary

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Progress")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)

                    Text(summary.progressText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Total calories")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)

                    Text("\(summary.totalCaloriesText) kcal")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrange)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CooksyTheme.stroke.opacity(0.9))

                    Capsule()
                        .fill(CooksyTheme.ctaOrange)
                        .frame(width: proxy.size.width * summary.progress)
                }
            }
            .frame(height: 7)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var mealSections: some View {
        VStack(spacing: 14) {
            ForEach(viewModel.selectedDayMeals) { meal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(meal.sectionTitle)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.86))

                    Button(action: { openPicker(for: meal.kind) }) {
                        PlannerMealCard(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weeklyOverviewCard: some View {
        let overview = viewModel.weeklyOverview

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrange)

                Text("Weekly Overview")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            HStack(spacing: 10) {
                PlannerOverviewMetric(title: "Planned", value: "\(overview.plannedMeals)")
                PlannerOverviewMetric(title: "Completed", value: "\(overview.completedMeals)")
                PlannerOverviewMetric(title: "Calories avg", value: "\(overview.averageDailyCalories)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func handleQuickAdd() {
        if let kind = viewModel.firstEmptyMealKind {
            openPicker(for: kind)
        } else {
            showsReplacementDialog = true
        }
    }

    private func openPicker(for kind: MealPlanEntry.MealKind) {
        pickerContext = MealPickerContext(
            date: viewModel.selectedDate,
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

private struct PlannerDayCard: View {
    let day: MealPlanViewModel.DayTile

    var body: some View {
        VStack(spacing: 8) {
            Text(day.weekdayTitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(day.isSelected ? Color.white.opacity(0.9) : CooksyTheme.secondaryText)

            Text(day.dayNumberText)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(day.isSelected ? .white : CooksyTheme.primaryText)

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(progressColor(for: index))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(width: 58, height: 82)
        .background(backgroundStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(day.isSelected ? Color.clear : CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var backgroundStyle: some ShapeStyle {
        if day.isSelected {
            return AnyShapeStyle(CooksyTheme.accentGradient)
        }

        return AnyShapeStyle(Color.white.opacity(0.98))
    }

    private func progressColor(for index: Int) -> Color {
        if day.isSelected {
            return index < day.progressDots ? Color.white.opacity(0.92) : Color.white.opacity(0.28)
        }

        return index < day.progressDots ? CooksyTheme.ctaOrange : CooksyTheme.stroke.opacity(0.92)
    }
}

private struct PlannerMealCard: View {
    let meal: MealPlanViewModel.MealSlot

    var body: some View {
        HStack(spacing: 12) {
            if let recipe = meal.recipe {
                PlannerRecipeThumbnail(recipe: recipe)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        if let caloriesLabel = caloriesLabel(for: recipe) {
                            PlannerMetaLabel(systemImage: "flame.fill", text: caloriesLabel)
                        }

                        if let minutes = recipe.totalMinutes {
                            PlannerMetaLabel(systemImage: "clock.fill", text: "\(minutes)m")
                        }
                    }
                }
            } else {
                Circle()
                    .fill(CooksyTheme.blush.opacity(0.7))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a recipe")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("Plan \(meal.title.lowercased()) for this day.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var cardBackground: some ShapeStyle {
        if meal.recipe != nil, meal.kind == .breakfast {
            return AnyShapeStyle(CooksyTheme.blush.opacity(0.62))
        }

        return AnyShapeStyle(Color.white.opacity(0.98))
    }

    private func caloriesLabel(for recipe: Recipe) -> String? {
        guard let calories = RecipePresentationFormatter.parseNumber(from: recipe.nutrition?.calories),
              calories > 0 else {
            return nil
        }

        return "\(Int(calories.rounded())) kcal"
    }
}

private struct PlannerRecipeThumbnail: View {
    let recipe: Recipe

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
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(CooksyTheme.recipeGradient(for: recipe.heroStyle))
    }
}

private struct PlannerMetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(CooksyTheme.secondaryText)
    }
}

private struct PlannerOverviewMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
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
                        Text("No recipes yet")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Import or create a recipe first, then come back to plan it here.")
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
                                        Text("Remove this meal")
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
                    Button("Close") {
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
                PlannerRecipeThumbnail(recipe: recipe)

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
        let calories = recipe.nutrition?.calories ?? "Calories TBD"
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
            return "Breakfast"
        case .lunch:
            return "Lunch"
        case .dinner:
            return "Dinner"
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
