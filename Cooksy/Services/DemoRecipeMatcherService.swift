import Foundation
import UIKit

enum DemoRecipeMatcherService {
    static func match(
        url: URL? = nil,
        sharedText: String? = nil,
        pageTitle: String? = nil,
        socialCaption: String? = nil,
        pageDescription: String? = nil
    ) -> RecipeEditorSeed? {
        let haystack = normalizedHaystack(
            url: url,
            sharedText: sharedText,
            pageTitle: pageTitle,
            socialCaption: socialCaption,
            pageDescription: pageDescription
        )

        guard !haystack.isEmpty else { return nil }
        guard let scenario = DemoRecipeCatalog.scenarios.first(where: { matches($0, haystack: haystack) }) else {
            return nil
        }

        return makeSeed(for: scenario, sourceURL: url, sourceName: sourceName(for: url))
    }

    private static func matches(_ scenario: DemoRecipeScenario, haystack: String) -> Bool {
        scenario.matchGroups.allSatisfy { group in
            group.contains { keyword in
                let normalizedKeyword = normalizedSearchText(keyword)
                return !normalizedKeyword.isEmpty && haystack.contains(normalizedKeyword)
            }
        }
    }

    private static func makeSeed(
        for scenario: DemoRecipeScenario,
        sourceURL: URL?,
        sourceName: String
    ) -> RecipeEditorSeed {
        let notes = [
            "Source demo : \(sourceName).",
            scenario.summary,
            "Recette activee localement par Cooksy a partir des mots-cles detectes dans le partage."
        ].joined(separator: "\n\n")

        return RecipeEditorSeed(
            title: scenario.title,
            sourceURL: sourceURL ?? URL(string: "https://cooksy.app/demo/\(scenario.id)"),
            ingredientDrafts: scenario.ingredients.map {
                IngredientDraft(amount: $0.amount, unit: $0.unit, name: $0.name)
            },
            stepDrafts: scenario.steps.map { StepDraft(detail: $0) },
            notesText: notes,
            prepTimeText: String(scenario.prepMinutes),
            cookTimeText: String(scenario.cookMinutes),
            servingsText: scenario.servings,
            imageData: renderHeroImage(for: scenario, sourceName: sourceName)
        )
    }

    private static func normalizedHaystack(
        url: URL?,
        sharedText: String?,
        pageTitle: String?,
        socialCaption: String?,
        pageDescription: String?
    ) -> String {
        [
            sharedText,
            pageTitle,
            socialCaption,
            pageDescription,
            url?.absoluteString,
            url?.host(percentEncoded: false),
            url?.path(percentEncoded: false)
        ]
        .compactMap { $0 }
        .map(normalizedSearchText)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceName(for url: URL?) -> String {
        let host = url?.host(percentEncoded: false)?.lowercased() ?? ""

        if host.contains("tiktok") {
            return "TikTok Demo"
        }

        if host.contains("instagram") {
            return "Instagram Demo"
        }

        if host.contains("pinterest") || host.contains("pin.it") {
            return "Pinterest Demo"
        }

        if host.isEmpty == false {
            return host
        }

        return "Cooksy Demo"
    }

    private static func renderHeroImage(for scenario: DemoRecipeScenario, sourceName: String) -> Data? {
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let cgContext = context.cgContext
            let colors = [UIColor(hex: scenario.hero.topColorHex).cgColor, UIColor(hex: scenario.hero.bottomColorHex).cgColor] as CFArray
            let locations: [CGFloat] = [0, 1]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            cgContext.setFillColor(UIColor(hex: scenario.hero.accentColorHex, alpha: 0.18).cgColor)
            cgContext.fillEllipse(in: CGRect(x: 830, y: 90, width: 260, height: 260))
            cgContext.fillEllipse(in: CGRect(x: -80, y: 600, width: 320, height: 320))

            drawPill(
                text: "COOKSY DEMO",
                in: CGRect(x: 78, y: 72, width: 230, height: 58),
                backgroundColor: UIColor.white.withAlphaComponent(0.2),
                textColor: UIColor.white,
                context: context
            )

            drawPill(
                text: sourceName.uppercased(),
                in: CGRect(x: 78, y: 142, width: 270, height: 54),
                backgroundColor: UIColor.black.withAlphaComponent(0.14),
                textColor: UIColor.white,
                context: context
            )

            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 230)
            ]
            NSString(string: scenario.hero.emoji).draw(
                in: CGRect(x: 820, y: 210, width: 250, height: 250),
                withAttributes: emojiAttributes
            )

            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.lineBreakMode = .byWordWrapping
            titleParagraph.alignment = .left

            NSString(string: scenario.title).draw(
                in: CGRect(x: 82, y: 260, width: 650, height: 220),
                withAttributes: [
                    .font: roundedFont(size: 72, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: titleParagraph
                ]
            )

            NSString(string: scenario.summary).draw(
                in: CGRect(x: 86, y: 500, width: 580, height: 120),
                withAttributes: [
                    .font: roundedFont(size: 28, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                    .paragraphStyle: titleParagraph
                ]
            )

            for (index, ingredient) in scenario.ingredients.prefix(3).enumerated() {
                drawPill(
                    text: ingredient.name.uppercased(),
                    in: CGRect(x: 84, y: 700 + CGFloat(index) * 58, width: 360, height: 46),
                    backgroundColor: UIColor.white.withAlphaComponent(0.16),
                    textColor: UIColor.white,
                    context: context
                )
            }
        }

        return image.jpegData(compressionQuality: 0.9)
    }

    private static func drawPill(
        text: String,
        in rect: CGRect,
        backgroundColor: UIColor,
        textColor: UIColor,
        context: UIGraphicsImageRendererContext
    ) {
        let pillPath = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        backgroundColor.setFill()
        pillPath.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        NSString(string: text).draw(
            in: rect.insetBy(dx: 18, dy: 10),
            withAttributes: [
                .font: roundedFont(size: 22, weight: .bold),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = baseFont.fontDescriptor.withDesign(.rounded) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
