import SwiftUI
import UniformTypeIdentifiers
import UIKit
import OSLog

final class ShareViewController: UIViewController {
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "ShareViewController")
    private let state = ShareExtensionState()
    private let sharedLinkInbox = SharedLinkInbox()

    override func viewDidLoad() {
        super.viewDidLoad()
        embedRootView()

        Task { @MainActor in
            await importSharedContent()
        }
    }

    private func embedRootView() {
        let rootView = ShareExtensionRootView(
            state: state,
            onCancel: { [weak self] in
                self?.finishExtension()
            },
            onRetry: { [weak self] in
                Task { @MainActor in
                    await self?.importSharedContent()
                }
            },
            onModifyInApp: { [weak self] in
                Task { @MainActor in
                    await self?.openCurrentPreviewInApp(action: .reviewInApp)
                }
            },
            onSaveInApp: { [weak self] in
                Task { @MainActor in
                    await self?.openCurrentPreviewInApp(action: .saveInApp)
                }
            },
            onCreateManually: { [weak self] in
                Task { @MainActor in
                    await self?.openManualCreationInApp()
                }
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    @MainActor
    private func importSharedContent() async {
        let loadingState = ShareLoadingState(
            title: "Cooksy prépare votre recette",
            message: "Nous analysons ce partage pour reconstruire les ingrédients, les étapes et les infos utiles."
        )

        state.isPerformingAction = false
        state.phase = .loading(loadingState)

        do {
            let draft = try await extractSharedDraft()
            state.latestDraft = draft

            let preview = try await makePreview(for: draft)
            if preview.assessment.validation.isRejected {
                state.phase = .failure(
                    ShareRecipeFailure(
                        draft: draft,
                        seed: preview.assessment.seed,
                        title: "Impossible d’importer cette recette",
                        message: "Le contenu partagé ne contient pas une recette exploitable",
                        allowsRetry: true
                    )
                )
            } else {
                state.phase = .preview(preview)
            }
        } catch {
            logger.error("Share extension import failed: \(error.localizedDescription, privacy: .public)")
            let fallbackDraft = state.latestDraft
            state.phase = .failure(
                ShareRecipeFailure(
                    draft: fallbackDraft,
                    seed: fallbackDraft.map { fallbackSeed(from: $0) },
                    title: "Import impossible",
                    message: error.localizedDescription.isEmpty
                        ? "Cooksy n'a pas réussi à analyser ce partage."
                        : error.localizedDescription,
                    allowsRetry: fallbackDraft != nil
                )
            )
        }
    }

    @MainActor
    private func makePreview(for draft: SharedImportDraft) async throws -> ShareRecipePreview {
        let sharedImageData = sharedLinkInbox.imageData(for: draft.sharedImageFilename)
        var seed: RecipeEditorSeed

        if let url = draft.preferredImportURL {
            seed = try await ShareExtensionImportService.importURL(url, sharedText: draft.sharedText)
        } else if let sharedText = nonEmpty(draft.sharedText) {
            seed = try await ShareExtensionImportService.importText(sharedText, imageData: sharedImageData)
        } else if let sharedImageData {
            seed = try await ShareExtensionImportService.importPhoto(sharedImageData)
        } else {
            throw ShareImportError.noURLFound
        }

        if seed.imageData == nil {
            seed.imageData = sharedImageData
        }

        if seed.imageData == nil,
           let remoteImageURL = seed.remoteImageURL,
           let downloadedImageData = await ShareExtensionImportService.downloadImageData(from: remoteImageURL) {
            seed.imageData = downloadedImageData
        }

        var assessment = RecipeValidationService.assess(seed, sourceKind: .shared)
        assessment.seed.imageData = assessment.seed.imageData ?? seed.imageData

        return ShareRecipePreview(
            draft: draft,
            assessment: assessment,
            heroImage: assessment.seed.imageData.flatMap(UIImage.init(data:))
        )
    }

    @MainActor
    private func openCurrentPreviewInApp(action: SharedImportHandoffAction) async {
        guard case .preview(let preview) = state.phase else { return }
        await handoffToApp(
            action: action,
            seed: preview.assessment.seed,
            originalDraft: preview.draft
        )
    }

    @MainActor
    private func openManualCreationInApp() async {
        switch state.phase {
        case .preview(let preview):
            await handoffToApp(
                action: .createManuallyInApp,
                seed: preview.assessment.seed,
                originalDraft: preview.draft
            )

        case .failure(let failure):
            guard let draft = failure.draft else {
                finishExtension()
                return
            }

            let seed = failure.seed ?? fallbackSeed(from: draft)
            await handoffToApp(
                action: .createManuallyInApp,
                seed: seed,
                originalDraft: draft
            )

        case .loading:
            break
        }
    }

    @MainActor
    private func handoffToApp(
        action: SharedImportHandoffAction,
        seed: RecipeEditorSeed,
        originalDraft: SharedImportDraft
    ) async {
        state.isPerformingAction = true

        var handoffDraft = originalDraft
        var handoffSeed = seed

        if let imageData = handoffSeed.imageData {
            handoffDraft.sharedImageFilename = sharedLinkInbox.storePendingImageData(imageData)
        }

        handoffSeed.imageData = nil
        handoffDraft.preparedSeed = handoffSeed
        handoffDraft.handoffAction = action
        handoffDraft.capturedAt = .now

        sharedLinkInbox.enqueue(draft: handoffDraft)
        openCooksyApp(for: action)
    }

    private func fallbackSeed(from draft: SharedImportDraft) -> RecipeEditorSeed {
        let fallbackTitle = draft.sharedText?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("http") })

        return RecipeEditorSeed(
            title: fallbackTitle ?? "Recette à compléter",
            sourceURL: draft.preferredImportURL,
            notesText: draft.sharedText ?? ""
        )
    }

    private func extractSharedDraft() async throws -> SharedImportDraft {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var foundURL: URL?
        var foundText: String?
        var foundImageFilename: String?

        for item in items {
            for provider in item.attachments ?? [] {
                if foundURL == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try await loadURL(from: provider) {
                    foundURL = url
                }

                if foundText == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try await loadString(from: provider) {
                    foundText = text

                    if foundURL == nil, let url = firstURL(in: text) {
                        foundURL = url
                    }
                }

                if foundImageFilename == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let imageData = try await loadImageData(from: provider) {
                    foundImageFilename = sharedLinkInbox.storePendingImageData(imageData)
                }
            }
        }

        var draft = SharedImportDraft(
            urlString: foundURL?.absoluteString,
            sourceApp: nil,
            sharedText: foundText,
            sharedImageFilename: foundImageFilename,
            preparedSeed: nil,
            handoffAction: nil,
            capturedAt: .now
        )

        if let rawURLString = draft.urlString {
            logger.debug("Share Extension extracted raw URL: \(rawURLString, privacy: .public)")
        }

        draft.urlString = draft.preferredImportURL?.absoluteString

        if let preferredURLString = draft.urlString {
            logger.debug("Share Extension handoff URL: \(preferredURLString, privacy: .public)")
        } else {
            logger.notice("Share Extension did not find a valid web URL in the shared payload.")
        }

        guard draft.hasPayload else {
            throw ShareImportError.noURLFound
        }

        return draft
    }

    @MainActor
    private func openCooksyApp(for action: SharedImportHandoffAction) {
        guard let extensionContext else { return }
        guard let appURL = Self.makeAppURL(for: action) else {
            extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        extensionContext.open(appURL) { _ in
            extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private static func makeAppURL(for action: SharedImportHandoffAction) -> URL? {
        var components = URLComponents()
        components.scheme = "cooksy"
        components.host = "shared-import"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
        return components.url
    }

    private func finishExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: Self.validatedURL(from: text))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadString(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }

                if let attributedString = item as? NSAttributedString {
                    continuation.resume(returning: attributedString.string)
                    return
                }

                if let data = item as? Data,
                   let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                    return
                }

                if let image = item as? UIImage,
                   let data = image.jpegData(compressionQuality: 0.92) {
                    continuation.resume(returning: data)
                    return
                }

                if let data = item as? Data {
                    continuation.resume(returning: data)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector?.firstMatch(in: text, options: [], range: range)
        return match?.url
    }

    nonisolated private static func validatedURL(from rawValue: String) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        return URLComponents(string: trimmedValue)?.url
    }
}

