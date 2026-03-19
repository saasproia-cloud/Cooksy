import SwiftUI
import UIKit

struct ShoppingListView: View {
    @StateObject private var viewModel: ShoppingListViewModel

    @FocusState private var isComposerFocused: Bool
    @State private var composerText = ""
    @State private var showsComposer = false
    @State private var selectedItem: ShoppingItem?
    @State private var showsShareSheet = false

    init(store: RecipeStore) {
        _viewModel = StateObject(wrappedValue: ShoppingListViewModel(store: store))
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.7))

                countBar

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.65))

                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsComposer {
                composerBar
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            ShoppingItemEditorView(
                item: item,
                onDelete: {
                    viewModel.delete($0)
                },
                onUpdate: { item, article, quantity, category in
                    viewModel.update(item, article: article, quantity: quantity, category: category)
                }
            )
        }
        .sheet(isPresented: $showsShareSheet) {
            ShoppingShareSheet(activityItems: [viewModel.shareText])
                .ignoresSafeArea()
        }
        .animation(.snappy(duration: 0.25), value: viewModel.items)
        .animation(.snappy(duration: 0.25), value: showsComposer)
        .onChange(of: showsComposer) { _, isVisible in
            guard isVisible else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isComposerFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Liste de courses")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 0)

            if viewModel.hasItems {
                HStack(spacing: 12) {
                    topCircleButton(
                        systemImage: "plus",
                        iconColor: CooksyTheme.ctaOrange,
                        backgroundColor: CooksyTheme.ctaOrange.opacity(0.15)
                    ) {
                        startComposer()
                    }

                    topCircleButton(
                        systemImage: "square.and.arrow.up",
                        iconColor: CooksyTheme.primaryText,
                        backgroundColor: Color.white
                    ) {
                        showsShareSheet = true
                    }

                    Menu {
                        if viewModel.checkedCount > 0 {
                            Button("Supprimer les cochés", role: .destructive) {
                                viewModel.clearCompleted()
                            }
                        }

                        Button("Vider la liste", role: .destructive) {
                            viewModel.clearAll()
                        }
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 56, height: 56)
                            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 10)
                            .overlay {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 26)
        .background(Color.white)
    }

    private var countBar: some View {
        HStack(spacing: 16) {
            Text(viewModel.totalCountLabel)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 0)

            if viewModel.hasItems {
                Menu {
                    ForEach(ShoppingListViewModel.SortMode.allCases) { mode in
                        Button(mode.title) {
                            viewModel.sortMode = mode
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 20, weight: .semibold))

                        Text(viewModel.sortMode.title)
                            .font(.system(size: 20, weight: .medium, design: .rounded))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.95), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.white)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.hasItems {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.sections) { section in
                        ShoppingSectionView(
                            section: section,
                            onToggle: { item in
                                viewModel.toggleCompletion(for: item)
                            },
                            onSelect: { item in
                                selectedItem = item
                            }
                        )
                    }

                    Color.clear
                        .frame(height: 130)
                }
            }
        } else if showsComposer {
            Rectangle()
                .fill(CooksyTheme.background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Button(action: startComposer) {
                        HStack(spacing: 16) {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .medium))

                            Text("Ajoutez votre premier ingrédient")
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
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                    EmptyShoppingIllustration()
                        .padding(.top, 82)

                    Text("Aucun article ajouté")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(CooksyTheme.primaryText.opacity(0.82))
                        .padding(.top, 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 140)
            }
        }
    }

    private var composerBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CooksyTheme.stroke.opacity(0.65))

            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CooksyTheme.ctaOrange, lineWidth: 2)
                        )

                    TextEditor(text: $composerText)
                        .scrollContentBackground(.hidden)
                        .focused($isComposerFocused)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 62, maxHeight: 90)

                    if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Tapez ou collez plusieurs ingrédients")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

                Button("Terminé") {
                    submitComposer()
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.ctaOrange)
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Color.white)
    }

    private func startComposer() {
        showsComposer = true
    }

    private func submitComposer() {
        let addedCount = viewModel.addItems(from: composerText)
        guard addedCount > 0 else {
            composerText = ""
            showsComposer = false
            isComposerFocused = false
            return
        }

        composerText = ""
        showsComposer = false
        isComposerFocused = false
    }

    private func topCircleButton(
        systemImage: String,
        iconColor: Color,
        backgroundColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(backgroundColor)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingSectionView: View {
    let section: ShoppingListViewModel.Section
    let onToggle: (ShoppingItem) -> Void
    let onSelect: (ShoppingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.brandBlueDark)
                .tracking(1.4)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 18)

            ForEach(section.items) { item in
                ShoppingItemRow(
                    item: item,
                    onToggle: {
                        onToggle(item)
                    },
                    onSelect: {
                        onSelect(item)
                    }
                )
            }
        }
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingItem
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    ShoppingItemArtwork(item: item)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.article)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .strikethrough(item.isCompleted, color: CooksyTheme.secondaryText)

                        if let quantity = item.displayQuantity {
                            Text(quantity)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.secondaryText)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.isCompleted ? CooksyTheme.ctaOrange : Color.clear)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CooksyTheme.secondaryText.opacity(0.7), lineWidth: 2)
                    )
                    .overlay {
                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.white.opacity(item.isCompleted ? 0.88 : 1))
    }
}

