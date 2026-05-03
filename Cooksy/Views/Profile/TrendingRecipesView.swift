import SwiftUI

/// Pushed from Profile → "Recettes tendance".
/// Lists all demo recipe scenarios as tappable cards. Each card pushes the
/// existing `TrendingRecipePreviewView` so the user can browse + save them
/// the same way they would from the home top trending carousel.
struct TrendingRecipesView: View {
    let store: RecipeStore

    private var scenarios: [DemoRecipeScenario] {
        DemoRecipeCatalog.scenarios
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                        NavigationLink {
                            TrendingRecipePreviewView(scenario: scenario, store: store)
                        } label: {
                            TrendingScenarioCard(scenario: scenario, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Recettes tendance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 56, height: 56)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sélection du jour")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("Les recettes les plus cuisinées par la communauté Cooksy en ce moment.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
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

private struct TrendingScenarioCard: View {
    let scenario: DemoRecipeScenario
    let rank: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: scenario.hero.topColorHex),
                        Color(hex: scenario.hero.bottomColorHex)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: 72, height: 72)

                Text(scenario.hero.emoji)
                    .font(.system(size: 32))

                // Rank badge top-left
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                    Text("\(rank)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .offset(x: -24, y: -24)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label("\(scenario.prepMinutes + scenario.cookMinutes) min", systemImage: "clock")
                        .labelStyle(InlineMetaLabelStyle())

                    Label("\(scenario.servings) portions", systemImage: "person.2")
                        .labelStyle(InlineMetaLabelStyle())
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
        }
        .padding(12)
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

private struct InlineMetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}
