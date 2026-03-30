import test from "node:test";
import assert from "node:assert/strict";

import { fallbackRecipeFromContext, strictRecipeFromContext } from "./heuristicRecipeService.js";
import { importFailureReason } from "../types/recipe.js";

test("fallbackRecipeFromContext extracts ingredients and steps from long TikTok captions", () => {
  const caption = [
    "FILET O FISH BURGER #food #recipe #fy #fyp #foryoupage #filet #fish #burger",
    "DOUGH 200 ml milk (lukewarm) 20 g honey 7 g instant yeast (1 tablespoon or 1 packet) 1 egg (medium) 30 ml sunflower oil 20 g butter (unsalted) 425 g flour (all-purpose) 8 g salt (1⅓ teaspoon)",
    "EXTRAS 1 egg (medium) sesame seeds",
    "COD MIXTURE 450 g cod 3 g salt (½ teaspoon) 3 g onion powder (1 teaspoon) 2 g cayenne powder (⅔ teaspoon) 1.5 g black pepper powder (½ teaspoon) 10 g mustard",
    "FLOUR MIXTURE 50 g flour (all-purpose) 50 g cornstarch 3 g salt (½ teaspoon)",
    "--- Instructions Pour the lukewarm milk into a deep bowl. Add honey and yeast, then mix well. Let the mixture rest for 5 minutes. Add sunflower oil, the beaten egg, butter, flour, and salt. Mix and knead the dough for 10-12 minutes until smooth."
  ].join(" ");

  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@kookmutsjes/video/7448673580990156054",
    socialCaption: caption,
    socialDescription: caption
  });

  assert.equal(recipe.title, "Filet O Fish Burger");
  assert.ok(recipe.ingredientDrafts.length >= 8, `expected >= 8 ingredients, got ${recipe.ingredientDrafts.length}`);
  assert.ok(recipe.stepDrafts.length >= 4, `expected >= 4 steps, got ${recipe.stepDrafts.length}`);
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => ingredient.name.includes("instant yeast")),
    "expected instant yeast ingredient to be kept intact"
  );
  assert.ok(
    !recipe.ingredientDrafts.some((ingredient) => ingredient.name === "packet)"),
    "did not expect packet fragment to become a standalone ingredient"
  );
  assert.equal(recipe.needsWebFallback, false);
  assert.equal(recipe.flags?.usedExplicitIngredients, true);
  assert.equal(recipe.flags?.generatedSteps, false);
  assert.ok((recipe.confidenceScore ?? 0) >= 0.7);
});

test("fallbackRecipeFromContext reconstructs a dish-first smash burger recipe from sparse social cues", () => {
  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/123456789",
    socialCaption: "SMASH BURGER #smashburger with onions, pickles and cheddar",
    socialDescription: "best smashburger ever",
    transcript: "okay friends this is so wild, smash it and trust the process, absolutely unreal"
  });

  assert.equal(recipe.title, "Smash Burger");
  assert.ok(recipe.ingredientDrafts.length >= 6, `expected >= 6 ingredients, got ${recipe.ingredientDrafts.length}`);
  assert.ok(recipe.stepDrafts.length >= 4, `expected >= 4 steps, got ${recipe.stepDrafts.length}`);
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => /boeuf|beef/i.test(ingredient.name) || /ground beef/i.test(ingredient.nutritionQuery)),
    "expected ground beef to be inferred"
  );
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => /pain|bun/i.test(ingredient.name) || /hamburger bun/i.test(ingredient.nutritionQuery)),
    "expected burger buns to be inferred"
  );
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => /cheddar/i.test(ingredient.name)),
    "expected cheddar to be kept"
  );
  assert.equal(recipe.flags?.usedExplicitIngredients, true);
  assert.equal(recipe.flags?.usedInferredIngredients, true);
  assert.equal(recipe.flags?.generatedSteps, true);
  assert.ok((recipe.confidenceScore ?? 0) >= 0.55);
  assert.equal(recipe.stepDrafts.some((step) => /trust the process|absolutely unreal/i.test(step.detail)), false);
});

test("fallbackRecipeFromContext reconstructs a truffle burger from a dish name even without description", () => {
  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/222222",
    socialTitle: "Burger a la truffe",
    sharedText: "Burger a la truffe"
  });

  assert.equal(recipe.title, "Burger a la truffe");
  assert.ok(recipe.ingredientDrafts.length >= 6, `expected >= 6 ingredients, got ${recipe.ingredientDrafts.length}`);
  assert.ok(recipe.stepDrafts.length >= 4, `expected >= 4 steps, got ${recipe.stepDrafts.length}`);
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => /truffe/i.test(ingredient.name) || /truffle/i.test(ingredient.nutritionQuery)),
    "expected truffle flavor to be inferred"
  );
  assert.ok(
    recipe.ingredientDrafts.some((ingredient) => /champignon/i.test(ingredient.name) || /mushroom/i.test(ingredient.nutritionQuery)),
    "expected mushrooms to be inferred"
  );
  assert.equal(recipe.flags?.usedInferredIngredients, true);
  assert.ok((recipe.confidenceScore ?? 0) >= 0.55);
});

