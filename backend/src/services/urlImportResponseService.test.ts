import test from "node:test";
import assert from "node:assert/strict";

import { buildURLImportFailureResponse, buildURLImportResponse } from "./urlImportResponseService.js";
import type { RecipeImportResult } from "../types/recipe.js";

test("buildURLImportResponse returns the strict success payload with stable defaults", async () => {
  const recipe: RecipeImportResult = {
    title: "Smash Burger",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/123",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "300", unit: "g", name: "boeuf hache", nutritionQuery: "ground beef" },
      { amount: "2", unit: "", name: "pain burger", nutritionQuery: "hamburger bun" },
      { amount: "4", unit: "tranches", name: "cheddar", nutritionQuery: "cheddar cheese" },
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "onion" },
      { amount: "2", unit: "cas", name: "sauce burger", nutritionQuery: "burger sauce" }
    ],
    stepDrafts: [
      { detail: "1. Faites cuire le boeuf sur une plaque chaude." },
      { detail: "Ajoutez le cheddar puis toastez les pains." },
      { detail: "Montez les burgers avec l'oignon et la sauce." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/123"
  });

  assert.equal(response.success, true);

  if (!response.success) {
    assert.fail("expected a success response");
  }

  assert.equal(response.data.title, "Smash Burger");
  assert.equal(response.data.sourceUrl, "https://www.tiktok.com/@cooksy/video/123");
  assert.equal(response.data.image, "https://placehold.co/1200x900/png?text=Cooksy+Recipe");
  assert.ok(response.data.ingredients.length >= 5);
  assert.ok(response.data.steps.length >= 4);
  assert.deepEqual(
    response.data.steps.map((step) => step.stepNumber),
    Array.from({ length: response.data.steps.length }, (_, index) => index + 1)
  );
  assert.equal(response.data.ingredients[4]?.unit, "c. à soupe");
  assert.ok(response.data.nutrition.calories > 0);
  assert.ok(response.data.nutrition.protein > 0);
  assert.ok(response.data.nutrition.carbs >= 0);
  assert.ok(response.data.nutrition.fat > 0);
});

test("buildURLImportResponse falls back to the strict failure payload for unusable recipes", async () => {
  const recipe: RecipeImportResult = {
    title: "",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [],
    stepDrafts: [],
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
    searchQuery: "",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/456"
  });

  assert.deepEqual(response, buildURLImportFailureResponse());
});

test("buildURLImportResponse replaces weak spoken fragments with complete French cooking steps", async () => {
  const recipe: RecipeImportResult = {
    title: "Chicken Wrap",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/789",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "wraps", nutritionQuery: "flour tortilla" },
      { amount: "300", unit: "g", name: "poulet", nutritionQuery: "chicken breast" },
      { amount: "80", unit: "g", name: "salade", nutritionQuery: "lettuce" },
      { amount: "1", unit: "", name: "tomate", nutritionQuery: "tomato" },
      { amount: "2", unit: "cas", name: "sauce yaourt", nutritionQuery: "yogurt sauce" }
    ],
    stepDrafts: [
      { detail: "Ensuite je vais prendre" },
      { detail: "et après voilà" },
      { detail: "comme ça" }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/789"
  });

  assert.equal(response.success, true);

  if (!response.success) {
    assert.fail("expected a success response");
  }

  assert.ok(response.data.steps.length >= 4);
  assert.equal(
    response.data.steps.some((step) => /ensuite je vais prendre|et après voilà|comme ça/i.test(step.description)),
    false
  );
});

test("buildURLImportResponse generates missing steps and nutrition when only ingredients are available", async () => {
  const recipe: RecipeImportResult = {
    title: "Crêpes",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/111222333",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "250", unit: "g", name: "farine", nutritionQuery: "flour" },
      { amount: "500", unit: "ml", name: "lait", nutritionQuery: "milk" },
      { amount: "3", unit: "oeufs", name: "oeufs", nutritionQuery: "egg" },
      { amount: "40", unit: "g", name: "sucre", nutritionQuery: "sugar" },
      { amount: "30", unit: "g", name: "beurre", nutritionQuery: "butter" }
    ],
    stepDrafts: [],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "4",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "Crêpes",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/111222333"
  });

  assert.equal(response.success, true);

  if (!response.success) {
    assert.fail("expected a success response");
  }

  assert.ok(response.data.steps.length >= 4);
  assert.ok(response.data.nutrition.calories > 0);
  assert.ok(response.data.nutrition.protein > 0);
  assert.ok(response.data.nutrition.carbs > 0);
  assert.ok(response.data.nutrition.fat > 0);
});

