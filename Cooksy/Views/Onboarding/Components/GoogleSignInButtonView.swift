import SwiftUI

/// "Continuer avec Google" button. Renders a clean white capsule with the
/// colored Google "G" drawn purely in SwiftUI (no asset required).
///
/// Wiring to GoogleSignIn-iOS is deferred: tapping the button today shows a
/// toast via `SessionStore.lastErrorMessage` explaining the provider still
/// needs to be configured. Once the SPM package is added and the reversed
/// client ID is in `Info.plist`, replace the `action` body with the real
/// `GIDSignIn.sharedInstance.signIn(...)` flow that forwards the resulting
/// `idToken` / `accessToken` to `SessionStore.signInWithGoogle`.
struct GoogleSignInButtonView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Button(action: {
            OnboardingHaptics.light()
            sessionStore.lastErrorMessage = "Connexion Google arrive bientôt."
        }) {
            HStack(spacing: 12) {
                GoogleGlyph()
                    .frame(width: 20, height: 20)

                Text("Continuer avec Google")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .shadow(color: CooksyTheme.softShadow, radius: 10, y: 4)
        }
        .buttonStyle(CooksyTheme.pressScale())
    }
}

/// Minimal rendering of the four-color Google "G".
private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            // Each quadrant is a simple rounded rectangle with a different Google brand color.
            // It reads clearly at 20pt without any asset.
            GeometryReader { proxy in
                let w = proxy.size.width
                let r = w / 2
                ZStack {
                    Circle().stroke(Color.clear, lineWidth: 0)
                    ArcSegment(start: .degrees(-30), end: .degrees(90))
                        .stroke(Color(hex: 0x34A853), lineWidth: r * 0.45)
                    ArcSegment(start: .degrees(90), end: .degrees(180))
                        .stroke(Color(hex: 0xFBBC05), lineWidth: r * 0.45)
                    ArcSegment(start: .degrees(180), end: .degrees(270))
                        .stroke(Color(hex: 0xEA4335), lineWidth: r * 0.45)
                    ArcSegment(start: .degrees(270), end: .degrees(330))
                        .stroke(Color(hex: 0x4285F4), lineWidth: r * 0.45)
                    // Horizontal "bar" of the G
                    Rectangle()
                        .fill(Color(hex: 0x4285F4))
                        .frame(width: r * 0.75, height: r * 0.42)
                        .offset(x: r * 0.38, y: 0)
                }
                .padding(r * 0.12)
            }
        }
    }
}

private struct ArcSegment: Shape {
    let start: Angle
    let end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        return path
    }
}
