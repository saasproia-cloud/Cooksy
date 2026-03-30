import test from "node:test";
import assert from "node:assert/strict";

import {
  hasCookabilityGaps,
  sanitizeRecipeImport,
  shouldFallbackToSearch
} from "./recipe.js";

test("sanitizeRecipeImport removes article-like noise from ingredients and steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "94 TikTok Recipes That Are Easy to Make and Actually Taste Good",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "", unit: "", name: "Read More celebrity travel fashion newsletter", nutritionQuery: "" },
      { amount: "2", unit: "", name: "oeufs", nutritionQuery: "egg" },
      { amount: "150", unit: "g", name: "farine", nutritionQuery: "flour" },
      { amount: "50", unit: "g", name: "sucre", nutritionQuery: "sugar" }
    ],
    stepDrafts: [
      { detail: "View post and follow for more celebrity news." },
      { detail: "Mélangez les oeufs avec le sucre." },
      { detail: "Ajoutez la farine puis faites cuire 20 minutes." }
    ],
    notesText: "Read More\nQuelques notes utiles.",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.ingredientDrafts.length, 3);
  assert.equal(sanitized.stepDrafts.length, 2);
  assert.equal(sanitized.confidence, "low");
  assert.equal(sanitized.needsWebFallback, true);
  assert.match(sanitized.notesText, /Quelques notes utiles/);
  assert.equal(shouldFallbackToSearch(sanitized), true);
});

test("sanitizeRecipeImport trims polluted titles and drops transcript timestamps from steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "SMASH BURGER 🍔 Ingrédients pour 2 burgers : - 1 oignon - 1 cas de sucre - 2 cas de worcester sauce",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "onion" },
      { amount: "1", unit: "cas", name: "sucre", nutritionQuery: "sugar" },
      { amount: "2", unit: "", name: "steaks", nutritionQuery: "beef patty" }
    ],
    stepDrafts: [
      { detail: "On va commencer par faire des oignons caramélisés, tu les coupes en lamelles et tu les fais cuire dans de l'huile." },
      { detail: "00:00:00.080 -->" },
      { detail: "00:00:00.840" },
      { detail: "J'espère que cette recette t'aura plu et que tu vas la refaire." },
      { detail: "Mettre 1 couvercle par-dessus pour qu'il puisse fondre." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "low",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.title, "Smash Burger");
  assert.equal(sanitized.stepDrafts.length, 2);
  assert.equal(sanitized.stepDrafts.some((step) => step.detail.includes("-->")), false);
  assert.equal(sanitized.stepDrafts.some((step) => /00:00:00/.test(step.detail)), false);
});

test("sanitizeRecipeImport drops incomplete spoken fragments from steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Chicken Wrap",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "wraps", nutritionQuery: "flour tortilla" },
      { amount: "300", unit: "g", name: "poulet", nutritionQuery: "chicken breast" },
      { amount: "80", unit: "g", name: "salade", nutritionQuery: "lettuce" }
    ],
    stepDrafts: [
      { detail: "Ensuite je vais prendre" },
      { detail: "et après voilà" },
      { detail: "Assaisonnez le poulet puis faites-le cuire dans une poele chaude." },
      { detail: "Rabattez les cotes, roulez le wrap et servez immediatement." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.stepDrafts.length, 2);
  assert.equal(sanitized.stepDrafts.some((step) => /ensuite je vais prendre|et après voilà/i.test(step.detail)), false);
});

test("sanitizeRecipeImport shortens verbose social titles and drops commentary-only steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "ANIMAL FRIES CAJUN Les Animal Fries d’un fast food qu’on a pas ici, mais avec plus de muscles et moins de gras",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "400", unit: "g", name: "pommes de terre", nutritionQuery: "potato" },
      { amount: "420", unit: "g", name: "viande hachée 5 %", nutritionQuery: "lean ground beef" },
      { amount: "2", unit: "tranches", name: "cheddar fondu", nutritionQuery: "cheddar cheese" }
    ],
    stepDrafts: [
      { detail: "Si t'en as pas, pas de souci, je t'explique comment faire ton mix maison dans les commentaires." },
      { detail: "Faites cuire les pommes de terre au air fryer puis secouez-les toutes les 5 minutes." },
      { detail: "Ajoutez le cheddar sur la viande chaude et laissez fondre avec un trait d'eau." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.title, "Animal Fries Cajun");
  assert.equal(sanitized.stepDrafts.length, 2);
  assert.equal(
    sanitized.stepDrafts.some((step) => step.detail.includes("commentaires")),
    false
  );
});

