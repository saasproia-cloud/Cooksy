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
  assert.equal(result.recipe.flags?.generatedNutrition, true);
});

test("enrichRecipeNutrition blends USDA matches with fallback estimates when the recipe is only partially covered", async () => {
  const recipe: RecipeImportResult = {
    title: "Burger poulet",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "180", unit: "g", name: "blanc de poulet", nutritionQuery: "chicken breast" },
      { amount: "1", unit: "c. a soupe", name: "huile d'olive", nutritionQuery: "olive oil" },
      { amount: "2", unit: "", name: "cornichons", nutritionQuery: "pickle" },
      { amount: "2", unit: "tranches", name: "emmental", nutritionQuery: "emmental cheese" },
      { amount: "1", unit: "", name: "sauce maison", nutritionQuery: "mystery relish" },
      { amount: "1", unit: "", name: "pain burger artisanal", nutritionQuery: "artisan bun surprise" }
    ],
    stepDrafts: [
      { detail: "Faites cuire le poulet." },
      { detail: "Montez le burger et servez." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "220 kcal",
    proteinText: "5 g",
    carbsText: "12 g",
    fatText: "7 g",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  };

  const mockFetch: typeof fetch = async (input, init) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as { query?: string };

    return {
      ok: true,
      async json() {
        if (body.query?.includes("olive")) {
          return {
            foods: [
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
          };
        }

        if (body.query?.includes("chicken")) {
          return {
            foods: [
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

        return { foods: [] };
      }
    } as Response;
  };

  const result = await enrichRecipeNutrition(recipe, {
    apiKey: "test-key",
    enabled: true,
    fetchImpl: mockFetch
  });

  assert.equal(result.usedUsda, true);
  assert.equal(result.matchedIngredients, 5);
  assert.equal(result.nutritionCoverage > 0.8, true);
  assert.equal(result.recipe.proteinText, "31,4 g");
  assert.equal(result.recipe.caloriesText, "319 kcal");
});

test("enrichRecipeNutrition infers burger servings and implicit condiment amounts from the final recipe", async () => {
  const recipe: RecipeImportResult = {
    title: "Burger tenders",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "2", unit: "", name: "hot tenders", nutritionQuery: "hot tenders" },
      { amount: "2", unit: "", name: "pain burger", nutritionQuery: "pain burger" },
      { amount: "", unit: "", name: "coleslaw", nutritionQuery: "coleslaw" },
      { amount: "", unit: "", name: "mayonnaise maison", nutritionQuery: "mayonnaise" }
    ],
    stepDrafts: [
      { detail: "Faites cuire les tenders." },
      { detail: "Montez les burgers avec le coleslaw et la mayonnaise." }
    ],
    notesText: "",
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
  };

  const mockFetch: typeof fetch = async (_input, init) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as { query?: string };

    return {
      ok: true,
      async json() {
        if (body.query?.includes("chicken tenders")) {
          return {
            foods: [
              {
                fdcId: 1,
                description: "Chicken tenders, breaded, cooked",
                dataType: "SR Legacy",
                foodNutrients: [
                  { nutrientNumber: "208", value: 220 },
                  { nutrientNumber: "203", value: 14 },
                  { nutrientNumber: "205", value: 16 },
                  { nutrientNumber: "204", value: 10 }
                ]
              }
            ]
          };
        }

        if (body.query?.includes("hamburger bun")) {
          return {
            foods: [
              {
                fdcId: 2,
                description: "Hamburger bun, plain",
                dataType: "SR Legacy",
                foodNutrients: [
                  { nutrientNumber: "208", value: 280 },
                  { nutrientNumber: "203", value: 9 },
                  { nutrientNumber: "205", value: 52 },
                  { nutrientNumber: "204", value: 4 }
                ]
              }
            ]
          };
        }

        if (body.query?.includes("coleslaw")) {
          return {
            foods: [
              {
                fdcId: 3,
                description: "Coleslaw salad",
                dataType: "SR Legacy",
                foodNutrients: [
                  { nutrientNumber: "208", value: 150 },
                  { nutrientNumber: "203", value: 1 },
                  { nutrientNumber: "205", value: 12 },
                  { nutrientNumber: "204", value: 10 }
                ]
              }
            ]
          };
        }

        if (body.query?.includes("mayonnaise")) {
          return {
            foods: [
              {
                fdcId: 4,
                description: "Mayonnaise, regular",
                dataType: "SR Legacy",
                foodNutrients: [
                  { nutrientNumber: "208", value: 680 },
                  { nutrientNumber: "203", value: 1 },
                  { nutrientNumber: "205", value: 1 },
                  { nutrientNumber: "204", value: 75 }
                ]
              }
            ]
          };
        }

        return { foods: [] };
      }
    } as Response;
  };

  const result = await enrichRecipeNutrition(recipe, {
    apiKey: "test-key",
    enabled: true,
    fetchImpl: mockFetch
  });

  assert.equal(result.usedUsda, true);
  assert.equal(result.matchedIngredients, 4);
  assert.equal(result.recipe.caloriesText, "380 kcal");
  assert.equal(result.recipe.proteinText, "13,3 g");
  assert.equal(result.recipe.carbsText, "48,1 g");
  assert.equal(result.recipe.fatText, "14,3 g");
});

test("enrichRecipeNutrition overrides mathematically inconsistent imported nutrition with hybrid coverage", async () => {
  const recipe: RecipeImportResult = {
    title: "Burger poulet",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "180", unit: "g", name: "blanc de poulet", nutritionQuery: "chicken breast" },
      { amount: "1", unit: "c. a soupe", name: "huile d'olive", nutritionQuery: "olive oil" },
      { amount: "2", unit: "", name: "cornichons", nutritionQuery: "pickle" },
      { amount: "2", unit: "tranches", name: "emmental", nutritionQuery: "emmental cheese" },
      { amount: "1", unit: "", name: "sauce maison", nutritionQuery: "mystery relish" },
      { amount: "1", unit: "", name: "pain burger artisanal", nutritionQuery: "artisan bun surprise" }
    ],
    stepDrafts: [
      { detail: "Faites cuire le poulet." },
      { detail: "Montez le burger et servez." }
    ],
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "2",
    caloriesText: "209 kcal",
    proteinText: "27,9 g",
    carbsText: "20 g",
    fatText: "8,6 g",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false
  };

  const mockFetch: typeof fetch = async (_input, init) => {
    const body = JSON.parse(String(init?.body ?? "{}")) as { query?: string };

    return {
      ok: true,
      async json() {
        if (body.query?.includes("olive")) {
          return {
            foods: [
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
          };
        }

        if (body.query?.includes("chicken")) {
          return {
            foods: [
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

        return { foods: [] };
      }
    } as Response;
  };

  const result = await enrichRecipeNutrition(recipe, {
    apiKey: "test-key",
    enabled: true,
    fetchImpl: mockFetch
  });

  assert.equal(result.usedUsda, true);
  assert.equal(result.nutritionCoverage > 0.8, true);
  assert.equal(result.recipe.caloriesText, "319 kcal");
  assert.equal(result.recipe.proteinText, "31,4 g");
  assert.equal(result.recipe.carbsText, "20,3 g");
  assert.equal(result.recipe.fatText, "12,1 g");
});
