import SwiftUI
import UIKit

private enum QuickImportPhotoSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var pickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }
}

private enum ImportRetrySource {
    case browser
    case pasteText
    case photo
}

private struct RecipeImportFlowHost: ViewModifier {
    @EnvironmentObject private var recipeStore: RecipeStore
    @StateObject private var quota = ImportQuotaService.shared

    @Binding var isPresented: Bool
    let preferredBookID: RecipeBook.ID?

    @State private var showsCreateRecipe = false
    @State private var showsPasteTextImport = false
    @State private var showsBrowserImport = false
    @State private var showsPhotoSourceDialog = false
    @State private var showsCameraUnavailableAlert = false
    @State private var activePhotoImportSource: QuickImportPhotoSource?
    @State private var browserImportInitialURL: URL?
    @State private var isProcessingPhotoImport = false
    @State private var createRecipeSeed: RecipeEditorSeed?
    @State private var importReviewAssessment: RecipeImportAssessment?
    @State private var importFailureAssessment: RecipeImportAssessment?
    @State private var importFailureRetrySource: ImportRetrySource?
    @State private var lastPastedText: String = ""
    @State private var showsQuotaReachedSheet = false
    @State private var showsPaywallFromQuota = false

    // --- Save-reminder toast (import abandoned without saving) ---
    /// The assessment the user was reviewing — kept so the toast's
    /// "Enregistrer" button can re-open the exact same recipe.
    @State private var lastReviewAssessment: RecipeImportAssessment?
    /// Set to true by the review screen's onSaved callback. When the
    /// review closes with this still false, the import was abandoned.
    @State private var importReviewWasSaved = false
    /// Drives the toast visibility.
    @State private var showsSaveReminderToast = false
    /// How many times this same import has been abandoned — each repeat
    /// shows the toast for a shorter duration.
    @State private var saveReminderRepeatCount = 0
    /// Cancellable handle for the toast's auto-dismiss timer.
    @State private var saveReminderDismissTask: Task<Void, Never>?

