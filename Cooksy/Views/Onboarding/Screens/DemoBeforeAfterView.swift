import SwiftUI

/// A2 — Demonstrates the core magic: a video link "becomes" a structured recipe.
/// Left side: a faux video link chip. Right side: an empty card that progressively
/// fills with title, ingredients, steps and a final "15s" completion badge.
struct DemoBeforeAfterView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var stage: DemoStage = .linkShown
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        OnboardingChrome(
            title: "Voilà ce qui se passe\nquand tu colles un lien.",
            subtitle: "Regarde Cooksy transformer une vidéo en recette claire, propre, cuisinable.",
            ctaTitle: "Montre-moi ce que Cooksy peut faire",
            canAdvance: true,
            progress: nil,
            showsBack: true,
            showsSkip: false,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 20) {
                DemoLinkChip()
                    .opacity(stage.rawValue >= DemoStage.linkShown.rawValue ? 1 : 0)

                DemoArrowIndicator(isActive: stage.rawValue >= DemoStage.converting.rawValue)
                    .frame(height: 24)

                DemoRecipeCard(stage: stage)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
            .onAppear { startLoop() }
            .onDisappear { stopLoop() }
        }
    }

    /// Cancels any previous run then kicks off an infinite loop:
    /// link → converting → title → ingredients → steps → complete → pause → reset → repeat.
    private func startLoop() {
        stopLoop()
        animationTask = Task { @MainActor in
            // Reset immediately in case we re-appeared mid-stage.
            stage = .linkShown
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                withStage(.converting)

                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                withStage(.showingTitle)

                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                OnboardingHaptics.selection()
                withStage(.showingIngredients)

                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                OnboardingHaptics.light()
                withStage(.showingSteps)

                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                OnboardingHaptics.success()
                withStage(.complete)

                // Hold on the finished recipe for a moment before resetting.
                try? await Task.sleep(for: .milliseconds(2000))
                guard !Task.isCancelled else { return }
                withStage(.linkShown)

                // Short breath before the next loop so the reset reads cleanly.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopLoop() {
        animationTask?.cancel()
        animationTask = nil
    }

    @MainActor
    private func withStage(_ newStage: DemoStage) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            stage = newStage
        }
    }
}

// MARK: - Stages

enum DemoStage: Int {
    case linkShown = 0
    case converting
    case showingTitle
    case showingIngredients
    case showingSteps
    case complete
}

// MARK: - Link chip

private struct DemoLinkChip: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryText)
                    .frame(width: 34, height: 34)
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Reel · tiktok.com")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("pasta au pesto · 47s")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Arrow indicator

private struct DemoArrowIndicator: View {
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(isActive ? CooksyTheme.accentGradient : LinearGradient(colors: [CooksyTheme.stroke, CooksyTheme.stroke], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isActive ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: isActive
                    )
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? CooksyTheme.ctaOrangeDark : CooksyTheme.secondaryText.opacity(0.5))
        }
    }
}

// MARK: - Recipe card

private struct DemoRecipeCard: View {
    let stage: DemoStage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            HStack(alignment: .center, spacing: 10) {
                if stage.rawValue >= DemoStage.showingTitle.rawValue {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CooksyTheme.accentGradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pasta au pesto maison")
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                        Text("2 portions · 15 min")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    skeletonLine(width: 180, height: 16)
                    Spacer()
                }
                Spacer(minLength: 0)
            }

            divider

            // Ingredients
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("INGRÉDIENTS", visible: stage.rawValue >= DemoStage.showingIngredients.rawValue)
                ingredientRow("200 g", "pâtes", visible: stage.rawValue >= DemoStage.showingIngredients.rawValue, delay: 0)
                ingredientRow("1 botte", "basilic", visible: stage.rawValue >= DemoStage.showingIngredients.rawValue, delay: 0.12)
                ingredientRow("40 g", "parmesan", visible: stage.rawValue >= DemoStage.showingIngredients.rawValue, delay: 0.24)
                ingredientRow("2 c. à s.", "huile d'olive", visible: stage.rawValue >= DemoStage.showingIngredients.rawValue, delay: 0.36)
            }

            divider

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("ÉTAPES", visible: stage.rawValue >= DemoStage.showingSteps.rawValue)
                stepRow("1", "Mixer basilic, huile et parmesan pour obtenir un pesto lisse.", visible: stage.rawValue >= DemoStage.showingSteps.rawValue, delay: 0)
                stepRow("2", "Cuire les pâtes al dente dans une eau bien salée.", visible: stage.rawValue >= DemoStage.showingSteps.rawValue, delay: 0.12)
                stepRow("3", "Mélanger, ajuster avec un peu d'eau de cuisson, servir.", visible: stage.rawValue >= DemoStage.showingSteps.rawValue, delay: 0.24)
            }

            if stage == .complete {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Recette prête en 15 secondes")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(CooksyTheme.primaryAccentSoft.opacity(0.85))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(CooksyTheme.ctaOrange.opacity(0.4), lineWidth: 1)
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CooksyTheme.cardRadius, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(CooksyTheme.dividerSubtle)
            .frame(height: 1)
    }

    private func sectionHeader(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(CooksyTheme.secondaryText)
            .opacity(visible ? 1 : 0.25)
    }

    private func ingredientRow(_ qty: String, _ name: String, visible: Bool, delay: Double) -> some View {
        HStack(spacing: 10) {
            Text(qty)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .frame(width: 68, alignment: .leading)
            Text(name)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
            Spacer(minLength: 0)
        }
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : -8)
        .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(delay), value: visible)
    }

    private func stepRow(_ number: String, _ text: String, visible: Bool, delay: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.primaryAccentSoft)
                    .frame(width: 22, height: 22)
                Text(number)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(delay), value: visible)
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(CooksyTheme.stroke.opacity(0.55))
            .frame(width: width, height: height)
    }
}