private enum ShareImportError: LocalizedError {
    case noURLFound

    var errorDescription: String? {
        switch self {
        case .noURLFound:
            return "Cooksy n'a pas trouvé de lien compatible dans ce partage."
        }
    }
}

@MainActor
private final class ShareExtensionState: ObservableObject {
    @Published var phase: ShareExtensionPhase = .loading(
        ShareLoadingState(
            title: "Cooksy prépare votre recette",
            message: "Nous analysons ce partage pour construire un aperçu propre."
        )
    )
    @Published var isPerformingAction = false

    var latestDraft: SharedImportDraft?
}

private enum ShareExtensionPhase {
    case loading(ShareLoadingState)
    case preview(ShareRecipePreview)
    case failure(ShareRecipeFailure)
}

private struct ShareLoadingState {
    let title: String
    let message: String
}

private struct ShareRecipePreview {
    let draft: SharedImportDraft
    let assessment: RecipeImportAssessment
    let heroImage: UIImage?
}

private struct ShareRecipeFailure {
    let draft: SharedImportDraft?
    let seed: RecipeEditorSeed?
    let title: String
    let message: String
    let allowsRetry: Bool
}

private struct ShareExtensionRootView: View {
    @ObservedObject var state: ShareExtensionState

    let onCancel: () -> Void
    let onRetry: () -> Void
    let onModifyInApp: () -> Void
    let onSaveInApp: () -> Void
    let onCreateManually: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xFBF8F1), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch state.phase {
            case .loading(let loadingState):
                ShareLoadingView(
                    loadingState: loadingState,
                    onCancel: onCancel
                )

            case .preview(let preview):
                ShareRecipePreviewView(
                    preview: preview,
                    isPerformingAction: state.isPerformingAction,
                    onCancel: onCancel,
                    onModifyInApp: onModifyInApp,
                    onSaveInApp: onSaveInApp
                )

            case .failure(let failure):
                ShareRecipeFailureView(
                    failure: failure,
                    isPerformingAction: state.isPerformingAction,
                    onCancel: onCancel,
                    onRetry: onRetry,
                    onCreateManually: onCreateManually
                )
            }

            if state.isPerformingAction {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.08)

                    Text("Ouverture de Cooksy")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                )
            }
        }
    }
}

