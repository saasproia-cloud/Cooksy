import Foundation
import OSLog

enum AppConfiguration {
    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "AppConfiguration")

    static var backendBaseURL: URL? {
        backendBaseURLConfiguration.url
    }

    static var backendBaseURLValidationError: String? {
        backendBaseURLConfiguration.validationError
    }

    static var backendBaseURLDebugValue: String? {
        backendBaseURLConfiguration.normalizedValue
    }

    static var backendBaseURLSource: String? {
        backendBaseURLConfiguration.source
    }

    private static var backendBaseURLConfiguration: BackendBaseURLConfiguration {
        resolveBackendBaseURLConfiguration()
    }

    private static func resolveBackendBaseURLConfiguration() -> BackendBaseURLConfiguration {
        let candidates = [
            BackendBaseURLCandidate(
                source: "environment variable BACKEND_BASE_URL",
                rawValue: ProcessInfo.processInfo.environment["BACKEND_BASE_URL"]
            ),
            BackendBaseURLCandidate(
                source: "Info.plist CooksyBackendBaseURL",
                rawValue: Bundle.main.object(forInfoDictionaryKey: "CooksyBackendBaseURL") as? String
            )
        ]

        var firstInvalidConfiguration: BackendBaseURLConfiguration?

        for candidate in candidates where candidate.rawValue != nil {
            let configuration = validateBackendBaseURL(candidate.rawValue, source: candidate.source)

            if configuration.isValid {
                logger.debug(
                    "Resolved BACKEND_BASE_URL from \(candidate.source, privacy: .public): \(configuration.normalizedValue ?? "(nil)", privacy: .public)"
                )
                return configuration
            }

            if firstInvalidConfiguration == nil {
                firstInvalidConfiguration = configuration
            }

            logger.error(
                "Invalid BACKEND_BASE_URL from \(candidate.source, privacy: .public): \(configuration.validationError ?? "Unknown error", privacy: .public)"
            )
        }

        return firstInvalidConfiguration ?? BackendBaseURLConfiguration(
            source: nil,
            rawValue: nil,
            normalizedValue: nil,
            url: nil,
            validationError: "BACKEND_BASE_URL n'est pas configurée."
        )
    }

    private static func validateBackendBaseURL(_ rawValue: String?, source: String) -> BackendBaseURLConfiguration {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedValue.isEmpty else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: nil,
                url: nil,
                validationError: "BACKEND_BASE_URL est vide."
            )
        }

        guard !trimmedValue.contains(where: { $0.isWhitespace }) else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL contient des espaces ou retours à la ligne invalides."
            )
        }

        guard var components = URLComponents(string: trimmedValue) else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL est mal formée: \(trimmedValue)"
            )
        }

        guard let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL doit inclure un schéma complet, par exemple https://cooksy-production-bbd1.up.railway.app"
            )
        }

        guard let host = components.host, !host.isEmpty else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL n'a pas d'hôte valide."
            )
        }

        if requiresSecureBackendBaseURL, scheme != "https" {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL doit commencer par https:// sur iPhone réel."
            )
        }

        if components.path.isEmpty {
            components.path = ""
        }

        guard let url = components.url else {
            return BackendBaseURLConfiguration(
                source: source,
                rawValue: rawValue,
                normalizedValue: trimmedValue,
                url: nil,
                validationError: "BACKEND_BASE_URL ne peut pas être convertie en URL valide."
            )
        }

        return BackendBaseURLConfiguration(
            source: source,
            rawValue: rawValue,
            normalizedValue: url.absoluteString,
            url: url,
            validationError: nil
        )
    }

    private static var requiresSecureBackendBaseURL: Bool {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }
}

private struct BackendBaseURLCandidate {
    let source: String
    let rawValue: String?
}

private struct BackendBaseURLConfiguration {
    let source: String?
    let rawValue: String?
    let normalizedValue: String?
    let url: URL?
    let validationError: String?

    var isValid: Bool {
        url != nil
    }
}
