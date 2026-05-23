import SwiftUI
import OSLog

private enum AppTab: Hashable {
    case home
    case recipes
    case plan
    case more
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var recipeStore: RecipeStore

    let sharedLinkInbox: SharedLinkInbox
    let appDelegate: CooksyAppDelegate
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "RootSharedImport")

    @State private var selection: AppTab = .home
    @State private var showsQuickImportSheet = false
    @State private var isProcessingSharedImport = false
    @State private var currentSharedImportHostLabel = ""
    @State private var currentSharedImportIsVideo = false
    @State private var sharedImportAssessment: RecipeImportAssessment?
    @State private var sharedImportFailureAssessment: RecipeImportAssessment?
    @State private var sharedImportCreateSeed: RecipeEditorSeed?
    @State private var lastDeferredSharedImportKey: String?
    @State private var savedImportedRecipeRoute: SavedImportedRecipeRoute?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack {
                    HomeView(
                        store: recipeStore,
                        sharedLinkInbox: sharedLinkInbox,
                        openRecipesTab: { selection = .recipes },
                        openPlanTab: { selection = .plan },
                        openImportSheet: { showsQuickImportSheet = true },
                        openProfileTab: { selection = .more }
                    )
                }
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }
                .tag(AppTab.home)

                NavigationStack {
                    MealPlanView(store: recipeStore)
                }
                .tabItem {
                    Label("Menu", systemImage: "calendar")
                }
                .tag(AppTab.plan)

                NavigationStack {
                    RecipeLibraryScreen(
                        store: recipeStore,
                        sharedLinkInbox: sharedLinkInbox,
                        openImportSheet: { showsQuickImportSheet = true }
                    )
                }
                .tabItem {
                    Label("Bibliothèque", systemImage: "book.closed")
                }
                .tag(AppTab.recipes)

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profil", systemImage: "line.horizontal.3")
                }
                .tag(AppTab.more)
            }

            if !isProcessingSharedImport {
                RootQuickImportButton {
                    showsQuickImportSheet = true
                }
                .padding(.bottom, 18)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .recipeImportFlow(isPresented: $showsQuickImportSheet)
        .task {
            await processPendingSharedImportIfNeeded()
        }

        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await processPendingSharedImportIfNeeded()
            }
        }
        .onOpenURL { url in
            Task {
                await handleIncomingURL(url)
            }
        }
        .onReceive(appDelegate.$pendingURL) { pendingURL in
            guard let pendingURL else { return }
            appDelegate.consumePendingURLIfNeeded(pendingURL)
            Task {
                await handleIncomingURL(pendingURL)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { sharedImportCreateSeed != nil },
                set: { if !$0 { sharedImportCreateSeed = nil } }
            )
        ) {
            if let createSeed = sharedImportCreateSeed {
                CreateRecipeView(store: recipeStore, seed: createSeed) {
                    sharedImportCreateSeed = nil
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { sharedImportAssessment != nil },
                set: { if !$0 { sharedImportAssessment = nil } }
            )
        ) {
            if let reviewAssessment = sharedImportAssessment {
                ImportedRecipeReviewView(
                    store: recipeStore,
                    seed: reviewAssessment.seed,
                    validation: reviewAssessment.validation,
                    onSaved: { recipeID in
                        handleSharedImportSaved(recipeID: recipeID)
                    }
                )
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { sharedImportFailureAssessment != nil },
                set: { if !$0 { sharedImportFailureAssessment = nil } }
            )
        ) {
            if let failureAssessment = sharedImportFailureAssessment {
                RecipeImportFailureView(
                    store: recipeStore,
                    seed: failureAssessment.seed,
                    preferredBookID: nil,
                    context: OopsContext.from(
                        seed: failureAssessment.seed,
                        onRetry: {
                            sharedImportFailureAssessment = nil
                            Task {
                                await processPendingSharedImportIfNeeded(force: true)
                            }
                        },
                        onCancel: {
                            dismissSharedImportFailure()
                        },
                        onCreateManually: {
                            dismissSharedImportFailure()
                        }
                    )
                )
            }
        }
        .overlay {
            if isProcessingSharedImport {
                RootSharedImportOverlay(
                    hostLabel: currentSharedImportHostLabel,
                    isVideoImport: currentSharedImportIsVideo
                )
            }
        }
        .sheet(item: $savedImportedRecipeRoute) { route in
            NavigationStack {
                RecipeDetailView(store: recipeStore, recipeID: route.recipeID)
            }
        }
    }

    @MainActor
    private func processPendingSharedImportIfNeeded(
        force: Bool = false,
        preferredHandoffToken: String? = nil
    ) async {
        guard !isProcessingSharedImport else { return }
        guard let draft = await pendingSharedImport(matching: preferredHandoffToken), draft.hasPayload else {
            return
        }

        if let acknowledgementToken = preferredHandoffToken ?? draft.handoffToken {
            sharedLinkInbox.acknowledgeHandoff(acknowledgementToken)
        }

        guard force || preferredHandoffToken != nil || lastDeferredSharedImportKey != draft.dedupeKey else {
            return
        }

        selection = .recipes
        isProcessingSharedImport = true
        currentSharedImportHostLabel = draft.hostLabel
        currentSharedImportIsVideo = draft.isLikelyVideoImport
        logger.debug(
            "App started processing shared import host=\(draft.hostLabel, privacy: .public) url=\(draft.preferredImportURL?.absoluteString ?? draft.urlString ?? "(nil)", privacy: .public) sharedTextLength=\(draft.sharedText?.count ?? 0, privacy: .public)"
        )

        do {
            if try await handlePreparedSharedImportIfNeeded(draft) == false {
                let assessment = try await RecipeImportPipeline.importSharedDraftAssessment(draft)
                if assessment.validation.isRejected {
                    if shouldRouteRejectedSharedImportToReview(assessment, draft: draft) {
                        logger.notice(
                            "App shared import routed to editable review host=\(draft.hostLabel, privacy: .public) title=\(assessment.seed.normalizedTitle, privacy: .public)"
                        )
                        sharedLinkInbox.clear()
                        lastDeferredSharedImportKey = nil
                        sharedImportAssessment = assessment
                    } else {
                        logger.error(
                            "App shared import rejected host=\(draft.hostLabel, privacy: .public) reason=\(assessment.userFacingFailureMessage, privacy: .public)"
                        )
                        lastDeferredSharedImportKey = draft.dedupeKey
                        // Clear the inbox right away so killing the app while
                        // the OOPS screen is on screen doesn't replay the same
                        // failed import on the next launch (infinite loop).
                        sharedLinkInbox.clear()
                        sharedImportFailureAssessment = assessment
                    }
                } else {
                    logger.debug(
                        "App shared import ready host=\(draft.hostLabel, privacy: .public) title=\(assessment.seed.normalizedTitle, privacy: .public)"
                    )
                    sharedLinkInbox.clear()
                    lastDeferredSharedImportKey = nil
                    sharedImportAssessment = assessment
                }
            }
        } catch {
            logger.error(
                "App shared import failed host=\(draft.hostLabel, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            lastDeferredSharedImportKey = draft.dedupeKey
            // Clear the inbox right away so killing the app while the OOPS
            // screen is on screen doesn't replay the same failed import on
            // the next launch (infinite loop).
            sharedLinkInbox.clear()
            // Convert the thrown error into a synthetic failure assessment so
            // the user sees the OOPS error screen (consistent with all other
            // failure paths) instead of a generic iOS alert.
            let failureSeed = RecipeEditorSeed(
                sourceURL: draft.preferredImportURL,
                importDebug: RecipeImportDebugInfo(
                    ingredientsCount: 0,
                    stepsCount: 0,
                    strategy: "shared",
                    durationMs: 0,
                    isLikelyValid: false,
                    missing: ["ingredients", "steps"],
                    failureReason: "not_food",
                    needsReview: false
                )
            )
            sharedImportFailureAssessment = RecipeValidationService.assess(
                failureSeed,
                sourceKind: .shared
            )
        }

        currentSharedImportHostLabel = ""
        currentSharedImportIsVideo = false
        isProcessingSharedImport = false
    }

    @MainActor
    /// Best-effort routing for cooksy:// deep links coming from push
    /// notifications. Sprint 1 lands the user on the right tab; sprint 2
    /// will refine with sheet presentations (paywall, gift wheel,
    /// specific recipe detail). Anything unknown falls back to home.
    private func routeDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .home, .homeTrending:
            selection = .home
        case .importRecipe:
            selection = .home
            showsQuickImportSheet = true
        case .library, .recipe:
            selection = .recipes
        case .plan:
            selection = .plan
        case .profileSubscription, .profileStats, .gift, .paywall:
            // Paywall + gift surfaces are owned by upstream RootRouter +
            // home overlays; navigating to .more brings the user close
            // enough to those entry points. Will be refined in sprint 2.
            selection = .more
        }
    }

    private func handleIncomingURL(_ url: URL) async {
        // cooksy:// deep links from push notifications take precedence
        // over share-extension URLs. Route them through DeepLinkRouter
        // and dispatch to the matching surface. We intentionally cover
        // the high-traffic destinations only; unknown deep links fall
        // back to home so a stale push never lands the user nowhere.
        if let destination = DeepLinkRouter.destination(for: url) {
            routeDeepLink(destination)
            return
        }

        guard let openRequest = SharedImportOpenRequest(url: url) else {
            await processPendingSharedImportIfNeeded()
            return
        }

        logger.debug(
            "App received shared import URL token=\(openRequest.handoffToken ?? "(nil)", privacy: .public)"
        )

        await processPendingSharedImportIfNeeded(
            force: true,
            preferredHandoffToken: openRequest.handoffToken
        )
    }

    @MainActor
    private func pendingSharedImport(matching handoffToken: String?) async -> SharedImportDraft? {
        if handoffToken == nil {
            return sharedLinkInbox.peek()
        }

        for attempt in 0..<12 {
            if let draft = sharedLinkInbox.peek(),
               draft.hasPayload,
               draft.handoffToken == handoffToken {
                return draft
            }

            let delayMilliseconds = attempt < 4 ? 120 : 220
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        }

        return sharedLinkInbox.peek().flatMap { draft in
            guard draft.handoffToken == handoffToken else { return nil }
            return draft
        }
    }

    private func shouldRouteRejectedSharedImportToReview(
        _ assessment: RecipeImportAssessment,
        draft: SharedImportDraft
    ) -> Bool {
        let ingredientCount = assessment.seed.normalizedIngredients.count
        let stepCount = assessment.seed.normalizedSteps.count
        let hasTitle = !assessment.seed.normalizedTitle.isEmpty
        let reasons = Set(assessment.validation.rejectionReasons)

        let hasEditableStructure = (ingredientCount >= 3 && hasTitle) ||
            (ingredientCount >= 2 && stepCount >= 1) ||
            stepCount >= 2

        guard hasEditableStructure else { return false }

        if reasons.contains(.repeatedTextDetected) || reasons.contains(.ingredientLineTooLong) {
            return false
        }

        let isSocialDraft = draft.preferredImportURL.map { url in
            let host = url.host?.lowercased() ?? ""
            return host.contains("tiktok") || host.contains("instagram") || host.contains("pinterest") || host.contains("pin.it")
        } ?? false

        return isSocialDraft || !(draft.sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    @MainActor
    private func handleSharedImportSaved(recipeID: Recipe.ID) {
        sharedImportAssessment = nil
        sharedImportCreateSeed = nil
        lastDeferredSharedImportKey = nil
        selection = .recipes

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            savedImportedRecipeRoute = SavedImportedRecipeRoute(recipeID: recipeID)
        }
    }

    private func dismissSharedImportFailure() {
        sharedImportFailureAssessment = nil
        sharedImportCreateSeed = nil
        lastDeferredSharedImportKey = nil
        sharedLinkInbox.clear()
    }

    @MainActor
    private func handlePreparedSharedImportIfNeeded(_ draft: SharedImportDraft) async throws -> Bool {
        guard let preparedSeed = draft.preparedSeed, let handoffAction = draft.handoffAction else {
            return false
        }

        var hydratedSeed = preparedSeed
        if hydratedSeed.imageData == nil {
            hydratedSeed.imageData = sharedLinkInbox.imageData(for: draft.sharedImageFilename)
        }

        let assessment = RecipeValidationService.assess(hydratedSeed, sourceKind: .shared)
        sharedLinkInbox.clear()
        lastDeferredSharedImportKey = nil

        switch handoffAction {
        case .reviewInApp:
            if assessment.validation.isRejected {
                sharedImportFailureAssessment = assessment
            } else {
                sharedImportAssessment = assessment
            }

        case .saveInApp:
            if assessment.validation.canSave {
                let recipeID = await savePreparedImportedRecipe(from: assessment.seed)
                selection = .recipes
                savedImportedRecipeRoute = SavedImportedRecipeRoute(recipeID: recipeID)
            } else if assessment.validation.isRejected {
                sharedImportFailureAssessment = assessment
            } else {
                sharedImportAssessment = assessment
            }

        case .createManuallyInApp:
            // No review screen on this handoff path — debit the import
            // éclair here since the import itself succeeded.
            if !assessment.validation.isRejected {
                ImportQuotaService.shared.incrementOnSuccess()
            }
            sharedImportCreateSeed = assessment.seed
        }

        return true
    }

    @MainActor
    private func savePreparedImportedRecipe(from seed: RecipeEditorSeed) async -> Recipe.ID {
        var finalSeed = seed

        if finalSeed.imageData == nil,
           let remoteImageURL = finalSeed.remoteImageURL,
           let imageData = await RecipeWebImportService.downloadImageData(from: remoteImageURL) {
            finalSeed.imageData = imageData
        }

        let recipeID = UUID()
        let destinationBookID = recipeStore.uncategorizedBookID
        let imageURL = finalSeed.imageData.flatMap { recipeStore.storeImageData($0, for: recipeID) }
        let recipe = finalSeed.makeRecipe(
            id: recipeID,
            bookID: destinationBookID,
            imageURL: imageURL
        )
        recipeStore.addRecipe(recipe, to: destinationBookID)
        return recipeID
    }


}