private struct ShareLoadingView: View {
    let loadingState: ShareLoadingState
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ShareHeaderBar(onCancel: onCancel)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xEAF2FF))
                        .frame(width: 92, height: 92)

                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x2E7DDE))

                    ProgressView()
                        .tint(Color(hex: 0xFF7A12))
                        .offset(y: 56)
                }

                Text(loadingState.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x221A14))
                    .multilineTextAlignment(.center)

                Text(loadingState.message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8B8378))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 34)
    }
}

private struct ShareRecipePreviewView: View {
    let preview: ShareRecipePreview
    let isPerformingAction: Bool
    let onCancel: () -> Void
    let onModifyInApp: () -> Void
    let onSaveInApp: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ShareHeaderBar(onCancel: onCancel)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                headerSection
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)

                ShareSectionDivider()

                section(
                    title: "INGRÉDIENTS",
                    rows: preview.assessment.seed.normalizedIngredients.map { ingredient in
                        ShareRow(
                            icon: ingredientEmoji(for: ingredient.name),
                            text: formattedIngredientText(for: ingredient)
                        )
                    }
                )

                if !preview.assessment.seed.normalizedSteps.isEmpty {
                    ShareSectionDivider()
                    instructionsSection
                }

                if nutritionItems.isEmpty == false {
                    ShareSectionDivider()
                    nutritionSection
                }

                VStack(spacing: 12) {
                    if let reviewNotice = preview.assessment.validation.reviewNotice {
                        Text(reviewNotice)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                preview.assessment.validation.canSave
                                    ? Color(hex: 0xD46B12)
                                    : Color(hex: 0xBF5B44)
                            )
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onSaveInApp) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    preview.assessment.validation.canSave
                                        ? Color(hex: 0xFF7A12)
                                        : Color(hex: 0xD9D3C8)
                                )
                                .frame(height: 62)

                            Text(
                                preview.assessment.validation.canSave
                                    ? "Enregistrer dans Cooksy"
                                    : "Modifier dans l’app pour continuer"
                            )
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPerformingAction || !preview.assessment.validation.canSave)

                    Text("Cooksy s’ouvrira pour finaliser l’enregistrement et afficher la recette.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x8B8378))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 18) {
            ShareHeroImage(image: preview.heroImage)

            VStack(alignment: .leading, spacing: 12) {
                Text(preview.assessment.seed.normalizedTitle)
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .foregroundStyle(Color(hex: 0x221A14))
                    .fixedSize(horizontal: false, vertical: true)

                if let sourceLabel = sourceLabel {
                    Text(sourceLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x2E7DDE))
                }

                Button(action: onModifyInApp) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .bold))

                        Text("Modifier dans l’app")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: 0xF07B20))
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xDDD4C7), lineWidth: 1.6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPerformingAction)
            }

            Spacer(minLength: 0)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("INSTRUCTIONS")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x5C89D8))
                .tracking(1.1)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            VStack(spacing: 16) {
                ForEach(Array(preview.assessment.seed.normalizedSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(hex: 0x2E7DDE))
                            )

                        Text(step.detail)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: 0x221A14))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NUTRITION")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x5C89D8))
                .tracking(1.1)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(nutritionItems, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x8B8378))

                        Text(item.value)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x221A14))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: 0xF7F4EE))
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var nutritionItems: [(label: String, value: String)] {
        let nutrition = preview.assessment.seed.nutrition

        return [
            ("Calories", nutrition?.calories ?? ""),
            ("Protéines", nutrition?.protein ?? ""),
            ("Glucides", nutrition?.carbs ?? ""),
            ("Lipides", nutrition?.fat ?? "")
        ]
        .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var sourceLabel: String? {
        guard let host = preview.assessment.seed.sourceURL?.host(percentEncoded: false), !host.isEmpty else {
            return nil
        }

        return host
    }

    private func section(title: String, rows: [ShareRow]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x5C89D8))
                .tracking(1.1)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            VStack(spacing: 16) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.icon)
                            .font(.system(size: 28))
                            .frame(width: 36)

                        row.text
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: 0x221A14))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func formattedIngredientText(for ingredient: RecipeIngredient) -> Text {
        let prefix = [ingredient.amount, ingredient.unit]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if prefix.isEmpty {
            return Text(ingredient.name)
        }

        return Text(prefix + " ").bold() + Text(ingredient.name)
    }

    private func ingredientEmoji(for ingredientName: String) -> String {
        let lowercased = ingredientName.lowercased()

        if lowercased.contains("chocolat") { return "🍫" }
        if lowercased.contains("farine") { return "🥣" }
        if lowercased.contains("beurre") { return "🧈" }
        if lowercased.contains("sucre") { return "🍚" }
        if lowercased.contains("amande") { return "🥜" }
        if lowercased.contains("oeuf") || lowercased.contains("œuf") || lowercased.contains("jaune") { return "🥚" }
        if lowercased.contains("crème") || lowercased.contains("creme") { return "🥛" }
        if lowercased.contains("citron") { return "🍋" }
        if lowercased.contains("tomate") { return "🍅" }
        if lowercased.contains("poulet") { return "🍗" }
        if lowercased.contains("boeuf") || lowercased.contains("bœuf") { return "🥩" }
        if lowercased.contains("fromage") { return "🧀" }
        if lowercased.contains("oignon") { return "🧅" }
        if lowercased.contains("ail") { return "🧄" }
        return "🍽️"
    }
}

