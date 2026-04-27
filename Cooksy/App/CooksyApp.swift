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

    /// True until the launch video (`SplashVideo.mp4` / `Cooksy-2.mp4`) has
    /// played to completion. While true, the video sits on top of whatever
    /// destination the router has resolved underneath, so the same splash
    /// plays whether the user lands on onboarding, paywall, tutorial, or home.
    @State private var showsLaunchSplash = true

    var body: some View {
        Group {
            switch destination {
            case .bootstrap:
                // While SessionStore is bootstrapping (or the profile row is
                // still loading), show nothing but the app background. The
                // native LaunchSplash image (declared in Info.plist via
                // `UILaunchScreen > UIImageName = LaunchSplash`) already
                // covers the cold-start moment, so we don't need a second
                // SwiftUI splash on top of it.
                CooksyTheme.background
                    .ignoresSafeArea()
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
        .overlay {
            if showsLaunchSplash {
                VideoSplashOverlay {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showsLaunchSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    /// Resolves the current routing decision from session state.
    /// Order matters: loading trumps everything; signed-out goes to onboarding;
    /// once signed in we gate on onboarding completion, then on premium, then
    /// on the first-run tutorial (device-local flag).
    private var destination: Destination {
        switch sessionStore.phase {
        case .loading:
            return .bootstrap

        case .signedOut:
            return .onboarding

        case .signedIn:
            // Profile row may still be loading — stay on the bootstrap
            // background rather than flashing through paywall if we don't
            // know the state yet.
            guard let profile = sessionStore.profile else { return .bootstrap }
            if profile.onboardingCompletedAt == nil { return .onboarding }
            if !profile.isPremium { return .paywall }
            if !hasSeenTutorial { return .tutorial }
            return .home
        }
    }

    private enum Destination: Equatable {
        case bootstrap, onboarding, paywall, tutorial, home
    }
}
