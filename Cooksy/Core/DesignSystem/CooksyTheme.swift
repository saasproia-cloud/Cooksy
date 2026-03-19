import SwiftUI
import UIKit

enum CooksyTheme {
    static let background = Color(hex: 0xF6F1E7)
    static let surface = Color(hex: 0xFFFDF9)
    static let warmCard = Color(hex: 0xF4E7D1)
    static let warmCardMuted = Color(hex: 0xE9DCC4)
    static let brandBlue = Color(hex: 0x8AB2FF)
    static let brandBlueDark = Color(hex: 0x587FD8)
    static let ctaOrange = Color(hex: 0xF47A1F)
    static let ctaOrangeDark = Color(hex: 0xD76613)
    static let sparkleYellow = Color(hex: 0xFFD74D)
    static let primaryText = Color(hex: 0x221D17)
    static let secondaryText = Color(hex: 0x8A7B6A)
    static let stroke = Color(hex: 0xE2D4BE)
    static let softCloud = Color(hex: 0xEFF4FA)
    static let blush = Color(hex: 0xF8D8BF)
    static let shadow = Color.black.opacity(0.06)
    static let softShadow = Color.black.opacity(0.035)

    static let ambientGradient = LinearGradient(
        colors: [
            Color(hex: 0xFFF8F1),
            Color(hex: 0xF6F1E7),
            Color(hex: 0xF7EEE2)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGlowGradient = LinearGradient(
        colors: [
            Color(hex: 0xFFE1B8),
            Color(hex: 0xFDECCC),
            Color(hex: 0xF0F5FF)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xF7A34B), Color(hex: 0xF47A1F)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroRadius: CGFloat = 30
    static let cardRadius: CGFloat = 26
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
