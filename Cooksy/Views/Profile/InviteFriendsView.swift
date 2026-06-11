import SwiftUI
import UIKit
import Contacts
import ContactsUI
import MessageUI

/// "Inviter des amis" rewards page.
///
/// Free-plan users earn a permanent **+1 weekly import** when they invite
/// 5 *unique* friends via SMS.
///
/// Anti-cheat:
/// - The invitation flow is **contact-picker → Messages**, so we know
///   exactly who the invite was sent to and can dedup by phone number.
/// - Multi-selecting 5 contacts at once correctly credits 5 (one per
///   recipient).
/// - Re-sending to a recipient who is already credited grants nothing.
/// - The "Send" callback only fires when iOS reports `MessageComposeResult.sent`
///   — opening Messages and cancelling does NOT count.
///
/// Premium users see a "vous êtes déjà premium" notice. They can still
/// invite (sharing is always welcome) but the bonus is irrelevant since
/// they already have unlimited imports.
struct InviteFriendsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var rewards = InviteRewardService.shared

    @State private var showsContactPicker = false
    @State private var pendingRecipients: [String] = []
    @State private var showsMessageComposer = false
    @State private var toast: ToastKind?
    @State private var showsCannotSendAlert = false

    private static let totalSteps = InviteRewardService.invitesNeededForBonus

    private var isPremium: Bool { sessionStore.isPremium }
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
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    if isPremium {
                        premiumNoticeCard
                    }

                    heroCard

                    if !isPremium {
                        progressCard
                        if bonusUnlocked {
                            unlockedCelebrationCard
                        }
                    }

                    rewardExplainerCard
                    shareButton

                    Text("Chaque ami n'est compté qu'une seule fois. L'invitation est créditée uniquement quand le message est réellement envoyé via Messages.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Layout.horizontalPadding(for: ScreenMetrics.width))
                .padding(.top, 8)
                .padding(.bottom, Layout.bottomScrollPadding(for: ScreenMetrics.width))
                .frame(maxWidth: Layout.maxReadingWidth)
                .frame(maxWidth: .infinity)
            }

            if let toast {
                ComingSoonToast(message: toast.message)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Inviter des amis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsContactPicker) {
            ContactsPicker(onSelect: handleContactsPicked)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsMessageComposer) {
            MessageComposer(
                recipients: pendingRecipients,
                body: inviteText,
                onResult: handleComposerResult
            )
            .ignoresSafeArea()
        }
        .alert("Messages indisponible", isPresented: $showsCannotSendAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ton appareil ne peut pas envoyer de SMS. Connecte-toi à un iPhone avec iMessage ou un forfait SMS pour inviter tes amis.")
        }
    }

    // MARK: - Premium notice

    private var premiumNoticeCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CooksyTheme.goldShimmer)
                    .frame(width: 42, height: 42)
                    .shadow(color: Color(hex: 0xF5B14E).opacity(0.35), radius: 6, y: 2)
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Tu es déjà Cooksy Plus 👑")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Tu as déjà les importations illimitées — le bonus invitation ne te concerne pas, mais tu peux toujours partager Cooksy avec tes amis.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.warmCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5B14E).opacity(0.55),
                            Color(hex: 0xFFE0A0).opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
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
                Text(isPremium
                     ? "Partage Cooksy à tes amis"
                     : "Débloque un éclair bonus")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text(isPremium
                     ? "Fais découvrir Cooksy autour de toi. Tes amis pourront importer leurs vidéos préférées en deux minutes."
                     : "Invite 5 amis pour gagner **1 importation supplémentaire chaque semaine**, à vie.")
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
                title: "Choisis tes amis",
                subtitle: "Sélectionne un ou plusieurs contacts depuis ton carnet d'adresses."
            )
            explainerRow(
                index: 2,
                title: "Envoie l'invitation par SMS",
                subtitle: "Messages s'ouvre avec ton invitation pré-remplie. Tu peux la modifier puis taper Envoyer."
            )
            explainerRow(
                index: 3,
                title: isPremium ? "Tu fais découvrir Cooksy" : "Reçois ton éclair bonus",
                subtitle: isPremium
                    ? "Tes amis débloquent leur cuisine vidéo, et toi tu gardes tes importations illimitées."
                    : "Une invitation = un ami unique. Au 5ème ami, +1 importation par semaine, à vie."
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
        Button(action: openContactPicker) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .bold))
                Text(bonusUnlocked || isPremium ? "Partager Cooksy" : "Inviter un ami")
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
    }

    // MARK: - Flow

    private func openContactPicker() {
        OnboardingHaptics.selection()
        guard MFMessageComposeViewController.canSendText() else {
            showsCannotSendAlert = true
            return
        }
        showsContactPicker = true
    }

    private func handleContactsPicked(_ contacts: [CNContact]) {
        // Pull the primary phone number from each contact. Contacts
        // without a phone number are silently skipped — we can't SMS
        // them.
        let phones = contacts.compactMap { contact -> String? in
            contact.phoneNumbers.first?.value.stringValue
        }
        guard !phones.isEmpty else {
            showToast(.noPhone)
            return
        }
        pendingRecipients = phones
        // Tiny delay so the contact-picker dismissal animation completes
        // before the Messages composer slides in — otherwise iOS skips it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showsMessageComposer = true
        }
    }

    private func handleComposerResult(_ result: MessageComposeResult) {
        let recipients = pendingRecipients
        pendingRecipients = []

        guard result == .sent else { return }

        let credited = rewards.recordInvites(forPhones: recipients)
        OnboardingHaptics.medium()

        if isPremium {
            showToast(.sentPremium)
        } else if credited == 0 {
            showToast(.alreadyInvited)
        } else if credited == 1 {
            showToast(.creditedOne)
        } else {
            showToast(.creditedMany(credited))
        }
    }

    // MARK: - Toast plumbing

    private enum ToastKind: Equatable {
        case sentPremium
        case alreadyInvited
        case creditedOne
        case creditedMany(Int)
        case noPhone

        var message: String {
            switch self {
            case .sentPremium: return "Invitation envoyée 🎉"
            case .alreadyInvited: return "Ces amis ont déjà été invités"
            case .creditedOne: return "+1 ami invité 🎉"
            case .creditedMany(let n): return "+\(n) amis invités 🎉"
            case .noPhone: return "Aucun numéro de téléphone trouvé"
            }
        }
    }

    private func showToast(_ kind: ToastKind) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toast = kind
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    toast = nil
                }
            }
        }
    }
}

