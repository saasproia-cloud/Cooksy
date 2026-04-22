import SwiftUI

/// C1 — "Construction du profil". Theatrical pause between the questions and
/// the personalized recap: pulsing logo, a circular gradient arc that spins,
/// and three status bullets that check themselves off one by one.
/// Auto-advances after ~3 seconds.
struct ProfileBuildingView: View {
    let onCompleted: () -> Void

    @State private var pulse: Bool = false
    @State private var spin: Double = 0
    @State private var completedBullets: Int = 0

    private let bullets: [String] = [
        "Analyse de tes préférences…",
        "Sélection de 250+ recettes adaptées…",
        "Personnalisation de ton espace…"
    ]

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer(minLength: 0)

                logo
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, text in
                        BulletRow(
                            text: text,
                            completed: completedBullets > index,
                            isActive: completedBullets == index
                        )
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Text("On prépare ton espace Cooksy, encore un instant ✨")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .onAppear(perform: runSequence)
    }

    // MARK: - Logo + spinning arc

    private var logo: some View {
        ZStack {
            // Soft halo
            Circle()
                .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
                .frame(width: 180, height: 180)
                .blur(radius: 22)
                .scaleEffect(pulse ? 1.08 : 0.92)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

            // Rotating arc
            Circle()
                .trim(from: 0.05, to: 0.85)
                .stroke(
                    CooksyTheme.accentGradient,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 128, height: 128)
                .rotationEffect(.degrees(spin))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)

            // Fork & knife emblem
            ZStack {
                Circle()
                    .fill(CooksyTheme.elevatedSurface)
                    .frame(width: 96, height: 96)
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.25), radius: 18, y: 8)

                Image(systemName: "fork.knife")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
            .scaleEffect(pulse ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
        }
    }

    // MARK: - Timed sequence

    private func runSequence() {
        pulse = true
        spin = 360

        // Cascade bullets
        for i in 0..<bullets.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 + Double(i) * 0.9) {
                OnboardingHaptics.success()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    completedBullets = i + 1
                }
            }
        }

        // Hand off
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
            onCompleted()
        }
    }
}

// MARK: - Bullet row

private struct BulletRow: View {
    let text: String
    let completed: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(completed ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.elevatedSurface, CooksyTheme.elevatedSurface], startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(completed ? Color.clear : CooksyTheme.stroke, lineWidth: 1)
                    )

                if completed {
                    AnimatedCheckmark()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 9)
                } else if isActive {
                    Circle()
                        .fill(CooksyTheme.ctaOrange)
                        .frame(width: 8, height: 8)
                        .opacity(isActive ? 1 : 0)
                        .scaleEffect(isActive ? 1 : 0.5)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isActive)
                }
            }

            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(completed ? CooksyTheme.primaryText : CooksyTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: completed)
    }
}
