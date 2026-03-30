import SwiftUI

struct CreateRecipeBookCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NOUVEAU")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)

                    Spacer(minLength: 0)

                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrange)

                    Text("Créer un livre")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(CooksyTheme.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            CooksyTheme.ctaOrange,
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                )
            }
        }
        .buttonStyle(.plain)
    }
}

struct RecipeBookCard: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                BookPreviewMosaic(book: book, recipes: recipes)
                    .frame(height: 132)

                Text(book.kind == .uncategorized ? "ESSENTIEL" : "LIVRE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(2)

                Text(recipeCountLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(CooksyTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 8)
    }

    private var recipeCountLabel: String {
        let suffix = book.recipeCount == 1 ? "" : "s"
        return "\(book.recipeCount) recette\(suffix)"
    }
}

private struct BookPreviewMosaic: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 3) {
            previewTile(for: tileContent(at: 0))
                .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                previewTile(for: tileContent(at: 1))
                previewTile(for: tileContent(at: 2))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CooksyTheme.warmCard.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CooksyTheme.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: CooksyTheme.softShadow, radius: 12, y: 8)
    }

    private func tileContent(at index: Int) -> Recipe? {
        switch recipes.count {
        case 0:
            return nil
        case 1:
            return index == 2 ? recipes[0] : nil
        case 2:
            if index == 0 { return recipes[0] }
            if index == 2 { return recipes[1] }
            return nil
        default:
            return recipes[safe: index]
        }
    }

    @ViewBuilder
    private func previewTile(for recipe: Recipe?) -> some View {
        if let recipe {
            RecipePreviewTile(recipe: recipe)
        } else {
            placeholderTile
        }
    }

    private var placeholderTile: some View {
        Rectangle()
            .fill(CooksyTheme.surface)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CooksyTheme.secondaryText.opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecipePreviewTile: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let heroImageURL = recipe.heroImageURL {
                if heroImageURL.isFileURL, let uiImage = UIImage(contentsOfFile: heroImageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: heroImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackTile
                        }
                    }
                }
            } else {
                fallbackTile
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallbackTile: some View {
        Rectangle()
            .fill(fallbackGradient)
            .overlay {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
            }
    }

    private var fallbackGradient: LinearGradient {
        CooksyTheme.recipeGradient(for: recipe.heroStyle)
    }

    private var fallbackIcon: String {
        switch recipe.heroStyle {
        case .warmCocoa:
            return "fork.knife"
        case .citrus:
            return "sun.max.fill"
        case .ocean:
            return "drop.fill"
        case .meadow:
            return "leaf.fill"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
