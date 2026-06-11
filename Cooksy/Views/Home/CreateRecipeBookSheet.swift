import SwiftUI

struct CreateRecipeBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool

    let onCreate: (String) -> Void

    @State private var title = ""
    private let maxLength = 50

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CooksyTheme.stroke)
                .frame(width: 76, height: 8)
                .padding(.top, 12)
                .padding(.bottom, 22)

            Text("Nouveau livre de recettes")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)
                .padding(.bottom, 22)

            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.6))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("Titre")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.top, 22)

                HStack(spacing: 12) {
                    TextField("", text: $title)
                        .focused($isTitleFocused)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)
                        .submitLabel(.done)
                        .onSubmit {
                            createBook()
                        }

                    if !title.isEmpty {
                        Button(action: { title = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CooksyTheme.ctaOrange, lineWidth: 2.4)
                )

                HStack {
                    Spacer()

                    Text("\(title.count)/\(maxLength)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 0)

            Rectangle()
                .fill(CooksyTheme.stroke.opacity(0.6))
                .frame(height: 1)

            Button(action: createBook) {
                Text("Créer un livre de recettes")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 66)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CooksyTheme.ctaOrange)
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(34)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            isTitleFocused = true
        }
        .onChange(of: title) { _, newValue in
            if newValue.count > maxLength {
                title = String(newValue.prefix(maxLength))
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createBook() {
        guard !trimmedTitle.isEmpty else { return }
        onCreate(trimmedTitle)
        dismiss()
    }
}
