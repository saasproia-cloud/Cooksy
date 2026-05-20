import SwiftUI
import UserNotifications

/// Profile → Notifications. Surfaces:
///   - the current iOS authorization status (with a CTA to open Settings
///     when denied),
///   - 5 category toggles backed by `notification_preferences` on the
///     backend (master + promo + suggestion + reminder + digest).
///
/// Copy mirrors the brand voice from the rest of the app: tutoiement,
/// short sentences, no emojis in body, single CTA per row.
struct NotificationSettingsView: View {
    @StateObject private var notifications = NotificationsCenter.shared
    @State private var isSaving: Bool = false

    var body: some View {
        ZStack {
            CooksyTheme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    authorizationCard

                    if notifications.authorizationStatus != .denied {
                        masterToggleCard
                        categoryTogglesCard
                    }

                    footerNote

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notifications.refreshAuthorizationStatus()
            await notifications.loadPreferences()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Garde la main")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Text("Choisis ce qui vaut un push. On respecte ton silence : pas de notif après 22h, 4 max par semaine.")
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Authorization card

    @ViewBuilder
    private var authorizationCard: some View {
        switch notifications.authorizationStatus {
        case .notDetermined:
            permissionCTACard(
                title: "Active les notifications",
                body: "On t'envoie un rappel J-2 avant la fin de ton essai et quand ton import quota repart à zéro.",
                actionLabel: "Activer"
            ) {
                Task {
                    _ = await notifications.requestExplicitAuthorization()
                }
            }

        case .denied:
            permissionCTACard(
                title: "Notifications désactivées",
                body: "Ouvre Réglages iOS pour les réactiver. Sans ça, on ne peut pas te prévenir avant la fin de l'essai.",
                actionLabel: "Ouvrir Réglages",
                tint: CooksyTheme.secondaryAccentStrong
            ) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }

        case .provisional:
            infoCard(
                icon: "moon.fill",
                title: "Mode discret activé",
                body: "Tes notifs arrivent en silence dans le Centre. Active-les complètement quand tu veux du son."
            )

        case .authorized, .ephemeral:
            infoCard(
                icon: "checkmark.circle.fill",
                title: "Notifications actives",
                body: "Tu reçois les rappels essentiels (fin d'essai, quota, cadeau)."
            )

        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Master toggle

    private var masterToggleCard: some View {
        toggleRow(
            icon: "bell.fill",
            title: "Toutes les notifications marketing",
            subtitle: "Coupe le robinet en un tap. Les rappels essentiels (essai, cadeau) restent actifs.",
            isOn: bindingFor(\.marketing_enabled),
            isMaster: true
        )
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                )
        )
    }

    // MARK: - Category toggles

    private var categoryTogglesCard: some View {
        VStack(spacing: 0) {
            toggleRow(
                icon: "gift.fill",
                title: "Offres & cadeaux",
                subtitle: "Roue cadeau, remises ponctuelles.",
                isOn: bindingFor(\.promo_enabled)
            )
            divider
            toggleRow(
                icon: "lightbulb.fill",
                title: "Suggestions de recettes",
                subtitle: "Idées tirées de ta bibli, à l'heure où tu cuisines.",
                isOn: bindingFor(\.suggestion_enabled)
            )
            divider
            toggleRow(
                icon: "clock.fill",
                title: "Rappels & étapes",
                subtitle: "Bienvenue, premier import, jalons.",
                isOn: bindingFor(\.reminder_enabled)
            )
            divider
            toggleRow(
                icon: "newspaper.fill",
                title: "Récap hebdo",
                subtitle: "Le dimanche soir, ce que tu as cuisiné cette semaine.",
                isOn: bindingFor(\.digest_enabled)
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
                )
        )
        .disabled(!notifications.preferences.marketing_enabled || isSaving)
        .opacity(notifications.preferences.marketing_enabled ? 1 : 0.45)
    }

    private var divider: some View {
        Rectangle()
            .fill(CooksyTheme.stroke.opacity(0.6))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Plages calmes : 22h–8h, jamais d'exception.", systemImage: "moon.zzz")
            Label("Maximum 4 push par semaine, toutes catégories confondues.", systemImage: "speaker.slash.fill")
            Label("Tu peux tout couper à tout moment depuis Réglages iOS.", systemImage: "gearshape")
        }
        .font(.system(size: 11.5, weight: .medium, design: .rounded))
        .foregroundStyle(CooksyTheme.secondaryText)
    }

    // MARK: - Reusable toggle row

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isMaster: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isMaster ? CooksyTheme.primaryAccent : CooksyTheme.warmCard)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isMaster ? .white : CooksyTheme.primaryText.opacity(0.7))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(CooksyTheme.primaryAccent)
        }
        .padding(.horizontal, isMaster ? 0 : 16)
        .padding(.vertical, isMaster ? 0 : 12)
    }

    private func permissionCTACard(
        title: String,
        body: String,
        actionLabel: String,
        tint: Color = CooksyTheme.primaryAccent,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Text(body)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(actionLabel)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(CooksyTheme.pressScale())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func infoCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(body)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1)
                )
        )
    }

    // MARK: - Bindings

    /// Build a Binding<Bool> that round-trips through the backend on
    /// change. The optimistic local update is reverted by the reload at
    /// the end of `updatePreferences`.
    private func bindingFor(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { notifications.preferences[keyPath: keyPath] },
            set: { newValue in
                Task {
                    isSaving = true
                    let columnName = NotificationSettingsView.columnName(for: keyPath)
                    await notifications.updatePreferences(patch: [columnName: newValue])
                    isSaving = false
                }
            }
        )
    }

    /// Maps a key path on NotificationPreferences to the matching JSON
    /// column name. Encoded as a static dictionary so the mapping is
    /// trivially auditable.
    private static func columnName(for keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> String {
        switch keyPath {
        case \NotificationPreferences.marketing_enabled:  return "marketing_enabled"
        case \NotificationPreferences.promo_enabled:      return "promo_enabled"
        case \NotificationPreferences.suggestion_enabled: return "suggestion_enabled"
        case \NotificationPreferences.reminder_enabled:   return "reminder_enabled"
        case \NotificationPreferences.digest_enabled:     return "digest_enabled"
        default:                                          return ""
        }
    }
}
