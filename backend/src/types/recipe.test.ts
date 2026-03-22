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