test("buildURLImportResponse removes transcript junk from imported ingredients", async () => {
  const recipe: RecipeImportResult = {
    title: "Crêpes Pierre Hermé",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/444555666",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "4", unit: "", name: "oeufs", nutritionQuery: "egg" },
      { amount: "60", unit: "g", name: "sucre", nutritionQuery: "sugar" },
      { amount: "1", unit: "", name: "pincée sel", nutritionQuery: "salt" },
      { amount: "200", unit: "g", name: "farine", nutritionQuery: "flour" },
      { amount: "500", unit: "ml", name: "lait", nutritionQuery: "milk" },
      { amount: "", unit: "", name: "je vais l'ajouter en plusieurs fois", nutritionQuery: "" },
      { amount: "", unit: "", name: "fois en tout.", nutritionQuery: "" },
      { amount: "", unit: "", name: "c'est 1 toute petite louche.", nutritionQuery: "" },
      { amount: "", unit: "", name: "Et ensuite", nutritionQuery: "" },
      { amount: "", unit: "", name: "on a", nutritionQuery: "" },
      { amount: "", unit: "", name: "C'est super simple à faire", nutritionQuery: "" },
      { amount: "", unit: "", name: "c'est délicieux.", nutritionQuery: "" },
      { amount: "", unit: "", name: "Crêpes Pierre Hermé", nutritionQuery: "" }
    ],
    stepDrafts: [],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "4",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "Crêpes",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/444555666"
  });

  assert.equal(response.success, true);

  if (!response.success) {
    assert.fail("expected a success response");
  }

  const ingredientNames = response.data.ingredients.map((ingredient) => ingredient.name.toLowerCase());
  assert.equal(
    ingredientNames.some((name) =>
      /ajouter en plusieurs fois|fois en tout|toute petite louche|et ensuite|on a|super simple|delicieux|pierre herme/.test(name)
    ),
    false
  );
  assert.ok(ingredientNames.includes("farine"));
  assert.ok(ingredientNames.includes("lait"));
  assert.ok(ingredientNames.includes("oeufs"));
});

test("buildURLImportResponse expands a naan sandwich import into a fuller multi-step recipe", async () => {
  const recipe: RecipeImportResult = {
    title: "Sandwich Naan",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/777888999",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "300", unit: "g", name: "farine", nutritionQuery: "flour" },
      { amount: "6", unit: "g", name: "levure deshydratee", nutritionQuery: "dry yeast" },
      { amount: "125", unit: "g", name: "yaourt nature", nutritionQuery: "plain yogurt" },
      { amount: "60", unit: "ml", name: "eau tiede", nutritionQuery: "water" },
      { amount: "30", unit: "g", name: "beurre mou", nutritionQuery: "butter" },
      { amount: "320", unit: "g", name: "blanc de poulet", nutritionQuery: "chicken breast" },
      { amount: "2", unit: "", name: "flatbread", nutritionQuery: "flatbread" },
      { amount: "2", unit: "tranches", name: "cheddar", nutritionQuery: "cheddar cheese" },
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "onion" },
      { amount: "60", unit: "g", name: "salade", nutritionQuery: "lettuce" },
      { amount: "2", unit: "cas", name: "sauce yaourt", nutritionQuery: "yogurt sauce" }
    ],
    stepDrafts: [
      { detail: "Preparez les garnitures en emincant l'oignon et en assaisonnant le poulet." },
      { detail: "Faites cuire le poulet dans une poele chaude jusqu'a ce qu'il soit bien dore." },
      { detail: "Toastez le flatbread puis preparez la garniture avec la salade et la sauce." },
      { detail: "Montez le sandwich naan avec le flatbread, le poulet et les garnitures." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "Sandwich Naan recette",
    inferredFromPhoto: false
  };

  const response = await buildURLImportResponse({
    recipe,
    sourceUrl: "https://www.tiktok.com/@cooksy/video/777888999"
  });

  assert.equal(response.success, true);

  if (!response.success) {
    assert.fail("expected a success response");
  }

  assert.ok(response.data.steps.length >= 6);
  assert.ok(response.data.steps.some((step) => /levure|pate|pâte|naan/i.test(step.description)));
  assert.ok(response.data.steps.some((step) => /poulet|sauce|salade/i.test(step.description)));
});
