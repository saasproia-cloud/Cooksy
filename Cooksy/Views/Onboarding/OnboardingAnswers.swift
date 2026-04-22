import Foundation

// MARK: - Enum types

enum OnboardingGoal: String, Codable, CaseIterable, Identifiable {
    case cookMore
    case saveTime
    case eatHealthy
    case saveRecipes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cookMore:     return "Cuisiner plus souvent"
        case .saveTime:     return "Gagner du temps"
        case .eatHealthy:   return "Manger plus sainement"
        case .saveRecipes:  return "Sauver mes recettes TikTok/Insta"
        }
    }

    var subtitle: String {
        switch self {
        case .cookMore:     return "J'ai envie de m'y mettre sérieusement"
        case .saveTime:     return "Cuisiner vite sans sacrifier la qualité"
        case .eatHealthy:   return "Des recettes équilibrées au quotidien"
        case .saveRecipes:  return "Plus jamais perdre un Reel qui me fait saliver"
        }
    }

    var systemImage: String {
        switch self {
        case .cookMore:     return "fork.knife"
        case .saveTime:     return "clock.badge.checkmark"
        case .eatHealthy:   return "leaf.fill"
        case .saveRecipes:  return "sparkles.rectangle.stack"
        }
    }
}

enum OnboardingSource: String, Codable, CaseIterable, Identifiable {
    case tiktok
    case instagram
    case youtube
    case blogs
    case books
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok:    return "TikTok"
        case .instagram: return "Instagram Reels"
        case .youtube:   return "YouTube"
        case .blogs:     return "Blogs cuisine"
        case .books:     return "Livres"
        case .people:    return "Amis / famille"
        }
    }

    var systemImage: String {
        switch self {
        case .tiktok:    return "music.note"
        case .instagram: return "camera.fill"
        case .youtube:   return "play.rectangle.fill"
        case .blogs:     return "doc.text.fill"
        case .books:     return "book.closed.fill"
        case .people:    return "person.2.fill"
        }
    }
}

enum OnboardingSkillLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:     return "Débutant"
        case .intermediate: return "Intermédiaire"
        case .advanced:     return "Confirmé"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner:     return "Je connais les bases, pas plus"
        case .intermediate: return "Je me débrouille bien"
        case .advanced:     return "J'invente mes propres plats"
        }
    }

    /// Number of filled dots out of 3 used for the level indicator.
    var filledDots: Int {
        switch self {
        case .beginner:     return 1
        case .intermediate: return 2
        case .advanced:     return 3
        }
    }
}

enum OnboardingDiet: String, Codable, CaseIterable, Identifiable {
    case none
    case vegetarian
    case vegan
    case glutenFree
    case lactoseFree
    case halal
    case kosher
    case keto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:         return "Aucun"
        case .vegetarian:   return "Végétarien"
        case .vegan:        return "Végan"
        case .glutenFree:   return "Sans gluten"
        case .lactoseFree:  return "Sans lactose"
        case .halal:        return "Halal"
        case .kosher:       return "Kasher"
        case .keto:         return "Keto / low-carb"
        }
    }

    var systemImage: String {
        switch self {
        case .none:         return "circle"
        case .vegetarian:   return "leaf"
        case .vegan:        return "leaf.fill"
        case .glutenFree:   return "exclamationmark.triangle"
        case .lactoseFree:  return "drop.triangle"
        case .halal:        return "checkmark.seal"
        case .kosher:       return "star.circle"
        case .keto:         return "flame.fill"
        }
    }
}

enum OnboardingAllergy: String, Codable, CaseIterable, Identifiable {
    case none
    case peanuts
    case treeNuts
    case eggs
    case dairy
    case fish
    case shellfish
    case soy
    case gluten

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:       return "Aucune allergie"
        case .peanuts:    return "Arachides"
        case .treeNuts:   return "Fruits à coque"
        case .eggs:       return "Œufs"
        case .dairy:      return "Lactose"
        case .fish:       return "Poisson"
        case .shellfish:  return "Crustacés"
        case .soy:        return "Soja"
        case .gluten:     return "Gluten"
        }
    }
}

