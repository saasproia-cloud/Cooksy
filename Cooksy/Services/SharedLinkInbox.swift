import Foundation

struct SharedLinkInbox {
    static let appGroupID = "group.com.cooksy.shared"
    private static let pendingImportsDirectoryName = "PendingImports"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let key = "cooksy.pending.shared.import"

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: SharedLinkInbox.appGroupID),
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults ?? .standard
        self.fileManager = fileManager
    }

    func enqueue(
        url: URL,
        sourceApp: String? = nil,
        sharedText: String? = nil,
        sharedImageFilename: String? = nil
    ) {
        let draft = SharedImportDraft(
            urlString: url.absoluteString,
            sourceApp: sourceApp,
            sharedText: sharedText,
            sharedImageFilename: sharedImageFilename,
            preparedSeed: nil,
            handoffAction: nil,
            capturedAt: .now
        )
        save(draft)
    }

    func enqueue(draft: SharedImportDraft) {
        save(draft)
    }

    func peek() -> SharedImportDraft? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedImportDraft.self, from: data)
    }

    @discardableResult
    func consume() -> SharedImportDraft? {
        let draft = peek()
        clear()
        return draft
    }

    func clear() {
        if let existingDraft = peek() {
            deletePendingImage(for: existingDraft.sharedImageFilename)
        }
        defaults.removeObject(forKey: key)
    }

    func storePendingImageData(_ data: Data) -> String? {
        guard let directoryURL = pendingImportsDirectoryURL() else { return nil }

        let filename = "shared-\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: [.atomic])
            return filename
        } catch {
            assertionFailure("Unable to store shared image: \(error)")
            return nil
        }
    }

    func imageData(for filename: String?) -> Data? {
        guard let fileURL = pendingImageURL(for: filename) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    private func save(_ draft: SharedImportDraft) {
        let previousDraft = peek()

        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key)

        if previousDraft?.sharedImageFilename != draft.sharedImageFilename {
            deletePendingImage(for: previousDraft?.sharedImageFilename)
        }
    }

    private func pendingImportsDirectoryURL() -> URL? {
        baseDirectoryURL()?
            .appendingPathComponent("Cooksy", isDirectory: true)
            .appendingPathComponent(Self.pendingImportsDirectoryName, isDirectory: true)
    }

    private func pendingImageURL(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        return pendingImportsDirectoryURL()?.appendingPathComponent(filename)
    }

    private func deletePendingImage(for filename: String?) {
        guard let fileURL = pendingImageURL(for: filename) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func baseDirectoryURL() -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedLinkInbox.appGroupID) ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}