    /// Closes the import options sheet, then surfaces `QuotaReachedSheet`.
    /// Used when a free user taps an AI-powered option (e.g. "Texte collé")
    /// while their weekly quota is exhausted — we catch it the instant the
    /// option is tapped, so the user never reaches the paste screen only to
    /// be blocked at save time (which felt punishing).
    private func presentQuotaReachedSheet() {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showsQuotaReachedSheet = true
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showsQuotaReachedSheet) {
                QuotaReachedSheet(
                    onUpgrade: {
                        showsQuotaReachedSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showsPaywallFromQuota = true
                        }
                    },
                    onDismiss: {
                        showsQuotaReachedSheet = false
                    }
                )
            }
            .fullScreenCover(isPresented: $showsPaywallFromQuota) {
                NavigationStack {
                    PremiumPaywallView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { showsPaywallFromQuota = false }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(CooksyTheme.primaryText)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(CooksyTheme.elevatedSurface))
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $isPresented) {
                QuickImportSheetView(
                    // "Depuis zéro" never costs an éclair, so it stays
                    // available even at the weekly limit. AI-powered options
                    // are gated below via `canImport`.
                    canImport: quota.canImport,
                    onCreateFromScratch: {
                        createRecipeSeed = nil
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsCreateRecipe = true
                        }
                    },
                    onBrowserImport: {
                        browserImportInitialURL = nil
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsBrowserImport = true
                        }
                    },
                    onCameraImport: {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsPhotoSourceDialog = true
                        }
                    },
                    onPasteText: {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showsPasteTextImport = true
                        }
                    },
                    onQuotaReached: presentQuotaReachedSheet
                )
            }
            .confirmationDialog(
                "Importer une image",
                isPresented: $showsPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Prendre une photo") {
                    presentPhotoImport(for: .camera)
                }

                Button("Choisir dans la galerie") {
                    presentPhotoImport(for: .photoLibrary)
                }

                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Choisissez votre source pour démarrer une recette à partir d'une photo.")
            }
            .alert("Appareil photo indisponible", isPresented: $showsCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("La caméra n'est pas disponible sur cet appareil. Vous pouvez choisir une image depuis la galerie.")
            }
            .sheet(item: $activePhotoImportSource) { source in
                SystemImagePicker(sourceType: source.pickerSourceType) { data in
                    handleImportedImage(data)
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showsBrowserImport) {
                BrowserImportView(initialURL: browserImportInitialURL) { assessment in
                    showsBrowserImport = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        presentImportedAssessment(assessment, retrySource: .browser)
                    }
                }
            }
            .fullScreenCover(isPresented: $showsPasteTextImport) {
                PasteTextImportView(initialText: lastPastedText) { text, assessment in
                    lastPastedText = text
                    showsPasteTextImport = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        presentImportedAssessment(assessment, retrySource: .pasteText)
                    }
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { importReviewAssessment != nil },
                    set: { if !$0 { importReviewAssessment = nil } }
                ),
                onDismiss: {
                    importReviewAssessment = nil
                    // If the review closed without a save, surface the
                    // "1 éclair utilisé" reminder so the user can jump
                    // straight back in and keep the recipe.
                    if !importReviewWasSaved {
                        triggerSaveReminderToast()
                    }
                }
            ) {
                if let reviewAssessment = importReviewAssessment {
                    ImportedRecipeReviewView(
                        store: recipeStore,
                        seed: reviewAssessment.seed,
                        validation: reviewAssessment.validation,
                        preferredBookID: preferredBookID,
                        onSaved: { _ in importReviewWasSaved = true }
                    )
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { importFailureAssessment != nil },
                    set: { if !$0 { importFailureAssessment = nil } }
                ),
                onDismiss: {
                    importFailureAssessment = nil
                    importFailureRetrySource = nil
                }
            ) {
                if let failureAssessment = importFailureAssessment {
                    RecipeImportFailureView(
                        store: recipeStore,
                        seed: failureAssessment.seed,
                        preferredBookID: preferredBookID,
                        source: failureSource(for: importFailureRetrySource),
                        context: OopsContext.from(
                            seed: failureAssessment.seed,
                            source: failureSource(for: importFailureRetrySource),
                            onRetry: retryLastImport,
                            onCancel: {
                                importFailureAssessment = nil
                                importFailureRetrySource = nil
                            },
                            onCreateManually: {
                                importFailureAssessment = nil
                                importFailureRetrySource = nil
                            }
                        )
                    )
                }
            }
            .fullScreenCover(isPresented: $showsCreateRecipe, onDismiss: {
                createRecipeSeed = nil
            }) {
                CreateRecipeView(
                    store: recipeStore,
                    seed: createRecipeSeed,
                    preferredBookID: preferredBookID
                )
            }
            .overlay {
                if isProcessingPhotoImport {
                    RecipeImportProcessingOverlay(
                        source: .photo
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if showsSaveReminderToast {
                    ImportSaveReminderToast(
                        onReturn: returnToAbandonedReview,
                        onClose: dismissSaveReminderToast
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private func presentPhotoImport(for source: QuickImportPhotoSource) {
        guard source != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showsCameraUnavailableAlert = true
            return
        }

        activePhotoImportSource = source
    }

    private func handleImportedImage(_ data: Data?) {
        activePhotoImportSource = nil

        guard let data else { return }

        isProcessingPhotoImport = true

        Task {
            let assessment = await RecipeImportPipeline.importPhotoAssessment(from: data)

            await MainActor.run {
                isProcessingPhotoImport = false
                presentImportedAssessment(assessment, retrySource: .photo)
            }
        }
    }

    private func presentImportedAssessment(
        _ assessment: RecipeImportAssessment,
        retrySource: ImportRetrySource
    ) {
        browserImportInitialURL = assessment.seed.sourceURL
        importFailureRetrySource = retrySource

        if assessment.validation.isRejected {
            importFailureAssessment = assessment
        } else {
            // A fresh import — clear any lingering save-reminder toast
            // and reset the abandon tracking for this new recipe.
            dismissSaveReminderToast()
            saveReminderRepeatCount = 0
            lastReviewAssessment = assessment
            importReviewWasSaved = false
            importReviewAssessment = assessment
        }
    }

    /// Shows the "recipe not saved — 1 éclair used" toast and schedules
    /// its auto-dismiss. Each repeat for the same import is shown for a
    /// shorter time (7 s → 4 s → 2.5 s) so it nags less aggressively.
    private func triggerSaveReminderToast() {
        guard lastReviewAssessment != nil else { return }
        saveReminderRepeatCount += 1

        let duration: Double
        switch saveReminderRepeatCount {
        case 1: duration = 7.0
        case 2: duration = 4.0
        default: duration = 2.5
        }

        saveReminderDismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showsSaveReminderToast = true
        }
        saveReminderDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showsSaveReminderToast = false
            }
        }
    }

    private func dismissSaveReminderToast() {
        saveReminderDismissTask?.cancel()
        saveReminderDismissTask = nil
        if showsSaveReminderToast {
            withAnimation(.easeInOut(duration: 0.3)) {
                showsSaveReminderToast = false
            }
        }
    }

    /// "Enregistrer" button on the toast — re-opens the exact recipe the
    /// user was reviewing so they can save it.
    private func returnToAbandonedReview() {
        guard let assessment = lastReviewAssessment else { return }
        dismissSaveReminderToast()
        importReviewWasSaved = false
        importReviewAssessment = assessment
    }

    private func failureSource(for retrySource: ImportRetrySource?) -> RecipeImportSourceKind {
        switch retrySource {
        case .pasteText: return .text
        case .photo: return .photo
        case .browser: return .url
        case nil: return .url
        }
    }

    private func retryLastImport() {
        let retrySource = importFailureRetrySource
        let retryURL = importFailureAssessment?.seed.sourceURL

        importFailureAssessment = nil
        importFailureRetrySource = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch retrySource {
            case .browser:
                browserImportInitialURL = retryURL
                showsBrowserImport = true
            case .pasteText:
                showsPasteTextImport = true
            case .photo:
                showsPhotoSourceDialog = true
            case nil:
                break
            }
        }
    }
}

