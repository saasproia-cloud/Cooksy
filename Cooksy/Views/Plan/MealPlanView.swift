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
                VStack(alignment: .leading, spacing: 22) {
                    journalHeader
                    weekNavigation
                    weekStripSection
                    todayHeadline
                    mealSections
                    weekStatsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 150)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $pickerContext) { context in
            MealPlanRecipePickerSheet(
                title: context.dayTitle,
                mealTitle: frenchMealTitle(for: context.mealKind),
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
        .confirmationDialog("Choisis un repas à remplacer", isPresented: $showsReplacementDialog, titleVisibility: .visible) {
            ForEach(MealPlanEntry.MealKind.allCases, id: \.self) { kind in
                Button(frenchMealTitle(for: kind)) {
                    openPicker(for: kind)
                }
            }

            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var journalHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Semaine du")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Text(Self.weekStartDisplay.string(from: viewModel.currentWeekStart).lowercased())
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Rectangle()
                        .fill(CooksyTheme.ctaOrange.opacity(0.55))
                        .frame(width: 22, height: 2)

                    Text(Self.weekEndDisplay.string(from: weekEndDate).lowercased())
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Button(action: handleQuickAdd) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: CooksyTheme.ctaOrange.opacity(0.28), radius: 10, y: 6)

                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var weekNavigation: some View {
        HStack(spacing: 14) {
            weekArrowButton(systemImage: "chevron.left", action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.showPreviousWeek()
                }
            })

            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.8))
                .frame(height: 1)

            Text(weekNavigationLabel)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.82))

            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.8))
                .frame(height: 1)

            weekArrowButton(systemImage: "chevron.right", action: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.showNextWeek()
                }
            })
        }
    }

    private func weekArrowButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white)
                )
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var weekStripSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.weekDays.enumerated()), id: \.element.id) { index, day in
                    Button(action: {
                        OnboardingHaptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.selectDay(day.date)
                        }
                    }) {
                        PlannerDayTile(day: day, accentIndex: index)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width <= -50 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            viewModel.showNextWeek()
                        }
                    } else if value.translation.width >= 50 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            viewModel.showPreviousWeek()
                        }
                    }
                }
        )
    }

    private var todayHeadline: some View {
        Text(selectedDayFullLabel)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.primaryText)
    }

    // MARK: - Meal sections

    private var mealSections: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.selectedDayMeals) { meal in
                Button(action: { openPicker(for: meal.kind) }) {
                    PlannerMealHeroCard(
                        meal: meal,
                        mealTitle: frenchMealTitle(for: meal.kind).uppercased()
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if meal.hasRecipe {
                        Button(role: .destructive) {
                            viewModel.removeRecipe(from: viewModel.selectedDate, meal: meal.kind)
                        } label: {
                            Label("Retirer de ce repas", systemImage: "trash")
                        }

                        Button {
                            openPicker(for: meal.kind)
                        } label: {
                            Label("Changer de recette", systemImage: "arrow.triangle.swap")
                        }
                    } else {
                        Button {
                            openPicker(for: meal.kind)
                        } label: {
                            Label("Ajouter une recette", systemImage: "plus.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Week stats

    private var weekStatsCard: some View {
        let overview = viewModel.weeklyOverview

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrange)
                Text("Bilan de la semaine")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.82))
                Spacer()
            }
            .padding(.bottom, 14)

            weekStatRow(label: "Repas planifiés", value: "\(overview.plannedMeals)")

            statsDivider

            weekStatRow(label: "Repas cuisinés", value: "\(overview.completedMeals)")

            statsDivider

            weekStatRow(
                label: "Calories moyennes",
                value: overview.averageDailyCalories > 0 ? "~\(overview.averageDailyCalories) kcal" : "—"
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }

    private func weekStatRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
        }
        .padding(.vertical, 12)
    }

    private var statsDivider: some View {
        Rectangle()
            .fill(CooksyTheme.stroke.opacity(0.75))
            .frame(height: 1)
    }

    // MARK: - Actions

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
            dayTitle: selectedDayFullLabel,
            mealKind: kind
        )
    }

    // MARK: - Derived labels

    private var weekEndDate: Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: viewModel.currentWeekStart)
            ?? viewModel.currentWeekStart
    }

    private var weekNavigationLabel: String {
        let now = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let start = Calendar(identifier: .gregorian).startOfDay(for: viewModel.currentWeekStart)
        let components = Calendar(identifier: .gregorian).dateComponents([.day], from: now, to: start)
        guard let days = components.day else { return "cette semaine" }

        switch days {
        case let d where d <= -7:
            return "semaine passée"
        case -6...(-1):
            return "cette semaine"
        case 0:
            return "cette semaine"
        case 1...7:
            return "semaine prochaine"
        default:
            return "à venir"
        }
    }

    private var selectedDayFullLabel: String {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: viewModel.selectedDate)
        let today = calendar.startOfDay(for: .now)
        let formatted = Self.selectedDayFull.string(from: day)

        if calendar.isDate(day, inSameDayAs: today) {
            return "Aujourd'hui, \(formatted)"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Demain, \(formatted)"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Hier, \(formatted)"
        }

        return formatted.capitalizedFrenchHeadline
    }

    private func frenchMealTitle(for kind: MealPlanEntry.MealKind) -> String {
        switch kind {
        case .breakfast: return "Petit-déjeuner"
        case .lunch:     return "Déjeuner"
        case .dinner:    return "Dîner"
        }
    }

    // MARK: - Formatters

    private static let weekStartDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let weekEndDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let selectedDayFull: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

