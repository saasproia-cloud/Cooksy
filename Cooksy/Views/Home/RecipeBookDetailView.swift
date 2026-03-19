import SwiftUI

struct RecipeBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeStore: RecipeStore

    let bookID: RecipeBook.ID

    @State private var showsQuickImportSheet = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if let book = currentBook {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 34)

                        Text(book.title)
                            .font(.system(size: 38, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .padding(.horizontal, 22)

                        Text(recipeCountLabel(for: book.recipeCount))
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 22)
                            .padding(.top, 6)

                        if recipes.isEmpty {
                            emptyState
                        } else {
                            populatedState
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .recipeImportFlow(isPresented: $showsQuickImportSheet, preferredBookID: bookID)
    }

    private var currentBook: RecipeBook? {
        recipeStore.books.first(where: { $0.id == bookID })
    }

    private var recipes: [Recipe] {
        guard let currentBook else { return [] }
        return recipeStore.recipes(in: currentBook)
    }

    private var topBar: some View {
        HStack {
            circleButton(systemImage: "chevron.left", action: { dismiss() })

            Spacer()

            HStack(spacing: 8) {
                capsuleIconButton(systemImage: "person.badge.plus")
                capsuleIconButton(systemImage: "ellipsis")
            }
            .padding(.horizontal, 8)
            .frame(height: 58)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Button(action: { showsQuickImportSheet = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))

                    Text("Ajouter votre première recette")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.ctaOrange)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 54)

            EmptyRecipeBookIllustration()
                .padding(.top, 92)

            Text("Aucune recette enregistrée")
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.88))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 34)
        }
    }

    private var populatedState: some View {
        LazyVStack(spacing: 16) {
            Button(action: { showsQuickImportSheet = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))

                    Text(recipes.isEmpty ? "Ajouter votre première recette" : "Ajouter une recette")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.ctaOrange)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            ForEach(recipes) { recipe in
                NavigationLink {
                    RecipeDetailView(store: recipeStore, recipeID: recipe.id)
                } label: {
                    RecipeBookRecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 46)
    }

    private func recipeCountLabel(for count: Int) -> String {
        let suffix = count == 1 ? "" : "s"
        return "\(count) Recette\(suffix)"
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
                )
        }
        .buttonStyle(.plain)
    }

    private func capsuleIconButton(systemImage: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyRecipeBookIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x5F88D6))
                .frame(width: 196, height: 196)

            Path { path in
                path.move(to: CGPoint(x: 30, y: 122))
                path.addCurve(
                    to: CGPoint(x: 168, y: 58),
                    control1: CGPoint(x: 78, y: 70),
                    control2: CGPoint(x: 118, y: 18)
                )
                path.addCurve(
                    to: CGPoint(x: 92, y: 186),
                    control1: CGPoint(x: 192, y: 122),
                    control2: CGPoint(x: 138, y: 176)
                )
            }
            .stroke(Color(hex: 0xA7CD57), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
            .frame(width: 196, height: 196)

            HStack(spacing: 190) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0xFFD74D))
                    .frame(width: 22, height: 108)
                    .rotationEffect(.degrees(22))
                    .overlay(alignment: .top) {
                        Ellipse()
                            .fill(Color(hex: 0xFFD74D))
                            .frame(width: 34, height: 52)
                            .offset(y: -30)
                    }

                ForkShape()
                    .stroke(Color(hex: 0xF2A86B), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 38, height: 112)
                    .rotationEffect(.degrees(-18))
            }
        }
        .frame(width: 280, height: 240)
    }
}

private struct ForkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX

        path.move(to: CGPoint(x: centerX, y: rect.maxY))
        path.addLine(to: CGPoint(x: centerX + 2, y: rect.height * 0.4))

        let tineYStart = rect.height * 0.02
        let tineYEnd = rect.height * 0.28
        let spacing: CGFloat = 8

        for offset in [-1.5, -0.5, 0.5, 1.5] {
            let tineX = centerX + CGFloat(offset) * spacing
            path.move(to: CGPoint(x: tineX, y: tineYEnd))
            path.addLine(to: CGPoint(x: tineX, y: tineYStart))
        }

        return path
    }
}

private struct RecipeBookRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeRowHero(recipe: recipe)

            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)

                Text("\(recipe.ingredients.count) ingrédients")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
        )
    }
}

private struct RecipeRowHero: View {
    let recipe: Recipe

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(gradient)
                .frame(width: 88, height: 88)

            Image(systemName: "fork.knife")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private var gradient: LinearGradient {
        switch recipe.heroStyle {
        case .warmCocoa:
            return LinearGradient(
                colors: [Color(hex: 0x7B4B33), Color(hex: 0xD59B6D)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .citrus:
            return LinearGradient(
                colors: [Color(hex: 0xFFB74D), Color(hex: 0xFFD95B)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .ocean:
            return LinearGradient(
                colors: [CooksyTheme.brandBlueDark, CooksyTheme.brandBlue],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .meadow:
            return LinearGradient(
                colors: [Color(hex: 0x74A962), Color(hex: 0xA9D467)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }
}
