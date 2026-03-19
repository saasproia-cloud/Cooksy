import SwiftUI

struct StepByStepCookingView: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let steps: [RecipeStep]

    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(CooksyTheme.stroke.opacity(0.7))

                if let currentStep {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            progressRow
                                .padding(.top, 26)

                            Text("Étape \(currentIndex + 1)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.brandBlueDark)
                                .tracking(1.1)

                            Text(currentStep.detail)
                                .font(.system(size: 30, weight: .regular, design: .serif))
                                .foregroundStyle(CooksyTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            if let title = currentStep.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CooksyTheme.secondaryText)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 180)
                    }
                } else {
                    Spacer()
                    Text("Aucune étape disponible.")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    private var currentStep: RecipeStep? {
        guard steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(CooksyTheme.primaryText)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Text(recipeTitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(Color.white)
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                Capsule(style: .continuous)
                    .fill(index <= currentIndex ? CooksyTheme.ctaOrange : CooksyTheme.warmCardMuted)
                    .frame(height: 8)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CooksyTheme.stroke.opacity(0.65))

            HStack(spacing: 14) {
                Button(action: previousStep) {
                    Text("Précédent")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(currentIndex == 0 ? CooksyTheme.secondaryText.opacity(0.6) : CooksyTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
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
                .disabled(currentIndex == 0)

                Button(action: nextStepOrDismiss) {
                    Text(currentIndex == steps.count - 1 ? "Terminer" : "Continuer")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CooksyTheme.ctaOrange)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }

    private func previousStep() {
        currentIndex = max(0, currentIndex - 1)
    }

    private func nextStepOrDismiss() {
        if currentIndex >= steps.count - 1 {
            dismiss()
        } else {
            currentIndex += 1
        }
    }
}
