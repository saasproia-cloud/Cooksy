import SwiftUI

struct MealPlanView: View {
    @StateObject private var viewModel: MealPlanViewModel
    @State private var pickerContext: MealPickerContext?

    init(store: RecipeStore) {
        _viewModel = StateObject(wrappedValue: MealPlanViewModel(store: store))
    }

    var body: some View {
        ZStack {
            PlanningBackground()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    topHeader
                    planningCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 156)
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

    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan.")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Button(action: { viewModel.showCurrentWeek() }) {
                    Text("Aujourd’hui")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Text("Organisez les repas de la semaine sans décalage ni zones coupées.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
        }
    }

    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            planningHeader
            weekStrip
            objectiveCard
            selectedDayHeader
            mealSections
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xF8F4ED), Color(hex: 0xF2EDE4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 26, y: 16)
    }

    private var planningHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Planning")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x413731))

                Text(viewModel.currentMonthLabel)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA39889))

                Text(viewModel.weekCaptionLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xB0A491))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: { viewModel.showPreviousWeek() }) {
                    PlanningActionButton(systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showCurrentWeek() }) {
                    PlanningActionButton(systemImage: "calendar")
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showNextWeek() }) {
                    PlanningActionButton(systemImage: "chevron.right")
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Vider la semaine", role: .destructive) {
                        viewModel.clearCurrentWeek()
                    }
                } label: {
                    PlanningActionButton(systemImage: "ellipsis")
                }
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 8) {
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
                Circle()
                    .fill(Color(hex: 0x9CAA83))
                    .frame(width: 50, height: 50)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OBJECTIF DU JOUR")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(Color(hex: 0xA2A98C))

                Text(summary.label)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x463D35))

                Text(summary.detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8C8478))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(summary.caloriesText)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0x93AD7F))

                    Text("KCAL")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: 0xBFB7AB))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(hex: 0xDCD5CA))

                        Capsule()
                            .fill(Color(hex: 0x93AD7F))
                            .frame(width: max(18, proxy.size.width * summary.progress))
                    }
                }
                .frame(width: 104, height: 7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: 0xEEE9DE))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0xDDD7CA), lineWidth: 1)
        )
    }

    private var selectedDayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Repas du jour")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color(hex: 0xA79A88))

            Text(viewModel.selectedDayTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x413731))
        }
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

private struct PlanningBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x1F1715), Color(hex: 0x140F0E)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ForEach(0..<14, id: \.self) { _ in
                        Circle()
                            .fill(Color(hex: 0x84695A).opacity(0.34))
                            .frame(width: 3, height: 3)
                    }
                }
                .padding(.top, 18)

                Spacer()
            }
        }
    }
}

private struct PlanningActionButton: View {
    let systemImage: String

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.96))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x5D5349))
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
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
                .font(.system(size: 26, weight: .heavy, design: .rounded))
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 106)
        .background(tileBackground)
        .overlay(tileBorder)
        .shadow(color: shadowColor, radius: 10, y: 6)
    }

    private var tileBackground: some ShapeStyle {
        if day.isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: 0xE98063), Color(hex: 0xD96A50)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        if day.isToday {
            return AnyShapeStyle(Color(hex: 0xFFF8EF))
        }

        return AnyShapeStyle(Color.white.opacity(0.92))
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(day.isSelected ? Color.clear : borderColor, lineWidth: 1.2)
    }

    private var labelColor: Color {
        day.isSelected ? Color.white.opacity(0.84) : Color(hex: 0xB3A99B)
    }

    private var numberColor: Color {
        day.isSelected ? .white : Color(hex: 0x574E45)
    }

    private var markerBackgroundColor: Color {
        day.isSelected ? Color.white.opacity(0.24) : (day.hasRecipes ? Color(hex: 0xE37B60) : Color(hex: 0xE7DED3))
    }

    private var markerTextColor: Color {
        day.isSelected ? .white : .white
    }

    private var borderColor: Color {
        day.isToday ? Color(hex: 0xE9C8BA) : Color(hex: 0xE1D9CE)
    }

    private var shadowColor: Color {
        day.isSelected ? Color(hex: 0xD8664D, opacity: 0.24) : Color.black.opacity(0.05)
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
                    Circle()
                        .fill(meal.hasRecipe ? Color(hex: 0xE97D61).opacity(0.16) : Color(hex: 0xEEE5D8))
                        .frame(width: 34, height: 34)

                    Image(systemName: meal.iconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(meal.hasRecipe ? Color(hex: 0xDE6F56) : Color(hex: 0xA49682))
                }

                Text(meal.title.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(Color(hex: 0xA08F7D))

                Spacer(minLength: 0)

                Text(meal.timeLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(meal.hasRecipe ? Color(hex: 0xD9755C) : Color(hex: 0xAEA294))
                    .padding(.horizontal, meal.hasRecipe ? 10 : 0)
                    .frame(height: meal.hasRecipe ? 26 : nil)
                    .background(
                        Capsule(style: .continuous)
                            .fill(meal.hasRecipe ? Color(hex: 0xF7DDD5) : .clear)
                    )
            }

            if let recipe = meal.recipe {
                MealPlanRecipeCard(recipe: recipe)

                HStack(spacing: 10) {
                    Button(action: onSelect) {
                        Text("Changer")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x534A42))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color(hex: 0xDDD3C6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: onRemove) {
                        Text("Retirer")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0xCC6A54))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(hex: 0xF8E5DE))
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
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0xF6F1E8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(hex: 0xE3DACE), lineWidth: 1)
        )
    }
}

private struct MealPlanRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            MealPlanRecipeThumbnail(recipe: recipe, size: 70, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x463D35))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let calories = recipe.nutrition?.calories, !calories.isEmpty {
                        Label("\(calories) kcal", systemImage: "flame.fill")
                            .foregroundStyle(Color(hex: 0x8FA67B))
                    }

                    if let minutes = recipe.totalMinutes {
                        Text("•")
                            .foregroundStyle(Color(hex: 0xC7BFB1))

                        Label("\(minutes) min", systemImage: "clock.fill")
                            .foregroundStyle(Color(hex: 0x9B9388))
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xE5DDD1), lineWidth: 1)
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
        switch recipe.heroStyle {
        case .warmCocoa:
            return LinearGradient(colors: [Color(hex: 0x5B2508), Color(hex: 0xE8A24C)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .citrus:
            return LinearGradient(colors: [Color(hex: 0xE28C20), Color(hex: 0xF8D35B)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:
            return LinearGradient(colors: [Color(hex: 0x497FC4), Color(hex: 0x88B6F6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .meadow:
            return LinearGradient(colors: [Color(hex: 0x53753E), Color(hex: 0x97BB67)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
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
                .fill(Color(hex: 0xF3ECDE))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0xA99986))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Ajouter au planning")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6E655B))

                Text("Choisissez une recette pour ce créneau.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA59A8C))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                .foregroundStyle(Color(hex: 0xDDD1C1))
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
                Color(hex: 0xF8F4ED)
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
                                    .foregroundStyle(Color(hex: 0xC95D48))
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .fill(Color(hex: 0xFCE8E1))
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
