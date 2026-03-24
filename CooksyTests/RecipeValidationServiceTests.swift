import XCTest
@testable import Cooksy

final class RecipeValidationServiceTests: XCTestCase {
    func testValidRecipePageFromStructuredDataPassesValidation() throws {
        let recipeJSONLD = """
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Brown Butter Pasta",
          "description": "A quick pasta finished with brown butter and parmesan.",
          "recipeIngredient": [
            "250 g pasta",
            "2 tbsp butter",
            "2 cloves garlic",
            "50 g parmesan"
          ],
          "recipeInstructions": [
            { "@type": "HowToStep", "text": "Bring a large pot of salted water to a boil and cook the pasta until al dente." },
            { "@type": "HowToStep", "text": "Melt the butter in a skillet until golden and stir in the garlic." },
            { "@type": "HowToStep", "text": "Add the drained pasta, toss with parmesan, then serve immediately." }
          ]
        }
        """

        let snapshotJSON = makeSnapshotJSON(
            title: "Brown Butter Pasta | Example Kitchen",
            h1Title: "Brown Butter Pasta",
            description: "A quick pasta finished with brown butter and parmesan.",
            jsonLD: [recipeJSONLD],
            sectionIngredients: ["Read More", "View post"],
            sectionInstructions: ["Read More", "View post"]
        )

        let imported = try RecipeWebImportService.importRecipe(from: snapshotJSON)
        let assessment = RecipeValidationService.assess(imported, sourceKind: .url)

        XCTAssertEqual(imported.normalizedTitle, "Brown Butter Pasta")
        XCTAssertEqual(imported.normalizedIngredients.count, 4)
        XCTAssertEqual(imported.normalizedSteps.count, 3)
        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
    }

    func testValidPinterestRecipePassesValidation() {
        let seed = RecipeEditorSeed(
            title: "Chickpea Crunch Salad",
            sourceURL: URL(string: "https://www.pinterest.com/pin/123456789/"),
            ingredientDrafts: [
                IngredientDraft(amount: "1", unit: "can", name: "chickpeas"),
                IngredientDraft(amount: "1", unit: "tbsp", name: "olive oil"),
                IngredientDraft(amount: "1", unit: "cup", name: "cherry tomatoes"),
                IngredientDraft(amount: "1/2", unit: "cup", name: "crumbled feta"),
                IngredientDraft(amount: "2", unit: "tbsp", name: "lemon juice")
            ],
            stepDrafts: [
                StepDraft(detail: "Roast the chickpeas in a hot oven until crisp."),
                StepDraft(detail: "Combine the tomatoes, feta, and lemon juice in a serving bowl."),
                StepDraft(detail: "Add the roasted chickpeas, toss well, and serve.")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
    }

    func testInvalidNewsArticlePageIsRejected() {
        let seed = RecipeEditorSeed(
            title: "Celebrity chef reveals the airport snack she always packs",
            sourceURL: URL(string: "https://news.example.com/celebrity/airport-snack-story"),
            ingredientDrafts: [
                IngredientDraft(name: "Read More"),
                IngredientDraft(name: "The celebrity opened up about travel routines, fashion week appearances, and the newsletter fans should subscribe to this month."),
                IngredientDraft(name: "View post")
            ],
            stepDrafts: [
                StepDraft(detail: "Read More"),
                StepDraft(detail: "The story continues with quotes about travel, style, and backstage celebrity moments from the interview.")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertTrue(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.articleLikeContentDetected))
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.sourcePageNotRecipe))
    }

    func testInvalidListiclePageIsRejected() {
        let repeatedBody = "Read More about the easiest dinner ideas, celebrity favorites, and fashion week comfort food trends."
        let seed = RecipeEditorSeed(
            title: "25 Easy Dinner Recipes to Make This Week",
            sourceURL: URL(string: "https://www.example.com/lifestyle/easy-dinner-recipes"),
            ingredientDrafts: [
                IngredientDraft(name: "Read More"),
                IngredientDraft(name: repeatedBody),
                IngredientDraft(name: repeatedBody)
            ],
            stepDrafts: [
                StepDraft(detail: "View post"),
                StepDraft(detail: "Read More"),
                StepDraft(detail: "Read More")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertTrue(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.invalidTitle))
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.repeatedTextDetected))
    }

    func testInvalidTikTokArticleRoundupPageIsRejected() {
        let seed = RecipeEditorSeed(
            title: "94 TikTok Recipes That Are Easy to Make and Actually Taste Good",
            sourceURL: URL(string: "https://www.example.com/news/tiktok-recipes-roundup"),
            ingredientDrafts: [
                IngredientDraft(name: "Read More"),
                IngredientDraft(name: "View post"),
                IngredientDraft(name: "This roundup includes celebrity interviews, travel notes, shopping tips, and newsletter links from the editors.")
            ],
            stepDrafts: [
                StepDraft(detail: "View post"),
                StepDraft(detail: "Read More"),
                StepDraft(detail: "The article highlights viral creators, celebrity cameos, fashion commentary, and more.")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertTrue(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.invalidTitle))
        XCTAssertTrue(assessment.validation.rejectionReasons.contains(.articleLikeContentDetected))
    }

    func testShoppingCatalogUsesSpecificFoodEmojiForCommonImportedIngredients() {
        XCTAssertEqual(ShoppingCatalog.specificEmoji(for: "viande hachée 5 %"), "🥩")
        XCTAssertEqual(ShoppingCatalog.specificEmoji(for: "cheddar fondu"), "🧀")
        XCTAssertEqual(ShoppingCatalog.specificEmoji(for: "sirop d'érable"), "🍁")
        XCTAssertEqual(ShoppingCatalog.specificEmoji(for: "ciboulette fraîche"), "🌿")
        XCTAssertEqual(ShoppingCatalog.specificEmoji(for: "sauce piquante"), "🌶️")
    }

    func testRecipeEditorSeedShortensVerboseImportedTitleForDisplayAndSave() {
        let seed = RecipeEditorSeed(
            title: "ANIMAL FRIES CAJUN Les Animal Fries d’un fast food qu’on a pas ici, mais avec plus de muscles et moins de gras"
        )

        XCTAssertEqual(seed.normalizedTitle, "Animal Fries Cajun")
    }

    private func makeSnapshotJSON(
        title: String,
        h1Title: String,
        description: String,
        jsonLD: [String],
        sectionIngredients: [String],
        sectionInstructions: [String]
    ) -> String {
        let object: [String: Any] = [
            "url": "https://www.example.com/recipes/brown-butter-pasta",
            "title": title,
            "h1Title": h1Title,
            "ogTitle": title,
            "ogImage": "",
            "description": description,
            "socialTitle": title,
            "socialDescription": description,
            "socialImage": "",
            "jsonLD": jsonLD,
            "microIngredients": [],
            "microInstructions": [],
            "sectionIngredients": sectionIngredients,
            "sectionInstructions": sectionInstructions
        ]

        let data = try! JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}
