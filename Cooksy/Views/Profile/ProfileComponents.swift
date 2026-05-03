import SwiftUI

// MARK: - Header card (avatar + name + edit link)

struct ProfileHeaderCard: View {
    let displayName: String
    let avatarInitial: String
    var avatarURL: URL? = nil
    var isPremium: Bool = false
    let onEditTap: () -> Void
    var onCrownTapWhenLocked: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.ctaOrange.opacity(0.25), radius: 12, y: 6)

                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Text(avatarInitial)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Text(avatarInitial)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                PremiumCrownBadge(
                    isPremium: isPremium,
                    size: 24,
                    onTapWhenLocked: onCrownTapWhenLocked
                )
                .offset(x: 4, y: -4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)

                Button(action: onEditTap) {
                    Text("Modifier le profil")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Premium banner

struct ProfilePremiumBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CooksyTheme.sparkleYellow)
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6B3B03))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Passer à Cooksy Plus")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Text("Recettes illimitées, IA avancée")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(CooksyTheme.warmCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section card (grouped rows)

struct ProfileSectionCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Row inside a section

struct ProfileRow: View {
    let systemImage: String
    let title: String
    var isLast: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.55))
                            .frame(width: 36, height: 36)

                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

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

            if !isLast {
                Rectangle()
                    .fill(CooksyTheme.dividerSubtle)
                    .frame(height: 1)
                    .padding(.leading, 66)
            }
        }
    }
}

// MARK: - Row that pushes a destination view (NavigationLink variant)

struct ProfileNavigationRow<Destination: View>: View {
    let systemImage: String
    let title: String
    var isLast: Bool = false
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: destination()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.55))
                            .frame(width: 36, height: 36)

                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

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

            if !isLast {
                Rectangle()
                    .fill(CooksyTheme.dividerSubtle)
                    .frame(height: 1)
                    .padding(.leading, 66)
            }
        }
    }
}

// MARK: - Row that triggers a system ShareLink

struct ShareLinkProfileRow: View {
    let systemImage: String
    let title: String
    var isLast: Bool = false
    let shareText: String

    var body: some View {
        VStack(spacing: 0) {
            ShareLink(item: shareText) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.blush.opacity(0.55))
                            .frame(width: 36, height: 36)

                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isLast {
                Rectangle()
                    .fill(CooksyTheme.dividerSubtle)
                    .frame(height: 1)
                    .padding(.leading, 66)
            }
        }
    }
}

// MARK: - Footer version

struct ProfileFooterVersion: View {
    var body: some View {
        Text(versionString)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

// MARK: - Coming soon toast

struct ComingSoonToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CooksyTheme.sparkleYellow)

            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(CooksyTheme.primaryText.opacity(0.92))
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
    }
}