private struct SharedImportOpenRequest {
    let handoffToken: String?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "cooksy",
              url.host?.lowercased() == "shared-import" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        handoffToken = components?.queryItems?.first(where: { $0.name == "handoffToken" })?.value
    }
}

private struct SavedImportedRecipeRoute: Identifiable {
    let recipeID: Recipe.ID

    var id: Recipe.ID { recipeID }
}

private struct RootQuickImportButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            OnboardingHaptics.medium()
            action()
        }) {
            ZStack {
                // Soft ambient halo
                Circle()
                    .fill(CooksyTheme.ctaOrange.opacity(0.18))
                    .frame(width: 78, height: 78)
                    .blur(radius: 6)

                // Main pill
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.7),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: CooksyTheme.ctaOrange.opacity(0.45), radius: 22, y: 12)
                    .shadow(color: Color.black.opacity(0.10), radius: 4, y: 1)

                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Importer une recette")
    }
}

private struct RootSharedImportOverlay: View {
    let hostLabel: String
    let isVideoImport: Bool

    @State private var messageIndex = 0
    @State private var floatOffset: CGFloat = 0
    @State private var progressPhase: CGFloat = 0

    private let messages = [
        "Lecture de la recette…",
        "Analyse du plat…",
        "Presque prêt…"
    ]

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("🍜")
                    .font(.system(size: 72))
                    .offset(y: floatOffset)

                VStack(spacing: 10) {
                    Text("Cooksy prépare ta recette")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Détends-toi, ça ne prend que quelques secondes")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Text(messages[messageIndex])
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: messageIndex)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.dividerSubtle)

                        Capsule(style: .continuous)
                            .fill(CooksyTheme.accentGradient)
                            .frame(width: max(24, proxy.size.width * progressPhase))
                    }
                }
                .frame(width: 200, height: 4)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 15)) {
                progressPhase = 0.92
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        messageIndex = (messageIndex + 1) % messages.count
                    }
                }
            }
        }
    }
}

