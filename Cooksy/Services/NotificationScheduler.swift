import Foundation
import OSLog

/// Sprint 2 — local (on-device) notification scheduling.
///
/// Why local and not remote for these 7?
///   - They are *deterministic*: once a trial starts we know exactly when
///     J-2 / J-1 fall. No server round-trip, no APNs cost, and they keep
///     firing even if the phone is offline.
///   - They are tied to an explicit on-device event (onboarding done,
///     first import, gift won, trial started) so the app is already the
///     authority on "should this fire".
///
/// The copy below mirrors the FR seed in
/// `supabase/migrations/20260519_notifications_seed.sql`. The DB rows
/// remain the source of truth for the *remote* templates; for these
/// local ones the copy must live on-device so they work offline, hence
/// the controlled duplication. Keep both in sync when tweaking copy.
///
/// All scheduling goes through `NotificationsCenter.scheduleLocalNotification`
/// which is upsert-by-identifier — re-scheduling with the same id simply
/// replaces the pending request.
@MainActor
enum NotificationScheduler {

    private static let logger = Logger(subsystem: "com.cooksy.ios", category: "NotificationScheduler")

    // MARK: - Stable identifiers

    private enum ID {
        static let welcome           = "cooksy.local.welcome_d0"
        static let importSilenceD2   = "cooksy.local.import_silence_d2"
        static let firstImport       = "cooksy.local.first_import_celebrate"
        static let import5Milestone  = "cooksy.local.import_5_milestone"
        static let trialWelcome      = "cooksy.local.trial_started_welcome"
        static let trialD5           = "cooksy.local.trial_d5"
        static let trialD6Morning    = "cooksy.local.trial_d6_morning"
        static let trialD6Evening    = "cooksy.local.trial_d6_evening"
        static let giftExpires       = "cooksy.local.gift_expires_6h"
        static let quotaReset        = "cooksy.local.quota_reset_reminder"
        static let giftCookTeaser    = "cooksy.local.gift_cook_teaser"
        static let giftCookAlmost    = "cooksy.local.gift_cook_almost"
        static let giftCookReady     = "cooksy.local.gift_cook_ready"

        /// Every trial-series identifier — used for bulk cancellation
        /// when the user converts early or turns off auto-renew.
        static let trialSeries = [trialWelcome, trialD5, trialD6Morning, trialD6Evening]
        /// Onboarding nudges retired once the user makes a first import.
        static let onboardingNudges = [welcome, importSilenceD2]
        /// The gift-cooldown anticipation series — cancelled in bulk
        /// when the user wins the gift or the account is reset.
        static let giftCookSeries = [giftCookTeaser, giftCookAlmost, giftCookReady]
    }

    // MARK: - Onboarding: welcome_d0

    /// Schedule the "transform your first video" nudge for ~1 h after
    /// onboarding completes, clamped into the 10:00–20:00 window so it
    /// never lands at night. Cancelled the moment the user imports their
    /// first recipe (see `cancelWelcome()`).
    static func scheduleWelcome() {
        // A1 — ~1 h out, daytime-clamped.
        let welcomeAt = clampToDaytime(Date().addingTimeInterval(3600))
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.welcome,
            title: "Prêt à transformer ta 1ère vidéo ?",
            body: "Colle un lien TikTok ou Insta — recette propre en 30 secondes.",
            fireAt: welcomeAt,
            deepLink: "cooksy://import"
        )