private struct ShareRecipeFailureView: View {
    let failure: ShareRecipeFailure
    let isPerformingAction: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onCreateManually: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ShareHeaderBar(onCancel: onCancel)

            Spacer(minLength: 0)

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 110, height: 110)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xF07B20))
                }

                VStack(spacing: 12) {
                    Text(failure.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x221A14))
                        .multilineTextAlignment(.center)

                    Text(failure.message)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x8B8378))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 34)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
            )

            VStack(spacing: 14) {
                if failure.allowsRetry {
                    Button(action: onRetry) {
                        Text("Réessayer")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(hex: 0xFF7A12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPerformingAction)
                }

                Button(action: onCreateManually) {
                    Text("Créer manuellement")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x221A14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(hex: 0xDDD4C7), lineWidth: 1.6)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isPerformingAction)

                Button("Annuler", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8B8378))
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }
}

private struct ShareHeaderBar: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            ShareWordmark()

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Text("Annuler")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x2A211B))
                    .padding(.horizontal, 22)
                    .frame(height: 54)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ShareWordmark: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Text("Cooksy")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(Color(hex: 0x2E7DDE).opacity(0.22))
                    .offset(y: 3)

                Text("Cooksy")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0x8FC5FF), Color(hex: 0x2E7DDE)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(hex: 0xFFE675), Color(hex: 0xF6A300))
                .offset(x: 12, y: -6)
        }
        .frame(width: 150, height: 54, alignment: .leading)
    }
}