// MARK: - Helpers

private extension String {
    /// Capitalize only the first letter so "mardi 22 avril" → "Mardi 22 avril".
    var capitalizedFrenchHeadline: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
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

// MARK: - Day tile

private struct PlannerDayTile: View {
    let day: MealPlanViewModel.DayTile
    let accentIndex: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(frenchWeekday)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(day.isSelected ? Color.white.opacity(0.95) : CooksyTheme.secondaryText)

            Text(day.dayNumberText)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(day.isSelected ? .white : CooksyTheme.primaryText)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(width: 68, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(day.isSelected ? CooksyTheme.ctaOrangeDark.opacity(0.35) : CooksyTheme.stroke, lineWidth: day.isSelected ? 2 : 1)
        )
        .shadow(color: day.isSelected ? CooksyTheme.ctaOrange.opacity(0.22) : Color.black.opacity(0.04), radius: day.isSelected ? 12 : 4, y: day.isSelected ? 6 : 2)
        .scaleEffect(day.isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: day.isSelected)
    }

    private var backgroundStyle: AnyShapeStyle {
        if day.isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white)
    }

    private var gradientColors: [Color] {
        // Pick a warm pairing that rotates across the week for a subtle mood-board feel.
        let palettes: [[Color]] = [
            [Color(hex: 0xEC8555), Color(hex: 0xC05F2F)],
            [Color(hex: 0xE17160), Color(hex: 0xB84A3B)],
            [Color(hex: 0xD98C5F), Color(hex: 0xB56A3C)],
            [Color(hex: 0xE79D5E), Color(hex: 0xB86B2F)],
            [Color(hex: 0xE98B4A), Color(hex: 0xB55B28)],
            [Color(hex: 0xDB7B52), Color(hex: 0xA94A24)],
            [Color(hex: 0xE7A26A), Color(hex: 0xB87333)]
        ]
        return palettes[accentIndex % palettes.count]
    }

    private func dotColor(for index: Int) -> Color {
        let filled = index < day.progressDots
        if day.isSelected {
            return filled ? Color.white.opacity(0.95) : Color.white.opacity(0.32)
        }
        return filled ? CooksyTheme.ctaOrange : CooksyTheme.stroke.opacity(0.9)
    }

    private var frenchWeekday: String {
        PlannerDayTile.weekdayFR.string(from: day.date).uppercased()
    }

    private static let weekdayFR: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

// MARK: - Meal hero card

private struct PlannerMealHeroCard: View {
    let meal: MealPlanViewModel.MealSlot
    let mealTitle: String

    var body: some View {
        Group {
            if let recipe = meal.recipe {
                filledCard(recipe: recipe)
            } else {
                emptyCard
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
    }

    private func filledCard(recipe: Recipe) -> some View {
        ZStack(alignment: .topLeading) {
            PlannerHeroBackground(recipe: recipe)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(mealTitle)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.25))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    Spacer()

                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)

                    HStack(spacing: 12) {
                        if let minutes = recipe.plannerTotalMinutes {
                            PlannerHeroMeta(icon: "clock.fill", text: "\(minutes) min")
                        }

                        if let caloriesLabel = plannerCaloriesLabel(for: recipe) {
                            PlannerHeroMeta(icon: "flame.fill", text: caloriesLabel)
                        }

                        PlannerHeroMeta(icon: "bolt.fill", text: RecipePresentationFormatter.difficultyLabel(for: recipe))
                    }
                }
            }
            .padding(18)
        }
    }

    private var emptyCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(CooksyTheme.ctaOrange.opacity(0.4))

            VStack(spacing: 14) {
                HStack {
                    Text(mealTitle)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.primaryAccentSoft)
                        )
                    Spacer()
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryAccentSoft)
                            .frame(width: 54, height: 54)
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }

                    Text(emptyPrompt)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Appuie pour choisir une recette")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private var emptyPrompt: String {
        switch meal.kind {
        case .breakfast: return "Ajoute ton petit-déjeuner"
        case .lunch:     return "Ajoute ton déjeuner"
        case .dinner:    return "Ajoute ton dîner"
        }
    }
}

private struct PlannerHeroBackground: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        CooksyTheme.recipeGradient(for: recipe.heroStyle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlannerHeroMeta: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color.white.opacity(0.92))
    }
}

private func plannerCaloriesLabel(for recipe: Recipe) -> String? {
    guard let calories = RecipePresentationFormatter.parseNumber(from: recipe.nutrition?.calories),
          calories > 0 else {
        return nil
    }

    return "\(Int(calories.rounded())) kcal"
}

private extension Recipe {
    var plannerTotalMinutes: Int? {
        let prep = details.prepTimeMinutes ?? 0
        let cook = details.cookTimeMinutes ?? 0
        let total = prep + cook
        return total > 0 ? total : nil
    }
}

// MARK: - Recipe picker sheet (kept, rebranded in French)

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
                        Text("Aucune recette")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Importe ou crée une recette, puis reviens ici pour la planifier.")
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
                                        Text("Retirer ce repas")
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
        let calories = recipe.nutrition?.calories ?? "Calories à estimer"
        if let totalMinutes = recipe.plannerTotalMinutes {
            return "\(calories) • \(totalMinutes) min"
        }
        return calories
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
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(CooksyTheme.recipeGradient(for: recipe.heroStyle))
    }
}
