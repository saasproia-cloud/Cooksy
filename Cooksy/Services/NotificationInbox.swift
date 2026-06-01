import Combine
import Foundation
import OSLog
import UserNotifications

/// One row in the in-app notifications inbox. Mirrors the most-useful
/// fields from `UNNotification` (title, body, delivery date, optional
/// deep-link) plus an `isRead` flag so the bell badge can show the
/// unread count.
struct NotificationInboxItem: Codable, Identifiable, Equatable {
    let id: UUID
    let requestIdentifier: String
    let title: String
    let body: String
    let deliveredAt: Date
    var isRead: Bool
    let deepLink: URL?
    /// Optional category key for surfacing an icon in the row UI
    /// (e.g. "trial", "gift", "import", "system"). Best-effort —
    /// the row falls back to a neutral bell glyph when nil.
    let category: String?
}

/// Keeps a persistent history of every UNNotification the user receives
/// so the home-screen bell can route to a real inbox instead of the
/// settings tab. Items are persisted to a JSON file in the app group
/// so the share extension can also append (future use).
///
/// State transitions:
///   • `record(from:)`  — append a new item (`isRead: false`)
///   • `markRead(id:)`  — flip a single item to read
///   • `markAllAsRead()` — bulk-clear the unread badge
///   • `removeItem(id:)` — swipe-to-delete
///   • `clear()`        — wipe everything (account deletion)
@MainActor
final class NotificationInbox: ObservableObject {
    static let shared = NotificationInbox()

    /// Cap on how many items we keep. iOS itself rotates Notification
    /// Center after ~50, so anything beyond 100 here is unread noise.
    private static let maxItems: Int = 100

    @Published private(set) var items: [NotificationInboxItem] = []

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    var hasUnread: Bool {
        unreadCount > 0
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "NotificationInbox")
    private var accountDeletionObserver: NSObjectProtocol?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()

        // Lifetime-scoped — the inbox lives for the app's lifetime so
        // no deinit cleanup is required (Swift 6's actor isolation
        // would also forbid touching the captured observer).
        accountDeletionObserver = NotificationCenter.default.addObserver(
            forName: .cooksyAccountDeleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clear()
            }
        }
    }

    // MARK: - Public API

    /// Sendable snapshot of a `UNNotification` — used by the
    /// nonisolated `UNUserNotificationCenterDelegate` methods to hand
    /// off to the @MainActor inbox without tripping Swift 6's
    /// strict-concurrency checks (UNNotification itself isn't Sendable).
    struct IncomingPayload: Sendable {
        let requestIdentifier: String
        let title: String
        let body: String
        let deliveredAt: Date
        let deepLink: URL?
        let category: String?

        init(from notification: UNNotification) {
            let request = notification.request
            let content = request.content
            self.requestIdentifier = request.identifier
            self.title = content.title.isEmpty ? "Cooksy" : content.title
            self.body = content.body
            self.deliveredAt = notification.date
            self.deepLink = (content.userInfo["cooksy_deep_link"] as? String)
                .flatMap(URL.init(string:))
            self.category = content.userInfo["cooksy_category"] as? String
                ?? NotificationInbox.inferCategory(fromIdentifier: request.identifier)
        }
    }

    /// Records a delivered notification into the inbox. Deduplicates on
    /// `requestIdentifier` so a redelivery (foreground willPresent +
    /// later tap) doesn't create two rows.
    func record(_ payload: IncomingPayload) {
        let requestID = payload.requestIdentifier

        if let existingIndex = items.firstIndex(where: { $0.requestIdentifier == requestID }) {
            items[existingIndex] = NotificationInboxItem(
                id: items[existingIndex].id,
                requestIdentifier: requestID,
                title: items[existingIndex].title,
                body: items[existingIndex].body,
                deliveredAt: payload.deliveredAt,
                isRead: items[existingIndex].isRead,
                deepLink: items[existingIndex].deepLink,
                category: items[existingIndex].category
            )
            persist()
            return
        }

        let item = NotificationInboxItem(
            id: UUID(),
            requestIdentifier: requestID,
            title: payload.title,
            body: payload.body,
            deliveredAt: payload.deliveredAt,
            isRead: false,
            deepLink: payload.deepLink,
            category: payload.category
        )

        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        persist()
    }

    /// Convenience overload used from @MainActor contexts where we
    /// already hold a `UNNotification` (e.g. the inbox UI's foreground
    /// sync). Off-actor delegate code MUST go through `IncomingPayload`
    /// to stay Sendable-clean.
    func record(from notification: UNNotification) {
        record(IncomingPayload(from: notification))
    }

    /// Polls iOS for already-delivered notifications and folds them
    /// into the inbox. Use on app foreground so the user doesn't miss
    /// notifications that arrived while the app wasn't running and
    /// were never tapped.
    func syncDeliveredFromSystem() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for notification in delivered {
            record(from: notification)
        }
    }

    func markRead(id: NotificationInboxItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if !items[index].isRead {
            items[index].isRead = true
            persist()
        }
    }

    func markAllAsRead() {
        var didChange = false
        for index in items.indices where !items[index].isRead {
            items[index].isRead = true
            didChange = true
        }
        if didChange { persist() }
    }

    func removeItem(id: NotificationInboxItem.ID) {
        let original = items.count
        items.removeAll { $0.id == id }
        if items.count != original { persist() }
    }

    func clear() {
        guard !items.isEmpty else { return }
        items = []
        persist()
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let baseDirectory =
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupID) ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseDirectory
            .appendingPathComponent("Cooksy", isDirectory: true)
            .appendingPathComponent("notifications-inbox.json")
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            items = try decoder.decode([NotificationInboxItem].self, from: data)
        } catch {
            // File doesn't exist yet on first run, or schema drift.
            items = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            let directory = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            logger.error("NotificationInbox persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Best-effort category inference from the local notification's
    /// scheduler identifier. Keeps the inbox UI varied without
    /// requiring every payload to carry an explicit `cooksy_category`.
    /// `nonisolated` so the Sendable `IncomingPayload` initialiser
    /// can call it from any actor context.
    nonisolated static func inferCategory(fromIdentifier id: String) -> String? {
        let lower = id.lowercased()
        if lower.contains("trial") { return "trial" }
        if lower.contains("gift")  { return "gift" }
        if lower.contains("import") || lower.contains("recipe") { return "import" }
        if lower.contains("quota") { return "import" }
        if lower.contains("welcome") || lower.contains("celebrate") { return "system" }
        return nil
    }
}
