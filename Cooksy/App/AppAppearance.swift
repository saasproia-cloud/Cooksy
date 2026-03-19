import SwiftUI
import UIKit

enum AppAppearance {
    @MainActor
    static func configure() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor(hex: 0xFFFDF9, alpha: 0.96)
        tabBarAppearance.shadowColor = UIColor(hex: 0xE4D7C2)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0x9B9488)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0xFF7A12)
        ]

        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(hex: 0x9B9488)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(hex: 0xFF7A12)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        UIScrollView.appearance().keyboardDismissMode = .interactive
    }
}
