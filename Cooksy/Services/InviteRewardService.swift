import Foundation
import Combine
import OSLog

/// Tracks the "invite friends" bonus that grants free-plan users a single
/// permanent extra import slot per rolling week.
///
/// Rules (set by product):
/// - Inviting **5** friends unlocks **+1** weekly import.
/// - The bonus is awarded **once**: after 5 invites the slot stays granted
///   forever; further invites are still tracked (the user can keep sharing)
///   but never grant additional slots.
/// - Each tap on the in-app "Inviter un ami" share button counts as one
///   invite. We can't verify the recipient really opens the link, so we
///   rely on intent — same trick used by every referral-share flow.
///
/// Persisted in `UserDefaults` so the count survives relaunches.
@MainActor
final class InviteRewardService: ObservableObject {
    static let shared = InviteRewardService()

    /// Number of invites required to unlock the bonus slot.
    static let invitesNeededForBonus = 5

    /// Cap on how many invites we display in the progress UI (also the
    /// number after which `recordInvite` becomes a no-op for counter
    /// purposes — the underlying bonus flag is already set).
    private static let displayCap = 5

    @Published private(set) var invitesSent: Int = 0
    @Published private(set) var bonusUnlocked: Bool = false

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.cooksy.ios", category: "InviteReward")

    private let invitesKey = "cooksy.invite.invitesSent"
    private let bonusKey = "cooksy.invite.bonusUnlocked"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.invitesSent = defaults.integer(forKey: invitesKey)
        self.bonusUnlocked = defaults.bool(forKey: bonusKey)
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

    /// Records a new invite intent (tap on the share button).
    /// Increments the counter and unlocks the bonus on the 5th invite.
    /// Idempotent for the bonus — calling after unlock won't toggle it back.
    func recordInvite() {
        invitesSent += 1
        defaults.set(invitesSent, forKey: invitesKey)

        if !bonusUnlocked && invitesSent >= Self.invitesNeededForBonus {
            bonusUnlocked = true
            defaults.set(true, forKey: bonusKey)
            logger.info("Invite bonus unlocked at \(self.invitesSent, privacy: .public) invites")
        }
    }

    func resetForDebug() {
        invitesSent = 0
        bonusUnlocked = false
        defaults.removeObject(forKey: invitesKey)
        defaults.removeObject(forKey: bonusKey)
    }
}
