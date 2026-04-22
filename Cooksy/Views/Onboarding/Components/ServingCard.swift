import SwiftUI

/// A square card showing a quantity label and silhouettes of people that get
/// stroked in when the card is selected.
struct ServingCard: View {
    let title: String
    let subtitle: String
    let silhouetteCount: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        Button(action: {
            OnboardingHaptics.light()
            action()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.7) : CooksyTheme.surface)
                        .frame(height: 68)

                    silhouetteRow
                }

                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .fill(isSelected ? CooksyTheme.primaryAccentSoft.opacity(0.45) : CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                    .stroke(isSelected ? CooksyTheme.ctaOrange : CooksyTheme.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(color: isSelected ? CooksyTheme.primaryAccent.opacity(0.15) : CooksyTheme.softShadow,
                    radius: isSelected ? 12 : 8, y: 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(CooksyTheme.pressScale())
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                drawProgress = 0
                withAnimation(.easeInOut(duration: 0.5)) { drawProgress = 1 }
            }
        }
        .onAppear { if isSelected { drawProgress = 1 } }
    }

    private var silhouetteRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, min(silhouetteCount, 5)), id: \.self) { index in
                SilhouetteShape()
                    .trim(from: 0, to: isSelected ? drawProgress : 0.6)
                    .stroke(
                        isSelected ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 22, height: 40)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.08),
                        value: drawProgress
                    )
            }
        }
    }
}

/// Minimal person silhouette used inside `ServingCard`.
private struct SilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let headRadius = w * 0.32
        let headCenter = CGPoint(x: w / 2, y: headRadius + h * 0.05)

        // Head
        path.addEllipse(in: CGRect(
            x: headCenter.x - headRadius,
            y: headCenter.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))

        // Body
        let bodyTop = headCenter.y + headRadius * 1.05
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.98))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.98),
            control: CGPoint(x: w / 2, y: bodyTop)
        )
        return path
    }
}
