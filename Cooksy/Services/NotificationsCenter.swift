import Foundation
import OSLog
import Supabase
import UIKit
import UserNotifications

// MARK: - Models

/// Mirrors the JSON shape of `GET /api/notifications/preferences`.
struct NotificationPreferences: Codable, Equatable {
    var marketing_enabled: Bool
    var promo_enabled: Bool
    var suggestion_enabled: Bool
    var reminder_enabled: Bool
    var digest_enabled: Bool
    var category_overrides: [String: Bool]

    static let defaults = NotificationPreferences(
        marketing_enabled: true,
        promo_enabled: true,
        suggestion_enabled: true,
        reminder_enabled: true,
        digest_enabled: true,
        category_overrides: [:]
    )
}

/// Event payload pushed to `POST /api/events`. Kept loose by design so we
/// can add new event types without touching iOS.
struct NotificationEvent: Codable {
    let event_type: String
    let event_data: [String: AnyCodableValue]?
    let occurred_at: String?

    init(
        type: String,
        data: [String: AnyCodableValue]? = nil,
        occurredAt: Date = Date()
    ) {
        self.event_type = type
        self.event_data = data
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.occurred_at = formatter.string(from: occurredAt)
    }
}

/// Heterogeneous JSON value wrapper (Codable). String/Int/Double/Bool/Date.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) {
            self = .int(v); return
        }
        if let v = try? c.decode(Double.self) {
            self = .double(v); return
        }
        if let v = try? c.decode(Bool.self) {
            self = .bool(v); return
        }
        let v = try c.decode(String.self)
        self = .string(v)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        }
    }
}

// MARK: - NotificationsCenter

/// Singleton orchestrator for everything notification-related on iOS:
///
///   - permission state (provisional vs explicit, granted/denied),
///   - APNs token registration (uplink to backend `/api/devices/register`),
///   - reading + writing user preferences,
///   - sending lightweight events to `/api/events` (app.opened, …),
///   - scheduling local notifications (trial timeline, gift expiry, …),
///   - beacon-back when the user opens or taps a remote push.
///
/// This is the single entry point the rest of the app calls. Keep
/// individual call sites free of UNUserNotificationCenter knowledge —
/// they should only see `NotificationsCenter.shared.something()`.
@MainActor
final class NotificationsCenter: NSObject, ObservableObject {
    static let shared = NotificationsCenter()

    private let logger = Logger(subsystem: "com.cooksy.ios", category: "NotificationsCenter")
    private let session: URLSession
    private let center = UNUserNotificationCenter.current()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var apnsTokenHex: String?
    @Published private(set) var preferences: NotificationPreferences = .defaults
    @Published private(set) var lastRegistrationError: String?

    private var hasRegisteredOnce = false

