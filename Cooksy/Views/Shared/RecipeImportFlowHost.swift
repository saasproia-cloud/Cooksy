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

    var analysisTitle: String {
        switch self {
        case .video:
            return "Analyse de la vidéo"
        case .webPage:
            return "Analyse de la page"
        case .photo:
            return "Analyse de la photo"
        case .text:
            return "Analyse du texte"
        }
    }

    var loaderTitle: String {
        switch self {
        case .video:
            return "Importation de la vidéo"
        case .webPage:
            return "Importation de la recette"
        case .photo:
            return "Importation de la photo"
        case .text:
            return "Importation du texte"
        }
    }

    var initialMessage: String {
        switch self {
        case .video:
            return "Lecture de la vidéo et détection du plat…"
        case .webPage:
            return "Lecture de la page et détection du plat…"
        case .photo:
            return "Lecture de l’image et détection du plat…"
        case .text:
            return "Lecture du texte et détection du plat…"
        }
    }
}

private enum RecipeImportStepState: Equatable {
    case completed
    case active
    case pending
}

private struct RecipeImportLoadingStep: Identifiable {
    let id = UUID()
    let title: String
    let messages: [String]
}

struct RecipeImportLoadingView: View {
    let source: RecipeImportLoadingSource
    var title: String? = nil
    var showsBackdrop = true

    @State private var activeStepIndex = 0
    @State private var activeMessageIndex = 0
    @State private var iconPulse = false
    @State private var iconSpin = false
    @State private var activeGlow = false

    private var steps: [RecipeImportLoadingStep] {
        [
            RecipeImportLoadingStep(
                title: source.analysisTitle,
                messages: [
                    source.initialMessage,
                    "Détection du plat principal…",
                    "Nettoyage des données importées…"
                ]
            ),
            RecipeImportLoadingStep(
                title: "Extraction des ingrédients",
                messages: [
                    "Extraction des ingrédients détectés…",
                    "Nettoyage des quantités et des unités…",
                    "Préparation d’une liste propre pour Cooksy…"
                ]
            ),
            RecipeImportLoadingStep(
                title: "Génération de la recette",
                messages: [
                    "Assemblage des étapes de cuisson…",
                    "Organisation de la recette finale…",
                    "Préparation d’une fiche claire et enregistrable…"
                ]
            ),
            RecipeImportLoadingStep(
                title: "Calcul nutritionnel",
                messages: [
                    "Calcul des macros…",
                    "Estimation des calories et portions…",
                    "Finalisation de la recette…"
                ]
            )
        ]
    }

    private var currentMessage: String {
        let step = steps[min(activeStepIndex, steps.count - 1)]
        let messageIndex = min(activeMessageIndex, step.messages.count - 1)
        return step.messages[messageIndex]
    }

    private var completedSteps: Int {
        min(activeStepIndex, max(steps.count - 1, 0))
    }

    private var progressValue: Double {
        let totalSteps = max(Double(steps.count), 1)
        let completed = Double(completedSteps)
        let partial = activeStepIndex < steps.count - 1 ? Double(activeMessageIndex + 1) / Double(max(steps[activeStepIndex].messages.count, 1)) : 1
        return min((completed + partial) / totalSteps, 1)
    }

