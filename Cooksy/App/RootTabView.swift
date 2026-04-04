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
    @State private var sharedImportErrorMessage = ""
    @State private var showsSharedImportError = false
    @State private var savedImportedRecipeRoute: SavedImportedRecipeRoute?
    @State private var showsLaunchSplash = true
    @State private var launchSplashHasEntered = false
    @State private var launchSplashIsLeaving = false
    @State private var showsPostSplashHero = false
    @State private var postSplashHeroHasEntered = false
    @State private var postSplashHeroIsLeaving = false

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
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

                NavigationStack {
                    MealPlanView(store: recipeStore)
                }
                .tabItem {
                    Label("Planner", systemImage: "calendar")
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
                    Label("Library", systemImage: "book.closed")
                }
                .tag(AppTab.recipes)

                NavigationStack {
                    PlaceholderView(
                        title: "Profile",
                        message: "Your account, settings and saved routines will live here soon.",
                        systemImage: "person.crop.circle"
                    )
                }
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(AppTab.more)
            }

            if !isProcessingSharedImport && !showsLaunchSplash && !showsPostSplashHero {
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
        .task {
            await playLaunchSplashIfNeeded()
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
                    message: failureAssessment.userFacingFailureMessage,
                    onRetry: {
                        sharedImportFailureAssessment = nil
                        Task {
                            await processPendingSharedImportIfNeeded(force: true)
                        }
                    },
                    onCancel: {
                        dismissSharedImportFailure()
                    },
                    onManualSaved: {
                        dismissSharedImportFailure()
                    }
                )
            }
        }
        .alert("Import partagé impossible", isPresented: $showsSharedImportError) {
            Button("Réessayer") {
                Task {
                    await processPendingSharedImportIfNeeded(force: true)
                }
            }

            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedImportErrorMessage)
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
        .overlay {
            if showsLaunchSplash {
                AppLaunchSplashOverlay(
                    hasEntered: launchSplashHasEntered,
                    isLeaving: launchSplashIsLeaving
                )
                .transition(.identity)
                .zIndex(10)
            }
        }
        .overlay {
            if showsPostSplashHero {
                AppPostSplashHeroOverlay(
                    hasEntered: postSplashHeroHasEntered,
                    isLeaving: postSplashHeroIsLeaving
                )
                .transition(.identity)
                .zIndex(9)
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
            sharedImportErrorMessage = makeSharedImportErrorMessage(for: error, hostLabel: draft.hostLabel)
            showsSharedImportError = true
        }

        currentSharedImportHostLabel = ""
        currentSharedImportIsVideo = false
        isProcessingSharedImport = false
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) async {
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

    private func makeSharedImportErrorMessage(for error: Error, hostLabel: String) -> String {
        let trimmedHost = hostLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return error.localizedDescription
        }

        return "Cooksy n'a pas reussi a importer ce partage depuis \(trimmedHost).\n\n\(error.localizedDescription)"
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

    @MainActor
    private func playLaunchSplashIfNeeded() async {
        guard showsLaunchSplash, !launchSplashHasEntered, !launchSplashIsLeaving else { return }

        withAnimation(.spring(duration: 0.72, bounce: 0.26)) {
            launchSplashHasEntered = true
        }

        try? await Task.sleep(for: .milliseconds(1250))

        guard showsLaunchSplash else { return }

        preparePostSplashHeroIfNeeded()

        withAnimation(.spring(duration: 0.78, bounce: 0.14)) {
            postSplashHeroHasEntered = true
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            launchSplashIsLeaving = true
        }

        try? await Task.sleep(for: .milliseconds(520))

        showsLaunchSplash = false
        await finishPostSplashHeroIfNeeded()
    }

    @MainActor
    private func preparePostSplashHeroIfNeeded() {
        guard !showsPostSplashHero else { return }
        showsPostSplashHero = true
        postSplashHeroHasEntered = false
        postSplashHeroIsLeaving = false
    }

    @MainActor
    private func finishPostSplashHeroIfNeeded() async {
        guard showsPostSplashHero, postSplashHeroHasEntered, !postSplashHeroIsLeaving else { return }

        try? await Task.sleep(for: .milliseconds(1180))

        guard showsPostSplashHero else { return }

        withAnimation(.easeInOut(duration: 0.45)) {
            postSplashHeroIsLeaving = true
        }

        try? await Task.sleep(for: .milliseconds(460))

        showsPostSplashHero = false
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

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 62, height: 62)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: CooksyTheme.ctaOrange.opacity(0.3), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
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
        "Reading the recipe…",
        "Understanding the dish…",
        "Almost there…"
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
                    Text("Cooksy is preparing your recipe")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Sit back, this will only take a few seconds")
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

private struct AppLaunchSplashOverlay: View {
    let hasEntered: Bool
    let isLeaving: Bool

    var body: some View {
        GeometryReader { geometry in
            splashContent(in: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(isLeaving ? 1.02 : (hasEntered ? 1 : 0.985))
                .opacity(isLeaving ? 0 : (hasEntered ? 1 : 0.82))
                .offset(y: isLeaving ? -10 : (hasEntered ? 0 : 14))
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func splashContent(in size: CGSize) -> some View {
        if UIImage(named: "LaunchSplash") != nil {
            ZStack {
                Color.white

                Image("LaunchSplash")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        } else {
            ZStack {
                SplashBackdrop()

                RadialGradient(
                    colors: [
                        Color(hex: 0xFFD46B, opacity: 0.64),
                        Color(hex: 0xFF9C33, opacity: 0)
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: min(size.width, size.height) * 0.48
                )
                .blendMode(.screen)

                VStack {
                    Spacer(minLength: 0)

                    ZStack {
                        Ellipse()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 260, height: 66)
                            .blur(radius: 22)
                            .offset(y: 170)

                        Image("HeaderLogo")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(size.width * 0.54, 350))
                            .shadow(color: Color(hex: 0xA84E14, opacity: 0.13), radius: 26, y: 16)

                        SplashSparkles()
                            .frame(width: min(size.width * 0.32, 140), height: min(size.width * 0.18, 84))
                            .offset(x: min(size.width * 0.16, 76), y: -min(size.width * 0.1, 44))
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, size.height * 0.16)
            }
        }
    }
}

private struct AppPostSplashHeroOverlay: View {
    let hasEntered: Bool
    let isLeaving: Bool

    @State private var animates = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CooksyTheme.ambientGradient
                    .ignoresSafeArea()

                Image("PostSplashHero")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .scaleEffect(animates ? 1.004 : 0.996)
                    .offset(y: animates ? -2 : 0)

                animatedHeroOverlays(in: geometry.size)
            }
            .scaleEffect(isLeaving ? 1.012 : (hasEntered ? 1 : 0.988))
            .opacity(isLeaving ? 0 : (hasEntered ? 1 : 0.78))
            .offset(y: isLeaving ? -16 : (hasEntered ? 0 : 22))
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animates = true
            }
        }
    }

    @ViewBuilder
    private func animatedHeroOverlays(in size: CGSize) -> some View {
        let clusterWidth = min(size.width * 0.47, 290)
        let clusterHeight = clusterWidth * 0.63
        let centerX = size.width * 0.5
        let centerY = size.height * 0.52

        ZStack {
            BowlBreathHalo()
                .frame(width: clusterWidth * 0.86, height: clusterHeight * 0.38)
                .offset(x: 0, y: clusterHeight * 0.18)

            BottleLiquidWave()
                .frame(width: clusterWidth * 0.15, height: clusterHeight * 0.46)
                .offset(x: clusterWidth * 0.3, y: clusterHeight * 0.04)

            ProduceFloatCluster()
                .frame(width: clusterWidth * 0.92, height: clusterHeight * 0.72)
                .offset(x: 0, y: -clusterHeight * 0.06)

            FloatingSparkPulse()
                .frame(width: clusterWidth * 0.14, height: clusterWidth * 0.14)
                .offset(x: 0, y: -clusterHeight * 0.28)

            GentleSpeckleField()
                .frame(width: clusterWidth, height: clusterHeight)
        }
        .position(x: centerX, y: centerY)
        .blendMode(.plusLighter)
    }
}

private struct BowlBreathHalo: View {
    @State private var expands = false

    var body: some View {
        Ellipse()
            .fill(Color(hex: 0xB0DC5A, opacity: 0.18))
            .blur(radius: 12)
            .scaleEffect(expands ? 1.06 : 0.92)
            .opacity(expands ? 0.18 : 0.1)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                    expands = true
                }
            }
    }
}

