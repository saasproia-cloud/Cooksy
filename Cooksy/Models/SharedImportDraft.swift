import Foundation

struct SharedImportDraft: Codable, Equatable, Hashable {
    var urlString: String?
    var sourceApp: String?
    var sharedText: String?
    var sharedImageFilename: String?
    var capturedAt: Date

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var hasPayload: Bool {
        url != nil ||
            !(sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            sharedImageFilename != nil
    }

    var hostLabel: String {
        if let host = url?.host, !host.isEmpty {
            return host
        }

        if let sourceApp, !sourceApp.isEmpty {
            return sourceApp
        }

        if let sharedText = sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), !sharedText.isEmpty {
            return sharedText
        }

        return urlString ?? "Import partagé"
    }

    var combinedTextContext: String {
        [sharedText?.trimmingCharacters(in: .whitespacesAndNewlines), url?.absoluteString]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n")
    }

    var dedupeKey: String {
        [
            urlString ?? "",
            sourceApp ?? "",
            sharedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            sharedImageFilename ?? "",
            ISO8601DateFormatter().string(from: capturedAt)
        ]
        .joined(separator: "|")
    }
}