    var body: some View {
        ZStack {
            if showsBackdrop {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 14) {
                header
                progressBar
                stepList
                previewSection
            }
            .padding(18)
            .frame(maxWidth: 344)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                CooksyTheme.elevatedSurface.opacity(0.98),
                                CooksyTheme.surface.opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 28, y: 14)
            .padding(.horizontal, 24)
        }
        .task {
            await runProgressLoop()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                iconPulse = true
                activeGlow = true
            }

            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                iconSpin = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.blush)
                    .frame(width: 66, height: 66)
                    .scaleEffect(iconPulse ? 1.04 : 0.96)

                Circle()
                    .trim(from: 0.08, to: 0.78)
                    .stroke(
                        CooksyTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(iconSpin ? 360 : 0))
                    .opacity(activeGlow ? 1 : 0.72)

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? source.loaderTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(currentMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineSpacing(2)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progression")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .tracking(0.6)

                Spacer(minLength: 0)

                Text("\(min(activeStepIndex + 1, steps.count))/\(steps.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.stroke.opacity(0.55))

                    Capsule(style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                        .frame(width: max(24, proxy.size.width * progressValue))
                }
            }
            .frame(height: 8)
        }
    }

    private var stepList: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 12) {
                    RecipeImportStepStatusIcon(state: state(for: index))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text(statusText(for: index))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(stepRowBackground(for: index))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stepRowBorder(for: index), lineWidth: 1)
                )
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Aperçu en préparation")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Spacer(minLength: 0)

                Text("Bientôt visible")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CooksyTheme.warmCard.opacity(0.55))
                    .frame(width: 84, height: 84)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.35))
                    )

                VStack(alignment: .leading, spacing: 10) {
                    skeletonLine(width: 148, height: 14)
                    skeletonLine(width: 104, height: 12)

                    HStack(spacing: 8) {
                        skeletonCapsule(width: 58)
                        skeletonCapsule(width: 72)
                        skeletonCapsule(width: 52)
                    }

                    VStack(spacing: 7) {
                        skeletonLine(width: 164, height: 10)
                        skeletonLine(width: 142, height: 10)
                    }
                }
            }

            HStack(spacing: 10) {
                skeletonMacro(color: CooksyTheme.ctaOrange)
                skeletonMacro(color: CooksyTheme.sparkleYellow)
                skeletonMacro(color: CooksyTheme.brandBlue)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func state(for index: Int) -> RecipeImportStepState {
        if index < activeStepIndex {
            return .completed
        }
        if index == activeStepIndex {
            return .active
        }
        return .pending
    }

    private func statusText(for index: Int) -> String {
        switch state(for: index) {
        case .completed:
            return "Terminé"
        case .active:
            return "En cours"
        case .pending:
            return "En attente"
        }
    }

    private func stepRowBackground(for index: Int) -> Color {
        switch state(for: index) {
        case .completed:
            return CooksyTheme.softCloud.opacity(0.45)
        case .active:
            return CooksyTheme.blush.opacity(0.75)
        case .pending:
            return Color.white.opacity(0.72)
        }
    }

    private func stepRowBorder(for index: Int) -> Color {
        switch state(for: index) {
        case .completed:
            return CooksyTheme.brandBlue.opacity(0.2)
        case .active:
            return CooksyTheme.ctaOrange.opacity(0.22)
        case .pending:
            return CooksyTheme.stroke
        }
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }

    private func skeletonCapsule(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.78))
            .frame(width: width, height: 24)
    }

    private func skeletonMacro(color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 10, height: 10)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func runProgressLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.05))
            guard !Task.isCancelled else { break }

            await MainActor.run {
                let currentMessages = steps[activeStepIndex].messages
                if activeMessageIndex < currentMessages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        activeMessageIndex += 1
                    }
                } else if activeStepIndex < steps.count - 1 {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        activeStepIndex += 1
                        activeMessageIndex = 0
                    }
                } else {
                    activeMessageIndex = (activeMessageIndex + 1) % currentMessages.count
                }
            }
        }
    }
}

private struct RecipeImportStepStatusIcon: View {
    let state: RecipeImportStepState

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch state {
            case .completed:
                Circle()
                    .fill(CooksyTheme.brandBlue)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

            case .active:
                Circle()
                    .fill(CooksyTheme.ctaOrange.opacity(0.12))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulse ? 1.08 : 0.92)

                Circle()
                    .stroke(CooksyTheme.ctaOrange.opacity(0.18), lineWidth: 3)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0.1, to: 0.72)
                    .stroke(
                        CooksyTheme.ctaOrange,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))

            case .pending:
                Circle()
                    .stroke(CooksyTheme.stroke, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
        .onAppear {
            startAnimationsIfNeeded()
        }
        .onChange(of: state) { _, _ in
            startAnimationsIfNeeded()
        }
    }

    private func startAnimationsIfNeeded() {
        guard state == .active else {
            spin = false
            pulse = false
            return
        }

        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            spin = true
        }

        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
