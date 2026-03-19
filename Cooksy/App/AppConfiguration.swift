import Foundation

enum AppConfiguration {
    static var backendBaseURL: URL? {
        let rawValue =
            ProcessInfo.processInfo.environment["BACKEND_BASE_URL"] ??
            Bundle.main.object(forInfoDictionaryKey: "CooksyBackendBaseURL") as? String

        guard
            let rawValue,
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
