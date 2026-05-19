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

/// Thumbnail used in the "Tendances du jour" list. Replaces the old
/// emoji-on-gradient look with a layered glass surface that mimics a
/// proper recipe cover (gradient + bokeh highlights + dotted texture +
/// symbol on a glass disc) so the feed feels editorial.
struct TrendingArtworkSurface: View {
    let style: TrendingArtworkStyle
    var symbolSize: CGFloat = 22
    /// When `true`, render the larger hero treatment (bigger glass disc,
    /// more pronounced highlights). Defaults to the compact thumbnail
    /// treatment so existing list cells stay visually consistent.
    var prominent: Bool = false

    var body: some View {
        ZStack {
            // Layer 1 — base gradient
            style.gradient

            // Layer 2 — diagonal sheen
            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color.white.opacity(0.0),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layer 3 — bokeh highlights for depth
            Circle()
                .fill(Color.white.opacity(prominent ? 0.22 : 0.18))
                .frame(width: prominent ? 110 : 70, height: prominent ? 110 : 70)
                .blur(radius: prominent ? 22 : 12)
                .offset(x: prominent ? -28 : 18, y: prominent ? -32 : -18)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: prominent ? 80 : 46, height: prominent ? 80 : 46)
                .blur(radius: 14)
                .offset(x: prominent ? 36 : 22, y: prominent ? 34 : 18)

            // Layer 4 — subtle dotted texture (only on prominent variant
            // to keep the small thumbnail crisp).
            if prominent {
                Canvas { context, size in
                    let stride: CGFloat = 14
                    for x in Swift.stride(from: 0, through: size.width, by: stride) {
                        for y in Swift.stride(from: 0, through: size.height, by: stride) {
                            let path = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                            context.fill(path, with: .color(.white.opacity(0.06)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }

            // Layer 5 — symbol on a glass disc.
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(
                        width: prominent ? symbolSize * 3.4 : symbolSize * 2.0,
                        height: prominent ? symbolSize * 3.4 : symbolSize * 2.0
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: prominent ? 1.4 : 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: prominent ? 14 : 6, y: prominent ? 8 : 3)

                Image(systemName: style.symbolName)
                    .font(.system(size: symbolSize, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
            }
        }
    }
}