enum OnboardingServings: String, Codable, CaseIterable, Identifiable {
    case one
    case two
    case threeToFour
    case fivePlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one:         return "1"
        case .two:         return "2"
        case .threeToFour: return "3-4"
        case .fivePlus:    return "5+"
        }
    }

    var subtitle: String {
        switch self {
        case .one:         return "Solo"
        case .two:         return "Couple"
        case .threeToFour: return "Famille"
        case .fivePlus:    return "Grande tablée"
        }
    }

    /// How many silhouettes to render in the choice card.
    var silhouetteCount: Int {
        switch self {
        case .one:         return 1
        case .two:         return 2
        case .threeToFour: return 4
        case .fivePlus:    return 5
        }
    }
}

enum OnboardingCuisine: String, Codable, CaseIterable, Identifiable {
    case french
    case italian
    case asian
    case indian
    case mexican
    case mediterranean
    case middleEastern
    case american
    case african

    var id: String { rawValue }

    var title: String {
        switch self {
        case .french:        return "Française"
        case .italian:       return "Italienne"
        case .asian:         return "Asiatique"
        case .indian:        return "Indienne"
        case .mexican:       return "Mexicaine"
        case .mediterranean: return "Méditerranéenne"
        case .middleEastern: return "Moyen-Orient"
        case .american:      return "Américaine"
        case .african:       return "Africaine"
        }
    }

    var systemImage: String {
        switch self {
        case .french:        return "fork.knife"
        case .italian:       return "leaf"
        case .asian:         return "takeoutbag.and.cup.and.straw"
        case .indian:        return "flame"
        case .mexican:       return "sun.max"
        case .mediterranean: return "sun.and.horizon"
        case .middleEastern: return "moon.stars"
        case .american:      return "star"
        case .african:       return "globe.europe.africa.fill"
        }
    }
}

enum OnboardingChallenge: String, Codable, CaseIterable, Identifiable {
    case time
    case ingredients
    case ideas
    case cleanup
    case balance
    case technique

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time:        return "Le temps que ça prend"
        case .ingredients: return "Les ingrédients compliqués à trouver"
        case .ideas:       return "Je manque d'idées"
        case .cleanup:     return "La vaisselle après"
        case .balance:     return "Je sais pas quoi cuisiner pour équilibrer"
        case .technique:   return "Les étapes techniques me bloquent"
        }
    }
}

// MARK: - Onboarding answers

/// The full set of user answers captured during onboarding.
/// Persisted locally in UserDefaults as a draft and pushed to
/// Supabase (`profiles.onboarding_answers` JSONB) at completion.
struct OnboardingAnswers: Codable, Equatable {
    var primaryGoal: OnboardingGoal?
    var sources: Set<OnboardingSource>
    var skillLevel: OnboardingSkillLevel?
    var timeMinutesPerMeal: Int
    var cookingFrequencyPerWeek: Int
    var diets: Set<OnboardingDiet>
    var allergies: Set<OnboardingAllergy>
    var typicalServings: OnboardingServings?
    var cuisines: Set<OnboardingCuisine>
    var challenges: Set<OnboardingChallenge>

    static let empty = OnboardingAnswers(
        primaryGoal: nil,
        sources: [],
        skillLevel: nil,
        timeMinutesPerMeal: 30,
        cookingFrequencyPerWeek: 4,
        diets: [],
        allergies: [],
        typicalServings: nil,
        cuisines: [],
        challenges: []
    )
}

// MARK: - Derived summary (used by PersonalizedPreviewView)

extension OnboardingAnswers {
    /// Short localized summary of dietary filters ("gluten, lactose" or nil if none).
    var dietSummary: String? {
        let exclusions = diets
            .filter { $0 != .none }
            .map { $0.title.lowercased() }
            .sorted()
        guard !exclusions.isEmpty else { return nil }
        return exclusions.joined(separator: ", ")
    }

    /// "rapides, < 30 min" / "équilibrées" / "gourmandes" — a tone marker for the recap screen.
    var paceDescriptor: String {
        switch timeMinutesPerMeal {
        case ..<16:  return "rapides, < 15 min"
        case 16...30: return "express, < 30 min"
        case 31...60: return "équilibrées, autour de 45 min"
        default:      return "gourmandes, avec le temps"
        }
    }

    /// Conversion of the primary goal into a short outcome phrase.
    var goalOutcome: String {
        switch primaryGoal {
        case .cookMore:    return "cuisiner plus souvent"
        case .saveTime:    return "faire gagner du temps"
        case .eatHealthy:  return "manger mieux"
        case .saveRecipes: return "ne plus perdre une recette"
        case nil:          return "te régaler"
        }
    }
}
