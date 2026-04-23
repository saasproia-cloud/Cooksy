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
    @StateObject private var sessionStore = SessionStore()
    private let sharedLinkInbox = SharedLinkInbox()

    init() {
        AppAppearance.configure()
        IngredientVisualCatalog.preload()
    }

    var body: some Scene {
        WindowGroup {
            RootRouter(sharedLinkInbox: sharedLinkInbox, appDelegate: appDelegate)
                .environmentObject(recipeStore)
                .environmentObject(sessionStore)
                .task {
                    await sessionStore.bootstrap()
                }
                .preferredColorScheme(.light)
        }
    }
}

/// Top-level route switch that decides whether to show the splash, the full
/// onboarding, the paywall, or the authenticated tab bar.
/// Reacts to `SessionStore.phase`, `profile.onboardingCompletedAt` and
/// `profile.isPremium` — each of which is `@Published`, so transitioning
/// between states is automatic.
private struct RootRouter: View {
    let sharedLinkInbox: SharedLinkInbox
    let appDelegate: CooksyAppDelegate

    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("cooksy.hasSeenTutorial") private var hasSeenTutorial: Bool = false

    var body: some View {
        Group {
            switch destination {
            case .splash:
                SplashView()
                    .transition(.opacity)

            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)

            case .paywall:
                PaywallView()
                    .transition(.opacity)

            case .tutorial:
                PostPaywallTutorialView()
                    .transition(.opacity)

            case .home:
                RootTabView(sharedLinkInbox: sharedLinkInbox, appDelegate: appDelegate)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: destination)
    }

    /// Resolves the current routing decision from session state.
    /// Order matters: loading trumps everything; signed-out goes to onboarding;
    /// once signed in we gate on onboarding completion, then on premium, then
    /// on the first-run tutorial (device-local flag).
    private var destination: Destination {
        switch sessionStore.phase {
        case .loading:
            return .splash

        case .signedOut:
            return .onboarding

        case .signedIn:
            // Profile row may still be loading — stay on splash rather than
            // flashing through paywall if we don't know the state yet.
            guard let profile = sessionStore.profile else { return .splash }
            if profile.onboardingCompletedAt == nil { return .onboarding }
            if !profile.isPremium { return .paywall }
            if !hasSeenTutorial { return .tutorial }
            return .home
        }
    }

    private enum Destination: Equatable {
        case splash, onboarding, paywall, tutorial, home
    }
}
