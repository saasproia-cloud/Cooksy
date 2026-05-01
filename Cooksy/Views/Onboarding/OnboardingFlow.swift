import SwiftUI

/// Container view that drives the entire pre-account onboarding (A1 → D1).
/// Renders the right screen for `coordinator.currentStep`, animates between
/// them with a slide+fade transition, and — once the user has authenticated —
/// pushes their draft answers to Supabase so the root router can route them
/// to the paywall (or home if they already had premium from a prior install).
struct OnboardingFlow: View {
    @StateObject private var coordinator = OnboardingCoordinator()
    @EnvironmentObject private var sessionStore: SessionStore

    /// When true we present the returning-user login screen on top of the flow.
    @State private var showingLogin: Bool = false

    /// Prevents double-writing the answers if the view reappears after auth.
    /// Persisted in UserDefaults because the OnboardingFlow gets unmounted
    /// briefly during the `.loading` window of OAuth sign-ins (Apple /
    /// Google) — when it remounts, in-memory `@State` would reset and we'd
    /// re-trigger the save unnecessarily, OR worse, the `.onChange`
    /// listener would have missed the `.signedIn` transition entirely
    /// because it happened while we were unmounted.
    @AppStorage("cooksy.onboarding.didSaveAnswers") private var didSaveAnswers: Bool = false

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            currentScreen
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .id(coordinator.currentStep)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: coordinator.currentStep)
        .fullScreenCover(isPresented: $showingLogin) {
            LoginView(
                onBack: { showingLogin = false },
                onGoToSignUp: { showingLogin = false }
            )
            .environmentObject(sessionStore)
        }
        .onChange(of: sessionStore.phase) { _, newValue in
            handlePhaseChange(newValue)
        }
        // Cover the case where Apple/Google OAuth flips the phase to
        // `.loading` then `.signedIn` while we were temporarily unmounted
        // (the root router shows `.bootstrap` during `.loading`). On
        // remount, the `.onChange` listener won't fire because the
        // current phase is the initial value — so we replay the handler
        // manually here to push the onboarding answers.
        .onAppear {
            handlePhaseChange(sessionStore.phase)
        }
    }

    // MARK: - Routing of individual screens

    @ViewBuilder
    private var currentScreen: some View {
        switch coordinator.currentStep {
        case .welcome:
            WelcomeHeroView(
                onContinue: { coordinator.next() },
                onExistingAccount: { showingLogin = true }
            )

        case .demo:
            DemoBeforeAfterView(
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .valueProof:
            ValueProofView(
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .primaryGoal:
            PrimaryGoalView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .sources:
            SourcesView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .skillLevel:
            SkillLevelView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .timeSlider:
            TimeSliderView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .frequency:
            FrequencyView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .diet:
            DietView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .allergies:
            AllergiesView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .servings:
            ServingSizeView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .cuisines:
            CuisinesGridView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .challenges:
            ChallengesView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .buildingProfile:
            ProfileBuildingView(
                onCompleted: {
                    coordinator.goTo(.personalizedPreview)
                }
            )

        case .personalizedPreview:
            PersonalizedPreviewView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .signUp:
            SignUpView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onGoToLogin: { showingLogin = true }
            )
        }
    }

    // MARK: - Auth completion handling

    /// When the SessionStore transitions to `.signedIn` during the onboarding
    /// flow, push the draft answers to Supabase so the root router moves us
    /// to the paywall. Only writes once per flow, and only if the backend
    /// hasn't already stored a completion timestamp for this account.
    private func handlePhaseChange(_ phase: SessionStore.Phase) {
        guard case .signedIn = phase, !didSaveAnswers else { return }
        didSaveAnswers = true

        Task {
            // Give SessionStore a moment to load the profile so we can decide
            // whether we actually need to push (avoid overwriting a completed
            // onboarding for a returning user who signed back in).
            try? await Task.sleep(for: .milliseconds(400))

            if sessionStore.profile?.onboardingCompletedAt == nil {
                await sessionStore.saveOnboardingAnswers(coordinator.answers)
            }

            await MainActor.run {
                coordinator.clearDraft()
                showingLogin = false
            }
        }
    }
}
