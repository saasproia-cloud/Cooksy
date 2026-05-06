import Foundation
import OSLog
import SwiftUI

/// All screens of the pre-account onboarding (Blocks A → D).
/// Paywall (E1) lives outside this coordinator — it is gated at the
/// CooksyApp level based on `profile.isPremium`.
enum OnboardingStep: Int, CaseIterable, Codable, Identifiable {
    case welcome = 0        // A1
    case appReview          // A1.5 — soft App Store rating prompt
    case demo               // A2
    case valueProof         // A3
    case primaryGoal        // B1
    case sources            // B2
    case skillLevel         // B3
    case timeSlider         // B4
    case frequency          // B5
    case diet               // B6
    case allergies          // B7
    case servings           // B8
    case cuisines           // B9
    case spiceLevel         // B11
    case equipment          // B12
    case budget             // B13
    case mealMoments        // B14
    case shopping           // B15
    case challenges         // B10
    case buildingProfile    // C1
    case personalizedPreview // C2
    case signUp             // D1

    var id: Int { rawValue }

    /// Block B indices (1-based) used by the progress bar — zero for non-question screens.
    var questionIndex: Int? {
        switch self {
        case .primaryGoal:    return 1
        case .sources:        return 2
        case .skillLevel:     return 3
        case .timeSlider:     return 4
        case .frequency:      return 5
        case .diet:           return 6
        case .allergies:      return 7
        case .servings:       return 8
        case .cuisines:       return 9
        case .spiceLevel:     return 10
        case .equipment:      return 11
        case .budget:         return 12
        case .mealMoments:    return 13
        case .shopping:       return 14
        case .challenges:     return 15
        default:              return nil
        }
    }

    /// Total number of question screens — used to size the progress bar.
    static let totalQuestions = 15

    /// Whether the "Passer" (skip) button should be shown on this screen.
    /// Only the softest behavioural signals can be skipped — every actual
    /// preference must be answered so the recipe engine has real data.
    var allowsSkip: Bool {
        switch self {
        case .mealMoments, .shopping, .challenges:
            return true
        default:
            return false
        }
    }

