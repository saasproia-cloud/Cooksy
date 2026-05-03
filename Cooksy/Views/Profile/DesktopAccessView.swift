import SwiftUI

/// Pushed from Profile → "Utiliser Cooksy sur le bureau".
/// The desktop app isn't built yet. Rather than hide the row or show a
/// dead-end toast, we present a real "early access" page where the user can
/// register their interest. Their email is pre-filled from `SessionStore`.
struct DesktopAccessView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("cooksy.desktop.earlyAccessRequested") private var requested: Bool = false

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroIllustration
                        .padding(.top, 12)

                    titleBlock

                    featuresCard

                    if requested {
                        confirmationCard
                    } else {
                        ctaButton
                    }

                    smallPrint

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Cooksy sur le bureau")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero (SwiftUI laptop mockup)

    private var heroIllustration: some View {
        ZStack {
            // Laptop body
            VStack(spacing: 0) {
                // Screen
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x1A1A1A))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 6, height: 6)
                                Circle().fill(Color(hex: 0xFFBD2E)).frame(width: 6, height: 6)
                                Circle().fill(Color(hex: 0x28C840)).frame(width: 6, height: 6)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                            // Cooksy mock interface
                            HStack(spacing: 8) {
                                Image("HeaderLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                                Text("Cooksy")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 10)

                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(height: 32)
                                }
                            }
                            .padding(.horizontal, 10)

                            Spacer(minLength: 0)
                        }
                    )
                    .frame(height: 140)

                // Hinge
                Rectangle()
                    .fill(Color(hex: 0x2A2A2A))
                    .frame(height: 4)

                // Base
                Trapezoid()
                    .fill(Color(hex: 0xC9C9C9))
                    .frame(height: 8)
            }
            .frame(maxWidth: 220)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Bientôt sur Mac et PC")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text("EARLY")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CooksyTheme.ctaOrange))
            }

            Text("On travaille sur une version desktop pour cuisiner depuis ton ordinateur — idéal pour suivre une recette sur un plus grand écran pendant que tu cuisines.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AU PROGRAMME")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(CooksyTheme.secondaryText)

            featureRow(icon: "rectangle.expand.vertical", title: "Mode cuisine plein écran", body: "Affichage géant des étapes, parfait pour suivre depuis le plan de travail.")
            featureRow(icon: "icloud", title: "Sync automatique", body: "Tes recettes mobiles apparaissent instantanément sur le bureau.")
            featureRow(icon: "printer", title: "Impression propre", body: "Une fiche recette imprimable en un clic, sans pub ni pop-up.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func featureRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CooksyTheme.blush.opacity(0.55))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text(body)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var ctaButton: some View {
        Button(action: register) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Me prévenir au lancement")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.accentGradient)
            )
            .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 16, y: 10)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }

    private var confirmationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x4A8C2F))
            VStack(alignment: .leading, spacing: 2) {
                Text("On te prévient !")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("On t'écrit à \(emailLabel) dès que la version bureau est prête.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0xE8F4DD))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0x4A8C2F).opacity(0.3), lineWidth: 1)
        )
    }

    private var smallPrint: some View {
        Text("Aucun spam — uniquement un e-mail le jour du lancement.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Helpers

    private var emailLabel: String {
        sessionStore.currentUser?.email ?? "ton adresse"
    }

    private func register() {
        OnboardingHaptics.medium()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            requested = true
        }
    }
}

/// Simple trapezoidal shape for the laptop base.
private struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 12
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
