import SwiftUI

struct StepByStepCookingView: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let steps: [RecipeStep]

    @State private var currentIndex = 0
    @State private var showsOverview = false

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let currentStep {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 26) {
                            progressRow
                                .padding(.top, 20)

                            HStack(alignment: .lastTextBaseline, spacing: 10) {
                                Text("Étape \(currentIndex + 1)")
                                    .font(.system(size: 24, weight: .regular, design: .serif))
                                    .foregroundStyle(CooksyTheme.primaryText)

                                Text("sur \(steps.count)")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }

                            if currentIndex > 0 {
                                Button(action: previousStep) {
                                    Label("Revenir à l’étape précédente", systemImage: "chevron.left")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(CooksyTheme.primaryText)
                                        .padding(.horizontal, 14)
                                        .frame(height: 38)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(CooksyTheme.elevatedSurface)
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            VStack(alignment: .leading, spacing: 18) {
                                if let title = currentStep.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(CooksyTheme.blush.opacity(0.9))
                                        )
                                }

                                Text(currentStep.detail)
                                    .font(.system(size: 26, weight: .regular, design: .serif))
                                    .foregroundStyle(CooksyTheme.primaryText)
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(26)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(CooksyTheme.elevatedSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(CooksyTheme.stroke.opacity(0.92), lineWidth: 1)
                            )
                            .shadow(color: CooksyTheme.shadow, radius: 18, y: 10)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 160)
                    }
                } else {
                    Spacer()

                    VStack(spacing: 14) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(CooksyTheme.ctaOrange)

                        Text("Aucune étape disponible.")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .gesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -50 {
                        nextStepOrDismiss()
                    } else if value.translation.width > 50 {
                        previousStep()
                    }
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sheet(isPresented: $showsOverview) {
            stepOverviewSheet
        }
    }

    private var currentStep: RecipeStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.85), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text(recipeTitle)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(CooksyTheme.background.opacity(0.94))
                .shadow(color: CooksyTheme.softShadow, radius: 14, y: 6)
        )
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                Capsule(style: .continuous)
                    .fill(index <= currentIndex ? CooksyTheme.ctaOrange : CooksyTheme.softCloud.opacity(0.92))
                    .frame(height: 7)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CooksyTheme.stroke.opacity(0.65))

            HStack(spacing: 14) {
                Button(action: { showsOverview = true }) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CooksyTheme.elevatedSurface)
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(CooksyTheme.primaryText)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CooksyTheme.stroke.opacity(0.9), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: nextStepOrDismiss) {
                    Text(currentIndex == steps.count - 1 ? "Terminer" : "Suivant")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CooksyTheme.accentGradient)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(CooksyTheme.background.opacity(0.96))
    }

    private var stepOverviewSheet: some View {
        NavigationStack {
            List(Array(steps.enumerated()), id: \.element.id) { index, step in
                Button(action: {
                    currentIndex = index
                    showsOverview = false
                }) {
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(index == currentIndex ? CooksyTheme.ctaOrange : CooksyTheme.brandBlueDark)
                            .frame(width: 28, alignment: .leading)

                        Text(step.detail)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                            .lineLimit(3)

                        Spacer(minLength: 0)

                        if index == currentIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CooksyTheme.ctaOrange)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CooksyTheme.background)
            .navigationTitle("Toutes les étapes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func previousStep() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentIndex = max(0, currentIndex - 1)
        }
    }

    private func nextStepOrDismiss() {
        if currentIndex >= steps.count - 1 {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentIndex += 1
            }
        }
    }
}
