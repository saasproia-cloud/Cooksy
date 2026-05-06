import SwiftUI

/// "Inviter des amis" rewards page.
///
/// Free-plan users earn a permanent **+1 weekly import** by inviting
/// 5 friends. Each tap on the share button counts as one invite — we
/// can't verify the recipient really opens the link, same as every
/// referral-share flow.
///
/// After the bonus unlocks the page stays accessible: users can keep
/// sharing (it just doesn't grant additional slots, since the cap is
/// `1` extra import).
struct InviteFriendsView: View {
    @StateObject private var rewards = InviteRewardService.shared

    private static let totalSteps = InviteRewardService.invitesNeededForBonus

    private var progress: Int { rewards.invitesProgress }
    private var bonusUnlocked: Bool { rewards.bonusUnlocked }

    private var inviteText: String {
        """
        Découvre Cooksy 🍳 — l'app qui transforme n'importe quelle vidéo cuisine TikTok ou Instagram en vraie recette structurée (ingrédients précis, étapes claires).

        Plus besoin de re-scroller la vidéo pendant que tu cuisines !

        https://apps.apple.com/app/cooksy
        """
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    heroCard
                    progressCard
                    if bonusUnlocked {
                        unlockedCelebrationCard
                    }
                    rewardExplainerCard
                    shareButton
                    Text("Une invitation = 1 partage. Tu peux continuer à inviter des amis même après avoir débloqué ton bonus.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle("Inviter des amis")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x6DAA5E), Color(hex: 0x4D8B47)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 78, height: 78)
                    .shadow(color: Color(hex: 0x6DAA5E).opacity(0.45), radius: 16, y: 8)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Débloque un éclair bonus")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text("Invite 5 amis pour gagner **1 importation supplémentaire chaque semaine**, à vie.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Progress dots

    private var progressCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text(bonusUnlocked ? "Bonus débloqué" : "Ta progression")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer()

                Text("\(progress)/\(Self.totalSteps)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(bonusUnlocked
                                     ? Color(hex: 0x4D8B47)
                                     : CooksyTheme.ctaOrangeDark)
            }

            HStack(spacing: 8) {
                ForEach(0..<Self.totalSteps, id: \.self) { index in
                    progressDot(filled: index < progress)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func progressDot(filled: Bool) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(filled
                      ? AnyShapeStyle(LinearGradient(
                          colors: [Color(hex: 0x6DAA5E), Color(hex: 0x4D8B47)],
                          startPoint: .topLeading,
                          endPoint: .bottomTrailing
                      ))
                      : AnyShapeStyle(Color(hex: 0xEEEAE2)))
                .frame(height: 10)

            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Unlocked celebration

    private var unlockedCelebrationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x6DAA5E).opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color(hex: 0x4D8B47))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("C'est confirmé !")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Tu as bien débloqué ton éclair bonus : +1 importation chaque semaine, pour toujours.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0xEAF5E6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0x6DAA5E).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Explainer

    private var rewardExplainerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comment ça marche")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            explainerRow(
                index: 1,
                title: "Partage Cooksy",
                subtitle: "Touche le bouton ci-dessous pour envoyer une invitation à un ami."
            )
            explainerRow(
                index: 2,
                title: "Atteins 5 invitations",
                subtitle: "Chaque partage compte pour une invitation."
            )
            explainerRow(
                index: 3,
                title: "Reçois ton éclair bonus",
                subtitle: "+1 importation par semaine, débloquée à vie."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func explainerRow(index: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.blush.opacity(0.55))
                    .frame(width: 28, height: 28)
                Text("\(index)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Share button

    private var shareButton: some View {
        ShareLink(item: inviteText) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .bold))
                Text(bonusUnlocked ? "Partager Cooksy" : "Inviter un ami")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .simultaneousGesture(TapGesture().onEnded {
            OnboardingHaptics.medium()
            rewards.recordInvite()
        })
    }
}

#Preview {
    NavigationStack {
        InviteFriendsView()
    }
}
