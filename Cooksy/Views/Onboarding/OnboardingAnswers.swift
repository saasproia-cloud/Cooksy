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

enum OnboardingSpiceLevel: String, Codable, CaseIterable, Identifiable {
    case mild
    case medium
    case spicy
    case fiery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mild:   return "Doux"
        case .medium: return "Modéré"
        case .spicy:  return "Épicé"
        case .fiery:  return "Très épicé"
        }
    }

    var subtitle: String {
        switch self {
        case .mild:   return "Pas de piment, merci"
        case .medium: return "Un peu de relief, sans excès"
        case .spicy:  return "J'aime quand ça pique"
        case .fiery:  return "Plus c'est fort, mieux c'est"
        }
    }

    /// Number of filled chili icons out of 4.
    var filledDots: Int {
        switch self {
        case .mild:   return 1
        case .medium: return 2
        case .spicy:  return 3
        case .fiery:  return 4
        }
    }
}

enum OnboardingEquipment: String, Codable, CaseIterable, Identifiable {
    case oven
    case microwave
    case airFryer
    case blender
    case foodProcessor
    case inductionStove
    case slowCooker
    case steamer
    case grill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oven:           return "Four"
        case .microwave:      return "Micro-ondes"
        case .airFryer:       return "Air fryer"
        case .blender:        return "Blender"
        case .foodProcessor:  return "Robot"
        case .inductionStove: return "Induction"
        case .slowCooker:     return "Cocotte / mijoteuse"
        case .steamer:        return "Cuit-vapeur"
        case .grill:          return "Plancha / grill"
        }
    }

    var systemImage: String {
        switch self {
        case .oven:           return "oven"
        case .microwave:      return "microwave"
        case .airFryer:       return "wind"
        case .blender:        return "drop.triangle.fill"
        case .foodProcessor:  return "fan.fill"
        case .inductionStove: return "flame.circle"
        case .slowCooker:     return "cooktop"
        case .steamer:        return "humidifier.fill"
        case .grill:          return "flame"
        }
    }
}

enum OnboardingBudget: String, Codable, CaseIterable, Identifiable {
    case budget
    case balanced
    case premium
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budget:    return "Petit budget"
        case .balanced:  return "Équilibré"
        case .premium:   return "Confort"
        case .unlimited: return "Sans limite"
        }
    }

    var subtitle: String {
        switch self {
        case .budget:    return "Je fais attention à chaque euro"
        case .balanced:  return "Bon rapport qualité-prix"
        case .premium:   return "Je m'autorise des bons produits"
        case .unlimited: return "Le budget n'est pas le sujet"
        }
    }

    var systemImage: String {
        switch self {
        case .budget:    return "eurosign.circle"
        case .balanced:  return "scalemass"
        case .premium:   return "sparkles"
        case .unlimited: return "crown.fill"
        }
    }
}

enum OnboardingMealMoment: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack
    case aperitif
    case dessert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Petit-déj"
        case .lunch:     return "Déjeuner"
        case .dinner:    return "Dîner"
        case .snack:     return "Snack / goûter"
        case .aperitif:  return "Apéro"
        case .dessert:   return "Dessert"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sun.haze.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "popcorn.fill"
        case .aperitif:  return "wineglass.fill"
        case .dessert:   return "birthday.cake.fill"
        }
    }
}

