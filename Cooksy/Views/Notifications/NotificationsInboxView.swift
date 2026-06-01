import SwiftUI
import UIKit

/// In-app notifications inbox. Reached from the bell icon on the
/// Home screen. Lists every push / local notification the user has
/// received, with read/unread state and swipe-to-delete. Tapping a
/// row marks it read and, when the payload carried a deep link,
/// routes the app to that destination.
struct NotificationsInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inbox = NotificationInbox.shared

    var body: some View {
        NavigationStack {
            ZStack {
                CooksyTheme.background
                    .ignoresSafeArea()

                if inbox.items.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(inbox.items) { item in
                                NotificationRow(
                                    item: item,
                                    onTap: { handleTap(item: item) },
                                    onDelete: { inbox.removeItem(id: item.id) }
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                        .animation(.easeInOut(duration: 0.18), value: inbox.items)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if inbox.hasUnread {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                inbox.markAllAsRead()
                            }
                        } label: {
                            Text("Tout lu")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(CooksyTheme.ctaOrange)
                        }
                    }
                }
            }
            .task {
                // Fold in any notifications still sitting in iOS's
                // Notification Center that we missed (delivered while
                // the app wasn't running and never tapped).
                await inbox.syncDeliveredFromSystem()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.ctaOrange.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "bell.slash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrange)
            }

            VStack(spacing: 6) {
                Text("Aucune notification")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Tu verras ici tes rappels d'essai, tes succès et toutes les actus Cooksy.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
        }
        .padding(.top, 60)
    }

    // MARK: - Handlers

    private func handleTap(item: NotificationInboxItem) {
        withAnimation(.easeInOut(duration: 0.15)) {
            NotificationInbox.shared.markRead(id: item.id)
        }
        if let deepLink = item.deepLink {
            // Hand off to the DeepLinkRouter via the AppDelegate, same
            // path Apple uses when the user taps a notification from
            // outside the app — keeps routing logic in one place.
            if let appDelegate = UIApplication.shared.delegate as? CooksyAppDelegate {
                appDelegate.pendingURL = deepLink
            }
            dismiss()
        }
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let item: NotificationInboxItem
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                categoryIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(relativeTimeString(for: item.deliveredAt))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !item.isRead {
                    Circle()
                        .fill(CooksyTheme.ctaOrange)
                        .frame(width: 9, height: 9)
                        .padding(.top, 6)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.isRead
                          ? Color.white.opacity(0.96)
                          : CooksyTheme.ctaOrange.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        item.isRead
                            ? CooksyTheme.stroke
                            : CooksyTheme.ctaOrange.opacity(0.35),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private var categoryIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconTint.opacity(0.16))
                .frame(width: 36, height: 36)
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconTint)
        }
    }

    private var iconName: String {
        switch item.category {
        case "trial":  return "calendar.badge.clock"
        case "gift":   return "gift.fill"
        case "import": return "tray.and.arrow.down.fill"
        case "system": return "sparkles"
        default:       return "bell.fill"
        }
    }

    private var iconTint: Color {
        switch item.category {
        case "trial":  return Color(hex: 0x6D4AE0)
        case "gift":   return CooksyTheme.ctaOrange
        case "import": return Color(hex: 0x2E7D32)
        case "system": return CooksyTheme.primaryAccent
        default:       return CooksyTheme.secondaryText
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
