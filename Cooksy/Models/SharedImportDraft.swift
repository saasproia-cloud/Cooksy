import Foundation

enum SharedImportHandoffAction: String, Codable, Hashable {
    case reviewInApp
    case saveInApp
    case createManuallyInApp
}

struct SharedImportDraft: Codable, Equatable, Hashable {
    var urlString: String?
    var sourceApp: String?
    var sharedText: String?
    var sharedImageFilename: String?
    var preparedSeed: RecipeEditorSeed?
    var handoffAction: SharedImportHandoffAction?
    var handoffToken: String?
    var capturedAt: Date

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var preferredImportURL: URL? {
        if let sharedTextURL = Self.preferredWebURL(in: sharedText, relativeTo: url) {
            return sharedTextURL
        }

        if let url, url.isWebImportURL {
            return url
        }

        return nil
    }

    var hasPayload: Bool {
        url != nil ||
            preparedSeed != nil ||
            !(sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            sharedImageFilename != nil
    }

    var hostLabel: String {
        if let host = preferredImportURL?.host, !host.isEmpty {
            return Self.presentableHostLabel(for: host)
        }

        if let host = url?.host, !host.isEmpty {
            return Self.presentableHostLabel(for: host)
        }

        if let sourceApp, !sourceApp.isEmpty {
            return sourceApp
        }

        if let title = preparedSeed?.normalizedTitle, !title.isEmpty {
            return title
        }

        if let sharedText = sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), !sharedText.isEmpty {
            return sharedText
        }

        return urlString ?? "Import partagé"
    }

    var isLikelyVideoImport: Bool {
        let candidates = [
            preferredImportURL?.host,
            url?.host,
            sourceApp
        ]
        .compactMap { $0?.lowercased() }

        return candidates.contains { value in
            value.contains("tiktok") || value.contains("instagram") || value.contains("reel")
        }
    }

    var combinedTextContext: String {
        [sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), preferredImportURL?.absoluteString]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n")
    }

    var dedupeKey: String {
        [
            preferredImportURL?.absoluteString ?? urlString ?? "",
            sourceApp ?? "",
            sharedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            sharedImageFilename ?? "",
            preparedSeed?.normalizedTitle ?? "",
            handoffAction?.rawValue ?? "",
            handoffToken ?? "",
            ISO8601DateFormatter().string(from: capturedAt)
        ]
        .joined(separator: "|")
    }

    private static func preferredWebURL(in text: String?, relativeTo baseURL: URL?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let webURLs = detector?.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter(\.isWebImportURL) ?? []

        guard webURLs.isEmpty == false else {
            return nil
        }

        if let baseURL, baseURL.isSocialImportURL {
            if let externalRecipeURL = webURLs.first(where: { !$0.isSocialImportURL }) {
                return externalRecipeURL
            }
        }

        return webURLs.first
    }

    private static func presentableHostLabel(for host: String) -> String {
        let normalizedHost = host.lowercased()

        if normalizedHost.contains("tiktok") {
            return "TikTok"
        }

        if normalizedHost.contains("instagram") {
            return "Instagram"
        }

        if normalizedHost.contains("pinterest") || normalizedHost.contains("pin.it") {
            return "Pinterest"
        }

        return host
    }
}

private extension URL {
    var isWebImportURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var isSocialImportURL: Bool {
        guard let host = host?.lowercased() else { return false }

        return host.contains("tiktok") ||
            host.contains("instagram") ||
            host.contains("pinterest") ||
            host.contains("pin.it")
    }
}