private struct BottleLiquidWave: View {
    @State private var phase: CGFloat = -18

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFFE97A, opacity: 0.18),
                                Color(hex: 0xFFD11A, opacity: 0.34),
                                Color(hex: 0xF6A300, opacity: 0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                WaveRibbon()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 14)
                    .offset(y: phase)
                    .blur(radius: 0.4)
            }
            .mask(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    .padding(.top, 24)
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                phase = -8
            }
        }
    }
}

private struct ProduceFloatCluster: View {
    @State private var offsetUp = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x7BCB32, opacity: 0.22))
                .frame(width: 12, height: 12)
                .offset(x: -78, y: -8)
                .offset(y: offsetUp ? -4 : 2)

            Circle()
                .fill(Color(hex: 0x8CD83F, opacity: 0.2))
                .frame(width: 9, height: 9)
                .offset(x: -62, y: -24)
                .offset(y: offsetUp ? 3 : -3)

            Circle()
                .fill(Color(hex: 0x9BE34E, opacity: 0.18))
                .frame(width: 10, height: 10)
                .offset(x: 66, y: -32)
                .offset(y: offsetUp ? -3 : 3)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 20, height: 6)
                .rotationEffect(.degrees(-22))
                .offset(x: -6, y: -68)
                .offset(y: offsetUp ? -2 : 2)

            Capsule(style: .continuous)
                .fill(Color(hex: 0xFFF9D4, opacity: 0.2))
                .frame(width: 16, height: 5)
                .rotationEffect(.degrees(16))
                .offset(x: 40, y: -18)
                .offset(y: offsetUp ? 2 : -2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                offsetUp = true
            }
        }
    }
}

