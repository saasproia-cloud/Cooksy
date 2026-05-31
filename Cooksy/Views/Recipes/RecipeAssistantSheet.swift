import SwiftUI

/// Premium recipe assistant sheet. Replaces the old hardcoded
/// CooksyAssistantView. Provides:
///   - history (rehydrated from Supabase on appear)
///   - immediate echo of the user's message + typing indicator
///   - suggestion chips (substitutions / scaling) rendered as tappable
///     pill buttons
///   - a "Modifier la recette" confirmation card for pending
///     modifications
///   - graceful error banner with retry on transient failures
struct RecipeAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RecipeAssistantViewModel
    @FocusState private var inputFocused: Bool
    @State private var bottomAnchorId = UUID()

    init(store: RecipeStore, recipeID: Recipe.ID) {
        _viewModel = StateObject(
            wrappedValue: RecipeAssistantViewModel(store: store, recipeID: recipeID)
        )
    }

    var body: some View {
        ZStack {
            CooksyTheme.backgroundCalm.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(CooksyTheme.dividerSubtle)
                conversation
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .task { await viewModel.loadIfNeeded() }
        .alert("Une erreur est survenue", isPresented: errorPresented) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if !presented { viewModel.errorMessage = nil }
            }
        )
    }

    // ------------------------------------------------------------------
    // Header
    // ------------------------------------------------------------------

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: { dismiss() }) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant Cooksy")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text(viewModel.recipe?.title ?? "Recette")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CooksyTheme.accentWarm)
                .padding(10)
                .background(
                    Circle().fill(CooksyTheme.accentWarm.opacity(0.12))
                )
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // ------------------------------------------------------------------
    // Conversation
    // ------------------------------------------------------------------

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.messages.isEmpty {
                        emptyStateCard
                    }

                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        TypingIndicator()
                            .id("typing-indicator")
                    }

                    // Hidden anchor we scroll to whenever the timeline
                    // changes. Using a stable id keeps the spring
                    // animation smooth without re-laying out the list.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isStreaming) { _, _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comment puis-je t'aider ?")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)

            quickQuestion(
                icon: "arrow.triangle.2.circlepath",
                title: "Remplacer un ingrédient"
            ) {
                await viewModel.send(presetQuickQuestion: "Je veux remplacer un ingrédient.")
            }

            quickQuestion(
                icon: "slider.horizontal.3",
                title: "Adapter les portions"
            ) {
                await viewModel.send(presetQuickQuestion: "Comment ajuster les portions de cette recette ?")
            }

            quickQuestion(
                icon: "leaf",
                title: "Rendre la recette plus saine"
            ) {
                await viewModel.send(presetQuickQuestion: "Comment rendre cette recette plus saine ?")
            }

            quickQuestion(
                icon: "questionmark.circle",
                title: "Une étape pas claire ?"
            ) {
                await viewModel.send(presetQuickQuestion: "Peux-tu simplifier les étapes ?")
            }
        }
    }

    private func quickQuestion(
        icon: String,
        title: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStreaming)
        .opacity(viewModel.isStreaming ? 0.5 : 1)
    }

    // ------------------------------------------------------------------
    // Per-message rendering
    // ------------------------------------------------------------------

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .assistant, .system:
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 32)
            VStack(alignment: .trailing, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CooksyTheme.accentWarm)
                    )
                if case .failed(let reason) = message.state {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func assistantBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(CooksyTheme.accentWarm.opacity(0.12))
                    )

                Text(message.text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
                    )
            }

            if let suggestions = message.suggestions {
                suggestionChips(suggestions, message: message)
            }

            if let pending = message.pendingModification {
                pendingModificationCard(pending)
            }
        }
    }

    private func suggestionChips(_ group: ChatSuggestionGroup, message: ChatMessage) -> some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(group.options) { option in
                Button {
                    Task { await viewModel.selectSuggestion(option, in: message) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                        Text(option.shortImpact)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.accentWarm.opacity(0.10))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CooksyTheme.accentWarm.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStreaming)
                .opacity(viewModel.isStreaming ? 0.6 : 1)
            }
        }
        .padding(.leading, 34)
    }

    private func pendingModificationCard(_ pending: PendingModification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CooksyTheme.accentWarm)
                Text("Modification proposée")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .textCase(.uppercase)
            }

            Text(pending.summary)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            diffSummary(for: pending.diff)

            Button {
                Task { await viewModel.confirmModification(pending) }
            } label: {
                HStack {
                    Spacer()
                    Text(pending.confirmLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CooksyTheme.accentWarm)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStreaming)
            .opacity(viewModel.isStreaming ? 0.6 : 1)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CooksyTheme.accentWarm.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CooksyTheme.accentWarm.opacity(0.30), lineWidth: 1)
        )
        .padding(.leading, 34)
    }

    @ViewBuilder
    private func diffSummary(for diff: RecipeDiff) -> some View {
        switch diff {
        case .ingredientSwap(let swap):
            VStack(alignment: .leading, spacing: 4) {
                Text("− \(swap.before.line)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                Text("+ \(swap.after.line)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                if !swap.stepRewrites.isEmpty {
                    Text("\(swap.stepRewrites.count) étape(s) ajustée(s)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
        case .scalePortions(let scale):
            VStack(alignment: .leading, spacing: 4) {
                Text("Portions : \(scale.before.servings ?? "—") → \(scale.after.servings ?? "—")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                Text("\(scale.ingredientPatches.count) ingrédient(s) recalculé(s)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
        }
    }

    // ------------------------------------------------------------------
    // Input bar
    // ------------------------------------------------------------------

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Pose une question sur cette recette", text: $viewModel.draft, axis: .vertical)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Color.white))
                .overlay(Capsule(style: .continuous).stroke(CooksyTheme.dividerSubtle, lineWidth: 1))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.submitDraft() } }

            Button {
                Task { await viewModel.submitDraft() }
            } label: {
                Image(systemName: viewModel.isStreaming ? "ellipsis" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CooksyTheme.accentWarm)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CooksyTheme.backgroundCalm.opacity(0.96))
    }
}

// ---------------------------------------------------------------------------
// Typing indicator
// ---------------------------------------------------------------------------

private struct TypingIndicator: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CooksyTheme.accentWarm)
                .frame(width: 24, height: 24)
                .background(Circle().fill(CooksyTheme.accentWarm.opacity(0.12)))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(CooksyTheme.accentWarm.opacity(phase == i ? 1.0 : 0.35))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: phase)
                }
                Text("Cooksy réfléchit…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CooksyTheme.dividerSubtle, lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// ---------------------------------------------------------------------------
// IngredientPatch — pretty line for the diff card.
// ---------------------------------------------------------------------------

private extension IngredientPatch {
    var line: String {
        [amount, unit, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