private struct ShareHeroImage: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0xF3EEE5))
                .frame(width: 116, height: 116)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(hex: 0x2E7DDE).opacity(0.82))
            }
        }
    }
}

private struct ShareSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: 0xEFE8DD))
            .frame(height: 14)
    }
}

private struct ShareRow: Identifiable {
    let id = UUID()
    let icon: String
    let text: Text
}

private enum ShareExtensionImportService {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "ShareExtensionImportService")

    private enum Endpoint: String {
        case importURL = "/api/import/url"
        case importText = "/api/import/text"
        case importPhoto = "/api/import/photo"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        return URLSession(configuration: configuration)
    }()

    static func importURL(_ url: URL, sharedText: String?) async throws -> RecipeEditorSeed {
        let requestBody = ShareURLImportRequest(
            url: encodedAbsoluteString(for: url),
            sharedText: nonEmpty(sharedText)
        )

        let envelope: ShareRecipeImportEnvelope = try await sendJSON(
            endpoint: .importURL,
            requestBody: requestBody
        )
        return envelope.recipe.asSeed()
    }

    static func importText(_ text: String, imageData: Data? = nil) async throws -> RecipeEditorSeed {
        let requestBody = ShareTextImportRequest(
            text: text,
            imageBase64: imageData?.base64EncodedString()
        )

        let envelope: ShareRecipeImportEnvelope = try await sendJSON(
            endpoint: .importText,
            requestBody: requestBody
        )
        return envelope.recipe.asSeed()
    }

    static func importPhoto(_ imageData: Data) async throws -> RecipeEditorSeed {
        let boundary = "CooksyShareBoundary-\(UUID().uuidString)"
        let request = try makeRequest(
            endpoint: .importPhoto,
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")

        var uploadRequest = request
        uploadRequest.httpBody = body

        let envelope: ShareRecipeImportEnvelope = try await send(uploadRequest, as: ShareRecipeImportEnvelope.self)
        var seed = envelope.recipe.asSeed()
        seed.imageData = seed.imageData ?? imageData
        return seed
    }

    static func downloadImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        do {
            logger.debug("Share extension requesting preview image at \(url.absoluteString, privacy: .public)")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200 ..< 300).contains(httpResponse.statusCode) == false {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }

    private static func sendJSON<Request: Encodable, Response: Decodable>(
        endpoint: Endpoint,
        requestBody: Request
    ) async throws -> Response {
        var request = try makeRequest(endpoint: endpoint)
        request.httpBody = try JSONEncoder().encode(requestBody)
        return try await send(request, as: Response.self)
    }

    private static func send<Response: Decodable>(
        _ request: URLRequest,
        as _: Response.Type
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            logger.debug("Share extension sending request to \(request.url?.absoluteString ?? "(nil)", privacy: .public)")
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ShareExtensionImportError.timedOut
            case .badURL, .unsupportedURL:
                throw ShareExtensionImportError.invalidRequestURL(request.url?.absoluteString ?? "(nil)")
            default:
                throw ShareExtensionImportError.serverError(error.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareExtensionImportError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if let backendError = try? JSONDecoder().decode(ShareBackendErrorEnvelope.self, from: data),
               let message = nonEmpty(backendError.message) ?? nonEmpty(backendError.error) {
                throw ShareExtensionImportError.serverError(message)
            }

            throw ShareExtensionImportError.serverError("Le backend Cooksy a échoué (\(httpResponse.statusCode)).")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ShareExtensionImportError.invalidResponse
        }
    }

    private static func makeRequest(
        endpoint: Endpoint,
        method: String = "POST",
        contentType: String? = "application/json"
    ) throws -> URLRequest {
        let baseURL = try resolvedBackendBaseURL()
        let url = try buildURL(baseURL: baseURL, endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func resolvedBackendBaseURL() throws -> URL {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: "CooksyBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !rawValue.isEmpty else {
            throw ShareExtensionImportError.missingBackendURL
        }

        guard var components = URLComponents(string: rawValue) else {
            throw ShareExtensionImportError.invalidBackendURL(rawValue)
        }

        if components.scheme?.isEmpty ?? true {
            throw ShareExtensionImportError.invalidBackendURL(rawValue)
        }

        if components.path.isEmpty {
            components.path = ""
        }

        guard let url = components.url else {
            throw ShareExtensionImportError.invalidBackendURL(rawValue)
        }

        return url
    }

    private static func buildURL(baseURL: URL, endpoint: Endpoint) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ShareExtensionImportError.invalidBackendURL(baseURL.absoluteString)
        }

        let trimmedBasePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedEndpointPath = endpoint.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = trimmedBasePath.isEmpty
            ? "/\(trimmedEndpointPath)"
            : "/\(trimmedBasePath)/\(trimmedEndpointPath)"

        guard let url = components.url else {
            throw ShareExtensionImportError.invalidRequestURL(endpoint.rawValue)
        }

        return url
    }

    private static func encodedAbsoluteString(for url: URL) -> String {
        if let normalizedURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url {
            return normalizedURL.absoluteString
        }

        return url.absoluteString
    }
}

