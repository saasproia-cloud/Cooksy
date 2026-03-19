import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
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
        let hostingController = UIHostingController(rootView: ShareExtensionRootView(state: state))

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
        state.phase = .loading

        do {
            let draft = try await extractSharedDraft()
            sharedLinkInbox.enqueue(draft: draft)
            state.phase = .success(draft.hostLabel)

            try? await Task.sleep(nanoseconds: 450_000_000)
            await openCooksyApp()
        } catch {
            state.phase = .failure("Cooksy n'a pas trouve de lien compatible dans ce partage.")
        }
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

        let draft = SharedImportDraft(
            urlString: foundURL?.absoluteString,
            sourceApp: nil,
            sharedText: foundText,
            sharedImageFilename: foundImageFilename,
            capturedAt: .now
        )

        guard draft.hasPayload else {
            throw ShareImportError.noURLFound
        }

        return draft
    }

    @MainActor
    private func openCooksyApp() async {
        guard let extensionContext else { return }
        guard let appURL = URL(string: "cooksy://shared-import") else {
            extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        await withCheckedContinuation { continuation in
            extensionContext.open(appURL) { _ in
                extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
                continuation.resume()
            }
        }
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
                    continuation.resume(returning: URL(string: text))
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
}

private enum ShareImportError: Error {
    case noURLFound
}

@MainActor
private final class ShareExtensionState: ObservableObject {
    @Published var phase: ShareExtensionPhase = .loading
}

private enum ShareExtensionPhase {
    case loading
    case success(String)
    case failure(String)

    var title: String {
        switch self {
        case .loading:
            return "Import dans Cooksy"
        case .success:
            return "Lien capture"
        case .failure:
            return "Import incomplet"
        }
    }

    var message: String {
        switch self {
        case .loading:
            return "Nous analysons le lien partage pour le preparer dans l'application."
        case .success(let host):
            return "Le lien provenant de \(host) est maintenant pret a etre transforme en recette."
        case .failure(let message):
            return message
        }
    }

    var tint: Color {
        switch self {
        case .loading:
            return Color(hex: 0x6FA8FF)
        case .success:
            return Color(hex: 0xFF7A12)
        case .failure:
            return Color(hex: 0xC56A56)
        }
    }

    var systemImage: String {
        switch self {
        case .loading:
            return "sparkles"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct ShareExtensionRootView: View {
    @ObservedObject var state: ShareExtensionState

    var body: some View {
        ZStack {
            Color(hex: 0xF7F4EE)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(state.phase.tint.opacity(0.16))
                        .frame(width: 84, height: 84)

                    Image(systemName: state.phase.systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(state.phase.tint)

                    if case .loading = state.phase {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(state.phase.tint)
                            .offset(y: 58)
                    }
                }

                Text(state.phase.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(Color(hex: 0x231E18))

                Text(state.phase.message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8E877A))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
