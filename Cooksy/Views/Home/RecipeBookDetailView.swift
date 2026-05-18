import SwiftUI

struct RecipeBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeStore: RecipeStore

    let bookID: RecipeBook.ID

    @State private var showsQuickImportSheet = false

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            if let book = currentBook {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        topBar
                        bookOverview(book)

                        if recipes.isEmpty {
                            emptyState
                        } else {
                            populatedState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
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
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
                    .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
            )
        }
    }

    private func bookOverview(_ book: RecipeBook) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(book.kind == .uncategorized ? "COLLECTION PRINCIPALE" : "LIVRE DE RECETTES")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(CooksyTheme.ctaOrangeDark)

            Text(book.title)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(recipeCountLabel(for: book.recipeCount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.surface)
                    )

                Spacer(minLength: 0)

                Button(action: { showsQuickImportSheet = true }) {
                    Label("Ajouter", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.shadow, radius: 18, y: 10)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Button(action: { showsQuickImportSheet = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))

                    Text("Ajouter votre première recette")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.accentGradient)
                )
            }
            .buttonStyle(.plain)

            EmptyRecipeBookIllustration()
                .padding(.top, 60)

            Text("Aucune recette enregistrée")
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText.opacity(0.88))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var populatedState: some View {
        LazyVStack(spacing: 16) {
            Button(action: { showsQuickImportSheet = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))

                    Text(recipes.isEmpty ? "Ajouter votre première recette" : "Ajouter une recette")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.blush.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.ctaOrange.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            ForEach(recipes) { recipe in
                NavigationLink {
                    RecipeDetailView(store: recipeStore, recipeID: recipe.id)
                } label: {
                    RecipeBookRecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recipeCountLabel(for count: Int) -> String {
        let suffix = count == 1 ? "" : "s"
        return "\(count) Recette\(suffix)"
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(CooksyTheme.elevatedSurface)
                        .shadow(color: CooksyTheme.softShadow, radius: 14, y: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private func capsuleIconButton(systemImage: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CooksyTheme.primaryText)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyRecipeBookIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(CooksyTheme.primaryAccentSoft)
                .frame(width: 196, height: 196)

            Circle()
                .fill(CooksyTheme.secondaryAccentSoft.opacity(0.96))
                .frame(width: 138, height: 138)
                .offset(x: 24, y: 10)

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
            .stroke(
                CooksyTheme.secondaryAccent,
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 196, height: 196)

            HStack(spacing: 190) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CooksyTheme.sparkleYellow)
                    .frame(width: 22, height: 108)
                    .rotationEffect(.degrees(22))
                    .overlay(alignment: .top) {
                        Ellipse()
                            .fill(CooksyTheme.sparkleYellow)
                            .frame(width: 34, height: 52)
                            .offset(y: -30)
                    }

                ForkShape()
                    .stroke(
                        CooksyTheme.primaryAccent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
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
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("\(recipe.ingredients.count) ingrédients")
                    if let totalMinutes = totalMinutes(for: recipe) {
                        Text("• \(totalMinutes) min")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private func totalMinutes(for recipe: Recipe) -> Int? {
        if let prep = recipe.details.prepTimeMinutes, let cook = recipe.details.cookTimeMinutes {
            return prep + cook
        }

        return recipe.details.prepTimeMinutes ?? recipe.details.cookTimeMinutes
    }
}

private struct RecipeRowHero: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        // Constrain + clip BEFORE bubbling up so overflow
                        // from `.scaledToFill()` doesn't leak past the
                        // rounded frame (imported recipes have large
                        // intrinsic sizes and would otherwise overlap
                        // neighbouring rows).
                        .frame(width: 72, height: 72)
                        .clipped()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                        default:
                            fallbackTile
                        }
                    }
                    .frame(width: 72, height: 72)
                }
            } else {
                fallbackTile
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
    }

    private var fallbackTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(fallbackGradient)

            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private var fallbackGradient: LinearGradient {
        CooksyTheme.recipeGradient(for: recipe.heroStyle)
    }
}