    override private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
        super.init()
        self.center.delegate = self
    }

    // MARK: - Permission

    /// Reads the current authorization status from iOS. Cheap; safe to call
    /// every time a screen that depends on it appears.
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Request **provisional** authorization (Apple's "Quiet Delivery" mode).
    /// No prompt is shown — Apple delivers notifications silently to the
    /// Notification Center. If the user expands or taps one, iOS asks
    /// whether to keep them visible. Perfect post-onboarding entry point
    /// because it can't be denied.
    ///
    /// Returns true if iOS granted the request, false otherwise.
    func requestProvisionalAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .provisional])
            await refreshAuthorizationStatus()
            if granted {
                // Provisional grants don't trigger didRegister automatically
                // on every iOS version — kick the registration explicitly.
                registerForRemoteNotificationsIfPossible()
            }
            return granted
        } catch {
            logger.warning("Provisional auth request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Request **explicit** authorization — shows the iOS prompt. Use this
    /// at points of value (after first import, on trial start, when the
    /// user toggles a category on in settings while currently denied).
    func requestExplicitAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                registerForRemoteNotificationsIfPossible()
            }
            return granted
        } catch {
            logger.warning("Explicit auth request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Ask UIKit for an APNs token. Safe to call repeatedly — UIKit
    /// will short-circuit if we've already registered this launch.
    func registerForRemoteNotificationsIfPossible() {
        guard !hasRegisteredOnce else { return }
        hasRegisteredOnce = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - APNs token uplink (called from AppDelegate)

    func didReceiveAPNsToken(_ data: Data) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        apnsTokenHex = hex
        lastRegistrationError = nil

        // Best-effort upload to the backend. Failures are non-fatal — we'll
        // retry on the next app launch (registerForRemoteNotifications is
        // idempotent on Apple's side).
        await uploadDeviceToken(hex)
    }

    func didFailToRegisterAPNs(_ error: Error) {
        lastRegistrationError = error.localizedDescription
        logger.warning("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Delivered-notification sweep
    //
    // The UN delegate only fires on foreground arrival (`willPresent`) or
    // explicit tap (`didReceive`). A push that lands while the app is
    // backgrounded and gets swiped away never reaches either path — so
    // it never lands in the in-app inbox. Sweep iOS's delivered queue on
    // every foreground transition so the inbox stays a faithful mirror
    // of what the user has actually received.
    func importDeliveredNotifications() async {
        let delivered = await center.deliveredNotifications()
        guard !delivered.isEmpty else { return }
        for notification in delivered {
            let payload = NotificationInbox.IncomingPayload(from: notification)
            NotificationInbox.shared.record(payload)
        }
    }

    // MARK: - Preferences

    /// Fetch the latest preferences from the backend. Falls back to
    /// `.defaults` when unauthenticated or the request fails.
    func loadPreferences() async {
        guard let request = await buildRequest(path: "/api/notifications/preferences", method: "GET") else { return }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: data)
            preferences = decoded
        } catch {
            logger.debug("loadPreferences failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Patch one or more preference fields, then re-fetch to stay
    /// authoritative.
    func updatePreferences(patch: [String: Any]) async {
        guard let request = await buildRequest(
            path: "/api/notifications/preferences",
            method: "POST",
            jsonBody: patch
        ) else { return }
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                logger.warning("updatePreferences non-200: \(http.statusCode, privacy: .public)")
            }
        } catch {
            logger.debug("updatePreferences failed: \(error.localizedDescription, privacy: .public)")
        }
        await loadPreferences()
    }

    // MARK: - Event beacon

    /// Track a single behavioral event. Use the convenience helpers
    /// (`trackAppOpened`, `trackPaywallShown`, …) at call sites to keep
    /// the event-type strings out of view code.
    func track(event: NotificationEvent) async {
        await trackBatch([event])
    }

    func trackBatch(_ events: [NotificationEvent]) async {
        guard !events.isEmpty else { return }
        guard let request = await buildRequest(
            path: "/api/events",
            method: "POST",
            jsonBody: ["events": events.map { event -> [String: Any] in
                var dict: [String: Any] = ["event_type": event.event_type]
                if let data = event.event_data {
                    dict["event_data"] = data.mapValues(anyCodableToAny)
                }
                if let occurredAt = event.occurred_at {
                    dict["occurred_at"] = occurredAt
                }
                return dict
            }]
        ) else { return }
        do {
            _ = try await session.data(for: request)
        } catch {
            logger.debug("trackBatch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Convenience shortcuts called from view code.
    func trackAppOpened() async {
        await track(event: NotificationEvent(type: "app.opened"))
    }
    func trackPaywallShown(source: String) async {
        await track(event: NotificationEvent(
            type: "paywall.shown",
            data: ["source": .string(source)]
        ))
    }
    func trackPaywallClosedWithoutPurchase(source: String) async {
        await track(event: NotificationEvent(
            type: "paywall.closed_without_purchase",
            data: ["source": .string(source)]
        ))
    }
    func trackCookSessionCompleted(recipeId: String, steps: Int) async {
        await track(event: NotificationEvent(
            type: "cook_session.completed",
            data: [
                "recipe_id": .string(recipeId),
                "step_count": .int(steps)
            ]
        ))
    }

    // MARK: - Beacons (opened / tapped)

    /// Report that the user opened or tapped a remote push. Called from
    /// the AppDelegate's UNUserNotificationCenterDelegate methods.
    func reportPushBeacon(dispatchId: String, event: PushBeaconEvent) async {
        guard let request = await buildRequest(
            path: "/api/notifications/\(dispatchId)/beacon",
            method: "POST",
            jsonBody: ["event": event.rawValue]
        ) else { return }
        _ = try? await session.data(for: request)
    }

    enum PushBeaconEvent: String { case opened, tapped }

    // MARK: - Local notifications

    /// Schedule a local notification. We treat local notifications as the
    /// "deterministic timeline" — trial day reminders, gift expiry —
    /// because they keep firing even if the user is offline and don't
    /// cost APNs traffic.
    ///
    /// Identifier semantics: pass a stable id (e.g. "trial_d5_{user_id}")
    /// so subsequent schedules replace earlier ones — `add(_:)` is
    /// upsert-by-identifier.
    func scheduleLocalNotification(
        id: String,
        title: String,
        body: String,
        fireAt date: Date,
        deepLink: String? = nil,
        categoryId: String = "default"
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let deepLink {
            content.userInfo = ["cooksy_deep_link": deepLink, "cooksy_local": true]
        }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { [logger] error in
            if let error {
                logger.warning("scheduleLocalNotification(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Cancel one or more scheduled local notifications by identifier.
    /// Useful when state changes invalidate a scheduled push (e.g. the
    /// user converted, so we cancel the trial-ending reminders).
    func cancelLocalNotifications(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Inspect what's currently pending. Useful in debug builds + tests.
    func pendingLocalNotificationIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map { $0.identifier }
    }

    // MARK: - Internals

    private func uploadDeviceToken(_ tokenHex: String) async {
        var payload: [String: Any] = [
            "apns_token": tokenHex,
            "apns_environment": NotificationsCenter.currentApnsEnvironment(),
            "device_model": UIDevice.current.modelIdentifier,
            "app_version": Bundle.main.shortVersion ?? "unknown",
            "os_version": UIDevice.current.systemVersion,
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier
        ]
        payload["push_authorization_status"] = authorizationStatusString

        guard let request = await buildRequest(
            path: "/api/devices/register",
            method: "POST",
            jsonBody: payload
        ) else {
            logger.debug("Skipping device upload — backend or session unavailable.")
            return
        }
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                logger.warning("uploadDeviceToken non-2xx: \(http.statusCode, privacy: .public)")
            }
        } catch {
            logger.debug("uploadDeviceToken failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var authorizationStatusString: String {
        switch authorizationStatus {
        case .authorized:    return "authorized"
        case .provisional:   return "provisional"
        case .denied:        return "denied"
        case .ephemeral:     return "ephemeral"
        case .notDetermined: return "unknown"
        @unknown default:    return "unknown"
        }
    }

    private static func currentApnsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Builds an authenticated URLRequest pointing at the backend. Returns
    /// nil if either the base URL or the Supabase access token is unavailable
    /// — caller should short-circuit silently.
    private func buildRequest(
        path: String,
        method: String,
        jsonBody: Any? = nil
    ) async -> URLRequest? {
        guard let baseURL = AppConfiguration.backendBaseURL else { return nil }
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if jsonBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let session = try? await SupabaseClientProvider.shared.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            // Endpoints all require auth — bail.
            return nil
        }

        if let jsonBody {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
            } catch {
                logger.warning("JSON encoding failed for \(path, privacy: .public)")
                return nil
            }
        }
        return request
    }

    private func anyCodableToAny(_ value: AnyCodableValue) -> Any {
        switch value {
        case .string(let v): return v
        case .int(let v):    return v
        case .double(let v): return v
        case .bool(let v):   return v
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationsCenter: UNUserNotificationCenterDelegate {
    /// Called when a notification arrives while the app is in the
    /// foreground. We choose to suppress the banner (the user is
    /// already with us) but still post to the Notification Center.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Mirror the delivered notification into the in-app inbox so
        // the home-screen bell badge picks it up immediately, even if
        // the user never taps the iOS banner. UNNotification itself
        // isn't Sendable — extract a value-typed snapshot here.
        let payload = NotificationInbox.IncomingPayload(from: notification)
        Task { @MainActor in
            NotificationInbox.shared.record(payload)
        }
        completionHandler([.list, .sound])
    }

    /// Called when the user taps a notification (foreground or
    /// background). Beacon the tap, then hand the deep-link off to the
    /// DeepLinkRouter via the AppDelegate's pendingURL.
    ///
    /// Note on concurrency: we resolve the completion handler *before*
    /// spawning the async Task so Swift 6's strict concurrency doesn't
    /// flag a data race on the captured non-Sendable closure. Apple is
    /// happy as long as the completion handler is called on the same
    /// run-loop tick — the analytics beacon and the deep-link write can
    /// run asynchronously afterwards without holding up iOS.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notification = response.notification
        let userInfo = notification.request.content.userInfo
        let dispatchId = userInfo["cooksy_dispatch_id"] as? String
        let deepLinkString = userInfo["cooksy_deep_link"] as? String
        // Snapshot the notification into a Sendable struct here so the
        // off-actor Task below stays Swift-6 strict-concurrency clean.
        let inboxPayload = NotificationInbox.IncomingPayload(from: notification)
        let requestID = notification.request.identifier

        // Fire-and-forget side effects.
        Task { @MainActor in
            // Ensure the tapped notification is in the inbox AND
            // marked read (the user has clearly seen it).
            NotificationInbox.shared.record(inboxPayload)
            if let existing = NotificationInbox.shared.items.first(where: {
                $0.requestIdentifier == requestID
            }) {
                NotificationInbox.shared.markRead(id: existing.id)
            }

            if let dispatchId {
                await NotificationsCenter.shared.reportPushBeacon(
                    dispatchId: dispatchId,
                    event: .tapped
                )
            }
            if let deepLinkString, let url = URL(string: deepLinkString) {
                if let appDelegate = UIApplication.shared.delegate as? CooksyAppDelegate {
                    appDelegate.pendingURL = url
                }
            }
        }

        completionHandler()
    }
}

// MARK: - Helpers

private extension UIDevice {
    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { acc, element in
            guard let value = element.value as? Int8, value != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

private extension Bundle {
    var shortVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