private struct RecipeImportProcessingOverlay: View {
    let source: RecipeImportLoadingSource

    var body: some View {
        RecipeImportLoadingView(source: source)
    }
}

/// Toast shown when the user closes the import review without saving.
/// Reminds them the import already cost 1 éclair and offers a one-tap
/// way back to the recipe.
private struct ImportSaveReminderToast: View {
    let onReturn: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.ctaOrangeDark.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Recette non enregistrée")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("1 éclair a déjà été utilisé pour cet import.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onReturn) {
                Text("Enregistrer")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule(style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.primaryText.opacity(0.96))
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }
}

extension View {
    func recipeImportFlow(
        isPresented: Binding<Bool>,
        preferredBookID: RecipeBook.ID? = nil
    ) -> some View {
        modifier(RecipeImportFlowHost(isPresented: isPresented, preferredBookID: preferredBookID))
    }
}

enum RecipeImportLoadingSource {
    case video
    case webPage
    case photo
    case text
}

// MARK: - Animated Noodle Bowl

private struct AnimatedNoodleBowl: View {
    @State private var floatOffset: CGFloat = 0
    @State private var chopstickAngle: Double = 0
    @State private var noodleLift: CGFloat = 0
    @State private var steamPhase: CGFloat = 0

    private let bowlSize: CGFloat = 90

    var body: some View {
        ZStack {
            // Steam particles
            ForEach(0..<3, id: \.self) { i in
                SteamParticle(delay: Double(i) * 0.6, phase: steamPhase)
            }

            // Bowl emoji base
            Text("🍜")
                .font(.system(size: 72))

            // Animated chopsticks + noodle strand
            ChopsticksView(angle: chopstickAngle, noodleLift: noodleLift)
                .offset(x: 8, y: -20)
        }
        .offset(y: floatOffset)
        .onAppear {
            // Gentle float
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
            // Steam
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                steamPhase = 1
            }
            // Chopstick pick cycle
            startChopstickCycle()
        }
    }

    private func startChopstickCycle() {
        // Phase 1: open chopsticks and dip down
        withAnimation(.easeInOut(duration: 0.6)) {
            chopstickAngle = 8
            noodleLift = 0
        }

        // Phase 2: close and lift noodles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeInOut(duration: 0.5)) {
                chopstickAngle = 2
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.8)) {
                noodleLift = -18
                chopstickAngle = 0
            }
        }

        // Phase 3: release and reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeIn(duration: 0.4)) {
                noodleLift = 0
                chopstickAngle = 3
            }
        }

        // Repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            startChopstickCycle()
        }
    }
}

private struct ChopsticksView: View {
    let angle: Double
    let noodleLift: CGFloat

