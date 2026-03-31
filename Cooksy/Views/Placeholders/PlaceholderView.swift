import SwiftUI

struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ZStack {
            CooksyTheme.ambientGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("BIENTOT")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(CooksyTheme.ctaOrangeDark)

                HStack(alignment: .top, spacing: 18) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CooksyTheme.blush.opacity(0.58))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.system(size: 32, weight: .regular, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text(message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
            .padding(.horizontal, 20)
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
            kind: .createFromScratch,
            title: "Depuis\nzéro",
            systemImage: "pencil",
            accentColor: CooksyTheme.ctaOrange
        ),
        QuickImportOption(
            kind: .browser,
            title: "Site\nweb",
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
            title: "Texte\ncollé",
            systemImage: "text.alignleft",
            accentColor: CooksyTheme.ctaOrange
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Text("Importer une recette")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .padding(.top, 8)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(options) { option in
                        QuickImportOptionCard(
                            option: option,
                            action: action(for: option.kind)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(CooksyTheme.background)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(CooksyTheme.background)
    }

    private func action(for kind: QuickImportOption.Kind) -> () -> Void {
        switch kind {
        case .createFromScratch:
            return onCreateFromScratch
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
        case createFromScratch
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
            VStack(spacing: 16) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(option.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.45))
                    )

                Text(option.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(option.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 146)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CooksyTheme.warmCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