private enum ShareExtensionImportError: LocalizedError {
    case missingBackendURL
    case invalidBackendURL(String)
    case invalidRequestURL(String)
    case invalidResponse
    case timedOut
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingBackendURL:
            return "Cooksy n'a pas d'URL backend configurée dans l'extension."
        case .invalidBackendURL(let value):
            return "L'URL backend de l'extension est invalide: \(value)"
        case .invalidRequestURL(let value):
            return "L'URL finale demandée par l'extension est invalide: \(value)"
        case .invalidResponse:
            return "Le backend Cooksy a renvoyé une réponse invalide."
        case .timedOut:
            return "Cooksy a mis trop de temps à analyser ce partage."
        case .serverError(let message):
            return message
        }
    }
}

private struct ShareURLImportRequest: Encodable {
    let url: String
    let sharedText: String?
}

private struct ShareTextImportRequest: Encodable {
    let text: String
    let imageBase64: String?
}

private struct ShareRecipeImportEnvelope: Decodable {
    let recipe: ShareBackendRecipeSeed
}

private struct ShareBackendRecipeSeed: Decodable {
    let title: String
    let sourceUrl: String
    let remoteImageUrl: String
    let ingredientDrafts: [ShareBackendIngredientDraft]
    let stepDrafts: [ShareBackendStepDraft]
    let notesText: String
    let prepTimeText: String
    let cookTimeText: String
    let servingsText: String
    let caloriesText: String
    let proteinText: String
    let carbsText: String
    let fatText: String

    func asSeed() -> RecipeEditorSeed {
        RecipeEditorSeed(
            title: title,
            sourceURL: urlIfPresent(sourceUrl),
            ingredientDrafts: ingredientDrafts.map { $0.asDraft() },
            stepDrafts: stepDrafts.map { $0.asDraft() },
            notesText: notesText,
            prepTimeText: prepTimeText,
            cookTimeText: cookTimeText,
            servingsText: servingsText,
            caloriesText: caloriesText,
            proteinText: proteinText,
            carbsText: carbsText,
            fatText: fatText,
            remoteImageURL: urlIfPresent(remoteImageUrl)
        )
    }
}

private struct ShareBackendIngredientDraft: Decodable {
    let amount: String
    let unit: String
    let name: String

    func asDraft() -> IngredientDraft {
        IngredientDraft(amount: amount, unit: unit, name: name)
    }
}

private struct ShareBackendStepDraft: Decodable {
    let detail: String

    func asDraft() -> StepDraft {
        StepDraft(detail: detail)
    }
}

private struct ShareBackendErrorEnvelope: Decodable {
    let error: String?
    let message: String?
}

private func urlIfPresent(_ string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(string: trimmed)
}

private func nonEmpty(_ string: String?) -> String? {
    guard let string else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
