import SwiftUI
import UIKit

struct HomeView: View {
    private let store: RecipeStore
    private let openRecipesTab: () -> Void
    private let openPlanTab: () -> Void
    private let openImportSheet: () -> Void
    private let openProfileTab: () -> Void

    @StateObject private var viewModel: HomeViewModel
    @StateObject private var quota = ImportQuotaService.shared
    @StateObject private var offers = PremiumOffersService.shared
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var showsGiftWheel: Bool = false
    @State private var showsExclusiveOffer: Bool = false
    /// Shown when the user taps the gift pill while in the post-forfeit
    /// cooldown — explains the gift will return rather than re-opening
    /// the wheel (which is a one-spin-per-cycle flow).
    @State private var showsGiftCooldownAlert: Bool = false
    @State private var showsPaywallFromBadge: Bool = false
    @State private var showsQuotaInfo: Bool = false
    @State private var showsImportGuide: Bool = false
    @State private var showsInviteFriends: Bool = false
    /// In-app notifications inbox — replaces the bell's previous shortcut
    /// to the Profile tab. Observed so the unread dot on the bell stays
    /// in sync the moment a notification lands while Home is on screen.
    @State private var showsNotificationsInbox: Bool = false
    @StateObject private var notificationsInbox = NotificationInbox.shared
    @AppStorage("cooksy.hasSeenImportGuide") private var hasSeenImportGuide: Bool = false
    /// True when the paywall is opened from the gift wheel's "Plus tard" —
    /// drives a soft reminder banner that the user can still play to
    /// unlock −25 %.
    @State private var paywallShowsGiftReminder: Bool = false
    /// Full-screen "shock" moment that fires once when a fresh gift
    /// cycle becomes available after a cooldown — see GiftNewCycleHypeView.
    @State private var showsHypeTakeover: Bool = false
    /// Per-session guard so the silent auto-show fires at most once
    /// between two cold starts (the persistent 6 h throttle in
    /// PremiumOffersService.shouldAutoShow handles the longer floor).
    @State private var didAutoShowThisSession: Bool = false

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openRecipesTab: @escaping () -> Void = {},
        openPlanTab: @escaping () -> Void = {},
        openImportSheet: @escaping () -> Void = {},
        openProfileTab: @escaping () -> Void = {}
    ) {
        self.store = store
        self.openRecipesTab = openRecipesTab
        self.openPlanTab = openPlanTab
        self.openImportSheet = openImportSheet
        self.openProfileTab = openProfileTab
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(store: store, sharedLinkInbox: sharedLinkInbox)
        )
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFCF9F4)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    topBar
                    welcomeBlock
                    giftCookingTeaser
                    importGuideCard
                    recentImportsSection
                    trendingTodaySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
        }
        // The fresh-gift celebration is now owned by the in-scroll
        // `GiftCookingTeaserCard` (its "ready" state) — the user has
        // been watching that card simmer for days, so the reveal lands
        // there rather than as a separate top toast.
        .animation(.spring(response: 0.5, dampingFraction: 0.85),
                   value: offers.hasFreshGiftCelebrationPending)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.refreshPendingImport()
            // Mirror live premium state into quota service.
            quota.isPremium = sessionStore.profile?.isPremium ?? false
            // Hydrate the greeting with the current display name (and react
            // to later updates from EditProfileView via the .onChange below).
            viewModel.setDisplayName(sessionStore.profile?.displayName)

            // Auto-present the import guide on the very first home appearance.
            // After dismissal, `hasSeenImportGuide` flips to true so we never
            // pop it up again — but the user can always re-open it via the
            // "Guide d'importation…" card on this screen.
            if !hasSeenImportGuide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showsImportGuide = true
                }
            }

            considerGiftPresentation()
        }
        .onChange(of: sessionStore.profile?.displayName) { _, newValue in
            viewModel.setDisplayName(newValue)
        }
        .sheet(isPresented: $showsImportGuide) {
            ImportGuideView(onClose: {
                hasSeenImportGuide = true
                showsImportGuide = false
            })
        }
        .fullScreenCover(isPresented: $showsHypeTakeover) {
            // The "shock" moment: a fresh cycle just unlocked. Both
            // routes acknowledge so the takeover doesn't re-fire on
            // every subsequent launch — once the user has seen it,
            // we're done.
            GiftNewCycleHypeView(
                offers: offers,
                onPlay: {
                    offers.acknowledgeFreshGiftCelebration()
                    showsHypeTakeover = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showsGiftWheel = true
                    }
                },
                onDismiss: {
                    offers.acknowledgeFreshGiftCelebration()
                    showsHypeTakeover = false
                }
            )
        }
        .fullScreenCover(isPresented: $showsGiftWheel) {
            // Routes to whichever mini-game is active for the current
            // gift cycle (wheel / scratch card / mystery box). The
            // selection rotates each cooldown so users don't replay
            // the same game twice in a row.
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
            // ExclusiveOfferView handles the purchase inline now — the
            // CTA there flips premium directly and dismisses the cover,
            // so we no longer route to the paywall after winning the
            // gift wheel.
            ExclusiveOfferView(
                discountPercent: offers.giftDiscountPercent ?? PremiumOffersService.defaultGiftDiscount,
                expiresAt: offers.giftOfferExpiresAt,
                onClose: { showsExclusiveOffer = false }
            )
        }
        .alert("Ton cadeau revient bientôt 🎁", isPresented: $showsGiftCooldownAlert) {
            Button("OK", role: .cancel) { showsGiftCooldownAlert = false }
        } message: {
            if let days = offers.giftCooldownDaysRemaining {
                Text(
                    days <= 1
                    ? "Un nouveau cadeau se débloque dans moins de 24 h."
                    : "Un nouveau cadeau se débloque dans \(days) jours."
                )
            } else {
                Text("Un nouveau cadeau se débloque très bientôt.")
            }
        }
        .fullScreenCover(isPresented: $showsPaywallFromBadge) {
            PremiumPaywallView(
                allowsFreeModeDismiss: true,
                showsGiftReminder: paywallShowsGiftReminder,
                onDismissToFreeMode: { showsPaywallFromBadge = false },
                onOpenGiftFromReminder: {
                    showsPaywallFromBadge = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showsGiftWheel = true
                    }
                }
            )
        }
        .sheet(isPresented: $showsQuotaInfo) {
            WeeklyImportsSheet(
                onUpgrade: {
                    showsQuotaInfo = false
                    paywallShowsGiftReminder = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showsPaywallFromBadge = true
                    }
                },
                onDismiss: { showsQuotaInfo = false },
                onTapBonusBolt: {
                    showsQuotaInfo = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showsInviteFriends = true
                    }
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showsInviteFriends) {
            NavigationStack {
                InviteFriendsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { showsInviteFriends = false }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsNotificationsInbox) {
            NotificationsInboxView()
        }
    }

    /// Decides what gift-related surface (if any) to auto-present after
    /// the home appears. Priority order, applied at most once per
    /// session:
    ///   1. **HYPE takeover** when a fresh cycle just unlocked — wins
    ///      over the silent auto-show because the user has been waiting
    ///      a week for this moment.
    ///   2. **Silent auto-show** of the active gift (game or exclusive
    ///      offer) ~1 in 4 launches, gated by the 6 h persistent
    ///      throttle in PremiumOffersService.
    ///
    /// Skipped entirely for premium users (no offer applies) and on the
    /// very first launch (the import guide owns that moment).
    private func considerGiftPresentation() {
        let isPremium = sessionStore.profile?.isPremium ?? false
        guard !isPremium, !didAutoShowThisSession else { return }

        if offers.hasFreshGiftCelebrationPending {
            didAutoShowThisSession = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showsHypeTakeover = true
            }
            return
        }

        // Don't compete with the first-launch import guide.
        guard hasSeenImportGuide else { return }

        guard offers.shouldAutoShow(from: .appLaunch) else { return }
        didAutoShowThisSession = true
        offers.recordAutoShownNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
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

    private var topBar: some View {
        HStack(spacing: 10) {
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

            Spacer()

            // Lightning pill is always visible — `n/3` for free users,
            // `∞` for premium. The gift pill is only shown to free
            // users (premium has nothing more to win on the discount
            // loop). Premium users also keep the bell + avatar.
            FreePlanHomeBadges(
                onTapQuota: { showsQuotaInfo = true },
                onTapGift: {
                    // Route the tap based on the gift's current phase:
                    //   • won + still in 24 h claim window → open the
                    //     exclusive offer view directly
                    //   • notWon → open the mini-game so they can spin
                    //   • forfeited → cooldown is active; show a brief
                    //     toast/alert rather than re-opening the wheel
                    //     (the wheel is a one-shot flow per cycle)
                    switch offers.giftPhase {
                    case .won where offers.giftOfferIsActive:
                        showsExclusiveOffer = true
                    case .notWon:
                        showsGiftWheel = true
                    case .forfeited:
                        OnboardingHaptics.selection()
                        showsGiftCooldownAlert = true
                    default:
                        showsGiftWheel = true
                    }
                }
            )

            if sessionStore.profile?.isPremium ?? false {
                HomeCircleIconButton(
                    systemName: "bell",
                    unreadCount: notificationsInbox.unreadCount
                ) {
                    showsNotificationsInbox = true
                }

                Button(action: openProfileTab) {
                    HomeAvatarBadge(
                        text: viewModel.profileBadgeText,
                        avatarURL: sessionStore.profile?.avatarURL
                    )
                        .overlay(alignment: .topTrailing) {
                            // Premium crown — celebratory gold variant.
                            PremiumCrownBadge(
                                isPremium: true,
                                size: 16
                            )
                            .offset(x: 4, y: -4)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(viewModel.greetingLine)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)

                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CooksyTheme.sparkleYellow)
            }

            Text(viewModel.homeHeadline)
                .font(.system(size: 35, weight: .bold, design: .serif))
                .tracking(-0.8)
                .foregroundStyle(CooksyTheme.primaryText)
                .lineSpacing(-2)
                .lineLimit(3)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Anticipation card shown to free users while a declined gift is
    /// cooling down: a pot that simmers a "surprise" with a live
    /// countdown, then flips to a tappable "ready" state that opens the
    /// gift mini-game. Hidden until the cooldown is a couple of days in
    /// (see `PremiumOffersService.shouldShowGiftTeaser`).
    @ViewBuilder
    private var giftCookingTeaser: some View {
        if !(sessionStore.profile?.isPremium ?? false),
           offers.shouldShowGiftTeaser || offers.hasFreshGiftCelebrationPending {
            GiftCookingTeaserCard(
                offers: offers,
                onPlay: {
                    offers.acknowledgeFreshGiftCelebration()
                    showsGiftWheel = true
                },
                onDismissReady: {
                    offers.acknowledgeFreshGiftCelebration()
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var importGuideCard: some View {
        Button(action: { showsImportGuide = true }) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: 0xFFF2E4))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: viewModel.pendingImport == nil ? "square.and.arrow.down" : "arrow.trianglehead.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.importGuideTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Text(viewModel.importGuideSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("Importer")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFF2E4))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var recentImportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Imports récents")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                if viewModel.hasRecentImports {
                    Button(action: openRecipesTab) {
                        Text("Voir tout")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.hasRecentImports {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.recentImportCards) { card in
                            recentImportDestination(for: card)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 4)
                }
            } else {
                HomeRecentImportsEmptyState(onImport: openImportSheet)
            }
        }
    }

    private var trendingTodaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tendances du jour")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrange)
                    .shadow(color: CooksyTheme.ctaOrange.opacity(0.35), radius: 6, y: 2)
            }

            // IG-Reel style horizontal carousel — each card is a bit narrower
            // than the content area so the next card peeks (Instagram vibe),
            // with viewAligned snapping for a premium swipe feel.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.trendingTodayItems) { item in
                        trendingDestination(for: item, width: trendingReelCardWidth)
                    }
                }
                .padding(.trailing, 4)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: trendingReelCardHeight)
        }
    }

    /// Slightly narrower than the page content area so the next card peeks ~40pt.
    private var trendingReelCardWidth: CGFloat {
        max(UIScreen.main.bounds.width - 80, 260)
    }

    /// 3:4 aspect + a little breathing room for the drop shadow.
    private var trendingReelCardHeight: CGFloat {
        trendingReelCardWidth * 4.0 / 3.0 + 12
    }

    @ViewBuilder
    private func recentImportDestination(for card: HomeViewModel.RecentImportCard) -> some View {
        if let recipeID = card.destinationRecipeID {
            NavigationLink {
                RecipeDetailView(store: store, recipeID: recipeID)
            } label: {
                HomeRecentImportCardView(card: card)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: openImportSheet) {
                HomeRecentImportCardView(card: card)
            }
            .buttonStyle(.plain)
        }
    }

    private func trendingDestination(for item: HomeViewModel.TrendingRecipe, width: CGFloat) -> some View {
        NavigationLink {
            TrendingRecipePreviewView(
                scenario: item.scenario,
                store: store
            )
        } label: {
            HomeTrendingReelCard(item: item)
                .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeCircleIconButton: View {
    let systemName: String
    /// When non-zero, a small orange dot sits on the top-right of the
    /// button to signal pending unread state (used by the bell icon
    /// for the in-app notifications inbox).
    var unreadCount: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CooksyTheme.secondaryText)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.98))
                )
                .overlay(
                    Circle()
                        .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        ZStack {
                            Circle()
                                .fill(CooksyTheme.ctaOrange)
                            Circle()
                                .stroke(Color.white, lineWidth: 1.5)
                        }
                        .frame(width: 11, height: 11)
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("\(unreadCount) notifications non lues")
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeAvatarBadge: View {
    let text: String
    let avatarURL: URL?

    init(text: String, avatarURL: URL? = nil) {
        self.text = text
        self.avatarURL = avatarURL
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xD9B596), Color(hex: 0xB77850)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Text(text)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct HomeRecentImportCardView: View {
    let card: HomeViewModel.RecentImportCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                HomeArtworkSurface(artwork: card.artwork, emojiSize: 42)
                    .frame(width: 208, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(alignment: .top) {
                    Text(card.sourceLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        )

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .bold))

                        Text(card.ratingLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                }
                .padding(10)
            }

            Text(card.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            HStack(spacing: 10) {
                HomeMetaLabel(systemName: "clock", text: card.durationLabel)
                HomeMetaLabel(systemName: "flame.fill", text: card.caloriesLabel)
            }
        }
        .frame(width: 208, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }
}

/// Full-bleed editorial card used in the "Tendances du jour" horizontal
/// carousel on Home. Magazine-style hero with the scenario emoji as a
/// glowing centerpiece, layered light flares, and a clean typographic
/// bottom block (source · handle · meta).
private struct HomeTrendingReelCard: View {
    let item: HomeViewModel.TrendingRecipe

    private var topColor: Color {
        guard case .demo(let scenario) = item.artwork else { return Color(hex: 0xEA662A) }
        return Color(hex: scenario.hero.topColorHex)
    }

    private var bottomColor: Color {
        guard case .demo(let scenario) = item.artwork else { return Color(hex: 0xC9471D) }
        return Color(hex: scenario.hero.bottomColorHex)
    }

    private var heroEmoji: String {
        guard case .demo(let scenario) = item.artwork else { return "🍽️" }
        return scenario.hero.emoji
    }

    private var sourceLabel: String {
        // Stable per-scenario "source" so the same recipe always shows the
        // same network — feels like a real curated import feed.
        let key = (item.id + item.title).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return key % 2 == 0 ? "Instagram" : "TikTok"
    }

    private var sourceIcon: String {
        sourceLabel == "TikTok" ? "music.note" : "camera.fill"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Layered gradient base — warmer, deeper than a single linear pass.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [topColor, bottomColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Soft radial halo behind the hero emoji to give it a "lit"
            // photographic feel without using an actual photo.
            RadialGradient(
                colors: [
                    Color.white.opacity(0.45),
                    Color.white.opacity(0.10),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 220
            )
            .blendMode(.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Decorative light blobs for depth.
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: 130, y: -120)

            Circle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 180, height: 180)
                .blur(radius: 28)
                .offset(x: -90, y: 160)

            // Hero emoji — large, soft, the visual anchor.
            Text(heroEmoji)
                .font(.system(size: 150))
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: -10)
                .allowsHitTesting(false)

            // Bottom scrim so title/meta stay legible over any palette.
            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top row: source pill (left) + rating pill (right)
            HStack(alignment: .top) {
                HomeTrendingPill(
                    icon: sourceIcon,
                    text: sourceLabel,
                    background: Color.black.opacity(0.42),
                    foreground: .white
                )

                Spacer(minLength: 0)

                HomeTrendingPill(
                    icon: "star.fill",
                    text: item.ratingLabel,
                    background: Color.black.opacity(0.42),
                    foreground: .white
                )
            }
            .padding(16)

            // Bottom block: rank chip + title + handle · duration
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("#\(item.rank) tendance")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )

                Text(item.title)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
                    .shadow(color: Color.black.opacity(0.30), radius: 8, y: 3)

                HStack(spacing: 6) {
                    Text(item.handle)
                        .fontWeight(.semibold)

                    Text("·")

                    Text(item.durationLabel)

                    Text("·")

                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(item.ratingLabel)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.40), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 24, y: 12)
    }
}

