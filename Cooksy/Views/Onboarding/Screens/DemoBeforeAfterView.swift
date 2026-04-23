import SwiftUI

/// A2 — Demonstrates the core magic with an explicit flow:
/// open a TikTok → tap the Share button → pick Cooksy in the iOS share sheet →
/// structured recipe appears.
///
/// The whole mini-movie lives in a fixed-size "device frame" and plays through
/// 5 numbered steps driven by a Task + Task.sleep. No TimelineView, no Canvas,
/// no particles — the only thing that moves is a finger cursor and a few
/// opacity/offset transitions.
struct DemoBeforeAfterView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var step: Int = 0
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        OnboardingChrome(
            title: "De la vidéo\nà la recette.",
            subtitle: "Ouvre un TikTok, partage vers Cooksy, cuisine. C'est tout.",
            ctaTitle: "Montre-moi ce que Cooksy peut faire",
            canAdvance: true,
            progress: nil,
            showsBack: true,
            showsSkip: false,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 18) {
                DemoStage(step: step)
                    .frame(height: 420)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(CooksyTheme.elevatedSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(CooksyTheme.stroke, lineWidth: 1)
                    )
                    .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)

                StepCaption(step: step)

                Button(action: replay) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Rejouer")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.primaryAccentSoft.opacity(0.6))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.ctaOrange.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(CooksyTheme.pressScale())
            }
            .padding(.top, 2)
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                animationTask?.cancel()
            }
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        step = 0
        animationTask = Task { @MainActor in
            // Step 0 → 1 : curseur apparaît + scroll du TikTok
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withStep(1)

            // Step 1 → 2 : tap share
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            OnboardingHaptics.selection()
            withStep(2)

            // Step 2 → 3 : tap Cooksy dans share sheet
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            OnboardingHaptics.light()
            withStep(3)

            // Step 3 → 4 : loader + recette
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            OnboardingHaptics.success()
            withStep(4)
        }
    }

    @MainActor
    private func withStep(_ newStep: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            step = newStep
        }
    }

    private func replay() {
        OnboardingHaptics.light()
        startAnimation()
    }
}

// MARK: - Step caption (the 1-liner explaining what's on screen)

private struct StepCaption: View {
    let step: Int

    var body: some View {
        Text(caption)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(CooksyTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .id(caption)
            .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var caption: String {
        switch step {
        case 0: return "Tu regardes un TikTok cuisine qui te plaît."
        case 1: return "Tu tapes sur le bouton Partager."
        case 2: return "Tu choisis Cooksy dans la feuille de partage."
        case 3: return "Cooksy extrait la recette en quelques secondes."
        default: return "Recette propre, structurée, prête à cuisiner."
        }
    }
}

// MARK: - Stage container — switches between the 3 "scenes"

private struct DemoStage: View {
    let step: Int

    var body: some View {
        ZStack {
            // Scene A : TikTok + optional share sheet + finger
            if step <= 2 {
                ScenePhone(step: step)
                    .transition(.opacity)
            }

            // Scene B : loader
            if step == 3 {
                SceneLoading()
                    .transition(.opacity)
            }

            // Scene C : recipe
            if step >= 4 {
                SceneRecipe()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

// MARK: - Scene A — TikTok post with finger cursor + share sheet

private struct ScenePhone: View {
    let step: Int  // 0 = idle, 1 = share tapped, 2 = cooksy picked

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                MockTikTokPost(scrolled: step >= 1)

                // Finger cursor: moves from middle → share icon → cooksy icon
                FingerCursor(
                    position: cursorPosition(in: size),
                    tapped: step == 1 || step == 2
                )
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: step)

                // Share sheet slides up when step >= 2
                VStack(spacing: 0) {
                    Spacer()
                    MockShareSheet(highlightCooksy: step == 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .opacity(step >= 2 ? 1 : 0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: step)
            }
        }
    }

    /// Idle → middle-right; after step 1 → share icon; after step 2 → cooksy in sheet.
    private func cursorPosition(in size: CGSize) -> CGPoint {
        switch step {
        case 0:
            return CGPoint(x: size.width * 0.55, y: size.height * 0.55)
        case 1:
            // Aim at the share button on the TikTok post (right column, ~70% down)
            return CGPoint(x: size.width * 0.85, y: size.height * 0.72)
        default:
            // Inside the share sheet (bottom quarter, centered on Cooksy icon — index 1 of 4)
            let sheetY = size.height * 0.80
            let cooksyX = size.width * 0.40
            return CGPoint(x: cooksyX, y: sheetY)
        }
    }
}

// MARK: - Mock TikTok post

private struct MockTikTokPost: View {
    var scrolled: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xF29434), Color(hex: 0xC8481E)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // "Plate" silhouette (cheap, no blur)
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 170, height: 170)
                .offset(y: scrolled ? -40 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: scrolled)

            // Username + caption, bottom-left
            VStack(alignment: .leading) {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@pastaqueen")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                        Text("Le VRAI pesto maison 🌿")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    // Right-column action icons (like/comment/share)
                    VStack(spacing: 14) {
                        iconCol(systemName: "heart.fill", label: "12k")
                        iconCol(systemName: "bubble.right.fill", label: "342")
                        iconCol(systemName: "square.and.arrow.up.fill", label: "Partage")
                    }
                }
                .padding(14)
            }
        }
    }

    private func iconCol(systemName: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Mock iOS share sheet

private struct MockShareSheet: View {
    var highlightCooksy: Bool

    var body: some View {
        VStack(spacing: 14) {
            // Grab handle
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Partager via…")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)

            HStack(spacing: 16) {
                appIcon(symbol: "envelope.fill", label: "Mail", tint: Color(hex: 0x4A90E2))
                cooksyAppIcon(highlighted: highlightCooksy)
                appIcon(symbol: "message.fill", label: "Messages", tint: Color(hex: 0x4BE0A0))
                appIcon(symbol: "bookmark.fill", label: "Notes", tint: Color(hex: 0xF6C849))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .padding(10)
    }

    private func appIcon(symbol: String, label: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)
        }
        .frame(width: 66)
    }

    private func cooksyAppIcon(highlighted: Bool) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CooksyTheme.accentGradient)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CooksyTheme.ctaOrangeDark, lineWidth: highlighted ? 3 : 0)
                )
                .scaleEffect(highlighted ? 1.10 : 1.0)
                .shadow(
                    color: CooksyTheme.primaryAccent.opacity(highlighted ? 0.55 : 0.25),
                    radius: highlighted ? 14 : 6,
                    y: 4
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: highlighted)
            Text("Cooksy")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .lineLimit(1)
        }
        .frame(width: 66)
    }
}

