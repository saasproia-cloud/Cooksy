import SwiftUI

/// C2 — Personalized recap. A big "profile card" assembles itself line by line
/// in front of the user, reflecting the answers they just gave. Value of this
/// screen = investment / payoff signal right before the account ask.
struct PersonalizedPreviewView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        OnboardingChrome(
            title: "Ton profil Cooksy\nest prêt ✨",
            subtitle: "Voici ce qu'on a retenu. Tu pourras le modifier à tout moment depuis ton profil.",
            ctaTitle: "Créer mon compte",
            canAdvance: true,
            progress: nil,
            showsBack: true,
            showsSkip: false,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 20) {
                ProfilePreviewCard(
                    answers: coordinator.answers,
                    appeared: appeared
                )

                SocialStrip(appeared: appeared)
            }
            .onAppear {
                appeared = false
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    await MainActor.run { appeared = true }
                }
            }
        }
    }
}

// MARK: - Profile card

private struct ProfilePreviewCard: View {
    let answers: OnboardingAnswers
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.05), value: appeared)

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(height: 1)

            VStack(spacing: 12) {
                PreviewLine(
                    index: 0,
                    appeared: appeared,
                    icon: "person.2.fill",
                    label: "Niveau",
                    value: levelTitle
                )

                PreviewLine(
                    index: 1,
                    appeared: appeared,
                    icon: "fork.knife.circle.fill",
                    label: "Tu cuisines pour",
                    value: servingsTitle
                )

                PreviewLine(
                    index: 2,
                    appeared: appeared,
                    icon: "sparkles",
                    label: "Tu aimes",
                    value: cuisineList
                )

                if let exclusions = dietList {
                    PreviewLine(
                        index: 3,
                        appeared: appeared,
                        icon: "leaf.fill",
                        label: "Sans",
                        value: exclusions
                    )
                }

                PreviewLine(
                    index: 4,
                    appeared: appeared,
                    icon: "clock.fill",
                    label: "Temps par repas",
                    value: "\(answers.timeMinutesPerMeal) min"
                )
            }

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(height: 1)

            Text(summary)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.9), value: appeared)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.heroRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.heroRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 56, height: 56)

                Text(initials)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.35), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mon profil Cooksy")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("Tes recettes, taillées sur mesure.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Derived strings

    private var initials: String {
        // No name at this stage — use a "C" for Cooksy so the card doesn't look empty.
        "C"
    }

    private var levelTitle: String {
        answers.skillLevel?.title ?? "À confirmer"
    }

    private var servingsTitle: String {
        guard let s = answers.typicalServings else { return "À confirmer" }
        return "\(s.title) (\(s.subtitle.lowercased()))"
    }

    private var cuisineList: String {
        let titles = answers.cuisines.map { $0.title.lowercased() }.sorted()
        if titles.isEmpty { return "un peu de tout" }
        if titles.count <= 3 { return titles.joined(separator: ", ") }
        return titles.prefix(3).joined(separator: ", ") + "…"
    }

    private var dietList: String? { answers.dietSummary }

    private var summary: String {
        "Des recettes \(answers.paceDescriptor) pour \(answers.goalOutcome)."
    }
}

// MARK: - Preview line

private struct PreviewLine: View {
    let index: Int
    let appeared: Bool
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.65))
                    .frame(width: 30, height: 30)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .tracking(0.5)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(
            .spring(response: 0.55, dampingFraction: 0.82).delay(0.2 + Double(index) * 0.12),
            value: appeared
        )
    }
}

// MARK: - Social proof strip

private struct SocialStrip: View {
    let appeared: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CooksyTheme.sparkleYellow)
                }
            }

            Text("4,8")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .monospacedDigit()

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(width: 1, height: 20)

            Text("24\u{00A0}128 passionnés nous ont rejoint")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.warmCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.warmCardMuted.opacity(0.5), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.6).delay(1.1), value: appeared)
    }
}
