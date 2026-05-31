import SwiftUI

/// Secondary settings page dedicated to account-level destructive actions.
/// Lives behind a discreet "Gérer mes données" link in the main settings —
/// kept reachable so the app stays compliant with App Store Review
/// Guideline 5.1.1(v) (account-creating apps must allow account deletion
/// from within the app), but no longer surfaced at first level.
struct AccountDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var showsFirstWarningAlert = false
    @State private var showsConfirmationSheet = false
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
        // Step 1 — heads-up alert. Acts as the first gate so a tap on
        // "Supprimer mon compte" can't immediately drop the user into
        // the typed-confirmation sheet by accident.
        .alert("Supprimer définitivement mon compte ?", isPresented: $showsFirstWarningAlert) {
            Button("Annuler", role: .cancel) {}
            Button("Continuer", role: .destructive) {
                showsConfirmationSheet = true
            }
        } message: {
            Text("Toutes tes recettes, ton plan de la semaine et tes préférences seront supprimés. Cette action est irréversible.")
        }
        // Step 2 — typed-phrase confirmation sheet. The user MUST type
        // the exact phrase and tick the acknowledgement before the
        // destructive RPC is allowed to fire.
        .sheet(isPresented: $showsConfirmationSheet) {
            DeleteAccountConfirmationSheet(
                userEmail: sessionStore.currentUser?.email,
                isDeleting: $isDeletingAccount,
                onCancel: { showsConfirmationSheet = false },
                onConfirm: {
                    Task {
                        isDeletingAccount = true
                        do {
                            try await sessionStore.deleteAccount()
                            // Session is now signed out; the sheet
                            // tears down with the view tree.
                        } catch {
                            deleteAccountError = error.localizedDescription
                            isDeletingAccount = false
                            showsConfirmationSheet = false
                        }
                    }
                }
            )
            .interactiveDismissDisabled(isDeletingAccount)
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
            Button(action: { showsFirstWarningAlert = true }) {
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

// MARK: - Typed-phrase confirmation sheet

/// Second-stage gate for account deletion. The user must:
///   1. tick the "I understand this is irreversible" acknowledgement
///   2. type the exact phrase `SUPPRIMER MON COMPTE` (case-insensitive,
///      accent-folded, whitespace-collapsed) into the text field
/// before the destructive button enables. The phrase is rendered with
/// `.textSelection(.disabled)` to push the user to read+type it instead
/// of copy-pasting on reflex.
private struct DeleteAccountConfirmationSheet: View {
    let userEmail: String?
    @Binding var isDeleting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var typedPhrase: String = ""
    @State private var acknowledged: Bool = false
    @FocusState private var phraseFocused: Bool

    /// The exact phrase the user must reproduce. Kept as a constant so
    /// the comparison logic and the displayed copy can never drift apart.
    private static let requiredPhrase: String = "SUPPRIMER MON COMPTE"

    private var normalizedTyped: String {
        typedPhrase
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private var phraseMatches: Bool {
        normalizedTyped == Self.requiredPhrase
    }

    private var canSubmit: Bool {
        acknowledged && phraseMatches && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CooksyTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        whatWillBeDeleted
                        acknowledgementToggle
                        phraseConfirmation
                        ctaButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Confirmer la suppression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                        .disabled(isDeleting)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.red)
                }
                Text("Action irréversible")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }

            if let userEmail, !userEmail.isEmpty {
                Text("Tu vas supprimer le compte associé à **\(userEmail)**.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tu vas supprimer définitivement ton compte Cooksy.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Une fois confirmée, cette opération ne peut PAS être annulée. Aucun e-mail de récupération ne sera envoyé.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
    }

    private var whatWillBeDeleted: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ce qui sera effacé")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                deletionRow(icon: "book.closed.fill", text: "Toutes tes recettes importées et créées")
                deletionRow(icon: "calendar", text: "Ton plan de la semaine")
                deletionRow(icon: "slider.horizontal.3", text: "Tes préférences et ton profil")
                deletionRow(icon: "photo.fill", text: "Les images et données stockées sur cet appareil")
            }
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

    private func deletionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CooksyTheme.ctaOrange)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var acknowledgementToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                acknowledged.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(acknowledged ? Color.red : CooksyTheme.stroke, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if acknowledged {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.red)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                    }
                }

                Text("Je comprends que cette action est définitive et que mes données ne pourront pas être récupérées.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .disabled(isDeleting)
    }

    private var phraseConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pour confirmer, tape exactement :")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(Self.requiredPhrase)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .textSelection(.disabled)

            HStack(spacing: 8) {
                TextField("Tape la phrase ici", text: $typedPhrase)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($phraseFocused)
                    .submitLabel(.done)

                if phraseMatches {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .transition(.scale.combined(with: .opacity))
                } else if !typedPhrase.isEmpty {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.55))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        phraseMatches ? Color.green.opacity(0.7) : CooksyTheme.stroke,
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: phraseMatches)
            .animation(.easeInOut(duration: 0.15), value: typedPhrase.isEmpty)
            .disabled(isDeleting)
        }
    }

    private var ctaButton: some View {
        Button(action: onConfirm) {
            HStack(spacing: 10) {
                if isDeleting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isDeleting ? "Suppression…" : "Supprimer définitivement")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canSubmit ? Color.red : Color.red.opacity(0.35))
            )
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
        .padding(.top, 4)
    }
}
