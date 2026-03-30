import SwiftUI
import UIKit

@MainActor
final class CooksyAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var pendingURL: URL?

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        pendingURL = url
        return true
    }

    func consumePendingURLIfNeeded(_ url: URL) {
        guard pendingURL == url else { return }
        pendingURL = nil
    }
}

@main
struct CooksyApp: App {
    @UIApplicationDelegateAdaptor(CooksyAppDelegate.self) private var appDelegate
    @StateObject private var recipeStore = RecipeStore()
    private let sharedLinkInbox = SharedLinkInbox()

    init() {
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(sharedLinkInbox: sharedLinkInbox, appDelegate: appDelegate)
                .environmentObject(recipeStore)
        }
    }
}
