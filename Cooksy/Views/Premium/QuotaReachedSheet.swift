import SwiftUI

/// Surfaced when a free user attempts a 4th import within the same ISO week.
/// Non-dismissible primary CTA that pushes the paywall; secondary "Plus tard"
/// closes the sheet without changing state.
struct QuotaReachedSheet: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @StateObject private var quota = ImportQuotaService.shared
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft)
                    .frame(width: 84, height: 84)
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Tu as atteint ta limite cette semaine")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.center)
                Text("3 recettes / semaine en gratuit · réinitialisation \(resetCopy)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 12) {
                bulletRow(icon: "infinity", title: "Imports illimités", subtitle: "TikTok · Insta · YouTube · Reels · Shorts")
                bulletRow(icon: "wand.and.stars", title: "IA culinaire avancée", subtitle: "Sections, conversions, nutrition")
                bulletRow(icon: "calendar.badge.clock", title: "Plan repas + courses", subtitle: "Génération automatique chaque semaine")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: {
                    OnboardingHaptics.medium()
                    onUpgrade()
                }) {
                    Text("Passer Premium")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 10)
                }
                .buttonStyle(CooksyTheme.pressScale())

                Button(action: {
                    OnboardingHaptics.selection()
                    onDismiss()
                }) {
                    Text("Compris, j'attends")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .background(CooksyTheme.background.ignoresSafeArea())
        .onReceive(timer) { _ in now = Date() }
    }

    private func bulletRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryAccentStrong)
                .frame(width: 36, height: 36)
                .background(Circle().fill(CooksyTheme.primaryAccentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            Spacer()
        }
    }

    private var resetCopy: String {
        let secs = quota.secondsUntilReset
        let hours = Int(secs / 3600)
        if hours > 24 {
            let days = Int(ceil(secs / 86400))
            return "dans \(days) jour\(days > 1 ? "s" : "")"
        }
        if hours <= 1 {
            return "dans moins d'1 h"
        }
        return "dans \(hours) h"
    }
}
