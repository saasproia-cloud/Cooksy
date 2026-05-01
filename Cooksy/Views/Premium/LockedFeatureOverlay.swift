import SwiftUI

/// Drop-in wrapper that blurs its content and overlays a lock + CTA when
/// the active session is non-premium. Used on the recipe nutrition card and
/// could be extended to other locked sections.
///
/// Tap anywhere on the overlay invokes `onUnlockTap` — typically presents
/// the paywall.
struct LockedFeatureOverlay<Content: View>: View {
    let title: String
    let subtitle: String
    let isLocked: Bool
    let onUnlockTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .blur(radius: isLocked ? 14 : 0)
                .allowsHitTesting(!isLocked)

            if isLocked {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(CooksyTheme.primaryAccentSoft)
                                    .frame(width: 56, height: 56)
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryAccentStrong)
                            }
                            Text(title)
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .multilineTextAlignment(.center)
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                            Button(action: {
                                OnboardingHaptics.selection()
                                onUnlockTap()
                            }) {
                                Text("Débloquer")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(CooksyTheme.accentGradient))
                            }
                            .buttonStyle(CooksyTheme.pressScale())
                        }
                        .padding(20)
                    )
                    .onTapGesture {
                        OnboardingHaptics.selection()
                        onUnlockTap()
                    }
            }
        }
    }
}