test("fallbackRecipeFromContext keeps structured TikTok captions clean and complete", () => {
  const caption = [
    "LaCuisineDeKam + Suivre",
    "SANDWICH NAAN",
    "✨ INGREDIENTS",
    "- 300g de farine ( ici de la T45 de chez Lidl )",
    "- 6g de levure deshydratee",
    "- 1 C.A.C de levure chimique",
    "- 125g de yaourt nature",
    "- 1 C.A.C de sucre",
    "- 1 C.A.C de sel",
    "- 30g de beurre mou",
    "- 60ml d'eau tiede",
    "- une 10 ene de fromage qui rit",
    "✨ ici mes naans font 80g chacun environ",
    "✨ CUISSON : sur une poele anti adhesive",
    "✨ INSTRUCTIONS",
    "1) diluer la levure boulangere seche dans 4 C.A.S d'eau tiede et laisser agir 10 min",
    "2) dans la cuve du robot melanger farine + sel + sucre + levure chimique",
    "3) ajouter ensuite le yaourt",
    "4) melanger puis ajouter la levure boulangere diluee",
    "5) ajouter le beurre mou et commencer a petrir",
    "6) finir par l'ajout de l'eau tiede",
    "7) degazer votre pate puis former des patons",
    "8) aplatir le paton et deposer le fromage au centre",
    "9) fermer les extremites puis retourner votre paton",
    "10) etaler ensuite votre paton et proceder comme sur la video",
    "11) les cuire sur une poele anti adhesive non huilee environ 2 min de chaque cote",
    "✨ POULET PANE",
    "✨ MARINADE (au moins 1h au frais)",
    "- j'ai utilise 3 grandes escalopes de poulet que j'ai coupe en longueurs",
    "- 1 c.a.s de sauce soja salee",
    "- sel poivre paprika epices poulet ail semoule persil seche",
    "👉 melanger tout et mettre au frais",
    "✨ PANURE",
    "- 150g de farine environ",
    "- 150g de chapelure ou comme ici des corn flakes non sucres",
    "12) enrober le poulet dans la farine puis dans la marinade et enfin dans la panure",
    "13) cuire le poulet jusqu'a ce qu'il soit bien dore et croustillant",
    "The playful waltz"
  ].join("\n");

  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@lacuisinedekam/video/123456789",
    sharedText: caption,
    socialCaption: caption,
    socialDescription: caption
  });

  assert.equal(recipe.title, "Sandwich Naan");
  assert.ok(recipe.ingredientDrafts.length >= 12, `expected >= 12 ingredients, got ${recipe.ingredientDrafts.length}`);
  assert.ok(recipe.stepDrafts.length >= 10, `expected >= 10 steps, got ${recipe.stepDrafts.length}`);
  assert.ok(recipe.ingredientDrafts.some((ingredient) => /poulet/i.test(ingredient.name)), "expected chicken to be kept");
  assert.ok(recipe.ingredientDrafts.some((ingredient) => /sauce soja/i.test(ingredient.name)), "expected soy sauce to be kept");
  assert.ok(recipe.ingredientDrafts.some((ingredient) => /chapelure|corn flakes/i.test(ingredient.name)), "expected breading ingredient to be kept");
  assert.equal(recipe.ingredientDrafts.some((ingredient) => /playful|waltz|suivre/i.test(ingredient.name)), false);
  assert.equal(recipe.stepDrafts.some((step) => /playful|waltz|suivre/i.test(step.detail)), false);
  assert.equal(recipe.needsWebFallback, false);
  assert.equal(importFailureReason(recipe), undefined);
});

test("fallbackRecipeFromContext only fails when there is no meaningful food signal", () => {
  const recipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/999999",
    socialCaption: "Outfit of the day, boots, coat and city walk #fashion #ootd",
    socialDescription: "nothing about cooking here"
  });

  assert.equal(recipe.title, "");
  assert.equal(recipe.ingredientDrafts.length, 0);
  assert.equal(recipe.stepDrafts.length, 0);
  assert.equal(recipe.flags?.usedExplicitIngredients, false);
  assert.equal(importFailureReason(recipe), "no_recipe_detected");
});

test("strictRecipeFromContext rebuilds weak food extractions into a full recipe", () => {
  const strictRecipe = strictRecipeFromContext(
    {
      mode: "url",
      sourceUrl: "https://www.tiktok.com/@cooksy/video/777777",
      socialCaption: "Crispy chicken wrap with lettuce and sauce",
      sharedText: "Crispy chicken wrap",
      transcript: "just add the crispy chicken and roll it up"
    },
    {
      title: "Crispy chicken wrap",
      sourceUrl: "https://www.tiktok.com/@cooksy/video/777777",
      remoteImageUrl: "",
      ingredientDrafts: [
        { amount: "", unit: "", name: "poulet croustillant", nutritionQuery: "chicken tenders" },
        { amount: "", unit: "", name: "salade", nutritionQuery: "lettuce" }
      ],
      stepDrafts: [
        { detail: "Ajoutez le poulet et roulez." }
      ],
      notesText: "",
      prepTimeText: "",
      cookTimeText: "",
      servingsText: "",
      caloriesText: "",
      proteinText: "",
      carbsText: "",
      fatText: "",
      confidence: "low",
      needsWebFallback: true,
      searchQuery: "Crispy chicken wrap",
      inferredFromPhoto: false
    }
  );

  assert.ok(strictRecipe, "expected food content to be reconstructed");
  assert.equal(strictRecipe?.title, "Chicken Wrap");
  assert.ok((strictRecipe?.ingredientDrafts.length ?? 0) >= 5);
  assert.ok((strictRecipe?.stepDrafts.length ?? 0) >= 4);
  assert.equal(strictRecipe?.needsWebFallback, false);
  assert.equal(strictRecipe?.flags?.usedInferredIngredients, true);
  assert.equal(strictRecipe?.flags?.generatedSteps, true);
});
