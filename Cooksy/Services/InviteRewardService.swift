import Foundation
import Combine
import OSLog

/// Tracks the "invite friends" bonus that grants free-plan users a single
/// permanent extra import slot per rolling week.
///
/// Rules (set by product):
/// - Inviting **5 unique** friends unlocks **+1** weekly import.
/// - The bonus is awarded **once**: after 5 invites the slot stays granted
///   forever; further invites are still tracked (the user can keep sharing)
///   but never grant additional slots.
/// - Counting is **per recipient**. Sending the invitation to 5 different
///   contacts in one batch counts as 5. Re-sending to a recipient already
///   credited counts as 0 (dedup by normalised phone number).
///
/// Persisted in `UserDefaults` so the count and the recipient ledger
/// survive relaunches.
@MainActor
final class InviteRewardService: ObservableObject {
    static let shared = InviteRewardService()

    /// Number of unique recipients required to unlock the bonus slot.
    static let invitesNeededForBonus = 5

    /// Cap on how many invites we display in the progress UI.
    private static let displayCap = 5

    @Published private(set) var invitesSent: Int = 0
    @Published private(set) var bonusUnlocked: Bool = false
    /// Normalised phone numbers (last 10 digits) of recipients we've
    /// already credited. Re-inviting any of them is a no-op — anti-cheat
    /// against tapping Send to the same friend on repeat.
    @Published private(set) var invitedRecipients: Set<String> = []

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "InviteReward")

    private let invitesKey = "cooksy.invite.invitesSent"
    private let bonusKey = "cooksy.invite.bonusUnlocked"
    private let recipientsKey = "cooksy.invite.recipients"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.invitesSent = defaults.integer(forKey: invitesKey)
        self.bonusUnlocked = defaults.bool(forKey: bonusKey)
        self.invitedRecipients = Set(defaults.stringArray(forKey: recipientsKey) ?? [])
    }

    /// Number of additional weekly import slots earned through invites.
    /// Always 0 or 1 — the bonus is single-use.
    var bonusImportSlots: Int { bonusUnlocked ? 1 : 0 }

    /// Number of invites still needed before the bonus unlocks.
    /// Returns 0 once the bonus is granted.
    var invitesRemaining: Int {
        max(Self.invitesNeededForBonus - invitesSent, 0)
    }

    /// Invites used for the in-progress bar (clamped to 0…5).
    var invitesProgress: Int {
        min(invitesSent, Self.displayCap)
    }

    /// Records invitations for a batch of recipients (typically the
    /// addressees of a single Messages send). Each recipient is
    /// normalised to its last 10 digits before dedup so cosmetic
    /// differences in formatting ("+33 6 …", "06 …", "0033 6 …") don't
    /// let the user replay the same friend.
    ///
    /// Returns the number of **new** recipients credited — the caller
    /// can show "+3 amis ajoutés" feedback when only some were new.
    @discardableResult
    func recordInvites(forPhones phones: [String]) -> Int {
        let normalised = phones.compactMap(Self.normalise(phone:))
        let fresh = normalised.filter { !invitedRecipients.contains($0) }
        guard !fresh.isEmpty else { return 0 }

        invitedRecipients.formUnion(fresh)
        defaults.set(Array(invitedRecipients), forKey: recipientsKey)

        invitesSent += fresh.count
        defaults.set(invitesSent, forKey: invitesKey)

        if !bonusUnlocked && invitesSent >= Self.invitesNeededForBonus {
            bonusUnlocked = true
            defaults.set(true, forKey: bonusKey)
            logger.info("Invite bonus unlocked at \(self.invitesSent, privacy: .public) recipients")
        }
        return fresh.count
    }

    /// `true` if at least one of the supplied phone numbers has already
    /// been credited. Used by the UI to warn the user "tu as déjà
    /// invité ce contact" before opening Messages.
    func anyAlreadyInvited(phones: [String]) -> Bool {
        let normalised = phones.compactMap(Self.normalise(phone:))
        return normalised.contains { invitedRecipients.contains($0) }
    }

    func resetForDebug() {
        invitesSent = 0
        bonusUnlocked = false
        invitedRecipients = []
        defaults.removeObject(forKey: invitesKey)
        defaults.removeObject(forKey: bonusKey)
        defaults.removeObject(forKey: recipientsKey)
    }

    // MARK: - Helpers

    /// Strips formatting and keeps the last 10 digits so different
    /// representations of the same phone (with/without country code,
    /// with/without spaces, with/without leading 0) collapse to the
    /// same key.
    private static func normalise(phone: String) -> String? {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 6 else { return nil }
        return String(digits.suffix(10))
    }
}
