import test from "node:test";
import assert from "node:assert/strict";

import { sanitizeRecipeImport, type RecipeImportResult } from "./recipe.js";

test("sanitizeRecipeImport strips obvious transcript fragments from ingredients and steps", () => {
  const sanitized = sanitizeRecipeImport({
    title: "Crêpes Pierre Hermé",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/123456",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "250", unit: "g", name: "farine", nutritionQuery: "flour" },
      { amount: "", unit: "", name: "je vais l'ajouter en plusieurs fois", nutritionQuery: "" },
      { amount: "", unit: "", name: "fois en tout", nutritionQuery: "" },
      { amount: "", unit: "", name: "C'est super simple à faire", nutritionQuery: "" }
    ],
    stepDrafts: [
      { detail: "Et ensuite" },
      { detail: "On a" },
      { detail: "C'est délicieux." },
      { detail: "Mélangez la farine avec le lait et les oeufs." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "Crêpes",
    inferredFromPhoto: false
  } satisfies RecipeImportResult);

  assert.deepEqual(
    sanitized.ingredientDrafts.map((ingredient) => ingredient.name),
    ["farine"]
  );
  assert.deepEqual(
    sanitized.stepDrafts.map((step) => step.detail),
    ["Mélangez la farine avec le lait et les oeufs."]
  );
});
