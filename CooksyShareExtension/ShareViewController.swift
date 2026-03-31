import SwiftUI
import UniformTypeIdentifiers
import UIKit
import OSLog

final class ShareViewController: UIViewController {
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "ShareViewController")
    private let state = ShareExtensionState()
    private let sharedLinkInbox = SharedLinkInbox()
    private var hasStartedHandoff = false

    override func viewDidLoad() {
        super.viewDidLoad()
        embedRootView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStartedHandoff else { return }
        hasStartedHandoff = true

        Task { @MainActor in
            await handoffSharedContentToCooksyApp()
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
    private func handoffSharedContentToCooksyApp() async {
        state.isPerformingAction = false
        state.phase = .loading(makeLoadingState(for: nil))

        do {
            var draft = try await extractSharedDraft()
            draft.handoffToken = UUID().uuidString
            state.latestDraft = draft
            state.phase = .loading(makeLoadingState(for: draft))
            logger.debug("Share extension captured draft for host \(draft.hostLabel, privacy: .public)")

            sharedLinkInbox.enqueue(draft: draft)
            state.isPerformingAction = true

            let didOpen = await openCooksyAppForSharedImport(handoffToken: draft.handoffToken)
            state.isPerformingAction = false

            guard didOpen else {
                throw ShareImportError.unableToOpenCooksy
            }
        } catch {
            logger.error("Share extension import failed: \(error.localizedDescription, privacy: .public)")
            let fallbackDraft = state.latestDraft
            let failureMessage = userFacingFailureMessage(for: error)
            logger.error("Share extension UI error shown: \(failureMessage, privacy: .public)")
            state.phase = .failure(
                ShareRecipeFailure(
                    draft: fallbackDraft,
                    seed: fallbackDraft.map { fallbackSeed(from: $0) },
                    title: "Import impossible",
                    message: failureMessage,
                    allowsRetry: fallbackDraft != nil
                )
            )
        }
    }

    @MainActor
    private func importSharedContent() async {
        await handoffSharedContentToCooksyApp()
    }

    private func makeLoadingState(for draft: SharedImportDraft?) -> ShareLoadingState {
        guard let draft else {
            return ShareLoadingState(
                title: "Cooksy prepare votre import",
                message: "Nous preparons le transfert vers l'app pour lancer l'analyse dans Cooksy.",
                hostLabel: nil,
                isVideoImport: false
            )
        }

        if draft.isLikelyVideoImport {
            return ShareLoadingState(
                title: "Import video en cours",
                message: "Cooksy recupere ce partage depuis \(draft.hostLabel) et prepare une recette claire a partir de la video.",
                hostLabel: draft.hostLabel,
                isVideoImport: true
            )
        }

        return ShareLoadingState(
            title: "Import en cours",
            message: "Cooksy transfere ce partage depuis \(draft.hostLabel) et prepare l'analyse dans l'app.",
            hostLabel: draft.hostLabel,
            isVideoImport: false
        )
    }

    @MainActor
    private func makePreview(for draft: SharedImportDraft) async throws -> ShareRecipePreview {
        let sharedImageData = sharedLinkInbox.imageData(for: draft.sharedImageFilename)
        let attempts = importAttempts(for: draft, imageData: sharedImageData)
        guard attempts.isEmpty == false else {
            throw ShareImportError.noURLFound
        }

        var lastError: Error?
        var seed: RecipeEditorSeed?

        for attempt in attempts {
            do {
                seed = try await attempt.execute()
                break
            } catch {
                lastError = error
                logger.error(
                    "Share extension \(attempt.debugLabel, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        guard var seed else {
            throw lastError ?? ShareImportError.noURLFound
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
        let rejectionReasons = assessment.validation.rejectionReasons.map(\.rawValue).joined(separator: ",")
        let backendReason = assessment.seed.importDebug?.failureReason ?? "none"
        let validationMessage = [
            "Share extension validation result",
            "status=\(String(describing: assessment.validation.status))",
            "score=\(assessment.validation.qualityScore)",
            "reasons=\(rejectionReasons)",
            "backendReason=\(backendReason)"
        ].joined(separator: " ")
        logger.debug("\(validationMessage, privacy: .public)")

        return ShareRecipePreview(
            draft: draft,
            assessment: assessment,
            heroImage: assessment.seed.imageData.flatMap(UIImage.init(data:))
        )
    }

    private func importAttempts(for draft: SharedImportDraft, imageData: Data?) -> [ShareImportAttempt] {
        var attempts: [ShareImportAttempt] = []

        if let url = draft.preferredImportURL {
            attempts.append(
                ShareImportAttempt(debugLabel: "URL import") {
                    try await ShareExtensionImportService.importURL(url, sharedText: draft.sharedText)
                }
            )
        }

        if let sharedText = nonEmpty(draft.sharedText) {
            attempts.append(
                ShareImportAttempt(debugLabel: "text import") {
                    try await ShareExtensionImportService.importText(sharedText, imageData: imageData)
                }
            )
        }

        if let imageData {
            attempts.append(
                ShareImportAttempt(debugLabel: "photo import") {
                    try await ShareExtensionImportService.importPhoto(imageData)
                }
            )
        }

        return attempts
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
        handoffDraft.handoffToken = UUID().uuidString
        handoffDraft.capturedAt = .now

        sharedLinkInbox.enqueue(draft: handoffDraft)

        let didOpen = await openCooksyApp(for: action, handoffToken: handoffDraft.handoffToken)
        state.isPerformingAction = false

        guard didOpen else {
            state.phase = .failure(
                ShareRecipeFailure(
                    draft: handoffDraft,
                    seed: handoffSeed,
                    title: "Ouverture impossible",
                    message: ShareImportError.unableToOpenCooksy.errorDescription ?? "Impossible d'ouvrir Cooksy depuis ce partage.",
                    allowsRetry: true
                )
            )
            return
        }
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
            if foundText == nil {
                foundText = firstNonEmptySharedText(in: item)

                if foundURL == nil, let text = foundText, let url = firstURL(in: text) {
                    foundURL = url
                }
            }

            for provider in item.attachments ?? [] {
                logger.debug(
                    "Share extension provider advertised types: \(provider.registeredTypeIdentifiers.joined(separator: ","), privacy: .public)"
                )

                if foundURL == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await bestEffortLoadURL(from: provider) {
                    foundURL = url
                }

                if foundText == nil,
                   let text = await bestEffortLoadString(from: provider) {
                    foundText = text

                    if foundURL == nil, let url = firstURL(in: text) {
                        foundURL = url
                    }
                }

                if foundImageFilename == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let imageData = await bestEffortLoadImageData(from: provider) {
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
            handoffToken: nil,
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

    private func firstNonEmptySharedText(in item: NSExtensionItem) -> String? {
        let candidates: [String?] = [
            item.attributedContentText?.string,
            item.attributedTitle?.string
        ]

        for candidate in candidates {
            if let value = nonEmpty(candidate) {
                logger.debug("Share extension found text directly on NSExtensionItem.")
                return value
            }
        }

        return nil
    }

    private func userFacingFailureMessage(for error: Error) -> String {
        if let shareImportError = error as? ShareImportError,
           let description = shareImportError.errorDescription {
            return description
        }

        if let importError = error as? ShareExtensionImportError {
            switch importError {
            case .missingBackendURL, .invalidBackendURL, .invalidRequestURL:
                return "Service d’import indisponible"
            case .invalidResponse:
                return "Résultat de recette invalide"
            case .timedOut:
                return "Import trop lent"
            case .serverError(let message):
                return sanitizedFailureMessage(from: message)
            }
        }

        return sanitizedFailureMessage(from: error.localizedDescription)
    }

    private func sanitizedFailureMessage(from rawMessage: String) -> String {
        let trimmedMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.isEmpty == false else {
            return "Résultat de recette invalide"
        }

        let lowercaseMessage = trimmedMessage.lowercased()
        if lowercaseMessage.contains("timeout") || lowercaseMessage.contains("timed out") {
            return "Import trop lent"
        }
        if lowercaseMessage.contains("weak_tiktok_metadata") || lowercaseMessage.contains("metadata") {
            return "Données TikTok insuffisantes"
        }
        if lowercaseMessage.contains("not_enough_ingredients") {
            return "Pas assez d’ingrédients"
        }
        if lowercaseMessage.contains("not_enough_steps") {
            return "Pas assez d’étapes"
        }
        if lowercaseMessage.contains("no_recipe_detected") {
            return "Aucune recette détectée"
        }

        let technicalFragments = [
            "application not found",
            "nsitemprovider",
            "cfprefs",
            "operation couldn",
            "couldn't communicate",
            "unsupported",
            "timed out",
            "network connection"
        ]

        if technicalFragments.contains(where: { lowercaseMessage.contains($0) }) {
            return "Données TikTok insuffisantes"
        }

        return trimmedMessage
    }

    @MainActor
    private func openCooksyApp(
        for action: SharedImportHandoffAction,
        handoffToken: String?
    ) async -> Bool {
        guard let appURL = Self.makeAppURL(for: action, handoffToken: handoffToken) else {
            finishExtension()
            return false
        }

        return await openCooksyApp(at: appURL, handoffToken: handoffToken)
    }

    @MainActor
    private func openCooksyAppForSharedImport(handoffToken: String?) async -> Bool {
        guard let appURL = Self.makeAppURL(for: .reviewInApp, handoffToken: handoffToken) else { return false }

        return await openCooksyApp(at: appURL, handoffToken: handoffToken)
    }

    @MainActor
    private func openCooksyApp(
        at appURL: URL,
        handoffToken: String?
    ) async -> Bool {
        logger.debug("Share extension opening Cooksy app with \(appURL.absoluteString, privacy: .public)")

        try? await Task.sleep(for: .milliseconds(80))

        let openedViaSharedApplication = await openCooksyAppViaSharedApplication(appURL)
        let openedViaApplicationResponder = openedViaSharedApplication ? false : await openCooksyAppViaApplicationResponder(appURL)
        let openedViaExtensionContext = (openedViaSharedApplication || openedViaApplicationResponder)
            ? false
            : await openCooksyAppThroughExtensionContext(appURL)
        let openedViaLegacyResponder = (openedViaSharedApplication || openedViaApplicationResponder || openedViaExtensionContext)
            ? false
            : openCooksyAppViaLegacyResponder(appURL)

        guard openedViaSharedApplication || openedViaApplicationResponder || openedViaExtensionContext || openedViaLegacyResponder else {
            return false
        }

        if let handoffToken, handoffToken.isEmpty == false {
            logger.debug(
                "Share extension dispatched Cooksy handoff token=\(handoffToken, privacy: .public); finishing extension immediately to let Cooksy take focus."
            )
        }
        finishExtension(afterDelay: true)
        return true
    }

    private func openCooksyAppViaSharedApplication(_ url: URL) async -> Bool {
        guard let application = sharedApplicationObject() else {
            logger.error("Share extension could not resolve UIApplication shared instance.")
            return false
        }

        return await openCooksyApp(url, with: application, label: "UIApplication shared instance")
    }

    private func openCooksyAppThroughExtensionContext(_ appURL: URL) async -> Bool {
        guard let extensionContext else { return false }

        let opened = await withCheckedContinuation { continuation in
            extensionContext.open(appURL) { success in
                continuation.resume(returning: success)
            }
        }

        if !opened {
            logger.error("Share extension could not open Cooksy via extension context.")
        }

        return opened
    }

    private static func makeAppURL(
        for action: SharedImportHandoffAction,
        handoffToken: String?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "cooksy"
        components.host = "shared-import"
        var queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
        if let handoffToken, handoffToken.isEmpty == false {
            queryItems.append(URLQueryItem(name: "handoffToken", value: handoffToken))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func finishExtension(afterDelay: Bool = false) {
        guard afterDelay else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        let extensionContext = self.extensionContext
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func openCooksyAppViaApplicationResponder(_ url: URL) async -> Bool {
        guard let application = applicationResponderObject() else {
            logger.error("Share extension could not find UIApplication in responder chain.")
            return false
        }

        return await openCooksyApp(url, with: application, label: "UIApplication responder chain")
    }

    private func openCooksyApp(
        _ url: URL,
        with application: AnyObject,
        label: String
    ) async -> Bool {
        let modernSelector = NSSelectorFromString("openURL:options:completionHandler:")
        let legacySelector = NSSelectorFromString("openURL:")

        if application.responds(to: modernSelector) {
            typealias OpenURLCompletionBlock = @convention(block) (Bool) -> Void
            typealias OpenURLModernIMP = @convention(c) (
                AnyObject,
                Selector,
                NSURL,
                NSDictionary,
                AnyObject
            ) -> Void

            let opened = await withCheckedContinuation { continuation in
                let completion: OpenURLCompletionBlock = { success in
                    continuation.resume(returning: success)
                }
                let completionObject = completion as AnyObject
                let implementation = application.method(for: modernSelector)
                let function = unsafeBitCast(implementation, to: OpenURLModernIMP.self)

                logger.debug("Share extension opening Cooksy app via \(label, privacy: .public) modern selector.")
                function(application, modernSelector, url as NSURL, [:] as NSDictionary, completionObject)
            }

            logger.debug(
                "Share extension \(label, privacy: .public) modern selector completed success=\(opened, privacy: .public)."
            )
            return opened
        }

        guard application.responds(to: legacySelector) else {
            logger.error("Share extension could not find supported openURL selector on \(label, privacy: .public).")
            return false
        }

        typealias OpenURLLegacyIMP = @convention(c) (AnyObject, Selector, NSURL) -> Bool

        let implementation = application.method(for: legacySelector)
        let function = unsafeBitCast(implementation, to: OpenURLLegacyIMP.self)
        let didOpen = function(application, legacySelector, url as NSURL)
        logger.debug(
            "Share extension opening Cooksy app via \(label, privacy: .public) legacy selector success=\(didOpen, privacy: .public)."
        )
        return didOpen
    }

    private func sharedApplicationObject() -> AnyObject? {
        let selector = NSSelectorFromString("sharedApplication")
        guard UIApplication.responds(to: selector),
              let application = UIApplication.perform(selector)?.takeUnretainedValue() else {
            return nil
        }

        return application as AnyObject
    }

    private func applicationResponderObject() -> AnyObject? {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if NSStringFromClass(type(of: currentResponder)) == "UIApplication" {
                return currentResponder
            }
            responder = currentResponder.next
        }

        return nil
    }

    private func openCooksyAppViaLegacyResponder(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                logger.debug("Share extension opening Cooksy app via legacy responder chain fallback.")
                currentResponder.perform(selector, with: url)
                return true
            }
            responder = currentResponder.next
        }

        logger.error("Share extension could not open Cooksy via legacy responder fallback.")
        return false
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

    private func bestEffortLoadURL(from provider: NSItemProvider) async -> URL? {
        do {
            return try await loadURL(from: provider)
        } catch {
            let typeList = provider.registeredTypeIdentifiers.joined(separator: ",")
            logger.error(
                "Share extension could not load URL from provider \(typeList, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func loadString(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
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

    private func bestEffortLoadString(from provider: NSItemProvider) async -> String? {
        let candidateTypeIdentifiers = orderedTextTypeIdentifiers(for: provider)

        for typeIdentifier in candidateTypeIdentifiers {
            do {
                if let text = try await loadString(from: provider, typeIdentifier: typeIdentifier),
                   nonEmpty(text) != nil {
                    return text
                }
            } catch {
                logger.error(
                    "Share extension could not load text from \(typeIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return nil
    }

    private func orderedTextTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        var identifiers: [String] = []

        let preferredIdentifiers = [
            UTType.plainText.identifier,
            UTType.text.identifier,
            "public.utf8-plain-text",
            "public.utf16-external-plain-text"
        ]

        for identifier in preferredIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            identifiers.append(identifier)
        }

        for identifier in provider.registeredTypeIdentifiers {
            guard identifiers.contains(identifier) == false else { continue }

            if let type = UTType(identifier), type.conforms(to: .text) {
                identifiers.append(identifier)
                continue
            }

            if identifier.localizedCaseInsensitiveContains("text") ||
                identifier.localizedCaseInsensitiveContains("plain-text") {
                identifiers.append(identifier)
            }
        }

        return identifiers
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

    private func bestEffortLoadImageData(from provider: NSItemProvider) async -> Data? {
        do {
            return try await loadImageData(from: provider)
        } catch {
            let typeList = provider.registeredTypeIdentifiers.joined(separator: ",")
            logger.error(
                "Share extension could not load image from provider \(typeList, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
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
    case unableToOpenCooksy

    var errorDescription: String? {
        switch self {
        case .noURLFound:
            return "Cooksy n'a pas trouvé de lien compatible dans ce partage."
        case .unableToOpenCooksy:
            return "Impossible d'ouvrir Cooksy automatiquement depuis ce partage. L'import reste disponible si vous ouvrez Cooksy manuellement."
        }
    }
}

@MainActor
private final class ShareExtensionState: ObservableObject {
    @Published var phase: ShareExtensionPhase = .loading(
        ShareLoadingState(
            title: "Cooksy prepare votre import",
            message: "Nous preparons le transfert vers l'app pour lancer l'analyse dans Cooksy.",
            hostLabel: nil,
            isVideoImport: false
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
    let hostLabel: String?
    let isVideoImport: Bool
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

private struct ShareImportAttempt {
    let debugLabel: String
    let execute: @Sendable () async throws -> RecipeEditorSeed
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
                ShareActionOverlay(isVideoImport: currentLoadingState?.isVideoImport ?? false)
            }
        }
    }

    private var currentLoadingState: ShareLoadingState? {
        guard case .loading(let loadingState) = state.phase else { return nil }
        return loadingState
    }
}

private struct ShareLoadingView: View {
    let loadingState: ShareLoadingState
    let onCancel: () -> Void
    @State private var activeStepIndex = 0
    @State private var activeMessageIndex = 0
    @State private var orbPulse = false
    @State private var orbSpin = false

    var body: some View {
        VStack(spacing: 18) {
            ShareHeaderBar(onCancel: onCancel)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 14) {
                headerRow
                heroRow
                progressBar
                stepList
                previewSection

                Text(footerMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8B8378))
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color(hex: 0xFFF7EF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(hex: 0xE6DED2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .task {
            await runProgressLoop()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                orbPulse = true
            }

            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                orbSpin = true
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            statusPill(
                text: loadingState.isVideoImport ? "Import vidéo" : "Import partagé",
                textColor: Color(hex: 0xA94F1D),
                background: Color(hex: 0xFFE9D3)
            )

            if let hostLabel = sanitizedHostLabel {
                statusPill(
                    text: hostLabel,
                    textColor: Color(hex: 0x275C9D),
                    background: Color(hex: 0xE6F0FF)
                )
            }

            Spacer(minLength: 0)

            Text("\(min(activeStepIndex + 1, progressSteps.count))/\(progressSteps.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0xA94F1D))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.9))
                )
        }
    }

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 16) {
            loadingOrb

            VStack(alignment: .leading, spacing: 6) {
                Text(loadingState.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x221A14))
                    .fixedSize(horizontal: false, vertical: true)

                Text(currentMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x7B7268))
                    .lineSpacing(2)
                    .contentTransition(.opacity)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xEEE5DA))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x6B9BFF), Color(hex: 0x2E7DDE)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(24, proxy.size.width * progressValue))
            }
        }
        .frame(height: 8)
    }

    private var loadingOrb: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x5B9AFF), Color(hex: 0x2E7DDE)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)

            Circle()
                .trim(from: 0.08, to: 0.76)
                .stroke(
                    Color.white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 98, height: 98)
                .rotationEffect(.degrees(orbSpin ? 360 : 0))

            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 62, height: 62)
                .scaleEffect(orbPulse ? 1.06 : 0.92)

            Image(systemName: loadingState.isVideoImport ? "play.rectangle.fill" : "sparkles")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var stepList: some View {
        VStack(spacing: 8) {
            ForEach(Array(progressSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    ShareLoadingStepIcon(state: stepState(for: index), tint: step.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x3F352D))

                        Text(stepStatusText(for: index))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: 0x7B7268))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(stepRowBackground(for: index))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    .foregroundStyle(Color(hex: 0x7B7268))

                Spacer(minLength: 0)

                Text("Recette propre")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA94F1D))
            }

            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0xF3E4D3))
                    .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 8) {
                    skeletonLine(width: 134, height: 12)
                    skeletonLine(width: 94, height: 10)

                    HStack(spacing: 8) {
                        skeletonCapsule(width: 56)
                        skeletonCapsule(width: 66)
                        skeletonCapsule(width: 48)
                    }

                    skeletonLine(width: 152, height: 9)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xEEE5DA), lineWidth: 1)
        )
    }

    private var sanitizedHostLabel: String? {
        guard let hostLabel = loadingState.hostLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hostLabel.isEmpty else {
            return nil
        }

        return hostLabel
    }

    private var currentMessage: String {
        let step = progressSteps[min(activeStepIndex, progressSteps.count - 1)]
        let messageIndex = min(activeMessageIndex, step.messages.count - 1)
        return step.messages[messageIndex]
    }

    private var progressValue: Double {
        let completed = Double(min(activeStepIndex, max(progressSteps.count - 1, 0)))
        let partial = activeStepIndex < progressSteps.count - 1
            ? Double(activeMessageIndex + 1) / Double(max(progressSteps[activeStepIndex].messages.count, 1))
            : 1
        return min((completed + partial) / Double(max(progressSteps.count, 1)), 1)
    }

    private var progressSteps: [ShareLoadingProgressStep] {
        if loadingState.isVideoImport {
            return [
                ShareLoadingProgressStep(
                    title: "Analyse de la vidéo",
                    tint: Color(hex: 0x2E7DDE),
                    messages: [
                        "Lecture de la vidéo et du contexte…",
                        "Détection du plat principal…",
                        "Nettoyage du contexte TikTok…"
                    ]
                ),
                ShareLoadingProgressStep(
                    title: "Extraction des ingrédients",
                    tint: Color(hex: 0xF07B20),
                    messages: [
                        "Extraction des ingrédients utiles…",
                        "Préparation des quantités propres…"
                    ]
                ),
                ShareLoadingProgressStep(
                    title: "Génération de la recette",
                    tint: Color(hex: 0x6A8F47),
                    messages: [
                        "Reconstruction des étapes dans Cooksy…",
                        "Assemblage de la fiche recette…"
                    ]
                ),
                ShareLoadingProgressStep(
                    title: "Calcul nutritionnel",
                    tint: Color(hex: 0x8C73D8),
                    messages: [
                        "Calcul des macros…",
                        "Finalisation avant ouverture…"
                    ]
                )
            ]
        }

        return [
            ShareLoadingProgressStep(
                title: "Analyse du partage",
                tint: Color(hex: 0x2E7DDE),
                messages: [
                    "Lecture du lien partagé…",
                    "Détection du plat et du contexte…"
                ]
            ),
            ShareLoadingProgressStep(
                title: "Extraction des ingrédients",
                tint: Color(hex: 0xF07B20),
                messages: [
                    "Nettoyage des ingrédients utiles…",
                    "Préparation des quantités…"
                ]
            ),
            ShareLoadingProgressStep(
                title: "Génération de la recette",
                tint: Color(hex: 0x6A8F47),
                messages: [
                    "Reconstruction de la recette dans Cooksy…",
                    "Préparation des étapes finales…"
                ]
            ),
            ShareLoadingProgressStep(
                title: "Calcul nutritionnel",
                tint: Color(hex: 0x8C73D8),
                messages: [
                    "Estimation des macros…",
                    "Finalisation avant ouverture…"
                ]
            )
        ]
    }

    private var footerMessage: String {
        if loadingState.isVideoImport {
            return "Cooksy reprendra l’import automatiquement dès que l’app s’ouvre."
        }

        return "Vous pouvez patienter ici, Cooksy reprend la main automatiquement."
    }

    private func stepState(for index: Int) -> ShareLoadingStepState {
        if index < activeStepIndex {
            return .completed
        }
        if index == activeStepIndex {
            return .active
        }
        return .pending
    }

    private func stepStatusText(for index: Int) -> String {
        switch stepState(for: index) {
        case .completed:
            return "Terminé"
        case .active:
            return "En cours"
        case .pending:
            return "En attente"
        }
    }

    private func stepRowBackground(for index: Int) -> Color {
        switch stepState(for: index) {
        case .completed:
            return Color(hex: 0xEFF7E6)
        case .active:
            return Color(hex: 0xFFF2E8)
        case .pending:
            return Color.white.opacity(0.88)
        }
    }

    private func stepRowBorder(for index: Int) -> Color {
        switch stepState(for: index) {
        case .completed:
            return Color(hex: 0xD8E8C6)
        case .active:
            return Color(hex: 0xF2D7C1)
        case .pending:
            return Color(hex: 0xEEE5DA)
        }
    }

    private func statusPill(text: String, textColor: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.white.opacity(0.76))
            .frame(width: width, height: height)
    }

    private func skeletonCapsule(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.78))
            .frame(width: width, height: 22)
    }

    private func runProgressLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { break }

            await MainActor.run {
                let messages = progressSteps[activeStepIndex].messages
                if activeMessageIndex < messages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeMessageIndex += 1
                    }
                } else if activeStepIndex < progressSteps.count - 1 {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        activeStepIndex += 1
                        activeMessageIndex = 0
                    }
                } else {
                    activeMessageIndex = (activeMessageIndex + 1) % messages.count
                }
            }
        }
    }
}

