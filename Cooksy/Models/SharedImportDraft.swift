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
    var capturedAt: Date

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var preferredImportURL: URL? {
        if let url, url.isWebImportURL {
            return url
        }

        return Self.firstWebURL(in: sharedText)
    }

    var hasPayload: Bool {
        url != nil ||
            preparedSeed != nil ||
            !(sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            sharedImageFilename != nil
    }

    var hostLabel: String {
        if let host = preferredImportURL?.host, !host.isEmpty {
            return host
        }

        if let host = url?.host, !host.isEmpty {
            return host
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
            ISO8601DateFormatter().string(from: capturedAt)
        ]
        .joined(separator: "|")
    }

    private static func firstWebURL(in text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector?.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first(where: { $0.isWebImportURL })
    }
}

private extension URL {
    var isWebImportURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
