import SwiftUI

/// Pushed from Profile → "Recettes tendance".
///
/// Curated monthly trending feed in the Cooksy import-grid style: a
/// decorative top banner, a serif "🔥 Recettes tendance" header, then a
/// two-column grid of ~20 recipes shown like real social imports
/// (importation count, source domain, hero artwork). Tapping a card
/// opens the existing `TrendingRecipePreviewView` so the user can save
/// it to their library exactly like a daily trending pick.
struct TrendingRecipesView: View {
    let store: RecipeStore

    private var entries: [MonthlyTrendingEntry] {
        MonthlyTrendingFeed.current()
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    bannerHeader

                    headerBlock
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(entries) { entry in
                            NavigationLink {
                                TrendingRecipePreviewView(
                                    scenario: entry.scenario,
                                    store: store
                                )
                            } label: {
                                TrendingImportCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Recettes tendance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Banner

    private var bannerHeader: some View {
        ZStack {
            // Soft green base with playful peach + blue blobs, evoking a
            // colourful editorial cover (matches the import-feed reference).
            LinearGradient(
                colors: [Color(hex: 0xC8E0A6), Color(hex: 0xB7D88C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Peach blob top-left
            Circle()
                .fill(Color(hex: 0xF7B79E))
                .frame(width: 220, height: 220)
                .blur(radius: 6)
                .offset(x: -90, y: -60)

            // Soft cream blob top-right
            Capsule()
                .fill(Color(hex: 0xFFF1D9))
                .frame(width: 180, height: 70)
                .rotationEffect(.degrees(-18))
                .offset(x: 110, y: -40)

            // Blue dots cluster
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0x4A6CF7)).frame(width: 22, height: 22)
                Circle().fill(Color(hex: 0x4A6CF7)).frame(width: 22, height: 22)
                Circle().fill(Color(hex: 0x4A6CF7)).frame(width: 22, height: 22)
            }
            .offset(x: 10, y: 10)

            // Cream comma / squiggle on the right
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xFFF1D9))
                .frame(width: 90, height: 36)
                .rotationEffect(.degrees(28))
                .offset(x: 130, y: 30)
        }
        .frame(height: 160)
        .clipped()
    }

    // MARK: - Header block

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🔥")
                .font(.system(size: 24))

            Text("Recettes tendance")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Text("\(entries.count) recettes")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card

private struct TrendingImportCard: View {
    let entry: MonthlyTrendingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .aspectRatio(0.78, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.scenario.title) \(entry.scenario.hero.emoji)")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }

    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            // Layered gradient with halo + emoji — same visual treatment as
            // the new home trending cards so the app feels coherent.
            LinearGradient(
                colors: [
                    Color(hex: entry.scenario.hero.topColorHex),
                    Color(hex: entry.scenario.hero.bottomColorHex)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.45),
                    Color.white.opacity(0.10),
                    .clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 130
            )
            .blendMode(.screen)

            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 140, height: 140)
                .blur(radius: 18)
                .offset(x: 60, y: -60)

            Text(entry.scenario.hero.emoji)
                .font(.system(size: 84))
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)

            // Top-left: importations pill
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .heavy))
                Text("\(entry.importationsLabel) importations")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color(hex: 0xC9471D))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: 0xFFE5D6))
            )
            .padding(10)

            // Bottom-left: source domain pill
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: 0xE5A93A))
                    Text(entry.sourceDomain)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.42))
                )
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Monthly feed model

struct MonthlyTrendingEntry: Identifiable {
    let id: String
    let scenario: DemoRecipeScenario
    let importations: Int
    let sourceDomain: String

    var importationsLabel: String {
        if importations >= 1000 {
            let value = Double(importations) / 1000.0
            // Round to 1 decimal for sub-10K, drop the .0 if exact.
            if importations < 10_000 {
                let rounded = (value * 10).rounded() / 10
                if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(Int(rounded))K"
                }
                return String(format: "%.1fK", rounded)
            }
            return "\(Int(value.rounded()))K"
        }
        return "\(importations)"
    }
}

/// Builds a stable, monthly-rotating feed of ~20 trending entries by
/// cycling through the demo catalog with a per-month seed and assigning
/// realistic-looking import counts that decrease with rank.
enum MonthlyTrendingFeed {
    /// Precomputed import counts so #1 looks dominant and the long tail
    /// still feels lived-in. Deliberately not perfectly linear — feels
    /// more like a real curated chart.
    private static let importCounts: [Int] = [
        2_900, 2_700, 2_500, 2_400, 2_200,
        2_000, 1_900, 1_800, 1_700, 1_500,
        1_400, 1_300, 1_200, 1_100, 1_000,
        980, 920, 870, 820, 760
    ]

    private static let sourceDomains: [String] = [
        "instagram.com",
        "instagram.com",
        "tiktok.com",
        "instagram.com",
        "tiktok.com",
        "instagram.com",
        "youtube.com",
        "instagram.com",
        "tiktok.com",
        "instagram.com"
    ]

    static func current(referenceDate: Date = .now) -> [MonthlyTrendingEntry] {
        let scenarios = DemoRecipeCatalog.scenarios
        guard !scenarios.isEmpty else { return [] }

        // Month-stable seed so the order shifts month over month but stays
        // identical within the month.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        let seed = (comps.year ?? 2025) * 100 + (comps.month ?? 1)

        let offset = seed % scenarios.count
        let rotated = Array(scenarios[offset...]) + Array(scenarios[..<offset])

        // 20 entries by cycling through the catalog twice, with a small
        // shift on the second pass so duplicates aren't adjacent.
        let firstPass = rotated
        let secondShift = max(1, scenarios.count / 2)
        let secondPass = Array(rotated[secondShift...]) + Array(rotated[..<secondShift])
        let combined = firstPass + secondPass

        return combined.prefix(importCounts.count).enumerated().map { index, scenario in
            let countSeed = (seed + index) // gentle per-month jitter
            let baseCount = importCounts[index]
            // Small ±5% jitter so counts feel alive across months.
            let jitter = (countSeed % 10) - 5
            let count = max(120, baseCount + jitter * 4)

            let domainIndex = (countSeed + scenario.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % sourceDomains.count
            let domain = sourceDomains[domainIndex]

            return MonthlyTrendingEntry(
                id: "monthly-\(seed)-\(index)-\(scenario.id)",
                scenario: scenario,
                importations: count,
                sourceDomain: domain
            )
        }
    }
}
