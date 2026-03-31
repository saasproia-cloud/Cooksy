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

    func testIngredientNameNormalizerCanonicalizesCommonBakingIngredients() {
        let flour = IngredientNameNormalizer.normalize("300 g de farine (ici de la T45 de chez Lidl)")
        XCTAssertTrue(flour.candidateKeys.contains("farine"))
        XCTAssertTrue(flour.familyHints.contains("flour"))

        let butter = IngredientNameNormalizer.normalize("unsalted butter")
        XCTAssertTrue(butter.candidateKeys.contains("unsalted butter"))
        XCTAssertTrue(butter.candidateKeys.contains("butter"))
        XCTAssertTrue(butter.familyHints.contains("butter"))

        let powderedSugar = IngredientNameNormalizer.normalize("powdered sugar")
        XCTAssertTrue(powderedSugar.candidateKeys.contains("powdered sugar"))
        XCTAssertTrue(powderedSugar.familyHints.contains("sugar"))

        let bakingPowder = IngredientNameNormalizer.normalize("levure chimique")
        XCTAssertTrue(bakingPowder.candidateKeys.contains("levure chimique"))
        XCTAssertTrue(bakingPowder.familyHints.contains("baking powder"))
    }

    func testIngredientVisualResolverMatchesFrenchAndEnglishAliases() {
        let resolver = makeIngredientVisualResolver()

        XCTAssertEqual(resolver.resolve("beurre demi-sel").assetName, "IngredientIconButter")
        XCTAssertEqual(resolver.resolve("powdered sugar").assetName, "IngredientIconSugar")
        XCTAssertEqual(resolver.resolve("œuf").assetName, "IngredientIconEgg")
        XCTAssertEqual(resolver.resolve("baking powder").assetName, "IngredientIconBakingPowder")
        XCTAssertEqual(resolver.resolve("fresh spinach").assetName, "IngredientIconLeafyGreen")
    }

    func testIngredientVisualResolverUsesFamilyFallbackBeforeLogo() {
        let resolver = makeIngredientVisualResolver()
        let resolution = resolver.resolve("romaine hearts")

        XCTAssertEqual(resolution.matchKind, .family)
        XCTAssertEqual(resolution.assetName, "IngredientIconLeafyGreen")
        XCTAssertFalse(resolution.usesLogoFallback)
    }

    func testIngredientVisualResolverFallsBackToLogoForUnknownIngredient() {
        let resolver = makeIngredientVisualResolver()
        let resolution = resolver.resolve("mystery galaxy powder")

        XCTAssertEqual(resolution.matchKind, .logo)
        XCTAssertNil(resolution.assetName)
        XCTAssertTrue(resolution.usesLogoFallback)
    }

    func testRecipeEditorSeedShortensVerboseImportedTitleForDisplayAndSave() {
        let seed = RecipeEditorSeed(
            title: "ANIMAL FRIES CAJUN Les Animal Fries d’un fast food qu’on a pas ici, mais avec plus de muscles et moins de gras"
        )

        XCTAssertEqual(seed.normalizedTitle, "Animal Fries Cajun")
    }

    func testCompactSharedRecipeWithTwoRealIngredientsCanStillBeSaved() {
        let seed = RecipeEditorSeed(
            title: "Omelette fromage",
            ingredientDrafts: [
                IngredientDraft(amount: "2", unit: "", name: "oeufs"),
                IngredientDraft(amount: "30", unit: "g", name: "gruyere")
            ],
            stepDrafts: [
                StepDraft(detail: "Battez les oeufs puis versez-les dans une poele chaude."),
                StepDraft(detail: "Ajoutez le fromage, repliez l'omelette et servez.")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .shared)

        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
        XCTAssertNil(assessment.validation.reviewNotice)
    }

    func testTrustedBackendRecipeAvoidsIncompleteBlocker() {
        let seed = RecipeEditorSeed(
            title: "Burger a la truffe",
            ingredientDrafts: [
                IngredientDraft(amount: "2", unit: "piece", name: "pains burger"),
                IngredientDraft(amount: "320", unit: "g", name: "boeuf hache"),
                IngredientDraft(amount: "120", unit: "g", name: "champignons")
            ],
            stepDrafts: [
                StepDraft(detail: "Faites revenir les champignons puis saisissez le boeuf dans une poele tres chaude."),
                StepDraft(detail: "Toastez les pains, ajoutez la viande, les champignons et servez aussitot.")
            ],
            notesText: "Recette reconstruite depuis le web.",
            importDebug: RecipeImportDebugInfo(
                ingredientsCount: 3,
                stepsCount: 2,
                strategy: "fallback",
                durationMs: 1200,
                isLikelyValid: true,
                missing: [],
                failureReason: nil
            )
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
        XCTAssertNotEqual(assessment.validation.reviewNotice, "Import incomplet. Modifiez la recette pour l'enregistrer.")
    }

    func testMergedImportedIngredientsAreSplitBeforeDisplayAndSave() {
        let seed = RecipeEditorSeed(
            title: "Burger maison",
            ingredientDrafts: [
                IngredientDraft(amount: "2", unit: "tranches", name: "emmental/cornichon"),
                IngredientDraft(name: "ketchup, mayonnaise"),
                IngredientDraft(name: "cheddar et salade")
            ],
            stepDrafts: [
                StepDraft(detail: "Faites cuire les steaks puis montez les burgers."),
                StepDraft(detail: "Ajoutez le fromage, les cornichons, la salade et les sauces avant de servir.")
            ]
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .shared)

        XCTAssertEqual(
            assessment.seed.normalizedIngredients.map(\.name),
            ["emmental", "cornichon", "ketchup", "mayonnaise", "cheddar", "salade"]
        )
        XCTAssertEqual(assessment.seed.normalizedIngredients.first?.amount, "2")
        XCTAssertEqual(assessment.seed.normalizedIngredients.first?.unit, "tranches")
    }

    func testRecipeTextParserParsesStructuredTikTokCaptionWithoutSocialNoise() {
        let caption = """
        LaCuisineDeKam + Suivre
        👇 SANDWICH NAAN 👇
        ⭐ INGREDIENTS
        - 300g de farine ( ici de la T45 de chez Lidl )
        - 6g de levure déshydratée
        - 1 C.A.C de levure chimique
        - 125g de yaourt nature
        - 1 C.A.C de sucre
        - 1 C.A.C de sel
        - 30g de beurre mou
        - 60ml d’eau tiède
        - une 10 ène de fromage qui rit
        ⭐ INSTRUCTIONS
        1) diluer la levure boulangère sèche dans 4 C.A.S d’eau tiède et laisser agir 10 min
        2) dans la cuve du robot mélanger farine + sel + sucre + levure chimique
        3) ajouter ensuite le yaourt
        4) puis mélangez et ajouter la levure boulangère diluée
        5) ajouter le beurre mou et commencer à pétrir
        6) finir par l’ajout de l’eau tiède
        7) dégazer votre pâte puis former des pâtons
        8) aplatir le pâton et déposer le fromage au centre
        9) fermer les extrémités puis retourner votre pâton
        10) étaler le naan puis le cuire 2 min de chaque côté
        The playful waltz
        """

        let seed = RecipeTextParser.parse(caption)
        let assessment = RecipeValidationService.assess(seed, sourceKind: .shared)

        XCTAssertEqual(seed.normalizedTitle, "Sandwich Naan")
        XCTAssertGreaterThanOrEqual(seed.normalizedIngredients.count, 8)
        XCTAssertGreaterThanOrEqual(seed.normalizedSteps.count, 8)
        XCTAssertFalse(seed.normalizedIngredients.contains { ingredient in
            ingredient.name.localizedCaseInsensitiveContains("playful") ||
                ingredient.name.localizedCaseInsensitiveContains("waltz") ||
                ingredient.name.localizedCaseInsensitiveContains("suivre")
        })
        XCTAssertFalse(seed.normalizedSteps.contains { step in
            step.detail.localizedCaseInsensitiveContains("playful") ||
                step.detail.localizedCaseInsensitiveContains("waltz") ||
                step.detail.localizedCaseInsensitiveContains("suivre")
        })
        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
        XCTAssertNil(assessment.validation.reviewNotice)
    }

    func testCompleteReconstructedRecipeWithNutritionIsAcceptedWithoutIncompleteNotice() {
        let seed = RecipeEditorSeed(
            title: "Chicken Wrap",
            sourceURL: URL(string: "https://www.tiktok.com/@cooksy/video/123456789"),
            ingredientDrafts: [
                IngredientDraft(amount: "2", unit: "", name: "wraps"),
                IngredientDraft(amount: "300", unit: "g", name: "poulet"),
                IngredientDraft(amount: "80", unit: "g", name: "salade"),
                IngredientDraft(amount: "1", unit: "", name: "tomate"),
                IngredientDraft(amount: "2", unit: "c. à soupe", name: "sauce yaourt")
            ],
            stepDrafts: [
                StepDraft(detail: "Assaisonnez le poulet puis faites-le cuire jusqu'à ce qu'il soit bien doré."),
                StepDraft(detail: "Réchauffez les wraps quelques secondes pour les assouplir."),
                StepDraft(detail: "Disposez la salade, la tomate, le poulet et la sauce au centre des wraps."),
                StepDraft(detail: "Rabattez les côtés, roulez les wraps bien serrés et servez immédiatement.")
            ],
            caloriesText: "540 kcal",
            proteinText: "31 g",
            carbsText: "38 g",
            fatText: "24 g"
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertFalse(assessment.validation.isRejected)
        XCTAssertTrue(assessment.validation.canSave)
        if case .accepted = assessment.validation.status {
        } else {
            XCTFail("Expected accepted validation status")
        }
        XCTAssertNil(assessment.validation.reviewNotice)
        XCTAssertTrue(assessment.validation.metrics.hasCompleteNutrition)
        XCTAssertEqual(assessment.validation.metrics.validStepCount, 4)
    }

    func testStepFragmentsAreDroppedBeforeValidation() {
        let seed = RecipeEditorSeed(
            title: "Chicken Wrap",
            ingredientDrafts: [
                IngredientDraft(amount: "2", unit: "", name: "wraps"),
                IngredientDraft(amount: "300", unit: "g", name: "poulet"),
                IngredientDraft(amount: "80", unit: "g", name: "salade"),
                IngredientDraft(amount: "1", unit: "", name: "tomate"),
                IngredientDraft(amount: "2", unit: "c. à soupe", name: "sauce yaourt")
            ],
            stepDrafts: [
                StepDraft(detail: "Ensuite je vais prendre"),
                StepDraft(detail: "et après voilà"),
                StepDraft(detail: "comme ça"),
                StepDraft(detail: "Assaisonnez le poulet puis faites-le cuire jusqu'à ce qu'il soit bien doré."),
                StepDraft(detail: "Réchauffez les wraps quelques secondes pour les assouplir."),
                StepDraft(detail: "Disposez la salade, la tomate, le poulet et la sauce au centre des wraps."),
                StepDraft(detail: "Rabattez les côtés, roulez les wraps bien serrés et servez immédiatement.")
            ],
            caloriesText: "540 kcal",
            proteinText: "31 g",
            carbsText: "38 g",
            fatText: "24 g"
        )

        let assessment = RecipeValidationService.assess(seed, sourceKind: .url)

        XCTAssertEqual(assessment.seed.normalizedSteps.count, 4)
        XCTAssertFalse(assessment.seed.normalizedSteps.contains { step in
            step.detail.localizedCaseInsensitiveContains("Ensuite je vais prendre") ||
                step.detail.localizedCaseInsensitiveContains("et après voilà") ||
                step.detail.localizedCaseInsensitiveContains("comme ça")
        })
        XCTAssertTrue(assessment.validation.canSave)
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

private func makeIngredientVisualResolver() -> IngredientVisualResolver {
    IngredientVisualResolver(
        entries: [
            IngredientVisualCatalogEntry(
                canonicalKey: "flour",
                assetName: "IngredientIconFlour",
                aliases: ["farine", "wheat flour", "all purpose flour"],
                family: "flour",
                priority: 100
            ),
            IngredientVisualCatalogEntry(
                canonicalKey: "butter",
                assetName: "IngredientIconButter",
                aliases: ["beurre", "unsalted butter", "salted butter"],
                family: "butter",
                priority: 100
            ),
            IngredientVisualCatalogEntry(
                canonicalKey: "sugar",
                assetName: "IngredientIconSugar",
                aliases: ["sucre", "powdered sugar", "sucre glace"],
                family: "sugar",
                priority: 100
            ),
            IngredientVisualCatalogEntry(
                canonicalKey: "egg",
                assetName: "IngredientIconEgg",
                aliases: ["oeuf", "œuf", "egg"],
                family: "egg",
                priority: 100
            ),
            IngredientVisualCatalogEntry(
                canonicalKey: "baking powder",
                assetName: "IngredientIconBakingPowder",
                aliases: ["levure chimique"],
                family: "baking powder",
                priority: 100
            ),
            IngredientVisualCatalogEntry(
                canonicalKey: "leafy green",
                assetName: "IngredientIconLeafyGreen",
                aliases: ["spinach", "epinard", "épinard"],
                family: "leafy green",
                priority: 100
            ),
        ]
    )
}
