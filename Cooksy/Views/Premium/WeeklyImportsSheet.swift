import SwiftUI

/// Bottom sheet shown when the lightning pill in the home top-bar is
/// tapped. Two flavours:
///
///   • Free user — counts the remaining weekly imports as a row of
///     lightning icons (filled = remaining, dimmed = consumed) and
///     pushes the upgrade CTA below.
///   • Premium user — same lightning row, all filled in gold, with a
///     thank-you message and no CTA.
///
/// Replaces the old `Alert` to give the lightning pill the same weight
/// as the gift flow (and to mirror what RecipeMe ships in their app —
/// see screenshot reference).
struct WeeklyImportsSheet: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @StateObject private var quota = ImportQuotaService.shared
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 60.0, on: .main, in: .common).autoconnect()

    private var isPremium: Bool { quota.isPremium }
    private var totalSlots: Int { ImportQuotaService.freeWeeklyLimit }
    private var remaining: Int {
        if isPremium { return totalSlots }
        return min(quota.remainingThisWeek, totalSlots)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            // Lightning row — visual cue of remaining capacity.
            HStack(spacing: 14) {
                ForEach(0..<totalSlots, id: \.self) { index in
                    boltIcon(filled: index < remaining)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 22)

            // Two-tone headline like the RecipeMe reference: orange/accent
            // numerator + dark grey rest of the sentence.
            headline
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Subtitle: reset countdown for free users, thank-you for premium.
            subtitle
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            Spacer(minLength: 18)

            if !isPremium {
                Button(action: {
                    OnboardingHaptics.medium()
                    onUpgrade()
                }) {
                    Text("Débloquez les importations illimitées")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 8)
                }
                .buttonStyle(CooksyTheme.pressScale())
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            } else {
                Button(action: {
                    OnboardingHaptics.selection()
                    onDismiss()
                }) {
                    Text("Continuer à cuisiner")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity)
        .background(CooksyTheme.background.ignoresSafeArea())
        .onReceive(timer) { _ in now = Date() }
    }

    // MARK: - Pieces

    private func boltIcon(filled: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(filled
                      ? AnyShapeStyle(CooksyTheme.goldShimmer)
                      : AnyShapeStyle(Color.gray.opacity(0.18)))
                .frame(width: 44, height: 56)
                .shadow(
                    color: filled ? CooksyTheme.primaryAccentGlow.opacity(0.45) : .clear,
                    radius: 12, y: 6
                )
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(filled ? CooksyTheme.heroDark : Color.gray.opacity(0.45))
        }
    }

    private var headline: some View {
        Group {
            if isPremium {
                (
                    Text("∞ ")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryAccentStrong)
                    + Text("importations illimitées cette semaine")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryText)
                )
            } else {
                (
                    Text("\(remaining) sur \(totalSlots) ")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryAccentStrong)
                    + Text("importations\nhebdomadaires restantes")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(CooksyTheme.primaryText)
                )
            }
        }
    }

    private var subtitle: some View {
        Group {
            if isPremium {
                Text("Merci d'être membre Cooksy Premium 💛")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            } else {
                (
                    Text("Réinitialisation \(resetCopy). ")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(CooksyTheme.secondaryText)
                    + Text("Rappelez-moi")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(CooksyTheme.primaryText)
                )
            }
        }
    }

    private var resetCopy: String {
        let secs = quota.secondsUntilReset
        let hours = Int(secs / 3600)
        if hours > 24 {
            let days = Int(ceil(secs / 86400))
            return "dans \(days) jour\(days > 1 ? "s" : "")"
        }
        if hours <= 1 { return "dans moins d'1 h" }
        return "dans \(hours) h"
    }
}