    var body: some View {
        ZStack {
            // Noodle strands being lifted
            NoodleStrands(lift: noodleLift)
                .offset(y: min(noodleLift + 6, 0))

            // Left chopstick
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x8B6914), Color(hex: 0xC49A3C)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3.5, height: 50)
                .rotationEffect(.degrees(-15 - angle), anchor: .top)
                .offset(x: -4, y: -14)

            // Right chopstick
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x8B6914), Color(hex: 0xC49A3C)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3.5, height: 50)
                .rotationEffect(.degrees(-15 + angle), anchor: .top)
                .offset(x: 4, y: -14)
        }
    }
}

private struct NoodleStrands: View {
    let lift: CGFloat

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let startY = size.height * 0.55
            let strands: [(CGFloat, CGFloat)] = [(-6, 0.8), (0, 1.0), (5, 0.7)]

            for (offsetX, opacity) in strands {
                var path = Path()
                path.move(to: CGPoint(x: cx + offsetX, y: startY))
                // Wavy noodle strand
                let endY = startY + 16
                path.addCurve(
                    to: CGPoint(x: cx + offsetX + 2, y: endY),
                    control1: CGPoint(x: cx + offsetX + 5, y: startY + 5),
                    control2: CGPoint(x: cx + offsetX - 4, y: startY + 11)
                )
                context.opacity = lift < -2 ? opacity : 0
                context.stroke(
                    path,
                    with: .color(Color(hex: 0xF5DEB3)),
                    lineWidth: 2.2
                )
            }
        }
        .frame(width: 40, height: 40)
    }
}

private struct SteamParticle: View {
    let delay: Double
    let phase: CGFloat

    @State private var opacity: Double = 0
    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0

    private var randomX: CGFloat {
        CGFloat([-8, 0, 7][Int(delay / 0.6) % 3])
    }

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.15))
            .frame(width: 8, height: 8)
            .blur(radius: 3)
            .offset(x: randomX + xOffset, y: -50 + yOffset)
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    startSteamLoop()
                }
            }
    }

    private func startSteamLoop() {
        // Reset
        opacity = 0
        yOffset = 0
        xOffset = 0

        // Animate up and fade
        withAnimation(.easeOut(duration: 1.8)) {
            opacity = 0.6
            yOffset = -20
            xOffset = CGFloat.random(in: -4...4)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.8)) {
                opacity = 0
                yOffset = -30
            }
        }
        // Repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            startSteamLoop()
        }
    }
}

// MARK: - Recipe Import Loading View

struct RecipeImportLoadingView: View {
    let source: RecipeImportLoadingSource
    var title: String? = nil
    var showsBackdrop = true

    @State private var activeStepIndex: Int = 0
    @State private var animationActive: Bool = false
    @State private var progressPhase: CGFloat = 0
    @State private var sparklePhase: CGFloat = 0

    private let steps: [LoadingStep] = [
        LoadingStep(icon: "doc.text.magnifyingglass", title: "Lecture du contenu", subtitle: "On parcourt ta recette mot par mot."),
        LoadingStep(icon: "sparkles", title: "Identification du plat", subtitle: "On reconnaît ce que tu veux cuisiner."),
        LoadingStep(icon: "leaf.fill", title: "Extraction des ingrédients", subtitle: "On note quantités, unités et marques."),
        LoadingStep(icon: "list.number", title: "Mise en forme des étapes", subtitle: "On organise tout dans le bon ordre."),
        LoadingStep(icon: "flame.fill", title: "Calcul nutritionnel", subtitle: "On estime calories, protéines, glucides, lipides.")
    ]

