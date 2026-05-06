import SwiftUI
import WebKit
import OSLog

@MainActor
struct BrowserImportView: View {
    @Environment(\.dismiss) private var dismiss

    let initialURL: URL?
    let onImported: (RecipeImportAssessment) -> Void

    @StateObject private var viewModel = BrowserImportViewModel()

    init(initialURL: URL? = nil, onImported: @escaping (RecipeImportAssessment) -> Void) {
        self.initialURL = initialURL
        self.onImported = onImported
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                brandBar

                Group {
                    if viewModel.hasLoadedPage {
                        browserContent
                    } else {
                        landingContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if viewModel.isImporting {
                RecipeImportLoadingView(
                    source: .webPage,
                    title: "Analyse Cooksy"
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .task {
            guard let initialURL else { return }
            viewModel.load(url: initialURL)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                TextField(
                    "",
                    text: $viewModel.addressText,
                    prompt: Text("Recherchez ou saisissez un site...")
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.9))
                )
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        viewModel.submitAddress()
                    }

                Button(action: viewModel.reloadOrSubmit) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(CooksyTheme.primaryText)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.75), lineWidth: 1.4)
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 16, y: 8)
            )
        }
    }

    private var brandBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Navigateur Cooksy")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Ouvrez une recette ou collez un lien, Cooksy s'occupe du reste.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.8), lineWidth: 1.2)
                    )

                Image("HeaderLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 88)
        .background(
            LinearGradient(
                colors: [CooksyTheme.softCloud, Color.white.opacity(0.92)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.7))
                .frame(height: 1)
        }
    }

    private var browserContent: some View {
        ZStack(alignment: .top) {
            BrowserWebView(webView: viewModel.webView)

            if viewModel.isLoading {
                ProgressView()
                    .tint(CooksyTheme.brandBlueDark)
                    .padding(.top, 16)
            }
        }
    }

    private var landingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)

            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.92), CooksyTheme.warmCard.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        Image("HeaderLogo")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82, height: 82)
                    )
                    .shadow(color: CooksyTheme.shadow, radius: 22, y: 12)

                Text("Trouvez, importez, cuisinez.")
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Cooksy sait lire une page recette, récupérer un lien social ou partir d'une simple recherche web.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }

            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(CooksyTheme.secondaryText)

                TextField(
                    "",
                    text: $viewModel.addressText,
                    prompt: Text("Search for a recipe or paste a URL")
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.92))
                )
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.submitAddress()
                    }
            }
            .padding(.horizontal, 24)
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(CooksyTheme.stroke.opacity(0.95), lineWidth: 2)
            )
            .padding(.horizontal, 38)
            .padding(.top, 34)

            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            Button(action: importCurrentPage) {
                Text(viewModel.importButtonTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.canImport ? CooksyTheme.primaryText : CooksyTheme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canImport || viewModel.isImporting)
            .buttonStyle(.plain)

            HStack(spacing: 40) {
                Button(action: viewModel.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(viewModel.canGoBack ? CooksyTheme.secondaryText : CooksyTheme.stroke)
                }
                .disabled(!viewModel.canGoBack)
                .buttonStyle(.plain)

                Button(action: viewModel.goForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(viewModel.canGoForward ? CooksyTheme.secondaryText : CooksyTheme.stroke)
                }
                .disabled(!viewModel.canGoForward)
                .buttonStyle(.plain)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 24, y: -4)
        )
    }

    private func importCurrentPage() {
        Task {
            do {
                let seed = try await viewModel.importCurrentPage()
                onImported(seed)
            } catch {
                // The import failed (TikTok with no caption, no usable recipe,
                // …). Instead of surfacing a system alert, route through the
                // OOPS failure screen so the user gets a tailored CTA back to
                // the source video.
                let fallbackURL = viewModel.currentURL
                let failureSeed = RecipeEditorSeed(
                    sourceURL: fallbackURL,
                    importDebug: RecipeImportDebugInfo(
                        ingredientsCount: 0,
                        stepsCount: 0,
                        strategy: "browser",
                        durationMs: 0,
                        isLikelyValid: false,
                        missing: ["ingredients", "steps"],
                        failureReason: "not_food",
                        needsReview: false
                    )
                )
                let assessment = RecipeValidationService.assess(
                    failureSeed,
                    sourceKind: .url
                )
                onImported(assessment)
            }
        }
    }
}