test("sanitizeRecipeImport rejects social hook titles and forces web fallback", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Réponse à @celia Maintenant vous n'avez plus d'excuses",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "pains burger", nutritionQuery: "hamburger bun" },
      { amount: "2", unit: "", name: "hot tenders", nutritionQuery: "chicken tenders" },
      { amount: "2", unit: "cas", name: "coleslaw", nutritionQuery: "coleslaw" }
    ],
    stepDrafts: [
      { detail: "Grillez les pains puis ajoutez les hot tenders." },
      { detail: "Ajoutez le coleslaw et refermez les burgers." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.title, "");
  assert.equal(sanitized.needsWebFallback, true);
  assert.equal(shouldFallbackToSearch(sanitized), true);
});

test("sanitizeRecipeImport splits merged ingredient entries into distinct ingredients", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Burger maison",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "tranches", name: "emmental/cornichon", nutritionQuery: "emmental cheese/pickle" },
      { amount: "", unit: "", name: "ketchup...mayonnaise", nutritionQuery: "ketchup...mayonnaise" },
      { amount: "2", unit: "", name: "steaks", nutritionQuery: "beef patties" }
    ],
    stepDrafts: [
      { detail: "Faites cuire les steaks puis montez les burgers." },
      { detail: "Ajoutez l'emmental, les cornichons et les sauces avant de servir." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.deepEqual(
    sanitized.ingredientDrafts.map((ingredient) => ingredient.name),
    ["emmental", "cornichon", "ketchup", "mayonnaise", "steaks"]
  );
  assert.equal(sanitized.ingredientDrafts[0]?.amount, "2");
  assert.equal(sanitized.ingredientDrafts[1]?.amount, "");
});

test("sanitizeRecipeImport splits merged ingredient entries joined by commas and conjunctions", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Burger maison",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "", unit: "", name: "ketchup, mayonnaise", nutritionQuery: "ketchup, mayonnaise" },
      { amount: "", unit: "", name: "cheddar et cornichons", nutritionQuery: "cheddar cheese and pickle" },
      { amount: "2", unit: "", name: "steaks", nutritionQuery: "beef patties" }
    ],
    stepDrafts: [
      { detail: "Faites cuire les steaks puis montez les burgers." },
      { detail: "Ajoutez le cheddar, les cornichons et les sauces avant de servir." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.deepEqual(
    sanitized.ingredientDrafts.map((ingredient) => ingredient.name),
    ["ketchup", "mayonnaise", "cheddar", "cornichons", "steaks"]
  );
});

test("hasCookabilityGaps detects when major ingredients are not reflected in steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Burger maison",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "pains burger", nutritionQuery: "hamburger bun" },
      { amount: "2", unit: "", name: "steaks", nutritionQuery: "beef patties" },
      { amount: "2", unit: "tranches", name: "emmental", nutritionQuery: "emmental cheese" },
      { amount: "4", unit: "", name: "cornichons", nutritionQuery: "pickle" }
    ],
    stepDrafts: [
      { detail: "Faites cuire les steaks." },
      { detail: "Servez bien chaud." }
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
  });

  assert.equal(hasCookabilityGaps(sanitized), true);
  assert.equal(shouldFallbackToSearch(sanitized), true);
});

test("sanitizeRecipeImport keeps simple complete recipes stable without forcing web fallback", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Omelette fromage",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "3", unit: "", name: "oeufs", nutritionQuery: "egg" },
      { amount: "30", unit: "g", name: "gruyere", nutritionQuery: "gruyere cheese" },
      { amount: "10", unit: "g", name: "beurre", nutritionQuery: "butter" }
    ],
    stepDrafts: [
      { detail: "Ajoutez une pincee de sel aux oeufs puis melangez." },
      { detail: "Faites fondre le beurre dans une poele puis versez les oeufs." },
      { detail: "Ajoutez le fromage, repliez l'omelette et servez." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "1",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.needsWebFallback, false);
  assert.equal(shouldFallbackToSearch(sanitized), false);
});

test("sanitizeRecipeImport keeps compact two-step recipes without forcing web fallback", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Burger poulet",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "pains burger", nutritionQuery: "hamburger bun" },
      { amount: "2", unit: "", name: "steaks de poulet", nutritionQuery: "chicken patty" },
      { amount: "2", unit: "tranches", name: "cheddar", nutritionQuery: "cheddar cheese" }
    ],
    stepDrafts: [
      { detail: "Faites cuire le poulet." },
      { detail: "Montez les burgers et servez." }
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
    searchQuery: "",
    inferredFromPhoto: false
  });

  assert.equal(sanitized.needsWebFallback, false);
  assert.equal(shouldFallbackToSearch(sanitized), false);
});
