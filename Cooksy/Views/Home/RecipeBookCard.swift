import SwiftUI

struct CreateRecipeBookCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 156)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 38, weight: .regular))
                            .foregroundStyle(CooksyTheme.ctaOrange)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(CooksyTheme.ctaOrange, lineWidth: 2.5)
                    )

                Text("Nouveau livre\nde recettes")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.leading)
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
            BookPreviewMosaic(book: book, recipes: recipes)
                .frame(height: 156)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .lineLimit(2)

                    Text(recipeCountLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
    }

    private var recipeCountLabel: String {
        let suffix = book.recipeCount == 1 ? "" : "s"
        return "\(book.recipeCount) Recette\(suffix)"
    }
}

private struct BookPreviewMosaic: View {
    let book: RecipeBook
    let recipes: [Recipe]

    var body: some View {
        HStack(spacing: 2) {
            previewTile(for: tileContent(at: 0))
                .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                previewTile(for: tileContent(at: 1))
                previewTile(for: tileContent(at: 2))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0xF1EBE1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: 0xD9CEBF), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .fill(Color(hex: 0xEFE8DD))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0xB8AEA1))
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
        switch recipe.heroStyle {
        case .warmCocoa:
            return LinearGradient(colors: [Color(hex: 0x8C5637), Color(hex: 0xD9A067)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .citrus:
            return LinearGradient(colors: [Color(hex: 0xF1A34A), Color(hex: 0xF7D96E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:
            return LinearGradient(colors: [Color(hex: 0x5E89D8), Color(hex: 0x99BCF2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .meadow:
            return LinearGradient(colors: [Color(hex: 0x6D8C4D), Color(hex: 0xA3C279)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
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
