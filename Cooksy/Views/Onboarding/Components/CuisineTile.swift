import SwiftUI

/// Grid tile for cuisine selection with a 3D flip animation on tap.
/// Front: gradient + icon + label. Back: checkmark badge on selected state.
struct CuisineTile: View {
    let title: String
    let systemImage: String
    let gradient: LinearGradient
    let isSelected: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: {
            OnboardingHaptics.selection()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                rotation += 180
            }
            action()
        }) {
            ZStack {
                // Front face
                tileFace
                    .opacity(rotation.truncatingRemainder(dividingBy: 360) < 90 || rotation.truncatingRemainder(dividingBy: 360) >= 270 ? 1 : 0)

                // Back face (mirrored so text reads normally after flip completion)
                backFace
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(rotation.truncatingRemainder(dividingBy: 360) >= 90 && rotation.truncatingRemainder(dividingBy: 360) < 270 ? 1 : 0)
            }
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: rotation)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isSelected {
                rotation = 360
            }
        }
    }

    private var tileFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(gradient)

            // Subtle dimming scrim at the bottom for label legibility
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.32)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
                Spacer()
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? Color.white : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? CooksyTheme.primaryAccent.opacity(0.35) : Color.black.opacity(0.12),
                radius: isSelected ? 14 : 8, y: 6)
    }

    private var backFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CooksyTheme.accentGradient)

            VStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
        )
        .shadow(color: CooksyTheme.primaryAccent.opacity(0.45), radius: 14, y: 6)
    }
}
