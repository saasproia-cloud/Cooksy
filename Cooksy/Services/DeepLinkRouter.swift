import Foundation
import OSLog

/// Resolves `cooksy://` URLs into a typed `DeepLinkDestination` the UI
/// can route on.
///
/// Pattern reference (kept in sync with backend templates):
///   cooksy://home
///   cooksy://import
///   cooksy://library
///   cooksy://recipe/{id}
///   cooksy://paywall            ?source=quota_push&gift=1
///   cooksy://profile/subscription
///   cooksy://profile/stats
///   cooksy://gift
///   cooksy://plan
///   cooksy://home/trending
///
/// Unknown links default to `.home` rather than failing — pushes should
/// always land the user somewhere reasonable.
enum DeepLinkDestination: Equatable {
    case home
    case homeTrending
    case importRecipe
    case library
    case recipe(id: String)
    case paywall(source: String?, gift: Bool)
    case profileSubscription
    case profileStats
    case gift
    case plan
}

enum DeepLinkRouter {
    static let scheme = "cooksy"

    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "DeepLinkRouter")

    /// Returns nil if the URL is not a Cooksy deep link (e.g. an https://
    /// universal link or a foreign scheme). The caller can then fall
    /// back to its default URL handler.
    static func destination(for url: URL) -> DeepLinkDestination? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // URL components for cooksy:// scheme behave a bit oddly — the
        // "host" portion holds the first segment (e.g. "recipe") and the
        // path holds the rest ("/{id}"). Normalize to a single segments
        // array so we don't have to special-case host vs path everywhere.
        let host = url.host?.lowercased() ?? ""
        let pathSegments = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
        var segments = [host] + pathSegments
        segments.removeAll(where: { $0.isEmpty })

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        let source = queryItems.first(where: { $0.name == "source" })?.value
        let gift = queryItems.first(where: { $0.name == "gift" })?.value == "1"

        guard let first = segments.first else { return .home }

        switch first {
        case "home":
            if segments.count >= 2, segments[1] == "trending" {
                return .homeTrending
            }
            return .home

        case "import":
            return .importRecipe

        case "library":
            return .library

        case "recipe":
            guard segments.count >= 2 else {
                logger.debug("Malformed cooksy://recipe link, falling back to library.")
                return .library
            }
            return .recipe(id: segments[1])

        case "paywall":
            return .paywall(source: source, gift: gift)

        case "profile":
            if segments.count >= 2 {
                switch segments[1] {
                case "subscription": return .profileSubscription
                case "stats":        return .profileStats
                default:             return .home
                }
            }
            return .home

        case "gift":
            return .gift

        case "plan":
            return .plan

        default:
            logger.warning("Unknown deep link host=\(first, privacy: .public)")
            return .home
        }
    }
}
