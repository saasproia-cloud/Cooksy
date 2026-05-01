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

    /// Returns `true` if the local Supabase session looks like it
    /// belongs to a returning user (we've persisted at least one
    /// authenticated bootstrap previously). Cheap UserDefaults read —
    /// safe to call from view-builders.
    fileprivate static var hasPersistedReturningUserHint: Bool {
        UserDefaults.standard.bool(forKey: "cooksy.session.hasReachedAuthenticated")
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
    /// Latched the first time we successfully route a signed-in user to
    /// a post-onboarding destination (paywall / tutorial / home). On
    /// subsequent app launches it tells the router "this user has
    /// already cleared onboarding before — don't flash the welcome
    /// screen while we wait for the profile row to come back from
    /// Supabase." Without this latch, returning users see a brief
    /// welcome flicker every cold start.
    @AppStorage("cooksy.session.hasReachedAuthenticated") private var hasReachedAuthenticated: Bool = false
    /// Observe the offers service so the router re-renders when the user
    /// taps the paywall close button — `chooseFreeMode()` flips
    /// `userChoseFreeMode` to true, which the destination resolver reads
    /// to route to `.home` instead of `.paywall`. Without this observer
    /// the value would change but the router wouldn't notice.
    @StateObject private var offers = PremiumOffersService.shared

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
                PremiumPaywallView()
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
            // Profile row may still be loading from Supabase right
            // after a cold start. For returning users we KNOW they've
            // cleared onboarding before (the latched
            // `hasReachedAuthenticated` flag tells us so) — so we keep
            // them on the silent `.bootstrap` screen instead of
            // flashing the welcome flow while we wait. For brand-new
            // signups the latch is still false → we fall back to
            // `.onboarding` so the OnboardingFlow can react to the
            // phase change and push the draft answers.
            guard let profile = sessionStore.profile else {
                return hasReachedAuthenticated ? .bootstrap : .onboarding
            }
            if profile.onboardingCompletedAt == nil { return .onboarding }
            // Users who explicitly closed the paywall (X button) get into
            // the home tab in free mode, with the gift + quota badge visible
            // there. They can upgrade any time from the badge.
            let resolved: Destination
            if !profile.isPremium {
                resolved = offers.userChoseFreeMode ? .home : .paywall
            } else if !hasSeenTutorial {
                resolved = .tutorial
            } else {
                resolved = .home
            }
            // Latch on every successful authenticated resolution so a
            // future cold start skips the welcome flicker.
            if !hasReachedAuthenticated {
                DispatchQueue.main.async { hasReachedAuthenticated = true }
            }
            return resolved
        }
    }

    private enum Destination: Equatable {
        case bootstrap, onboarding, paywall, tutorial, home
    }
}