    /// Whether the back chevron is shown (off on the first screen and during the auto-loading transition).
    var allowsBack: Bool {
        switch self {
        case .welcome, .buildingProfile:
            return false
        default:
            return true
        }
    }
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var currentStep: OnboardingStep
    @Published var answers: OnboardingAnswers

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "OnboardingCoordinator")
    private let draftKey = "cooksy.onboarding.draft.v1"
    private let stepKey = "cooksy.onboarding.step.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore draft if present.
        if let data = defaults.data(forKey: draftKey),
           let decoded = try? JSONDecoder().decode(OnboardingAnswers.self, from: data) {
            self.answers = decoded
        } else {
            self.answers = .empty
        }

        let restoredStepRaw = defaults.integer(forKey: stepKey)
        if let restored = OnboardingStep(rawValue: restoredStepRaw), restoredStepRaw > 0 {
            self.currentStep = restored
        } else {
            self.currentStep = .welcome
        }
    }

    // MARK: - Navigation

    func goTo(_ step: OnboardingStep, animated: Bool = true) {
        withOptionalAnimation(animated) {
            currentStep = step
        }
        persistStep()
    }

    func next() {
        let nextRaw = currentStep.rawValue + 1
        guard let next = OnboardingStep(rawValue: nextRaw) else { return }
        goTo(next)
    }

    func back() {
        let prevRaw = currentStep.rawValue - 1
        guard let previous = OnboardingStep(rawValue: prevRaw), currentStep.allowsBack else { return }
        goTo(previous)
    }

    // MARK: - Persistence

    /// Call whenever `answers` mutates to keep the draft warm across app kills.
    func persistDraft() {
        do {
            let data = try JSONEncoder().encode(answers)
            defaults.set(data, forKey: draftKey)
        } catch {
            logger.error("Failed to persist onboarding draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistStep() {
        defaults.set(currentStep.rawValue, forKey: stepKey)
    }

    /// Called after the account is created and answers have been pushed to Supabase.
    func clearDraft() {
        defaults.removeObject(forKey: draftKey)
        defaults.removeObject(forKey: stepKey)
        answers = .empty
        currentStep = .welcome
    }

    // MARK: - Step validation

    /// Whether the user has given enough input on the current step for the CTA to be enabled.
    func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .appReview, .demo, .valueProof, .buildingProfile, .personalizedPreview, .signUp:
            return true
        case .primaryGoal:
            return answers.primaryGoal != nil
        case .sources:
            return !answers.sources.isEmpty
        case .skillLevel:
            return answers.skillLevel != nil
        case .timeSlider:
            return true // slider always has a value
        case .frequency:
            return answers.cookingFrequencyPerWeek > 0
        case .diet:
            return !answers.diets.isEmpty
        case .allergies:
            return !answers.allergies.isEmpty
        case .servings:
            return answers.typicalServings != nil
        case .cuisines:
            return !answers.cuisines.isEmpty
        case .spiceLevel:
            return answers.spiceLevel != nil
        case .equipment:
            return !answers.equipment.isEmpty
        case .budget:
            return answers.budget != nil
        case .mealMoments:
            return !answers.mealMoments.isEmpty
        case .shopping:
            return !answers.shoppingPlaces.isEmpty
        case .challenges:
            return !answers.challenges.isEmpty
        }
    }

    // MARK: - Mutators (publish draft automatically)

    func selectGoal(_ goal: OnboardingGoal) {
        answers.primaryGoal = goal
        persistDraft()
    }

    func toggleSource(_ source: OnboardingSource) {
        toggleMember(source, in: \.sources)
    }

    func selectSkill(_ level: OnboardingSkillLevel) {
        answers.skillLevel = level
        persistDraft()
    }

    func setTime(_ minutes: Int) {
        answers.timeMinutesPerMeal = minutes
        persistDraft()
    }

    func setFrequency(_ times: Int) {
        answers.cookingFrequencyPerWeek = times
        persistDraft()
    }

    func toggleDiet(_ diet: OnboardingDiet) {
        toggleWithExclusive(diet, exclusive: .none, in: \.diets)
    }

    func toggleAllergy(_ allergy: OnboardingAllergy) {
        toggleWithExclusive(allergy, exclusive: .none, in: \.allergies)
    }

    func selectServings(_ servings: OnboardingServings) {
        answers.typicalServings = servings
        persistDraft()
    }

    func toggleCuisine(_ cuisine: OnboardingCuisine) {
        toggleMember(cuisine, in: \.cuisines)
    }

    func toggleChallenge(_ challenge: OnboardingChallenge) {
        toggleMember(challenge, in: \.challenges)
    }

    func selectSpiceLevel(_ level: OnboardingSpiceLevel) {
        answers.spiceLevel = level
        persistDraft()
    }

    func toggleEquipment(_ equipment: OnboardingEquipment) {
        toggleMember(equipment, in: \.equipment)
    }

    func selectBudget(_ budget: OnboardingBudget) {
        answers.budget = budget
        persistDraft()
    }

    func toggleMealMoment(_ moment: OnboardingMealMoment) {
        toggleMember(moment, in: \.mealMoments)
    }

    func toggleShopping(_ shopping: OnboardingShopping) {
        toggleMember(shopping, in: \.shoppingPlaces)
    }

    // MARK: - Internals

    private func toggleMember<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<OnboardingAnswers, Set<T>>) {
        if answers[keyPath: keyPath].contains(value) {
            answers[keyPath: keyPath].remove(value)
        } else {
            answers[keyPath: keyPath].insert(value)
        }
        persistDraft()
    }

    /// Adds exclusivity logic: tapping the `exclusive` value clears all others;
    /// tapping any other value clears the `exclusive` value.
    private func toggleWithExclusive<T: Hashable>(
        _ value: T,
        exclusive: T,
        in keyPath: WritableKeyPath<OnboardingAnswers, Set<T>>
    ) {
        var current = answers[keyPath: keyPath]
        if value == exclusive {
            if current.contains(exclusive) {
                current.remove(exclusive)
            } else {
                current = [exclusive]
            }
        } else {
            current.remove(exclusive)
            if current.contains(value) {
                current.remove(value)
            } else {
                current.insert(value)
            }
        }
        answers[keyPath: keyPath] = current
        persistDraft()
    }

    private func withOptionalAnimation(_ animated: Bool, _ body: () -> Void) {
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                body()
            }
        } else {
            body()
        }
    }
}
