import SwiftUI
import UIKit

enum AppAppearance {
    @MainActor
    static func configure() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor(hex: 0xFFF8F0, alpha: 0.98)
        tabBarAppearance.shadowColor = UIColor(hex: 0xE6D4BF)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0x7A6554)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0xEA662A)
        ]

        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(hex: 0x7A6554)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(hex: 0xEA662A)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(hex: 0x2B1A12)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(hex: 0x2B1A12)
        ]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        UIScrollView.appearance().keyboardDismissMode = .interactive
    }
}
