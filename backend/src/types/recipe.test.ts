import test from "node:test";
import assert from "node:assert/strict";

import { sanitizeRecipeImport, shouldFallbackToSearch } from "./recipe.js";

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