enum OnboardingShopping: String, Codable, CaseIterable, Identifiable {
    case supermarket
    case market
    case organic
    case drive
    case localProducer
    case asianGrocery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supermarket:   return "Supermarché"
        case .market:        return "Marché"
        case .organic:       return "Bio"
        case .drive:         return "Drive / livraison"
        case .localProducer: return "Producteur local"
        case .asianGrocery:  return "Épicerie du monde"
        }
    }

    var systemImage: String {
        switch self {
        case .supermarket:   return "cart.fill"
        case .market:        return "basket.fill"
        case .organic:       return "leaf.fill"
        case .drive:         return "shippingbox.fill"
        case .localProducer: return "tractor"
        case .asianGrocery:  return "globe.asia.australia.fill"
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
    var spiceLevel: OnboardingSpiceLevel?
    var equipment: Set<OnboardingEquipment>
    var budget: OnboardingBudget?
    var mealMoments: Set<OnboardingMealMoment>
    var shoppingPlaces: Set<OnboardingShopping>
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
        spiceLevel: nil,
        equipment: [],
        budget: nil,
        mealMoments: [],
        shoppingPlaces: [],
        challenges: []
    )

    private enum CodingKeys: String, CodingKey {
        case primaryGoal, sources, skillLevel, timeMinutesPerMeal,
             cookingFrequencyPerWeek, diets, allergies, typicalServings,
             cuisines, spiceLevel, equipment, budget, mealMoments,
             shoppingPlaces, challenges
    }

    // Custom decoder so older drafts (without the new fields) still load —
    // keeps existing in-progress onboardings from getting wiped on update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryGoal = try c.decodeIfPresent(OnboardingGoal.self, forKey: .primaryGoal)
        sources = try c.decodeIfPresent(Set<OnboardingSource>.self, forKey: .sources) ?? []
        skillLevel = try c.decodeIfPresent(OnboardingSkillLevel.self, forKey: .skillLevel)
        timeMinutesPerMeal = try c.decodeIfPresent(Int.self, forKey: .timeMinutesPerMeal) ?? 30
        cookingFrequencyPerWeek = try c.decodeIfPresent(Int.self, forKey: .cookingFrequencyPerWeek) ?? 4
        diets = try c.decodeIfPresent(Set<OnboardingDiet>.self, forKey: .diets) ?? []
        allergies = try c.decodeIfPresent(Set<OnboardingAllergy>.self, forKey: .allergies) ?? []
        typicalServings = try c.decodeIfPresent(OnboardingServings.self, forKey: .typicalServings)
        cuisines = try c.decodeIfPresent(Set<OnboardingCuisine>.self, forKey: .cuisines) ?? []
        spiceLevel = try c.decodeIfPresent(OnboardingSpiceLevel.self, forKey: .spiceLevel)
        equipment = try c.decodeIfPresent(Set<OnboardingEquipment>.self, forKey: .equipment) ?? []
        budget = try c.decodeIfPresent(OnboardingBudget.self, forKey: .budget)
        mealMoments = try c.decodeIfPresent(Set<OnboardingMealMoment>.self, forKey: .mealMoments) ?? []
        shoppingPlaces = try c.decodeIfPresent(Set<OnboardingShopping>.self, forKey: .shoppingPlaces) ?? []
        challenges = try c.decodeIfPresent(Set<OnboardingChallenge>.self, forKey: .challenges) ?? []
    }

    init(
        primaryGoal: OnboardingGoal?,
        sources: Set<OnboardingSource>,
        skillLevel: OnboardingSkillLevel?,
        timeMinutesPerMeal: Int,
        cookingFrequencyPerWeek: Int,
        diets: Set<OnboardingDiet>,
        allergies: Set<OnboardingAllergy>,
        typicalServings: OnboardingServings?,
        cuisines: Set<OnboardingCuisine>,
        spiceLevel: OnboardingSpiceLevel?,
        equipment: Set<OnboardingEquipment>,
        budget: OnboardingBudget?,
        mealMoments: Set<OnboardingMealMoment>,
        shoppingPlaces: Set<OnboardingShopping>,
        challenges: Set<OnboardingChallenge>
    ) {
        self.primaryGoal = primaryGoal
        self.sources = sources
        self.skillLevel = skillLevel
        self.timeMinutesPerMeal = timeMinutesPerMeal
        self.cookingFrequencyPerWeek = cookingFrequencyPerWeek
        self.diets = diets
        self.allergies = allergies
        self.typicalServings = typicalServings
        self.cuisines = cuisines
        self.spiceLevel = spiceLevel
        self.equipment = equipment
        self.budget = budget
        self.mealMoments = mealMoments
        self.shoppingPlaces = shoppingPlaces
        self.challenges = challenges
    }
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
