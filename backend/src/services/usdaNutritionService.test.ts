import test from "node:test";
import assert from "node:assert/strict";

import { enrichRecipeNutrition } from "./usdaNutritionService.js";
import type { RecipeImportResult } from "../types/recipe.js";

test("enrichRecipeNutrition computes per-serving values from USDA matches", async () => {
  const recipe: RecipeImportResult = {
    title: "Poulet saute",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "100", unit: "g", name: "blanc de poulet", nutritionQuery: "chicken breast" },
      { amount: "1", unit: "c. a soupe", name: "huile d'olive", nutritionQuery: "olive oil" }
    ],
    stepDrafts: [
      { detail: "Faites cuire le poulet." },
      { detail: "Ajoutez l'huile et servez." }
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

  const mockFetch: typeof fetch = async (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    assert.match(url, /api_key=test-key/);
    const body = JSON.parse(String(init?.body ?? "{}")) as { query?: string };

    return {
      ok: true,
      async json() {
        if (url.includes("foods/search")) {
          return {
            foods: body.query?.includes("olive")
              ? [
                {
                  fdcId: 1,
                  description: "Oil, olive, salad or cooking",
                  dataType: "Foundation",
                  foodNutrients: [
                    { nutrientNumber: "208", value: 884 },
                    { nutrientNumber: "203", value: 0 },
                    { nutrientNumber: "205", value: 0 },
                    { nutrientNumber: "204", value: 100 }
                  ]
                }
              ]
              : [
                {
                  fdcId: 2,
                  description: "Chicken, broilers or fryers, breast, meat only, cooked, roasted",
                  dataType: "SR Legacy",
                  foodNutrients: [
                    { nutrientNumber: "208", value: 165 },
                    { nutrientNumber: "203", value: 31 },
                    { nutrientNumber: "205", value: 0 },
                    { nutrientNumber: "204", value: 3.6 }
                  ]
                }
              ]
          };
        }

        return {};
      }
    } as Response;
  };

  const result = await enrichRecipeNutrition(recipe, {
    apiKey: "test-key",
    enabled: true,
    fetchImpl: mockFetch
  });

  assert.equal(result.usedUsda, true);
  assert.equal(result.matchedIngredients, 2);
  assert.equal(result.nutritionCoverage, 1);
  assert.equal(result.recipe.caloriesText, "143 kcal");
  assert.equal(result.recipe.proteinText, "15,5 g");
  assert.equal(result.recipe.carbsText, "0 g");
  assert.equal(result.recipe.fatText, "8,6 g");
});
