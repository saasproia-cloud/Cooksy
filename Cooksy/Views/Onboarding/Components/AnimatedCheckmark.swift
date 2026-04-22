import SwiftUI

/// Checkmark glyph that draws itself with stroke trimming.
/// `progress` in 0…1 controls how much of the mark is visible — use
/// `.animation(.spring(...), value: progress)` on the parent to animate.
struct AnimatedCheckmark: Shape {
    var progress: CGFloat = 1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0.18 * w, y: 0.54 * h))
        path.addLine(to: CGPoint(x: 0.42 * w, y: 0.78 * h))
        path.addLine(to: CGPoint(x: 0.84 * w, y: 0.26 * h))
        return path.trimmedPath(from: 0, to: max(0, min(1, progress)))
    }
}

/// Circular fill + animated checkmark — the selection indicator used
/// across onboarding (cards, pills, plan cards).
struct CheckmarkBadge: View {
    var isOn: Bool
    var size: CGFloat = 24
    var tint: Color = CooksyTheme.ctaOrangeDark

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? tint : Color.white.opacity(0.001))
                .overlay(
                    Circle()
                        .stroke(isOn ? Color.clear : CooksyTheme.stroke, lineWidth: 1.5)
                )

            AnimatedCheckmark(progress: isOn ? progress : 0)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.7, height: size * 0.7)
        }
        .frame(width: size, height: size)
        .onChange(of: isOn) { _, newValue in
            if newValue {
                progress = 0
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    progress = 1
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    progress = 0
                }
            }
        }
        .onAppear {
            if isOn { progress = 1 }
        }
    }
}
