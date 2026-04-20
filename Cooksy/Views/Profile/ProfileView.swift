import SwiftUI

struct ProfileView: View {
    @State private var toastMessage: String?

    private let displayName = "Invité"
    private let avatarInitial = "I"

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ProfileHeaderCard(
                        displayName: displayName,
                        avatarInitial: avatarInitial,
                        onEditTap: { showToast("Bientôt disponible") }
                    )

                    ProfilePremiumBanner(
                        action: { showToast("Bientôt disponible") }
                    )

                    sectionTitle("Découverte")
                    discoverySection

                    sectionTitle("Communauté")
                    communitySection

                    sectionTitle("Réglages")
                    settingsSection

                    ProfileFooterVersion()
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }

            if let toastMessage {
                ComingSoonToast(message: toastMessage)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    private var discoverySection: some View {
        ProfileSectionCard {
            ProfileRow(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Recettes tendance",
                action: { showToast("Bientôt disponible") }
            )

            ProfileRow(
                systemImage: "square.and.arrow.up.on.square",
                title: "Ajouter le raccourci Cooksy",
                action: { showToast("Bientôt disponible") }
            )

            ProfileRow(
                systemImage: "book.closed",
                title: "Lire nos guides d'importation",
                action: { showToast("Bientôt disponible") }
            )

            ProfileRow(
                systemImage: "desktopcomputer",
                title: "Utiliser Cooksy sur le bureau",
                isLast: true,
                action: { showToast("Bientôt disponible") }
            )
        }
    }

    private var communitySection: some View {
        ProfileSectionCard {
            ProfileRow(
                systemImage: "person.badge.plus",
                title: "Inviter des amis",
                action: { showToast("Bientôt disponible") }
            )

            ProfileRow(
                systemImage: "questionmark.circle",
                title: "Aide",
                isLast: true,
                action: { showToast("Bientôt disponible") }
            )
        }
    }

    private var settingsSection: some View {
        ProfileSectionCard {
            NavigationLink(destination: ProfileSettingsView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.55))
                            .frame(width: 36, height: 36)

                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    Text("Paramètres")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }
}