// MARK: - Finger cursor

private struct FingerCursor: View {
    let position: CGPoint
    let tapped: Bool

    var body: some View {
        ZStack {
            // Tap ripple
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: tapped ? 54 : 24, height: tapped ? 54 : 24)
                .opacity(tapped ? 0 : 0.9)
                .animation(.easeOut(duration: 0.45), value: tapped)

            // Hand
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .scaleEffect(tapped ? 0.88 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: tapped)
        }
        .position(position)
    }
}

// MARK: - Scene B — Loading state between share and recipe

private struct SceneLoading: View {
    @State private var spin: Bool = false

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(CooksyTheme.stroke, lineWidth: 4)
                        .frame(width: 68, height: 68)

                    Circle()
                        .trim(from: 0, to: 0.32)
                        .stroke(
                            CooksyTheme.accentGradient,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(
                            .linear(duration: 0.9).repeatForever(autoreverses: false),
                            value: spin
                        )
                }
                .onAppear { spin = true }

                Text("Extraction en cours…")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("15s ⚡")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.primaryAccentSoft.opacity(0.8))
                )
            }
        }
    }
}

// MARK: - Scene C — Final structured recipe card

private struct SceneRecipe: View {
    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.accentGradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pasta au pesto maison")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                        Text("2 portions · 15 min")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(CooksyTheme.dividerSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("INGRÉDIENTS")
                    ingredientRow("200 g", "pâtes", index: 0)
                    ingredientRow("1 botte", "basilic", index: 1)
                    ingredientRow("40 g", "parmesan", index: 2)
                    ingredientRow("2 c. à s.", "huile d'olive", index: 3)
                }

                Rectangle()
                    .fill(CooksyTheme.dividerSubtle)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("ÉTAPES")
                    stepRow("1", "Mixer basilic, huile, parmesan.", index: 4)
                    stepRow("2", "Cuire les pâtes al dente.", index: 5)
                    stepRow("3", "Mélanger et servir.", index: 6)
                }
            }
            .padding(14)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Prêt à cuisiner ✨")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CooksyTheme.ctaOrangeDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.primaryAccentSoft.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CooksyTheme.ctaOrange.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.8), value: appeared)
        }
        .padding(6)
        .onAppear { appeared = true }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(CooksyTheme.secondaryText)
    }

    private func ingredientRow(_ qty: String, _ name: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Text(qty)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .frame(width: 64, alignment: .leading)
            Text(name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -6)
        .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.08 * Double(index)), value: appeared)
    }

    private func stepRow(_ number: String, _ text: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft)
                    .frame(width: 20, height: 20)
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.08 * Double(index)), value: appeared)
    }
}