private struct FloatingSparkPulse: View {
    @State private var pulses = false

    var body: some View {
        SplashSparkleShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xFF8C71), Color(hex: 0xFF5D46)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(pulses ? 1.12 : 0.92)
            .opacity(pulses ? 0.92 : 0.55)
            .shadow(color: Color(hex: 0xFF8860, opacity: 0.28), radius: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                    pulses = true
                }
            }
    }
}

private struct GentleSpeckleField: View {
    @State private var drifts = false

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color(hex: 0xA2D946, opacity: index.isMultiple(of: 2) ? 0.18 : 0.1))
                    .frame(width: index.isMultiple(of: 2) ? 7 : 5, height: index.isMultiple(of: 2) ? 7 : 5)
                    .offset(position(for: index))
                    .offset(y: drifts ? -5 : 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                drifts = true
            }
        }
    }

    private func position(for index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -96, height: -14),
            CGSize(width: -78, height: -36),
            CGSize(width: 58, height: -34),
            CGSize(width: 86, height: -18),
            CGSize(width: -24, height: -74)
        ]
        return positions[index]
    }
}

private struct WaveRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.22, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.78, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SplashBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xF78421),
                        Color(hex: 0xFF9A32),
                        Color(hex: 0xFF8A21)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "circle.hexagongrid.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(CooksyTheme.elevatedSurface.opacity(0.12))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blendMode(.overlay)

                Circle()
                    .fill(Color(hex: 0xFFE162).opacity(0.9))
                    .frame(width: geometry.size.width * 0.46, height: geometry.size.width * 0.46)
                    .blur(radius: 1.2)
                    .offset(x: -geometry.size.width * 0.37, y: geometry.size.height * 0.44)

                Circle()
                    .fill(Color(hex: 0xFFB66E).opacity(0.72))
                    .frame(width: geometry.size.width * 0.62, height: geometry.size.width * 0.62)
                    .offset(x: geometry.size.width * 0.37, y: geometry.size.height * 0.48)

                Circle()
                    .fill(Color(hex: 0xFFA342).opacity(0.88))
                    .frame(width: geometry.size.width * 0.24, height: geometry.size.width * 0.24)
                    .offset(x: geometry.size.width * 0.49, y: geometry.size.height * 0.02)

                Circle()
                    .fill(Color(hex: 0xFFD06B).opacity(0.96))
                    .frame(width: geometry.size.width * 0.28, height: geometry.size.width * 0.28)
                    .offset(x: -geometry.size.width * 0.52, y: geometry.size.height * -0.05)

                UnevenRoundedRectangle(
                    topLeadingRadius: 90,
                    bottomLeadingRadius: 68,
                    bottomTrailingRadius: 120,
                    topTrailingRadius: 52
                )
                .fill(
                    LinearGradient(
                        colors: [
                            CooksyTheme.secondaryAccent.opacity(0.96),
                            CooksyTheme.secondaryAccentStrong.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: geometry.size.width * 0.22, height: geometry.size.height * 0.18)
                .rotationEffect(.degrees(12))
                .offset(x: -geometry.size.width * 0.42, y: -geometry.size.height * 0.4)

                CheeseCorner()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFF39B), Color(hex: 0xFFE678)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.34, height: geometry.size.width * 0.34)
                    .offset(x: geometry.size.width * 0.42, y: -geometry.size.height * 0.42)

                SplashSpeckles()
            }
        }
    }
}

