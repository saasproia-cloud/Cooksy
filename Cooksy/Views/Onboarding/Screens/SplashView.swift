import SwiftUI

/// Shown while `SessionStore.phase == .loading` — a short branded moment so
/// the first frame feels intentional instead of an empty gradient.
struct SplashView: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(CooksyTheme.primaryAccentSoft.opacity(0.55))
                        .frame(width: 160, height: 160)
                        .blur(radius: 24)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    Circle()
                        .fill(CooksyTheme.elevatedSurface)
                        .frame(width: 96, height: 96)
                        .shadow(color: CooksyTheme.primaryAccent.opacity(0.3), radius: 18, y: 8)

                    Image(systemName: "fork.knife")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                Text("Cooksy")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .tracking(0.5)
            }
        }
        .onAppear { pulse = true }
    }
}