    var body: some View {
        ZStack {
            if showsBackdrop {
                ZStack {
                    CooksyTheme.backgroundCalm
                    backdropGradient
                    sparkleLayer
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 26) {
                Spacer(minLength: 0)

                heroBlock

                contentCard

                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .task {
            await runLoadingChoreography()
        }
    }

    // MARK: Hero block

    private var heroBlock: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CooksyTheme.primaryAccent.opacity(0.32),
                                CooksyTheme.primaryAccent.opacity(0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 140
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 12)

                AnimatedNoodleBowl()
                    .frame(width: 130, height: 130)
            }

            VStack(spacing: 8) {
                Text("On compose ta recette…")
                    .font(.system(size: 26, weight: .heavy, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Détends-toi, on s'occupe de tout. Quelques secondes seulement.")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Content card (steps + progress)

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Text("IA Cooksy en cours")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Spacer(minLength: 0)
                Text("\(activeStepDisplay) / \(steps.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            stepList

            progressBar
                .padding(.top, 2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 24, y: 12)
    }

    private var stepList: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                stepRow(step: step, index: index)
            }
        }
    }

    private func stepRow(step: LoadingStep, index: Int) -> some View {
        let state = stepState(for: index)
        return HStack(spacing: 12) {
            stepIconView(step: step, state: state)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.system(size: 13.5, weight: state == .active ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(state == .pending ? CooksyTheme.secondaryText : CooksyTheme.primaryText)
                Text(step.subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(state == .pending ? 0.55 : 0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .opacity(state == .pending ? 0.7 : 1)
        .animation(.easeInOut(duration: 0.35), value: state)
    }

    @ViewBuilder
    private func stepIconView(step: LoadingStep, state: StepState) -> some View {
        ZStack {
            Circle()
                .fill(
                    state == .pending
                        ? AnyShapeStyle(CooksyTheme.dividerSubtle)
                        : AnyShapeStyle(CooksyTheme.accentGradient)
                )
                .frame(width: 34, height: 34)

            if state == .active {
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .scaleEffect(animationActive ? 1.15 : 1)
                    .opacity(animationActive ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: animationActive)
            }

            Image(systemName: step.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(state == .pending ? CooksyTheme.secondaryText : Color.white)
                .symbolEffect(.pulse, options: .repeating, isActive: state == .active)
        }
        .shadow(color: state == .pending ? .clear : CooksyTheme.primaryAccent.opacity(0.25), radius: 6, y: 3)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(CooksyTheme.dividerSubtle.opacity(0.6))

                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: max(18, proxy.size.width * progressPhase))
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 6, y: 2)
            }
        }
        .frame(height: 6)
        .padding(.top, 6)
    }

    // MARK: Background ornamentation

    private var backdropGradient: some View {
        LinearGradient(
            colors: [
                CooksyTheme.primaryAccentSoft.opacity(0.35),
                Color.clear,
                CooksyTheme.warmCard.opacity(0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blur(radius: 30)
    }

    private var sparkleLayer: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill(CooksyTheme.primaryAccent.opacity(0.22))
                        .frame(width: 4, height: 4)
                        .blur(radius: 0.5)
                        .position(
                            x: sparklePosition(index: i, width: proxy.size.width).x,
                            y: sparklePosition(index: i, width: proxy.size.width).y - sparklePhase * 80
                        )
                        .opacity(1 - Double(sparklePhase) * 0.8)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sparklePosition(index: Int, width: CGFloat) -> CGPoint {
        let seeds: [(CGFloat, CGFloat)] = [
            (0.10, 0.20), (0.30, 0.55), (0.45, 0.15), (0.55, 0.75),
            (0.70, 0.30), (0.82, 0.62), (0.18, 0.80), (0.92, 0.45)
        ]
        let seed = seeds[index % seeds.count]
        return CGPoint(x: width * seed.0, y: 900 * seed.1)
    }

    // MARK: State helpers

    private enum StepState {
        case done, active, pending
    }

    private func stepState(for index: Int) -> StepState {
        if index < activeStepIndex { return .done }
        if index == activeStepIndex { return .active }
        return .pending
    }

    private var activeStepDisplay: Int {
        min(activeStepIndex + 1, steps.count)
    }

    // MARK: Animation choreography

    private func runLoadingChoreography() async {
        animationActive = true

        // Progress bar advances smoothly to 92% over ~16s, capped so the
        // bar never appears stuck at 100% if the import keeps running.
        withAnimation(.easeOut(duration: 16)) {
            progressPhase = 0.92
        }

        // Sparkle loop drifts upward continuously.
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            sparklePhase = 1
        }

        // Each step gets ~3.2 s — total ~16s, which matches the
        // observed median import duration. Real completion will
        // unmount this view, no need to hard-cap.
        for index in 0..<steps.count {
            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    activeStepIndex = index
                }
            }
            try? await Task.sleep(for: .seconds(3.2))
            if Task.isCancelled { return }
        }
        // After the last "advance", mark everything done.
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                activeStepIndex = steps.count
            }
        }
    }
}

private struct LoadingStep {
    let icon: String
    let title: String
    let subtitle: String
}
