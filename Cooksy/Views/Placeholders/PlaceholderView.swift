import SwiftUI

struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("BIENTOT")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)

                HStack(alignment: .top, spacing: 18) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CooksyTheme.blush.opacity(0.58))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.system(size: 32, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text(message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct QuickImportSheetView: View {
    /// `false` once the free user has used up their weekly import quota.
    /// Gates AI-powered options ("Texte collé"); "Depuis zéro" stays free.
    var canImport: Bool = true
    let onCreateFromScratch: () -> Void
    let onBrowserImport: () -> Void
    let onCameraImport: () -> Void
    let onPasteText: () -> Void
    /// Called when the user taps an AI option while their quota is spent —
    /// the host responds by showing `QuotaReachedSheet`.
    var onQuotaReached: () -> Void = {}

    private let options: [QuickImportOption] = [
        QuickImportOption(
            kind: .createFromScratch,
            title: "Depuis\nzéro",
            systemImage: "pencil",
            accentColor: CooksyTheme.ctaOrange,
            isLocked: false,
            eclairCost: 0
        ),
        QuickImportOption(
            kind: .browser,
            title: "Site\nweb",
            systemImage: "safari",
            accentColor: CooksyTheme.ctaOrange,
            isLocked: true,
            eclairCost: 1
        ),
        QuickImportOption(
            kind: .camera,
            title: "Appareil\nphoto",
            systemImage: "camera",
            accentColor: CooksyTheme.ctaOrange,
            isLocked: true,
            eclairCost: 1
        ),
        QuickImportOption(
            kind: .pasteText,
            title: "Texte\ncollé",
            systemImage: "text.alignleft",
            accentColor: CooksyTheme.ctaOrange,
            isLocked: false,
            eclairCost: 1
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Text("Importer une recette")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.top, 8)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(options) { option in
                        QuickImportOptionCard(
                            option: option,
                            isQuotaLocked: isQuotaLocked(option),
                            action: action(for: option.kind)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(CooksyTheme.background)
        }
        .presentationDetents([.height(475)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(CooksyTheme.background)
    }

    private func action(for kind: QuickImportOption.Kind) -> () -> Void {
        switch kind {
        case .createFromScratch:
            return onCreateFromScratch
        case .browser:
            return onBrowserImport
        case .camera:
            return onCameraImport
        case .pasteText:
            // Quota spent → route straight to the limit screen instead of
            // opening the paste editor.
            return canImport ? onPasteText : onQuotaReached
        }
    }

    /// An otherwise-available, AI-powered option that the free user can no
    /// longer use this week because their import quota is exhausted.
    private func isQuotaLocked(_ option: QuickImportOption) -> Bool {
        !option.isLocked && option.eclairCost > 0 && !canImport
    }
}

private struct QuickImportOption: Identifiable {
    enum Kind {
        case createFromScratch
        case browser
        case camera
        case pasteText
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let systemImage: String
    let accentColor: Color
    let isLocked: Bool
    /// How many free-plan éclairs (weekly import slots) this path
    /// consumes when the recipe is saved. 0 = no AI work, no quota hit.
    let eclairCost: Int
}

private struct QuickImportOptionCard: View {
    let option: QuickImportOption
    /// `true` when the free user's weekly quota is spent and this option
    /// would consume an éclair. The card stays tappable on purpose — the
    /// tap routes to the limit screen rather than doing nothing.
    var isQuotaLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 14) {
                    if option.isLocked {
                        topPill(text: "BIENTÔT")
                    } else if isQuotaLocked {
                        topPill(text: "INDISPONIBLE")
                    }

                    Image(systemName: option.systemImage)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(option.accentColor)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.45))
                        )

                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(option.accentColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    costBadge
                }
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .opacity(option.isLocked ? 0.55 : (isQuotaLocked ? 0.82 : 1.0))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CooksyTheme.warmCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 1)
                )

                if option.isLocked || isQuotaLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                        )
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        // Only the "coming soon" options are truly disabled. A quota-locked
        // option stays tappable so its tap can surface the limit screen.
        .disabled(option.isLocked)
        .allowsHitTesting(!option.isLocked)
    }

    private func topPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(CooksyTheme.ctaOrangeDark.opacity(0.12))
            )
    }

    /// Bottom chip: the éclair cost normally, or a "Limite atteinte" lock
    /// chip when the weekly quota is spent.
    @ViewBuilder
    private var costBadge: some View {
        if isQuotaLocked {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .black))
                Text("Limite atteinte")
                    .font(.system(size: 10, weight: .black, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.ctaOrangeDark.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.ctaOrangeDark.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel("Limite hebdomadaire atteinte")
        } else {
            eclairCostBadge
        }
    }

    /// "–0 ⚡" / "–1 ⚡" chip telling the user up-front how many
    /// éclairs (weekly free-plan import slots) this option will burn.
    /// Free, no-AI paths show a green "0" so users feel safe tapping.
    private var eclairCostBadge: some View {
        let isFree = option.eclairCost == 0
        let tint: Color = isFree
            ? Color(hex: 0x4D8B47)
            : CooksyTheme.ctaOrangeDark
        return HStack(spacing: 4) {
            Text("–\(option.eclairCost)")
                .font(.system(size: 11, weight: .black, design: .rounded))
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .black))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityLabel(isFree
            ? "Aucun éclair consommé"
            : "\(option.eclairCost) éclair consommé")
    }
}
