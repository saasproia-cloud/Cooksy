import SwiftUI
import UIKit

enum CooksyTheme {
    static let background = Color(hex: 0xFFF6EA)
    static let surface = Color(hex: 0xFFF9F1)
    static let elevatedSurface = Color(hex: 0xFFFDF8)
    static let primaryAccent = Color(hex: 0xEA662A)
    static let primaryAccentStrong = Color(hex: 0xC9471D)
    static let primaryAccentSoft = Color(hex: 0xFFD8BD)
    static let primaryAccentGlow = Color(hex: 0xF5B14E)
    static let secondaryAccent = Color(hex: 0x7EA34A)
    static let secondaryAccentStrong = Color(hex: 0x4F6F2C)
    static let secondaryAccentSoft = Color(hex: 0xEEF4D9)
    static let warmCard = Color(hex: 0xFFE4C7)
    static let warmCardMuted = Color(hex: 0xF4C86A)
    static let brandBlue = secondaryAccent
    static let brandBlueDark = secondaryAccentStrong
    static let ctaOrange = primaryAccent
    static let ctaOrangeDark = primaryAccentStrong
    static let sparkleYellow = primaryAccentGlow
    static let primaryText = Color(hex: 0x2B1A12)
    static let secondaryText = Color(hex: 0x7A6554)
    static let stroke = Color(hex: 0xE7D6C3)
    static let softCloud = secondaryAccentSoft
    static let blush = Color(hex: 0xFCE4D0)
    static let shadow = Color(hex: 0x7C3F16, opacity: 0.12)
    static let softShadow = Color(hex: 0x7C3F16, opacity: 0.06)

    static let ambientGradient = LinearGradient(
        colors: [
            Color(hex: 0xFFF9F0),
            Color(hex: 0xFFF0DE),
            Color(hex: 0xF9E1CA)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGlowGradient = LinearGradient(
        colors: [
            Color(hex: 0xFFD4AE),
            Color(hex: 0xFFF4DD),
            Color(hex: 0xE7F1CD)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xF2852F), Color(hex: 0xD94B20)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroRadius: CGFloat = 26
    static let cardRadius: CGFloat = 22

    static func recipeGradient(for heroStyle: HeroStyle) -> LinearGradient {
        LinearGradient(
            colors: recipeGradientColors(for: heroStyle),
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    static func recipeGradientColors(for heroStyle: HeroStyle) -> [Color] {
        switch heroStyle {
        case .warmCocoa:
            return [Color(hex: 0xC8481E), Color(hex: 0xF29434)]
        case .citrus:
            return [Color(hex: 0xF28E26), Color(hex: 0xF7D15B)]
        case .ocean:
            return [Color(hex: 0x5F8636), Color(hex: 0x9AC95B)]
        case .meadow:
            return [Color(hex: 0x43722D), Color(hex: 0x83B14B)]
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
