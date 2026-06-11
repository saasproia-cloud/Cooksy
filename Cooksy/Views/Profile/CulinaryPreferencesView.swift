import SwiftUI

/// Lets the signed-in user review and edit the 10 culinary preferences they
/// captured during onboarding. Source of truth is `sessionStore.profile.onboardingAnswers`.
/// Each row pushes an edit sheet that reuses the onboarding components
/// (`BigChoiceCard`, `ChoicePill`, `LevelCard`…) for consistency.
struct CulinaryPreferencesView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var editing: EditQuestion?

    /// Local mirror of the persisted answers so the UI updates immediately;
    /// reloaded every time the profile changes.
    @State private var answers: OnboardingAnswers = .empty

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    ProfileSectionCard {
                        row(.goal, title: "Objectif principal", value: goalValue)
                        divider
                        row(.sources, title: "Sources préférées", value: sourcesValue)
                        divider
                        row(.skillLevel, title: "Niveau culinaire", value: skillValue)
                        divider
                        row(.time, title: "Temps par repas", value: timeValue)
                        divider
                        row(.frequency, title: "Fréquence", value: frequencyValue)
                    }

                    ProfileSectionCard {
                        row(.diet, title: "Régime alimentaire", value: dietValue)
                        divider
                        row(.allergies, title: "Allergies", value: allergiesValue)
                        divider
                        row(.servings, title: "Taille typique", value: servingsValue)
                        divider
                        row(.cuisines, title: "Cuisines préférées", value: cuisinesValue)
                        divider
                        row(.challenges, title: "Freins en cuisine", value: challengesValue, isLast: true)
                    }
                }
                .padding(.horizontal, Layout.horizontalPadding(for: ScreenMetrics.width))
                .padding(.top, 8)
                .padding(.bottom, Layout.bottomScrollPadding(for: ScreenMetrics.width))
                .frame(maxWidth: Layout.maxReadingWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Préférences culinaires")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: sessionStore.profile) { _, _ in reload() }
        .sheet(item: $editing) { question in
            CulinaryPreferenceEditSheet(
                question: question,
                answers: answers,
                onSave: { updated in
                    answers = updated
                    Task { await sessionStore.saveOnboardingAnswers(updated) }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ajuste tes préférences")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
            Text("Tes choix servent à personnaliser tes recommandations et la liste de courses.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Row

    private func row(
        _ question: EditQuestion,
        title: String,
        value: String,
        isLast: Bool = false
    ) -> some View {
        Button {
            editing = question
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(CooksyTheme.dividerSubtle)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    // MARK: - Loading

    private func reload() {
        answers = sessionStore.profile?.onboardingAnswers ?? .empty
    }

    // MARK: - Value summaries

    private var goalValue: String {
        answers.primaryGoal?.title ?? "—"
    }

    private var sourcesValue: String { summary(set: answers.sources, titleKey: { $0.title }) }
    private var skillValue: String { answers.skillLevel?.title ?? "—" }
    private var timeValue: String { "\(answers.timeMinutesPerMeal) min" }
    private var frequencyValue: String { "\(answers.cookingFrequencyPerWeek)× /sem" }
    private var dietValue: String {
        answers.diets.contains(.none) ? "Aucun" : summary(set: answers.diets, titleKey: { $0.title })
    }
    private var allergiesValue: String {
        answers.allergies.contains(.none) ? "Aucune" : summary(set: answers.allergies, titleKey: { $0.title })
    }
    private var servingsValue: String { answers.typicalServings.map { "\($0.title) pers." } ?? "—" }
    private var cuisinesValue: String { summary(set: answers.cuisines, titleKey: { $0.title }) }
    private var challengesValue: String { summary(set: answers.challenges, titleKey: { $0.title }) }

    /// "TikTok, Instagram, +1" style summary for multi-select sets.
    private func summary<T: Hashable>(set: Set<T>, titleKey: (T) -> String) -> String {
        guard !set.isEmpty else { return "—" }
        let titles = set.map(titleKey).sorted()
        if titles.count <= 2 {
            return titles.joined(separator: ", ")
        } else {
            let head = titles.prefix(2).joined(separator: ", ")
            return "\(head), +\(titles.count - 2)"
        }
    }
}

// MARK: - Edit question enum

enum EditQuestion: String, Identifiable {
    case goal, sources, skillLevel, time, frequency, diet, allergies, servings, cuisines, challenges

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal:        return "Objectif principal"
        case .sources:     return "D'où viennent tes recettes ?"
        case .skillLevel:  return "Ton niveau culinaire"
        case .time:        return "Temps par repas"
        case .frequency:   return "Fréquence de cuisine"
        case .diet:        return "Régime alimentaire"
        case .allergies:   return "Allergies"
        case .servings:    return "Taille typique"
        case .cuisines:    return "Cuisines préférées"
        case .challenges:  return "Freins en cuisine"
        }
    }
}

// MARK: - Edit sheet

struct CulinaryPreferenceEditSheet: View {
    let question: EditQuestion
    let initialAnswers: OnboardingAnswers
    let onSave: (OnboardingAnswers) -> Void
    let onCancel: () -> Void

    @State private var draft: OnboardingAnswers

    init(
        question: EditQuestion,
        answers: OnboardingAnswers,
        onSave: @escaping (OnboardingAnswers) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.question = question
        self.initialAnswers = answers
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: answers)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CooksyTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            editor
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }

                    Button(action: save) {
                        Text("Enregistrer")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CooksyTheme.accentGradient)
                            )
                            .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 14, y: 8)
                    }
                    .buttonStyle(CooksyTheme.pressScale())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(question.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch question {
        case .goal:       goalEditor
        case .sources:    sourcesEditor
        case .skillLevel: skillEditor
        case .time:       timeEditor
        case .frequency:  frequencyEditor
        case .diet:       dietEditor
        case .allergies:  allergiesEditor
        case .servings:   servingsEditor
        case .cuisines:   cuisinesEditor
        case .challenges: challengesEditor
        }
    }

    private func save() {
        OnboardingHaptics.light()
        onSave(draft)
    }

    // MARK: - Individual editors

    private var goalEditor: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingGoal.allCases) { goal in
                BigChoiceCard(
                    systemImage: goal.systemImage,
                    title: goal.title,
                    subtitle: goal.subtitle,
                    isSelected: draft.primaryGoal == goal,
                    action: { draft.primaryGoal = goal }
                )
            }
        }
    }

    private var sourcesEditor: some View {
        LazyVGrid(columns: twoCols, spacing: 10) {
            ForEach(OnboardingSource.allCases) { source in
                ChoicePill(
                    title: source.title,
                    systemImage: source.systemImage,
                    isSelected: draft.sources.contains(source),
                    action: { toggle(source, in: \.sources) }
                )
            }
        }
    }

    private var skillEditor: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingSkillLevel.allCases) { level in
                BigChoiceCard(
                    systemImage: "flame.fill",
                    title: level.title,
                    subtitle: level.subtitle,
                    isSelected: draft.skillLevel == level,
                    action: { draft.skillLevel = level }
                )
            }
        }
    }

    private var timeEditor: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(draft.timeMinutesPerMeal)")
                    .font(.system(size: 60, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            Slider(
                value: Binding(
                    get: { Double(draft.timeMinutesPerMeal) },
                    set: { newValue in
                        let stepped = Int((newValue / 5).rounded()) * 5
                        draft.timeMinutesPerMeal = max(10, min(90, stepped))
                    }
                ),
                in: 10...90,
                step: 5
            )
            .tint(CooksyTheme.ctaOrange)

            Text(timeLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var timeLabel: String {
        switch draft.timeMinutesPerMeal {
        case ..<16:  return "Mode rapide — bol en 15 min max"
        case 16...30: return "Express — du goût sans perdre de temps"
        case 31...60: return "Confortable — tu prends ton temps"
        default:      return "Les grands jours — tu te fais plaisir"
        }
    }

    private var frequencyEditor: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(draft.cookingFrequencyPerWeek)")
                    .font(.system(size: 60, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .monospacedDigit()
                Text("× /semaine")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                ForEach(1...7, id: \.self) { n in
                    Button {
                        OnboardingHaptics.selection()
                        draft.cookingFrequencyPerWeek = n
                    } label: {
                        Circle()
                            .fill(n <= draft.cookingFrequencyPerWeek ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.elevatedSurface, CooksyTheme.elevatedSurface], startPoint: .top, endPoint: .bottom))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(n <= draft.cookingFrequencyPerWeek ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(frequencyLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var frequencyLabel: String {
        switch draft.cookingFrequencyPerWeek {
        case 1...2: return "Le weekend warrior 🏆"
        case 3...4: return "Un bon rythme régulier"
        case 5...6: return "La cuisine c'est ton truc"
        default:    return "Tu cuisines plus que tu respires"
        }
    }

    private var dietEditor: some View {
        LazyVGrid(columns: twoCols, spacing: 10) {
            ForEach(OnboardingDiet.allCases) { diet in
                ChoicePill(
                    title: diet.title,
                    systemImage: diet.systemImage,
                    isSelected: draft.diets.contains(diet),
                    action: { toggleExclusive(diet, exclusive: .none, in: \.diets) }
                )
            }
        }
    }

    private var allergiesEditor: some View {
        LazyVGrid(columns: twoCols, spacing: 10) {
            ForEach(OnboardingAllergy.allCases) { allergy in
                ChoicePill(
                    title: allergy.title,
                    systemImage: nil,
                    isSelected: draft.allergies.contains(allergy),
                    action: { toggleExclusive(allergy, exclusive: .none, in: \.allergies) }
                )
            }
        }
    }

    private var servingsEditor: some View {
        LazyVGrid(columns: twoCols, spacing: 12) {
            ForEach(OnboardingServings.allCases) { serving in
                BigChoiceCard(
                    systemImage: "person.2.fill",
                    title: serving.title,
                    subtitle: serving.subtitle,
                    isSelected: draft.typicalServings == serving,
                    action: { draft.typicalServings = serving }
                )
            }
        }
    }

    private var cuisinesEditor: some View {
        LazyVGrid(columns: twoCols, spacing: 10) {
            ForEach(OnboardingCuisine.allCases) { cuisine in
                ChoicePill(
                    title: cuisine.title,
                    systemImage: cuisine.systemImage,
                    isSelected: draft.cuisines.contains(cuisine),
                    action: { toggle(cuisine, in: \.cuisines) }
                )
            }
        }
    }

    private var challengesEditor: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingChallenge.allCases) { challenge in
                ChoicePill(
                    title: challenge.title,
                    systemImage: nil,
                    isSelected: draft.challenges.contains(challenge),
                    action: { toggle(challenge, in: \.challenges) }
                )
            }
        }
    }

    // MARK: - Toggle helpers

    private var twoCols: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<OnboardingAnswers, Set<T>>) {
        var set = draft[keyPath: keyPath]
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        draft[keyPath: keyPath] = set
    }

    private func toggleExclusive<T: Hashable>(
        _ value: T,
        exclusive: T,
        in keyPath: WritableKeyPath<OnboardingAnswers, Set<T>>
    ) {
        var set = draft[keyPath: keyPath]
        if value == exclusive {
            if set.contains(exclusive) {
                set.remove(exclusive)
            } else {
                set = [exclusive]
            }
        } else {
            set.remove(exclusive)
            if set.contains(value) { set.remove(value) } else { set.insert(value) }
        }
        draft[keyPath: keyPath] = set
    }
}
