import SwiftUI

/// Semantic typography tokens for the redesigned premium surfaces.
///
/// The original screens scattered `.system(size: 36, weight: .bold,
/// design: .serif)` and friends inline across hundreds of `Text(…)`
/// calls. That made tonal adjustments (smaller headlines on SE,
/// nudging body line-height for legibility) require visiting every
/// file. These tokens map intent → font so we can sweep all surfaces
/// from one place.
///
/// Use through the `.font(.cooksy(...))` extension below:
///
///     Text("Une vidéo. Une recette.")
///         .font(.cooksy(.displayLarge))
///
enum CooksyFont {
    /// Hero headline (Welcome / Paywall main title). 36pt serif bold.
    case displayLarge
    /// Section headline. 28pt serif bold.
    case displayMedium
    /// Card title / paywall plan price. 22pt rounded heavy.
    case titleLarge
    /// Sub-title / paywall section header. 17pt rounded semibold.
    case titleMedium
    /// Body copy. 15pt rounded medium. Slightly larger than .system
    /// body so it reads premium without feeling oversized.
    case body
    /// Small label / footnote inside cards. 13pt rounded semibold.
    case caption
    /// Smallest legal / metadata text. 11pt rounded medium.
    case footnote
}

extension Font {
    /// Resolves a {@link CooksyFont} into a SwiftUI `Font`.
    static func cooksy(_ token: CooksyFont) -> Font {
        switch token {
        case .displayLarge:
            return .system(size: 36, weight: .bold, design: .serif)
        case .displayMedium:
            return .system(size: 28, weight: .bold, design: .serif)
        case .titleLarge:
            return .system(size: 22, weight: .heavy, design: .rounded)
        case .titleMedium:
            return .system(size: 17, weight: .semibold, design: .rounded)
        case .body:
            return .system(size: 15, weight: .medium, design: .rounded)
        case .caption:
            return .system(size: 13, weight: .semibold, design: .rounded)
        case .footnote:
            return .system(size: 11, weight: .medium, design: .rounded)
        }
    }
}