// MARK: - Contact picker

/// SwiftUI bridge around `CNContactPickerViewController`. Multi-select
/// is enabled. The closure is fired with the user's selection on
/// dismiss; cancelling returns an empty array.
private struct ContactsPicker: UIViewControllerRepresentable {
    let onSelect: ([CNContact]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Only show contacts that have at least one phone number we can SMS.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([CNContact]) -> Void

        init(onSelect: @escaping ([CNContact]) -> Void) {
            self.onSelect = onSelect
        }

        // Multi-select branch.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(contacts)
        }

        // Single-select branch — iOS calls this one when the user taps a
        // single row rather than entering multi-select mode.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect([contact])
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onSelect([])
        }
    }
}

// MARK: - Message composer

/// SwiftUI bridge around `MFMessageComposeViewController`. Pre-fills the
/// recipients and body so the user only has to tap Send.
private struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onResult: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = recipients
        composer.body = body
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void

        init(onResult: @escaping (MessageComposeResult) -> Void) {
            self.onResult = onResult
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            // Fire the callback *before* asking iOS to dismiss the
            // composer — the parent SwiftUI sheet will collapse on its
            // own once `showsMessageComposer` flips back to false in the
            // result handler. This avoids passing the callback into the
            // dismiss completion (which trips Swift 6 strict-concurrency).
            onResult(result)
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        InviteFriendsView()
            .environmentObject(SessionStore())
    }
}
