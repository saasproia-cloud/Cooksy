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

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                QuickImportSheetView(
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
                    }
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
                PasteTextImportView { assessment in
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
                }
            ) {
                if let reviewAssessment = importReviewAssessment {
                    ImportedRecipeReviewView(
                        store: recipeStore,
                        seed: reviewAssessment.seed,
                        validation: reviewAssessment.validation,
                        preferredBookID: preferredBookID
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
                        message: failureAssessment.userFacingFailureMessage,
                        preferredBookID: preferredBookID,
                        onRetry: retryLastImport,
                        onCancel: {
                            importFailureAssessment = nil
                            importFailureRetrySource = nil
                        },
                        onManualSaved: {
                            importFailureAssessment = nil
                            importFailureRetrySource = nil
                        }
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
            importReviewAssessment = assessment
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

    @State private var messageIndex = 0
    @State private var progressPhase: CGFloat = 0

    private let messages = [
        "Reading the recipe…",
        "Understanding the dish…",
        "Almost there…"
    ]

    var body: some View {
        ZStack {
            if showsBackdrop {
                CooksyTheme.backgroundCalm
                    .ignoresSafeArea()
            }

            VStack(spacing: 32) {
                Spacer()

                // Animated noodle bowl with chopsticks
                AnimatedNoodleBowl()
                    .frame(width: 120, height: 120)

                // Title + subtitle
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

                // Micro message
                Text(messages[messageIndex])
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: messageIndex)

                // Thin progress bar
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
        .task {
            await runMessageLoop()
        }
    }

    private func runMessageLoop() async {
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
