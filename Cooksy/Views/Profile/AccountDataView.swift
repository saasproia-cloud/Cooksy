import SwiftUI

/// Secondary settings page dedicated to account-level destructive actions.
/// Lives behind a discreet "Gérer mes données" link in the main settings —
/// kept reachable so the app stays compliant with App Store Review
/// Guideline 5.1.1(v) (account-creating apps must allow account deletion
/// from within the app), but no longer surfaced at first level.
struct AccountDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var showsDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard

                    sectionTitle("Zone sensible")
                    deleteAccountCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle("Gérer mes données")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Supprimer définitivement mon compte ?", isPresented: $showsDeleteAccountConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    do {
                        try await sessionStore.deleteAccount()
                    } catch {
                        deleteAccountError = error.localizedDescription
                    }
                    isDeletingAccount = false
                }
            }
        } message: {
            Text("Toutes tes recettes, ton plan de la semaine et tes préférences seront supprimés. Cette action est irréversible.")
        }
        .alert("Erreur", isPresented: .init(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tes données chez Cooksy")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("Cette page rassemble les actions sensibles liées à ton compte. La suppression est définitive et concerne l'ensemble de tes recettes, ton plan de la semaine et tes préférences.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var deleteAccountCard: some View {
        ProfileSectionCard {
            Button(action: { showsDeleteAccountConfirm = true }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.red)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supprimer mon compte")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red)
                        Text("Suppression définitive de toutes tes données")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if isDeletingAccount {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}