        // A3 — import_silence_d2: ~48 h out, daytime-clamped. Both this
        // and the welcome nudge are retired the moment the user imports.
        let silenceAt = clampToDaytime(Date().addingTimeInterval(48 * 3600))
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.importSilenceD2,
            title: "On t'attend en cuisine 🍝",
            body: "Essaie un Reel que tu as sauvegardé — on en fait une recette claire.",
            fireAt: silenceAt,
            deepLink: "cooksy://import"
        )
        logger.info("Scheduled onboarding nudges (welcome \(welcomeAt, privacy: .public), silence \(silenceAt, privacy: .public))")
    }

    static func cancelWelcome() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: ID.onboardingNudges)
    }

    // MARK: - First import celebration

    /// Fires ~5 min after the user's very first import. If they're still
    /// in the app the foreground delegate keeps it silent in the list;
    /// if they backgrounded it pops as a banner. Also cancels the
    /// now-redundant welcome nudge.
    static func scheduleFirstImportCelebration(recipeID: String) {
        cancelWelcome()
        let fireAt = Date().addingTimeInterval(5 * 60)
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.firstImport,
            title: "Ta première recette est prête 👨‍🍳",
            body: "Ouvre-la avant de cuisiner — étapes, ingrédients, tout y est.",
            fireAt: fireAt,
            deepLink: "cooksy://recipe/\(recipeID)"
        )
        logger.info("Scheduled first_import_celebrate at \(fireAt, privacy: .public)")
    }

    /// A5 — fired right after the user's 5th lifetime import. Latched by
    /// the caller (RecipeStore) so it only ever schedules once.
    static func scheduleImportMilestone5() {
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.import5Milestone,
            title: "5 recettes, déjà 🎉",
            body: "Tu prends le rythme. Voilà ton organiseur de la semaine.",
            fireAt: Date().addingTimeInterval(10),
            deepLink: "cooksy://library"
        )
        logger.info("Scheduled import_5_milestone")
    }

    // MARK: - Trial series (C1 / C3 / C4 / C5)

    /// Schedule the full 7-day-trial reminder series at trial start.
    ///
    /// - C1 trial_started_welcome → immediately (a few seconds out so it
    ///   lands after the purchase sheet dismisses).
    /// - C3 trial_d5_reminder    → day 5 at 11:00.
    /// - C4 trial_d6_morning     → day 6 at 09:00.
    /// - C5 trial_d6_evening     → day 6 at 19:30.
    ///
    /// `trialDays` is normally 7; we derive the J-2 / J-1 offsets from it
    /// so a 14-day promo trial would still land correctly.
    static func scheduleTrialSeries(trialDays: Int, annualPriceText: String) {
        let now = Date()
        let days = max(trialDays, 3) // guard against absurd trial lengths
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let endDateText = Self.frenchLongDate(endDate)

        // C1 — welcome, ~8 s out so the StoreKit sheet has dismissed.
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.trialWelcome,
            title: "Premium débloqué pour \(days) jours 🔓",
            body: "Plonge dans nutrition, plan de repas et mode guidé. Aucun paiement.",
            fireAt: now.addingTimeInterval(8),
            deepLink: "cooksy://home"
        )

        // C3 — J-2 reminder at 11:00.
        if let d5 = fireDate(daysFromNow: days - 2, hour: 11, minute: 0, from: now), d5 > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.trialD5,
                title: "Plus que 2 jours d'essai",
                body: "Ton premium continue automatiquement le \(endDateText). Aucune action requise.",
                fireAt: d5,
                deepLink: "cooksy://profile/subscription"
            )
        }

        // C4 — J-1 morning at 09:00.
        if let d6m = fireDate(daysFromNow: days - 1, hour: 9, minute: 0, from: now), d6m > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.trialD6Morning,
                title: "Demain, ton premium continue",
                body: "Pas convaincu ? Annule depuis Réglages avant ce soir.",
                fireAt: d6m,
                deepLink: "cooksy://profile/subscription"
            )
        }

        // C5 — J-1 evening at 19:30. We can't know live import/cook
        // counts at schedule time, so the local variant leads on the
        // price the user keeps rather than on a count. (The richer
        // count-based copy lives in the DB seed for a future remote
        // version.)
        if let d6e = fireDate(daysFromNow: days - 1, hour: 19, minute: 30, from: now), d6e > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.trialD6Evening,
                title: "Dernier soir d'essai 📊",
                body: "Ta semaine premium se termine. Garde tout pour \(annualPriceText)/an.",
                fireAt: d6e,
                deepLink: "cooksy://home"
            )
        }

        logger.info("Scheduled trial series — ends \(endDateText, privacy: .public)")
    }

    /// Cancel the whole trial series. Called when the user converts early
    /// or — once Sprint 3's RevenueCat webhook lands — when they turn off
    /// auto-renew (so the "garde tout pour X/an" line never lies).
    static func cancelTrialSeries() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: ID.trialSeries)
        logger.info("Cancelled trial series")
    }

    /// Cancel only the day-1 evening recap (C5). Used when the user has
    /// turned off auto-renew during the trial: the J-2 / J-1-morning
    /// "annule avant ce soir" copy is still accurate, but the evening
    /// "garde tout" copy would be wrong.
    static func cancelTrialEveningRecap() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: [ID.trialD6Evening])
    }

    // MARK: - Gift expiry (H1)

    /// Schedule the "6 h left on your −25 %" reminder. `expiresAt` is the
    /// hard 24 h deadline from `PremiumOffersService`; we fire 6 h before
    /// it. If the offer is already inside its last 6 h (app was closed),
    /// we fire ~1 min out so the user still gets the nudge.
    static func scheduleGiftExpiry(expiresAt: Date, discountPercent: Int) {
        let sixHoursBefore = expiresAt.addingTimeInterval(-6 * 3600)
        let fireAt = sixHoursBefore > Date()
            ? sixHoursBefore
            : Date().addingTimeInterval(60)
        // Never fire after the offer is dead.
        guard fireAt < expiresAt else {
            logger.info("Gift already expired/too close — skipping H1")
            return
        }
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.giftExpires,
            title: "Plus que 6h pour ton −\(discountPercent) % 🎁",
            body: "Ton cadeau expire ce soir. Annulable à tout moment après.",
            fireAt: fireAt,
            deepLink: "cooksy://paywall?gift=1"
        )
        logger.info("Scheduled gift_expires_6h at \(fireAt, privacy: .public)")
    }

    static func cancelGiftExpiry() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: [ID.giftExpires])
    }

    // MARK: - Gift cooldown (re-issue anticipation)

    /// Schedule the anticipation notifications that run while a declined
    /// gift is in its re-issue cooldown. They pull the user back to
    /// watch the Home "something's cooking" card simmer toward its
    /// reveal — and ping them the moment the surprise is claimable.
    ///
    ///   - teaser  → when the Home card surfaces (forfeit + teaserDelay)
    ///   - almost  → ~1 day before the cooldown ends
    ///   - ready   → the moment the gift becomes claimable again
    ///
    /// Each fire time is clamped into the 10:00–20:00 daytime band so a
    /// cooldown that ends at 03:00 never pings the user at night.
    /// Re-scheduling with the same identifiers simply replaces any
    /// pending requests.
    static func scheduleGiftCooldown(cooldownEndsAt: Date, teaserAppearsAt: Date) {
        let now = Date()

        // The Home teaser card surfaces — a mid-cooldown discovery.
        if teaserAppearsAt > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.giftCookTeaser,
                title: "Quelque chose mijote pour toi 🍲",
                body: "Une surprise se prépare dans l'app — viens jeter un œil.",
                fireAt: clampToDaytime(teaserAppearsAt),
                deepLink: "cooksy://home"
            )
        }

        // Almost ready — one last nudge the day before the reveal.
        let almostAt = cooldownEndsAt.addingTimeInterval(-86_400)
        if almostAt > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.giftCookAlmost,
                title: "Ta surprise est presque prête ⏳",
                body: "Plus qu'un jour de cuisson — ton cadeau arrive bientôt.",
                fireAt: clampToDaytime(almostAt),
                deepLink: "cooksy://home"
            )
        }

        // Ready — the gift is claimable again.
        if cooldownEndsAt > now {
            NotificationsCenter.shared.scheduleLocalNotification(
                id: ID.giftCookReady,
                title: "C'est prêt ! Ton cadeau t'attend 🎁",
                body: "Joue au mini-jeu et débloque ton −25 %.",
                fireAt: clampToDaytime(cooldownEndsAt),
                deepLink: "cooksy://home"
            )
        }
        logger.info("Scheduled gift cooldown series — ready \(cooldownEndsAt, privacy: .public)")
    }

    static func cancelGiftCooldown() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: ID.giftCookSeries)
    }

    // MARK: - Weekly import quota reset reminder

    /// Schedule the "your weekly imports are back" reminder, fired at the
    /// moment the rolling quota window resets. Triggered explicitly by
    /// the user tapping "Rappelez-moi" in the WeeklyImportsSheet — so it
    /// only ever exists when the user asked for it.
    ///
    /// `secondsUntilReset` comes from `ImportQuotaService.secondsUntilReset`.
    /// The raw reset instant can land at any hour (the window is anchored
    /// to the user's first import), so we clamp it into the 10:00–20:00
    /// band — a reset at 03:00 would otherwise ping the user at 03:00.
    /// Clamping only ever moves the fire time *forward*, so the user is
    /// always reminded after their slots have genuinely refilled.
    static func scheduleQuotaResetReminder(secondsUntilReset: TimeInterval) {
        guard secondsUntilReset > 60 else {
            logger.info("Quota reset too close/elapsed — skipping reminder")
            return
        }
        let rawResetDate = Date().addingTimeInterval(secondsUntilReset)
        let fireAt = clampToDaytime(rawResetDate)
        NotificationsCenter.shared.scheduleLocalNotification(
            id: ID.quotaReset,
            title: "Tes imports hebdo sont de retour 🔄",
            body: "5 nouvelles importations t'attendent. Un Reel en tête ?",
            fireAt: fireAt,
            deepLink: "cooksy://import"
        )
        logger.info("Scheduled quota_reset_reminder at \(fireAt, privacy: .public)")
    }

    static func cancelQuotaResetReminder() {
        NotificationsCenter.shared.cancelLocalNotifications(ids: [ID.quotaReset])
    }

    /// True when a quota-reset reminder is currently pending — lets the
    /// WeeklyImportsSheet render the "Rappel activé" confirmed state on
    /// re-open instead of offering to schedule it again.
    static func isQuotaResetReminderScheduled() async -> Bool {
        let pending = await NotificationsCenter.shared.pendingLocalNotificationIdentifiers()
        return pending.contains(ID.quotaReset)
    }

    // MARK: - Convert cleanup

    /// Call when the user becomes a paying premium member. Cancels any
    /// dangling conversion-oriented local notifications so a freshly
    /// converted user never gets a "your trial is ending" ping.
    static func cancelAllConversionNudges() {
        NotificationsCenter.shared.cancelLocalNotifications(
            ids: ID.trialSeries + ID.onboardingNudges + ID.giftCookSeries
                + [ID.giftExpires, ID.quotaReset]
        )
    }

    // MARK: - Engagement queue (variety + intrigue)

    /// Number of distinct templates to keep pending at any time. The
    /// queue is rebuilt on every app launch so the user always has the
    /// next 6 days lined up; running this is idempotent (it cancels the
    /// previous queue and reschedules).
    private static let engagementQueueSize = 6

    /// Number of days back we treat a template as "recently sent" and
    /// avoid picking again. Tuned so the user never sees the same nudge
    /// in less than a month.
    private static let engagementCooldownDays = 30

    private static let recentlySentKey = "cooksy.notif.engagement.recentlySent"

    /// (Re)build the engagement queue — schedules `engagementQueueSize`
    /// varied local notifications across the coming days. Categories,
    /// time-of-day slots, and inactivity gates are all respected; nothing
    /// fires before 09:00 or after 20:00 local; weekend-specific copy
    /// only lands on Sat/Sun.
    ///
    /// Safe to call from anywhere — old engagement requests are wiped
    /// before the new batch is added.
    static func scheduleEngagementQueue(isUserInactive: Bool = false) {
        cancelEngagementQueue()

        let recentlySent = loadRecentlySentTemplateIDs()
        var freshlyPicked: [String] = []

        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)

        // If we're early enough in the day, start the queue today;
        // otherwise the first slot is tomorrow. Keeps a fresh-install
        // user from waiting 24 h to see ANY engagement push.
        let startsToday = currentHour < 18

        var scheduledCount = 0
        var dayOffset = startsToday ? 0 : 1

        // Track which (day-bucket) we've already filled so we never put
        // 2 notifications on the same calendar day.
        var filledDayKeys = Set<String>()

        while scheduledCount < engagementQueueSize && dayOffset < 14 {
            defer { dayOffset += 1 }

            guard let targetDate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: targetDate)
            let dayKey = engagementDateKey(targetDate)
            if filledDayKeys.contains(dayKey) { continue }

            // Filter the pool down to whatever is allowed today.
            let allowed = EngagementTemplate.pool.filter { template in
                if recentlySent.contains(template.id) { return false }
                if freshlyPicked.contains(template.id) { return false }
                if let needed = template.weekday, needed != weekday { return false }
                if template.requiresInactivity && !isUserInactive { return false }
                return true
            }
            guard let pick = allowed.randomElement() else { continue }

            // Build the fire date, respecting the daytime window. If the
            // selected hour is already in the past for "today", roll
            // forward to the next slot in the same window instead of
            // firing immediately.
            guard var fireAt = cal.date(
                bySettingHour: pick.preferredHour,
                minute: pick.preferredMinute,
                second: 0,
                of: targetDate
            ) else { continue }
            if fireAt <= now.addingTimeInterval(30) {
                // Today's slot has passed — push to tomorrow same hour.
                guard let bumped = cal.date(byAdding: .day, value: 1, to: fireAt) else { continue }
                fireAt = bumped
            }
            fireAt = clampToDaytime(fireAt)

            let scheduledID = "cooksy.local.engagement.\(scheduledCount + 1)"
            NotificationsCenter.shared.scheduleLocalNotification(
                id: scheduledID,
                title: pick.title,
                body: pick.body,
                fireAt: fireAt,
                deepLink: pick.deepLink
            )
            logger.info(
                "Engagement queued [\(pick.id, privacy: .public)] at \(fireAt, privacy: .public)"
            )

            freshlyPicked.append(pick.id)
            filledDayKeys.insert(dayKey)
            scheduledCount += 1
        }

        // Persist the freshly picked IDs so the next rebuild avoids them
        // for ~30 days. Prepend so the oldest entries fall off naturally.
        if !freshlyPicked.isEmpty {
            persistRecentlySent(freshlyPicked + recentlySent)
        }
    }

    /// Cancel every previously scheduled engagement request. Always
    /// called before a re-schedule so we don't stack queues.
    static func cancelEngagementQueue() {
        let ids = (1...engagementQueueSize).map { "cooksy.local.engagement.\($0)" }
        NotificationsCenter.shared.cancelLocalNotifications(ids: ids)
    }

    // MARK: Engagement persistence

    private static func loadRecentlySentTemplateIDs() -> [String] {
        guard let raw = UserDefaults.standard.array(forKey: recentlySentKey) as? [[String: Any]]
        else { return [] }
        let cutoff = Date().addingTimeInterval(-TimeInterval(engagementCooldownDays) * 86_400)
        return raw.compactMap { entry -> String? in
            guard let id = entry["id"] as? String,
                  let stamp = entry["at"] as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: stamp) >= cutoff ? id : nil
        }
    }

    private static func persistRecentlySent(_ ids: [String]) {
        // Coalesce: union by id, keep the newest timestamp per id.
        var index: [String: TimeInterval] = [:]
        if let raw = UserDefaults.standard.array(forKey: recentlySentKey) as? [[String: Any]] {
            for entry in raw {
                if let id = entry["id"] as? String,
                   let stamp = entry["at"] as? TimeInterval {
                    index[id] = max(index[id] ?? 0, stamp)
                }
            }
        }
        let now = Date().timeIntervalSince1970
        for id in ids { index[id] = now }

        // Drop entries older than the cooldown window.
        let cutoff = now - TimeInterval(engagementCooldownDays) * 86_400
        let cleaned = index
            .filter { $1 >= cutoff }
            .map { ["id": $0.key, "at": $0.value] as [String: Any] }
        UserDefaults.standard.set(cleaned, forKey: recentlySentKey)
    }

    private static func engagementDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Date helpers

    /// Build a fire date `days` from `base`, set to `hour:minute` local time.
    private static func fireDate(
        daysFromNow days: Int,
        hour: Int,
        minute: Int,
        from base: Date
    ) -> Date? {
        let cal = Calendar.current
        guard let shifted = cal.date(byAdding: .day, value: days, to: base) else { return nil }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: shifted)
    }

    /// Clamp a date into the 10:00–20:00 daytime window. Before 10:00 →
    /// pushed to 10:00 the same day; at/after 20:00 → 10:00 next day.
    private static func clampToDaytime(_ date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let startHour = 10
        let endHour = 20
        if hour >= startHour && hour < endHour {
            return date
        }
        var target = date
        if hour >= endHour {
            target = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return cal.date(bySettingHour: startHour, minute: 0, second: 0, of: target) ?? date
    }

    /// "24 mai 2026" — used in the trial-end reminder copy.
    private static func frenchLongDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}