private final class BrowserImportViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "BrowserImportViewModel")

    enum RecipeDetectionState: Equatable {
        case idle
        case scanning
        case ready
        case unavailable
    }

    @Published var addressText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasLoadedPage = false
    @Published private(set) var isImporting = false
    @Published private(set) var detectionState: RecipeDetectionState = .idle

    let webView: WKWebView
    var currentURL: URL? {
        webView.url ?? lastSuccessfulURL
    }
    private var lastSuccessfulURL: URL?
    private var cachedSnapshotJSON: String?
    private var cachedSnapshotURL: String?
    private var detectionTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    var canImport: Bool {
        hasLoadedPage && !isLoading && detectionState != .scanning
    }

    var importButtonTitle: String {
        if isImporting {
            return "Import en cours..."
        }

        switch detectionState {
        case .idle:
            return "Ouvrir une recette à importer"
        case .scanning:
            return "Analyse de la recette..."
        case .ready:
            return "Ouvrir une recette à importer"
        case .unavailable:
            return "Essayer d'importer cette page"
        }
    }

    func submitAddress() {
        guard let url = resolvedURL(for: addressText) else { return }
        load(url: url)
    }

    func load(url: URL) {
        resetDetectionState()
        addressText = url.absoluteString
        isLoading = true
        logger.debug("Browser import loading \(url.absoluteString, privacy: .public)")
        webView.load(URLRequest(url: url))
    }

    func reloadOrSubmit() {
        if hasLoadedPage {
            resetDetectionState()
            webView.reload()
        } else {
            submitAddress()
        }
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func importCurrentPage() async throws -> RecipeImportAssessment {
        guard hasLoadedPage else {
            throw RecipeWebImportError.noRecipeFound
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let snapshotJSON = try await currentSnapshotJSON()
            return try await Task.detached(priority: .userInitiated) {
                let seed = try RecipeWebImportService.importRecipe(from: snapshotJSON)
                return RecipeValidationService.assess(seed, sourceKind: .url)
            }.value
        } catch {
            guard let currentURL = webView.url else {
                throw error
            }

            return try await RecipeImportPipeline.importURLAssessment(currentURL)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        resetDetectionState()
        isLoading = true
        syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        lastSuccessfulURL = webView.url
        syncNavigationState()
        startRecipeDetection()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !shouldIgnoreNavigationError(error) else {
            isLoading = false
            syncNavigationState()
            return
        }
        isLoading = false
        syncNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !shouldIgnoreNavigationError(error) else {
            isLoading = false
            syncNavigationState()
            return
        }
        isLoading = false
        syncNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        guard isSupportedInAppURL(url) else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url, isSupportedInAppURL(url) else {
            return nil
        }

        webView.load(URLRequest(url: url))
        return nil
    }

    private func syncNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        hasLoadedPage = lastSuccessfulURL != nil
        if let currentURL = webView.url?.absoluteString {
            addressText = currentURL
        }
    }

    private func resolvedURL(for input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if
            let explicitComponents = URLComponents(string: trimmed),
            let scheme = explicitComponents.scheme,
            !scheme.isEmpty,
            let explicitURL = explicitComponents.url
        {
            return explicitURL
        }

        if !trimmed.contains(" "), trimmed.contains(".") {
            return httpsURL(for: trimmed)
        }

        return googleSearchURL(for: trimmed)
    }

    private func httpsURL(for input: String) -> URL? {
        let separatorIndex = input.firstIndex(of: "/") ?? input.endIndex
        let host = String(input[..<separatorIndex])
        guard !host.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host

        if separatorIndex != input.endIndex {
            let remainder = String(input[separatorIndex...])
            if let remainderComponents = URLComponents(string: remainder) {
                components.percentEncodedPath = remainderComponents.percentEncodedPath
                components.queryItems = remainderComponents.queryItems
                components.fragment = remainderComponents.fragment
            } else {
                components.percentEncodedPath = remainder
            }
        }

        return components.url
    }

    private func googleSearchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private func isSupportedInAppURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "about", "data", "blob"].contains(scheme)
    }

    private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        if nsError.domain == WKErrorDomain,
           nsError.code == 102
        {
            return true
        }

        return false
    }

    private func resetDetectionState() {
        detectionTask?.cancel()
        detectionTask = nil
        detectionState = .idle
        cachedSnapshotJSON = nil
        cachedSnapshotURL = nil
    }

    private func startRecipeDetection() {
        guard let currentURL = webView.url?.absoluteString else { return }

        detectionTask?.cancel()
        detectionState = .scanning

        detectionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshotJSON = try await self.evaluateJavaScriptString(RecipeWebImportService.pageExtractionJavaScript)
                guard !Task.isCancelled else { return }

                let canImport = await Task.detached(priority: .userInitiated) {
                    RecipeWebImportService.canImportRecipe(from: snapshotJSON)
                }.value

                guard !Task.isCancelled else { return }
                guard self.webView.url?.absoluteString == currentURL else { return }

                self.cachedSnapshotJSON = snapshotJSON
                self.cachedSnapshotURL = currentURL
                self.detectionState = canImport ? .ready : .unavailable
            } catch {
                guard !Task.isCancelled else { return }
                guard self.webView.url?.absoluteString == currentURL else { return }
                self.detectionState = .unavailable
            }
        }
    }

    private func currentSnapshotJSON() async throws -> String {
        if let currentURL = webView.url?.absoluteString,
           cachedSnapshotURL == currentURL,
           let cachedSnapshotJSON
        {
            return cachedSnapshotJSON
        }

        let snapshotJSON = try await evaluateJavaScriptString(RecipeWebImportService.pageExtractionJavaScript)
        cachedSnapshotJSON = snapshotJSON
        cachedSnapshotURL = webView.url?.absoluteString
        return snapshotJSON
    }

    private func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let stringResult = result as? String ?? ""
                    continuation.resume(returning: stringResult)
                }
            }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
