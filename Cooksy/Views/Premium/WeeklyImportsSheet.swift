import SwiftUI

/// Bottom sheet shown when the lightning pill in the home top-bar is
/// tapped. Two flavours:
///
///   • Free user — counts the remaining weekly imports as a row of
///     lightning icons (filled = remaining, dimmed = consumed) and
///     pushes the upgrade CTA below.
///   • Premium user — same lightning row, all filled in gold, with a
///     thank-you message and no CTA.
///
/// Replaces the old `Alert` to give the lightning pill the same weight
/// as the gift flow (and to mirror what RecipeMe ships in their app —
/// see screenshot reference).
struct WeeklyImportsSheet: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void
    /// Tapped when the free user touches the locked "bonus" bolt — host
    /// dismisses the sheet and routes to the invite-friends rewards page.
    var onTapBonusBolt: (() -> Void)? = nil

    @StateObject private var quota = ImportQuotaService.shared
    @StateObject private var rewards = InviteRewardService.shared
    @State private var now: Date = Date()
    /// Tracks the "Rappelez-moi" reminder state so the row can flip to a
    /// confirmed "Rappel activé" affordance once scheduled.
    @State private var reminderState: ReminderState = .idle
    private let timer = Timer.publish(every: 60.0, on: .main, in: .common).autoconnect()

    private enum ReminderState {
        case idle        // not scheduled — show the "Rappelez-moi" CTA
        case scheduled   // a reminder is pending — show the confirmed state
        case working     // request in flight (permission prompt / settings)
    }

    private var isPremium: Bool { quota.isPremium }
    /// Base free slots (3) — never changes.
    private var baseSlots: Int { ImportQuotaService.freeWeeklyLimit }
    /// True when the invite-friends bonus has been earned (free users only).
    private var hasBonusSlot: Bool { rewards.bonusUnlocked }
    /// Total active slots, including the earned bonus when applicable.
    private var totalSlots: Int { baseSlots + (hasBonusSlot ? 1 : 0) }
    /// Number of base slots still available (the gold bolts at the start).
    private var baseRemaining: Int {
        if isPremium { return baseSlots }
        return min(quota.remainingThisWeek, baseSlots)
    }
    /// True when the bonus slot is still unused this week. Drives the
    /// green-active vs green-consumed bolt rendering.
    private var bonusRemainingActive: Bool {
        guard hasBonusSlot, !isPremium else { return false }
        return quota.remainingThisWeek > baseSlots
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            // Lightning row — visual cue of remaining capacity. Premium
            // users keep the gold-only row; free users always see a 4th
            // green bolt (active when earned, locked-green teaser when
            // not), which routes to the invite-friends reward page.
            HStack(spacing: 14) {
                ForEach(0..<baseSlots, id: \.self) { index in
                    boltIcon(filled: index < baseRemaining)
                }

                if !isPremium {
                    bonusBolt
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 22)

            // Two-tone headline like the RecipeMe reference: orange/accent
            // numerator + dark grey rest of the sentence.
            headline
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Subtitle: reset countdown for free users, thank-you for premium.
            subtitle
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            Spacer(minLength: 18)

            if !isPremium {
                Button(action: {
                    OnboardingHaptics.medium()
                    onUpgrade()
                }) {
                    Text("Débloquez les importations illimitées")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 8)
                }
                .buttonStyle(CooksyTheme.pressScale())
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            } else {
                Button(action: {
                    OnboardingHaptics.selection()
                    onDismiss()
                }) {
                    Text("Continuer à cuisiner")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity)
        .background(CooksyTheme.background.ignoresSafeArea())
        .onReceive(timer) { _ in now = Date() }
        .task {
            // Re-opening the sheet should reflect a reminder the user
            // already set in a previous session.
            if await NotificationScheduler.isQuotaResetReminderScheduled() {
                reminderState = .scheduled
            }
        }
    }

    // MARK: - Pieces

    private func boltIcon(filled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(filled
                      ? AnyShapeStyle(CooksyTheme.goldShimmer)
                      : AnyShapeStyle(Color.gray.opacity(0.18)))
                .frame(width: 44, height: 56)
                .shadow(
                    color: filled ? CooksyTheme.primaryAccentGlow.opacity(0.45) : .clear,
                    radius: 12, y: 6
                )
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(filled ? CooksyTheme.heroDark : Color.gray.opacity(0.45))
        }
    }

    // MARK: - Bonus bolt (invite-reward)

    /// Fourth bolt slot for free users. Three visual states:
    /// - **Bonus earned + still available this week**: vivid green active.
    /// - **Bonus earned + already consumed this week**: faded green.
    /// - **Bonus not yet earned**: muted gray-green "locked teaser" with
    ///   a tiny lock badge — tapping it routes to the invite-friends page.
    @ViewBuilder
    private var bonusBolt: some View {
        if hasBonusSlot {
            bonusBoltShape(
                fillStyle: AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: 0x6DAA5E), Color(hex: 0x4D8B47)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )),
                iconColor: .white,
                glow: bonusRemainingActive
            )
            .opacity(bonusRemainingActive ? 1 : 0.55)
        } else {
            Button(action: { onTapBonusBolt?() }) {
                bonusBoltShape(
                    fillStyle: AnyShapeStyle(LinearGradient(
                        colors: [Color(hex: 0xC8DDC0), Color(hex: 0xA8C7A0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )),
                    iconColor: Color(hex: 0x4D8B47).opacity(0.85),
                    glow: false
                )
                .overlay(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color(hex: 0x4D8B47))
                    }
                    .offset(x: 6, y: -6)
                }
            }
            .buttonStyle(CooksyTheme.pressScale())
        }
    }

    private func bonusBoltShape(
        fillStyle: AnyShapeStyle,
        iconColor: Color,
        glow: Bool
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fillStyle)
                .frame(width: 44, height: 56)
                .shadow(
                    color: glow ? Color(hex: 0x6DAA5E).opacity(0.45) : .clear,
                    radius: 12, y: 6
                )
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(iconColor)
        }
    }

    private var headline: some View {
        Group {
            if isPremium {
                (
                    Text("∞ ")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryAccentStrong)
                    + Text("importations illimitées cette semaine")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryText)
                )
            } else {
                (
                    Text("\(min(quota.remainingThisWeek, totalSlots)) sur \(totalSlots) ")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryAccentStrong)
                    + Text("importations\nhebdomadaires restantes")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryText)
                )
            }
        }
    }

    private var subtitle: some View {
        Group {
            if isPremium {
                Text("Merci d'être membre Cooksy Premium 💛")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            } else if windowStarted {
                VStack(spacing: 8) {
                    Text(resetCopy)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(CooksyTheme.secondaryText)
                    remindMeControl
                }
            } else {
                Text("Le compteur démarre à ta première importation.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
    }

    /// "Rappelez-moi" — a real button now. On tap:
    ///   • notifications authorized  → schedule the reset reminder, flip
    ///     to the confirmed "Rappel activé" pill.
    ///   • notifications denied      → bounce to iOS Settings so the user
    ///     can re-enable them.
    ///   • not yet determined       → request permission, then schedule
    ///     if granted.
    @ViewBuilder
    private var remindMeControl: some View {
        switch reminderState {
        case .scheduled:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                Text("Rappel activé — on te prévient au reset")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
            )

        case .idle, .working:
            Button(action: handleRemindMeTap) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12, weight: .bold))
                    Text("Rappelez-moi")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(reminderState == .working)
        }
    }

    private func handleRemindMeTap() {
        OnboardingHaptics.selection()
        reminderState = .working
        Task {
            await NotificationsCenter.shared.refreshAuthorizationStatus()
            switch NotificationsCenter.shared.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                NotificationScheduler.scheduleQuotaResetReminder(
                    secondsUntilReset: quota.secondsUntilReset
                )
                reminderState = .scheduled
                OnboardingHaptics.success()

            case .denied:
                // Permission was refused — there is nothing we can
                // schedule that would surface. Send the user to iOS
                // Settings so they can flip Cooksy's switch back on.
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(settingsURL)
                }
                reminderState = .idle

            case .notDetermined:
                let granted = await NotificationsCenter.shared.requestExplicitAuthorization()
                if granted {
                    NotificationScheduler.scheduleQuotaResetReminder(
                        secondsUntilReset: quota.secondsUntilReset
                    )
                    reminderState = .scheduled
                    OnboardingHaptics.success()
                } else {
                    reminderState = .idle
                }

            @unknown default:
                reminderState = .idle
            }
        }
    }

    private var windowStarted: Bool {
        quota.secondsUntilReset > 0
    }

    /// Reset line. The `now` timer drives a refresh every minute so the
    /// hour/minute readout on the final day stays live.
    private var resetCopy: String {
        _ = now // keep the view subscribed to the per-minute tick
        if quota.isOnFinalResetDay {
            return "Réinitialisation : \(quota.resetCountdownText) restant"
        }
        return "Réinitialisation dans \(quota.resetCountdownText)."
    }
}
