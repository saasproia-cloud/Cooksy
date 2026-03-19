import SwiftUI

struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(CooksyTheme.brandBlue)

                Text(title)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)

                Text(message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct QuickImportSheetView: View {
    let onCreateFromScratch: () -> Void
    let onBrowserImport: () -> Void
    let onCameraImport: () -> Void
    let onPasteText: () -> Void

    private let options: [QuickImportOption] = [
        QuickImportOption(
            kind: .browser,
            title: "Navigateur",
            systemImage: "safari",
            accentColor: CooksyTheme.ctaOrange
        ),
        QuickImportOption(
            kind: .camera,
            title: "Appareil\nphoto",
            systemImage: "camera",
            accentColor: CooksyTheme.ctaOrange
        ),
        QuickImportOption(
            kind: .pasteText,
            title: "Coller\ndu texte",
            systemImage: "text.alignleft",
            accentColor: CooksyTheme.ctaOrange
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 22) {
                Text("Importer une recette")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.top, 8)

                HStack(spacing: 14) {
                    ForEach(options) { option in
                        QuickImportOptionCard(
                            option: option,
                            action: action(for: option.kind)
                        )
                    }
                }

                HStack(spacing: 14) {
                    Rectangle()
                        .fill(CooksyTheme.stroke.opacity(0.9))
                        .frame(height: 1)

                    Text("ou")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText)

                    Rectangle()
                        .fill(CooksyTheme.stroke.opacity(0.9))
                        .frame(height: 1)
                }

                Button(action: onCreateFromScratch) {
                    HStack(spacing: 14) {
                        Image(systemName: "pencil")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Écrire à partir de zéro")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CooksyTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CooksyTheme.stroke.opacity(0.65), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .background(CooksyTheme.surface)
        }
        .presentationDetents([.height(365)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(CooksyTheme.surface)
    }

    private func action(for kind: QuickImportOption.Kind) -> () -> Void {
        switch kind {
        case .browser:
            return onBrowserImport
        case .camera:
            return onCameraImport
        case .pasteText:
            return onPasteText
        }
    }
}

private struct QuickImportOption: Identifiable {
    enum Kind {
        case browser
        case camera
        case pasteText
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let systemImage: String
    let accentColor: Color
}

private struct QuickImportOptionCard: View {
    let option: QuickImportOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(option.accentColor)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.45))
                    )

                Text(option.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(option.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(CooksyTheme.warmCard)
            )
        }
        .buttonStyle(.plain)
    }
}
