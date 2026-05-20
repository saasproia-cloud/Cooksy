import SwiftUI

/// Container view that drives the entire pre-account onboarding (A1 → D1).
/// Renders the right screen for `coordinator.currentStep`, animates between
/// them with a slide+fade transition, and — once the user has authenticated —
/// pushes their draft answers to Supabase so the root router can route them
/// to the paywall (or home if they already had premium from a prior install).
struct OnboardingFlow: View {
    @StateObject private var coordinator = OnboardingCoordinator()
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    /// Toast banner shown when the user tries to import a recipe (via the
    /// share extension) before finishing onboarding. The pending import
    /// gets cleared so it does not auto-process once they reach the home
    /// screen — the user must re-share the link.
    @State private var importBlockedBannerVisible: Bool = false

    private let sharedLinkInbox = SharedLinkInbox()

    /// Prevents double-writing the answers if the view reappears after auth.
    /// Persisted in UserDefaults because the OnboardingFlow gets unmounted
    /// briefly during the `.loading` window of OAuth sign-ins (Apple /
    /// Google) — when it remounts, in-memory `@State` would reset and we'd
    /// re-trigger the save unnecessarily, OR worse, the `.onChange`
    /// listener would have missed the `.signedIn` transition entirely
    /// because it happened while we were unmounted.
    @AppStorage("cooksy.onboarding.didSaveAnswers") private var didSaveAnswers: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            CooksyTheme.background
                .ignoresSafeArea()

            // Shared animated background — mounted ONCE here at the flow
            // level rather than per-screen. Previously each hero/interlude
            // overlaid its own `AnimatedAmbientBackground()`, which meant
            // SwiftUI ran two 30fps TimelineViews simultaneously during the
            // cross-fade `.transition()` (one fading out, one fading in) —
            // a measurable hitch on welcome → appReview → next. With the
            // background hoisted up here it persists across steps and never
            // double-renders.
            AnimatedAmbientBackground()
                .ignoresSafeArea()

            currentScreen
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .id(coordinator.currentStep)

            if importBlockedBannerVisible {
                ImportBlockedBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        // Tighter transition spring (was 0.5/0.88 → 0.38/0.92): a snappier
        // crossfade window leaves less time for stale frames during the
        // hand-off between screens.
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: coordinator.currentStep)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: importBlockedBannerVisible)
        .onChange(of: sessionStore.phase) { _, newValue in
            handlePhaseChange(newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                consumePendingImportIfAny()
            }
        }
        .onOpenURL { _ in
            consumePendingImportIfAny()
        }
        // Cover the case where Apple/Google OAuth flips the phase to
        // `.loading` then `.signedIn` while we were temporarily unmounted
        // (the root router shows `.bootstrap` during `.loading`). On
        // remount, the `.onChange` listener won't fire because the
        // current phase is the initial value — so we replay the handler
        // manually here to push the onboarding answers.
        .onAppear {
            handlePhaseChange(sessionStore.phase)
            consumePendingImportIfAny()
        }
    }

    /// If a recipe was shared via the share extension while the user is
    /// still in onboarding, drop it and show a banner explaining they have
    /// to finish onboarding first. The user must re-share the link once
    /// onboarding completes — we never auto-launch a stale import.
    private func consumePendingImportIfAny() {
        guard let draft = sharedLinkInbox.peek(), draft.hasPayload else { return }
        sharedLinkInbox.clear()
        OnboardingHaptics.selection()
        importBlockedBannerVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            importBlockedBannerVisible = false
        }
    }

    // MARK: - Routing of individual screens

    @ViewBuilder
    private var currentScreen: some View {
        switch coordinator.currentStep {
        case .welcome:
            WelcomeHeroView(
                onContinue: { coordinator.next() }
            )

        case .appReview:
            AppReviewView(
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
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

        case .lifestyleGoal:
            LifestyleGoalView(
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

        case .planningStyle:
            PlanningStyleView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .interludeNumbers:
            InterludeNumbersView(
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

        case .cookingFor:
            CookingForView(
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

        case .cookingStyle:
            CookingStyleView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .spiceLevel:
            SpiceLevelView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .interludeTestimonial:
            InterludeTestimonialView(
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .equipment:
            EquipmentView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .budget:
            BudgetView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .mealMoments:
            MealMomentsView(
                coordinator: coordinator,
                onBack: { coordinator.back() },
                onContinue: { coordinator.next() }
            )

        case .shopping:
            ShoppingView(
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

        case .photoSharing:
            PhotoSharingView(
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
                onBack: { coordinator.back() }
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
            }
        }
    }
}

private struct ImportBlockedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 36, height: 36)
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Termine d'abord ton inscription")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Tu pourras importer ta recette une fois ton compte créé. Re-partage le lien à ce moment-là.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 18, y: 8)
    }
}