private struct ShareActionOverlay: View {
    let isVideoImport: Bool
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulse ? 1.06 : 0.92)

                    Circle()
                        .trim(from: 0.08, to: 0.74)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    Image(systemName: isVideoImport ? "play.rectangle.fill" : "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Ouverture de Cooksy")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(
                    isVideoImport
                        ? "La vidéo est prête à être reprise dans l’app."
                        : "Le partage est prêt à être repris dans l’app."
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.8), Color.black.opacity(0.66)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
        }
    }
}

private enum ShareLoadingStepState: Equatable {
    case completed
    case active
    case pending
}

private struct ShareLoadingProgressStep {
    let title: String
    let tint: Color
    let messages: [String]
}

private struct ShareLoadingStepIcon: View {
    let state: ShareLoadingStepState
    let tint: Color

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch state {
            case .completed:
                Circle()
                    .fill(tint)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

            case .active:
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulse ? 1.08 : 0.92)

                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))

            case .pending:
                Circle()
                    .stroke(Color(hex: 0xD9D0C5), lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
        .onAppear {
            refreshAnimations()
        }
        .onChange(of: state) { _, _ in
            refreshAnimations()
        }
    }

    private func refreshAnimations() {
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

                if let importNotice = preview.assessment.seed.importNotice {
                    importNoticeSection(importNotice)
                }

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

    private func importNoticeSection(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0x5C89D8))
                .padding(.top, 2)

            Text(notice)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x221A14))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
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
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    static func importURL(_ url: URL, sharedText: String?) async throws -> RecipeEditorSeed {
        let requestBody = ShareURLImportRequest(
            url: encodedAbsoluteString(for: url),
            sharedText: nonEmpty(sharedText),
            previewMode: true
        )

        let envelope: ShareRecipeImportEnvelope = try await sendJSON(
            endpoint: .importURL,
            requestBody: requestBody
        )
        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        return envelope.recipe.asSeed(debug: debug)
    }

    static func importText(_ text: String, imageData: Data? = nil) async throws -> RecipeEditorSeed {
        let requestBody = ShareTextImportRequest(
            text: text,
            imageBase64: imageData?.base64EncodedString(),
            previewMode: true
        )

        let envelope: ShareRecipeImportEnvelope = try await sendJSON(
            endpoint: .importText,
            requestBody: requestBody
        )
        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        return envelope.recipe.asSeed(debug: debug)
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
        let debug = envelope.debug?.asImportDebug()
        logBackendDebug(debug)
        var seed = envelope.recipe.asSeed(debug: debug)
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
            let requestStartedAt = Date()
            logger.debug(
                "Share extension request start t=\(requestStartedAt.timeIntervalSince1970, privacy: .public) url=\(request.url?.absoluteString ?? "(nil)", privacy: .public)"
            )
            (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            logger.debug("Share extension response received in \(durationMs)ms")
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

        let responseURLString = httpResponse.url?.absoluteString ?? request.url?.absoluteString ?? "(nil)"
        logger.debug(
            "Share extension backend response \(httpResponse.statusCode) from \(responseURLString, privacy: .public)"
        )

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if !data.isEmpty {
                let responseBody = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                logger.error(
                    "Share extension backend error payload for \(responseURLString, privacy: .public): \(String(responseBody.prefix(500)), privacy: .public)"
                )
            }

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

    private static func logBackendDebug(_ debug: RecipeImportDebugInfo?) {
        guard let debug else { return }
        let message = [
            "Share extension backend debug",
            "strategy=\(debug.strategy)",
            "ingredients=\(debug.ingredientsCount)",
            "steps=\(debug.stepsCount)",
            "duration=\(debug.durationMs)ms",
            "valid=\(debug.isLikelyValid)",
            "missing=\(debug.missing.joined(separator: ","))",
            "failureReason=\(debug.failureReason ?? "none")"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
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
    let previewMode: Bool?
}

private struct ShareTextImportRequest: Encodable {
    let text: String
    let imageBase64: String?
    let previewMode: Bool?
}

private struct ShareRecipeImportEnvelope: Decodable {
    let recipe: ShareBackendRecipeSeed
    let debug: ShareBackendImportDebug?
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

    func asSeed(debug: RecipeImportDebugInfo?) -> RecipeEditorSeed {
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
            remoteImageURL: urlIfPresent(remoteImageUrl),
            importDebug: debug
        )
    }
}

private struct ShareBackendImportDebug: Decodable {
    let ingredientsCount: Int
    let stepsCount: Int
    let strategy: String
    let durationMs: Int
    let isLikelyValid: Bool
    let missing: [String]
    let failureReason: String?

    func asImportDebug() -> RecipeImportDebugInfo {
        RecipeImportDebugInfo(
            ingredientsCount: ingredientsCount,
            stepsCount: stepsCount,
            strategy: strategy,
            durationMs: durationMs,
            isLikelyValid: isLikelyValid,
            missing: missing,
            failureReason: failureReason
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
