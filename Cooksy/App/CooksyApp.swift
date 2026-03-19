import SwiftUI

@main
struct CooksyApp: App {
    @StateObject private var recipeStore = RecipeStore()
    private let sharedLinkInbox = SharedLinkInbox()

    init() {
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(sharedLinkInbox: sharedLinkInbox)
                .environmentObject(recipeStore)
        }
    }
}

