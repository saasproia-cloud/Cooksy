import SwiftUI
import UIKit

enum AppAppearance {
    @MainActor
    static func configure() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = UIColor(hex: 0xFFFDF8, alpha: 0.98)
        tabBarAppearance.shadowColor = UIColor(hex: 0xE8DCCD)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0x8A796C)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(hex: 0xEA662A)
        ]

        let appearances = [
            tabBarAppearance.stackedLayoutAppearance,
            tabBarAppearance.inlineLayoutAppearance,
            tabBarAppearance.compactInlineLayoutAppearance
        ]

        for itemAppearance in appearances {
            itemAppearance.normal.iconColor = UIColor(hex: 0x8A796C)
            itemAppearance.normal.titleTextAttributes = normalAttributes
            itemAppearance.selected.iconColor = UIColor(hex: 0xEA662A)
            itemAppearance.selected.titleTextAttributes = selectedAttributes
        }

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
