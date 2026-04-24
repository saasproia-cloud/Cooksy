import SwiftUI

/// Thematic visual style applied to "Tendances du jour" trending rows so the
/// Home feed feels curated instead of a generic emoji-on-gradient look.
///
/// Each style pairs a cooking-appropriate SF Symbol with a category-specific
/// gradient. Mapping is driven by `DemoRecipeScenario.id` via
/// `TrendingArtworkStyle.forScenarioID(_:)` so we stay decoupled from the
/// scenario catalog and can add future categories without touching the feed.
enum TrendingArtworkStyle: Hashable {
    case pasta
    case asianBowl
    case healthyGreens
    case breakfast
    case tomato
    case honeyGlaze
    case streetFood
    case bakedCheese
    case wrap
    case ricebowl

    /// SF Symbol rendered in white on top of the gradient.
    var symbolName: String {
        switch self {
        case .pasta:          return "fork.knife"
        case .asianBowl:      return "takeoutbag.and.cup.and.straw.fill"
        case .healthyGreens:  return "leaf.fill"
        case .breakfast:      return "cup.and.saucer.fill"
        case .tomato:         return "flame.fill"
        case .honeyGlaze:     return "drop.fill"
        case .streetFood:     return "flame.fill"
        case .bakedCheese:    return "oven.fill"
        case .wrap:           return "scroll.fill"
        case .ricebowl:       return "bowl.fill"
        }
    }

    /// Fallback symbol for platforms where the primary one is unavailable.
    /// Currently only `oven.fill` (iOS 17+) needs a fallback.
    var fallbackSymbolName: String {
        switch self {
        case .bakedCheese: return "flame.fill"
        default: return symbolName
        }
    }

    /// Top-leading to bottom-trailing gradient used as the artwork background.
    var gradient: LinearGradient {
        switch self {
        case .pasta:
            return Self.gradient(0xF1B24A, 0xF6E3A1)
        case .asianBowl:
            return Self.gradient(0xD9583C, 0xF2A65A)
        case .healthyGreens:
            return Self.gradient(0x6DAE4F, 0xC9D96A)
        case .breakfast:
            return Self.gradient(0xE5864A, 0xF4C276)
        case .tomato:
            return Self.gradient(0xD94D4D, 0xF58A5A)
        case .honeyGlaze:
            return Self.gradient(0xC56B2E, 0xF2C05A)
        case .streetFood:
            return Self.gradient(0xD36B1F, 0xF0C14D)
        case .bakedCheese:
            return Self.gradient(0xC83F3F, 0xF2A65A)
        case .wrap:
            return Self.gradient(0xE08642, 0xF4D07D)
        case .ricebowl:
            return Self.gradient(0xF46D5B, 0xF7B267)
        }
    }

    private static func gradient(_ top: UInt, _ bottom: UInt) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: top), Color(hex: bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Maps the catalog scenario id to a trending style. Unknown ids fall
    /// back to `.pasta` (safe warm neutral).
    static func forScenarioID(_ id: String) -> TrendingArtworkStyle {
        switch id {
        case "nuggets-pasta":              return .streetFood
        case "chicken-wrap":               return .wrap
        case "salmon-rice-bowl":           return .ricebowl
        case "creamy-pasta":               return .pasta
        case "overnight-oats":             return .breakfast
        case "vodka-pasta":                return .tomato
        case "honey-garlic-chicken-rice":  return .honeyGlaze
        case "avocado-egg-toast":          return .healthyGreens
        case "crispy-potato-tacos":        return .streetFood
        case "baked-feta-pasta":           return .bakedCheese
        default:                            return .pasta
        }
    }
}

/// Round thumbnail used in the "Tendances du jour" list. Replaces the old
/// emoji-on-gradient look with a clean SF Symbol + thematic gradient that
/// reads more like a real food app.
struct TrendingArtworkSurface: View {
    let style: TrendingArtworkStyle
    var symbolSize: CGFloat = 22

    var body: some View {
        ZStack {
            style.gradient

            // Subtle light blob in the corner to give the surface depth
            // without costing a blur pass.
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 58, height: 58)
                .offset(x: 18, y: -18)

            Image(systemName: style.symbolName)
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
        }
    }
}
