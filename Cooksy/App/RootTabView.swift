import SwiftUI
import OSLog
import AVKit
import AVFoundation

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
    @State private var showsVideoSplash = true

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
                    ProfileView()
                }
                .tabItem {
                    Label("Plus", systemImage: "line.horizontal.3")
                }
                .tag(AppTab.more)
            }

            if !isProcessingSharedImport && !showsVideoSplash {
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
        .alert("Import partagé impossible", isPresented: $showsSharedImportError) {
            Button("Réessayer") {
                Task {
                    await processPendingSharedImportIfNeeded(force: true)
                }
            }

            Button("OK", role: .cancel) {
                sharedLinkInbox.clear()
            }
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
            if showsVideoSplash {
                VideoSplashOverlay {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showsVideoSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
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

// MARK: - Video Splash Overlay

private struct VideoSplashOverlay: View {
    let onFinished: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player {
                VideoPlayerView(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .allowsHitTesting(true)
    }

    private func setupPlayer() {
        // Looks for a file named "SplashVideo" in the app bundle
        // Supports .mp4, .mov, .m4v formats
        let supportedExtensions = ["mp4", "mov", "m4v"]
        var videoURL: URL?

        for ext in supportedExtensions {
            if let url = Bundle.main.url(forResource: "SplashVideo", withExtension: ext) {
                videoURL = url
                break
            }
        }

        guard let url = videoURL else {
            // No video found → skip splash immediately
            onFinished()
            return
        }

        let avPlayer = AVPlayer(url: url)
        avPlayer.actionAtItemEnd = .none

        // Prevent iOS from pausing Spotify / Apple Music / podcasts while
        // the splash plays. Category `.ambient` + `.mixWithOthers` means our
        // audio (if any) mixes silently with other apps instead of taking
        // the monopoly — the default `.soloAmbient` behaviour would duck
        // whatever the user was already listening to.
        // The mp4 itself has its audio track stripped, but we stay defensive
        // in case a future replacement of SplashVideo.mp4 re-introduces one.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        avPlayer.isMuted = true
        avPlayer.volume = 0

        // Listen for video end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            onFinished()
        }

        self.player = avPlayer
        avPlayer.play()
    }
}

private struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