private struct ShoppingItemArtwork: View {
    let item: ShoppingItem

    var body: some View {
        Group {
            if let remoteImageURL = item.remoteImageURL {
                AsyncImage(url: remoteImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CooksyTheme.stroke.opacity(0.7), lineWidth: 1)
        )
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CooksyTheme.surface)

            Text(item.emoji)
                .font(.system(size: 28))
        }
    }
}

private struct EmptyShoppingIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color(hex: 0xB9DA7E))
                .frame(width: 214, height: 214)
                .rotationEffect(.degrees(16))

            Path { path in
                path.move(to: CGPoint(x: 34, y: 152))
                path.addCurve(
                    to: CGPoint(x: 144, y: 30),
                    control1: CGPoint(x: 66, y: 114),
                    control2: CGPoint(x: 104, y: 38)
                )
                path.addCurve(
                    to: CGPoint(x: 176, y: 126),
                    control1: CGPoint(x: 182, y: 26),
                    control2: CGPoint(x: 186, y: 94)
                )
                path.addCurve(
                    to: CGPoint(x: 110, y: 164),
                    control1: CGPoint(x: 170, y: 146),
                    control2: CGPoint(x: 136, y: 162)
                )
                path.addCurve(
                    to: CGPoint(x: 22, y: 120),
                    control1: CGPoint(x: 62, y: 170),
                    control2: CGPoint(x: 38, y: 146)
                )
            }
            .stroke(
                Color(hex: 0x9C70C8),
                style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 214, height: 214)
            .rotationEffect(.degrees(16))
        }
        .frame(width: 260, height: 230)
    }
}

private struct ShoppingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingItem
    let onDelete: (ShoppingItem) -> Void
    let onUpdate: (ShoppingItem, String, String, ShoppingCategory) -> Void

    @State private var article: String
    @State private var quantity: String
    @State private var category: ShoppingCategory

    init(
        item: ShoppingItem,
        onDelete: @escaping (ShoppingItem) -> Void,
        onUpdate: @escaping (ShoppingItem, String, String, ShoppingCategory) -> Void
    ) {
        self.item = item
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        _article = State(initialValue: item.article)
        _quantity = State(initialValue: item.quantity ?? "")
        _category = State(initialValue: item.category)
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(CooksyTheme.surface)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(CooksyTheme.primaryText)
                            }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Text("Modifier l’ingrédient")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Spacer(minLength: 0)

                    Color.clear
                        .frame(width: 58, height: 58)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.7))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        editorField(title: "Article") {
                            TextField("", text: $article)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }

                        editorField(title: "Quantité") {
                            TextField("", text: $quantity)
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .keyboardType(.numbersAndPunctuation)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Catégorie")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Menu {
                                ForEach(ShoppingCategory.allCases) { category in
                                    Button(category.title) {
                                        self.category = category
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(category.title)
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(CooksyTheme.primaryText)
                                }
                                .padding(.horizontal, 18)
                                .frame(height: 82)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(CooksyTheme.stroke, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 160)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.65))

                HStack(spacing: 16) {
                    Button("Supprimer") {
                        onDelete(item)
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.red.opacity(0.8), lineWidth: 2)
                    )

                    Button("Mettre à jour") {
                        onUpdate(item, trimmedArticle, trimmedQuantity, category)
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(canUpdate ? .white : CooksyTheme.secondaryText.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(canUpdate ? CooksyTheme.ctaOrange : CooksyTheme.warmCardMuted)
                    )
                    .disabled(!canUpdate)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .background(Color.white)
        }
    }

    private var trimmedArticle: String {
        ShoppingCatalog.displayArticle(for: article)
    }

    private var trimmedQuantity: String {
        quantity.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canUpdate: Bool {
        guard !trimmedArticle.isEmpty else { return false }

        return trimmedArticle != item.article ||
            trimmedQuantity != (item.quantity ?? "") ||
            category != item.category
    }

    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            content()
                .padding(.horizontal, 18)
                .frame(height: 82)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.stroke, lineWidth: 2)
                )
        }
    }
}

private struct ShoppingShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let store = RecipeStore()
    NavigationStack {
        ShoppingListView(store: store)
            .environmentObject(store)
    }
}
