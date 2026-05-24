import StoreKit
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var recipeStore: RecipeStore
    @Environment(\.requestReview) private var requestReview

    @StateObject private var offers = PremiumOffersService.shared

    @State private var toastMessage: String?
    @State private var showsEditProfile = false
    @State private var showsPaywall = false
    @State private var showsImportGuide = false
    /// Routed to when the silent auto-show fires on Profile entry and
    /// the user hasn't played the mini-game yet for this cycle.
    @State private var showsGiftWheel = false
    /// Routed to when the silent auto-show fires on Profile entry and
    /// the user has already won the gift — re-surfaces the exclusive
    /// offer with the live urgency timer.
    @State private var showsExclusiveOffer = false
    /// Per-session guard so the silent auto-show never fires twice
    /// when the user re-enters the Profile tab in the same launch.
    @State private var didAutoShowThisSession = false

    private var displayName: String {
        let raw = sessionStore.profile?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Chef" : raw
    }

    private var avatarInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "C"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ProfileHeaderCard(
                        displayName: displayName,
                        avatarInitial: avatarInitial,
                        avatarURL: sessionStore.profile?.avatarURL,
                        isPremium: sessionStore.isPremium,
                        onEditTap: { showsEditProfile = true },
                        onCrownTapWhenLocked: { showsPaywall = true }
                    )

                    if sessionStore.isPremium {
                        PremiumActiveCard()
                    } else {
                        ProfilePremiumBanner(action: { showsPaywall = true })
                    }

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
        .sheet(isPresented: $showsEditProfile) {
            EditProfileView()
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showsImportGuide) {
            ImportGuideView(onClose: { showsImportGuide = false })
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PremiumPaywallView(
                allowsFreeModeDismiss: true,
                onDismissToFreeMode: { showsPaywall = false }
            )
        }
        .fullScreenCover(isPresented: $showsGiftWheel) {
            GiftMiniGameHost(
                onClose: { showsGiftWheel = false },
                onClaim: { discount in
                    offers.recordGiftWon(percent: discount)
                    showsGiftWheel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showsExclusiveOffer = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showsExclusiveOffer) {
            ExclusiveOfferView(
                discountPercent: offers.giftDiscountPercent
                    ?? PremiumOffersService.defaultGiftDiscount,
                expiresAt: offers.giftOfferExpiresAt,
                onClose: { showsExclusiveOffer = false }
            )
        }
        .onAppear { considerGiftAutoShow() }
    }

    /// Profile is a lower-intent surface than Home, so the auto-show
    /// probability is meaningfully smaller (≈1 in 6) — see
    /// `PremiumOffersService.AutoShowOrigin.settingsOpen`. The 6 h
    /// persistent throttle still applies across origins, so a recent
    /// Home auto-show prevents a settings auto-show right after.
    private func considerGiftAutoShow() {
        guard !sessionStore.isPremium, !didAutoShowThisSession else { return }
        guard offers.shouldAutoShow(from: .settingsOpen) else { return }

        didAutoShowThisSession = true
        offers.recordAutoShownNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            switch offers.giftPhase {
            case .notWon:
                showsGiftWheel = true
            case .won where offers.giftOfferIsActive:
                showsExclusiveOffer = true
            default:
                break
            }
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

    private var discoverySection: some View {
        ProfileSectionCard {
            ProfileNavigationRow(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Recettes tendance"
            ) {
                TrendingRecipesView(store: recipeStore)
            }

            ProfileRow(
                systemImage: "star.fill",
                title: "Noter Cooksy",
                action: { requestReview() }
            )

            // "Lire nos guides d'importation" — opens the same multi-page
            // tutorial users see at first launch, but on demand from here.
            ProfileRow(
                systemImage: "book.closed",
                title: "Lire nos guides d'importation",
                action: { showsImportGuide = true }
            )

            ProfileNavigationRow(
                systemImage: "square.and.arrow.up",
                title: "Ajouter Cooksy au partage",
                isLast: true
            ) {
                ShareShortcutGuideView()
            }
        }
    }

    private var communitySection: some View {
        ProfileSectionCard {
            // Routes to the rewards page where each share counts toward
            // the +1 weekly-import bonus (5 invites = 1 extra import).
            ProfileNavigationRow(
                systemImage: "person.badge.plus",
                title: "Inviter des amis"
            ) {
                InviteFriendsView()
            }

            ProfileNavigationRow(
                systemImage: "questionmark.circle",
                title: "Aide",
                isLast: true
            ) {
                HelpView()
            }
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
