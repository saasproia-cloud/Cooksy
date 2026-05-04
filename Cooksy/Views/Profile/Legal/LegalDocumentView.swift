import SwiftUI

/// Shared scaffolding for the static legal pages (Privacy / ToS).
/// Renders an intro paragraph + a list of titled sections in the Cooksy style.
struct LegalDocumentView: View {
    let title: String
    let lastUpdated: String
    let intro: String
    let sections: [LegalSection]

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(CooksyTheme.primaryText)

                        Text("Dernière mise à jour : \(lastUpdated)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                    }

                    Text(intro)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
                        .lineSpacing(4)

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText)

                            Text(section.body)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(CooksyTheme.primaryText.opacity(0.85))
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(CooksyTheme.elevatedSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(CooksyTheme.stroke, lineWidth: 1)
                        )
                    }

                    Text("Une question ? Écris-nous à azizelghazel@gmail.com")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}