private struct SplashSparkles: View {
    var body: some View {
        ZStack {
            SplashSparkle(size: 54)
                .offset(x: 20, y: -18)

            SplashSparkle(size: 34)
                .offset(x: -14, y: 18)
        }
    }
}

private struct SplashSparkle: View {
    let size: CGFloat

    var body: some View {
        SplashSparkleShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xFFF7A7), Color(hex: 0xFFCF33)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                SplashSparkleShape()
                    .stroke(Color(hex: 0xFF9800), lineWidth: max(1.4, size * 0.07))
            }
            .shadow(color: Color(hex: 0xFFD54F, opacity: 0.38), radius: size * 0.18)
            .frame(width: size, height: size)
    }
}

private struct SplashSpeckles: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<18, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index.isMultiple(of: 4) ? 0.18 : 0.1))
                        .frame(
                            width: index.isMultiple(of: 3) ? 18 : 10,
                            height: index.isMultiple(of: 3) ? 18 : 10
                        )
                        .blur(radius: index.isMultiple(of: 2) ? 1.6 : 0.4)
                        .position(specklePosition(for: index, in: geometry.size))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func specklePosition(for index: Int, in size: CGSize) -> CGPoint {
        let positions: [CGPoint] = [
            CGPoint(x: size.width * 0.08, y: size.height * 0.18),
            CGPoint(x: size.width * 0.14, y: size.height * 0.28),
            CGPoint(x: size.width * 0.26, y: size.height * 0.08),
            CGPoint(x: size.width * 0.86, y: size.height * 0.12),
            CGPoint(x: size.width * 0.9, y: size.height * 0.3),
            CGPoint(x: size.width * 0.78, y: size.height * 0.35),
            CGPoint(x: size.width * 0.11, y: size.height * 0.36),
            CGPoint(x: size.width * 0.07, y: size.height * 0.44),
            CGPoint(x: size.width * 0.9, y: size.height * 0.44),
            CGPoint(x: size.width * 0.22, y: size.height * 0.53),
            CGPoint(x: size.width * 0.68, y: size.height * 0.54),
            CGPoint(x: size.width * 0.83, y: size.height * 0.6),
            CGPoint(x: size.width * 0.16, y: size.height * 0.68),
            CGPoint(x: size.width * 0.31, y: size.height * 0.75),
            CGPoint(x: size.width * 0.72, y: size.height * 0.74),
            CGPoint(x: size.width * 0.91, y: size.height * 0.8),
            CGPoint(x: size.width * 0.12, y: size.height * 0.87),
            CGPoint(x: size.width * 0.63, y: size.height * 0.9)
        ]

        return positions[index]
    }
}

private struct CheeseCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX * 0.2, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.14),
            control: CGPoint(x: rect.maxX * 0.94, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY * 0.8),
            control: CGPoint(x: rect.maxX * 0.52, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.52),
            control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY * 0.7)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.1))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.2, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.02)
        )

        path.addEllipse(in: CGRect(x: rect.width * 0.58, y: rect.height * 0.16, width: rect.width * 0.22, height: rect.height * 0.16))
        path.addEllipse(in: CGRect(x: rect.width * 0.78, y: rect.height * 0.03, width: rect.width * 0.17, height: rect.height * 0.13))
        path.addEllipse(in: CGRect(x: rect.width * 0.79, y: rect.height * 0.28, width: rect.width * 0.15, height: rect.height * 0.11))
        path.addEllipse(in: CGRect(x: rect.width * 0.57, y: rect.height * 0.43, width: rect.width * 0.19, height: rect.height * 0.12))
        path.addEllipse(in: CGRect(x: rect.width * 0.1, y: rect.height * 0.52, width: rect.width * 0.14, height: rect.height * 0.1))

        return path
    }
}

private struct SplashSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: center.x, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: center.y)
        let bottom = CGPoint(x: center.x, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: center.y)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(x: rect.maxX * 0.6, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.38)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.38),
            control2: CGPoint(x: rect.maxX * 0.6, y: rect.maxY - rect.height * 0.18)
        )
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.width * 0.4, y: rect.maxY - rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.38)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.4, y: rect.minY + rect.height * 0.18)
        )
        path.closeSubpath()
        return path
    }
}