private struct HomeTrendingPill: View {
    let icon: String?
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            Capsule(style: .continuous)
                .fill(background)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

private struct HomeRecentImportsEmptyState: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.5))

            VStack(spacing: 6) {
                Text("Aucune recette pour l'instant")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Importe ta première recette depuis TikTok, Instagram ou n'importe quel lien")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onImport) {
                Text("Importer une recette")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFF2E4))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct HomeMetaLabel: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))

            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(CooksyTheme.secondaryText)
    }
}

private struct HomeArtworkSurface: View {
    let artwork: HomeViewModel.Artwork
    let emojiSize: CGFloat

    var body: some View {
        Group {
            switch artwork {
            case .recipe(let recipe):
                if recipe.heroImageURL == nil,
                   let previewSeed = DemoRecipeMatcherService.match(sharedText: recipe.title),
                   let imageData = previewSeed.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    RecipeThumbnail(recipe: recipe)
                }
            case .demo(let scenario):
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hex: scenario.hero.topColorHex),
                            Color(hex: scenario.hero.bottomColorHex)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 92, height: 92)
                        .offset(x: 38, y: -28)

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 74, height: 74)
                        .offset(x: -34, y: 30)

                    Text(scenario.hero.emoji)
                        .font(.system(size: emojiSize))
                }
            }
        }
        // Always honour the size the parent proposes — without this,
        // a freshly-imported recipe whose 1024×1024 image hasn't been
        // through `.frame(...)` yet would push its surrounding card
        // out of bounds.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct RecipeLibraryView: View {
    @ObservedObject private var store: RecipeStore

    private let sharedLinkInbox: SharedLinkInbox
    private let openImportSheet: () -> Void

    @State private var showsCreateBookSheet = false
    @State private var pendingImportHostLabel: String?

    private let columns = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    init(
        store: RecipeStore,
        sharedLinkInbox: SharedLinkInbox,
        openImportSheet: @escaping () -> Void = {}
    ) {
        self.store = store
        self.sharedLinkInbox = sharedLinkInbox
        self.openImportSheet = openImportSheet
    }

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    libraryHeader
                    libraryOverview
                    ImportGuideBanner(
                        title: pendingImportHostLabel == nil ? "Importer une recette depuis un lien ou une vidéo" : "Lien partagé depuis \(pendingImportHostLabel ?? "une app")",
                        action: openImportSheet
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Vos livres")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("\(displayedBookCount) livres pour \(store.recipes.count) recettes.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        CreateRecipeBookCard {
                            showsCreateBookSheet = true
                        }

                        if let uncategorizedBook {
                            NavigationLink {
                                RecipeBookDetailView(bookID: uncategorizedBook.id)
                            } label: {
                                RecipeBookCard(
                                    book: uncategorizedBook,
                                    recipes: store.recipes(in: uncategorizedBook)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(customBooks) { book in
                            NavigationLink {
                                RecipeBookDetailView(bookID: book.id)
                            } label: {
                                RecipeBookCard(
                                    book: book,
                                    recipes: store.recipes(in: book)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 146)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            pendingImportHostLabel = sharedLinkInbox.peek()?.hostLabel
        }
        .sheet(isPresented: $showsCreateBookSheet) {
            CreateRecipeBookSheet { title in
                store.createBook(title: title)
            }
        }
    }

    private var uncategorizedBook: RecipeBook? {
        store.books.first(where: { $0.kind == .uncategorized })
    }

    private var customBooks: [RecipeBook] {
        store.books
            .filter { $0.kind == .collection }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var displayedBookCount: Int {
        (uncategorizedBook == nil ? 0 : 1) + customBooks.count
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECETTES")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text("Votre bibliothèque")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("Tous les livres et toutes les recettes vivent ici, sans encombrer l’accueil.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }

    private var libraryOverview: some View {
        HStack(spacing: 14) {
            libraryMetric(title: "Recettes", value: "\(store.recipes.count)")
            libraryMetric(title: "Livres", value: "\(displayedBookCount)")
            libraryMetric(title: "Semaine", value: "\(store.mealPlanEntries.count)")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func libraryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(CooksyTheme.secondaryText)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomePrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            .foregroundStyle(CooksyTheme.primaryText)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactBookBridgeChip: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 10) {
            BookPreviewStrip(recipes: recipes)
                .frame(width: 72, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)

                Text("\(book.recipeCount) recette\(book.recipeCount > 1 ? "s" : "")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct CompactRecentRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumbnail(recipe: recipe)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)

                Text("\(recipe.ingredients.count) ingrédients • \(recipe.steps.count) étapes")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(.vertical, 14)
    }
}

private struct MiniBookBridgeCard: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookPreviewStrip(recipes: recipes)
                .frame(width: 208, height: 86)

            Text(book.title)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(2)

            Text("\(book.recipeCount) recette\(book.recipeCount > 1 ? "s" : "")")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .padding(14)
        .frame(width: 228, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

private struct BookPreviewStrip: View {
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(recipes.prefix(3).enumerated()), id: \.offset) { _, recipe in
                RecipeThumbnail(recipe: recipe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if recipes.isEmpty {
                placeholderTile
            } else if recipes.count == 1 {
                placeholderTile
                placeholderTile
            } else if recipes.count == 2 {
                placeholderTile
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.warmCard.opacity(0.72))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CooksyTheme.elevatedSurface.opacity(0.88))
    }
}

private struct RecipeFeatureArtwork: View {
    let recipe: Recipe

    var body: some View {
        RecipeThumbnail(recipe: recipe)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(CooksyTheme.stroke.opacity(0.82), lineWidth: 1)
            )
    }
}

private struct RecipeThumbnail: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        // Lock the thumbnail to whatever the parent proposes — the
        // library / home cards always pass an explicit size, but a
        // large 1024×1024 import would otherwise blow up any parent
        // that doesn't.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallback: some View {
        LinearGradient(
            colors: fallbackColors,
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var fallbackColors: [Color] {
        CooksyTheme.recipeGradientColors(for: recipe.heroStyle)
    }
}

private struct HomeWordmarkHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            Text("Cooksy")
                .font(.custom("AvenirNext-HeavyItalic", size: 38))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cooksy")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
