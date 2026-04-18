import test from "node:test";
import assert from "node:assert/strict";

import { analyzeGaps } from "./gapAnalyzer.js";
import type { RecipeImportResult } from "../types/recipe.js";

function makeRecipe(overrides: Partial<RecipeImportResult> = {}): RecipeImportResult {
  return {
    title: "Poulet curry",
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
    confidence: "medium",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false,
    ...overrides,
  } as RecipeImportResult;
}

test("analyzeGaps: empty recipe recommends full reconstruction", () => {
  const gaps = analyzeGaps(makeRecipe({ title: "" }));
  assert.equal(gaps.recommendedMode, "full");
  assert.ok(gaps.needsIngredients);
  assert.ok(gaps.needsSteps);
  assert.ok(gaps.needsTitle);
});

test("analyzeGaps: complete recipe recommends none", () => {
  const gaps = analyzeGaps(
    makeRecipe({
      title: "Poulet au curry coco",
      ingredientDrafts: Array.from({ length: 6 }, (_, i) => ({
        amount: "1", unit: "", name: `ingredient ${i}`, nutritionQuery: "", group: "",
      })),
      stepDrafts: Array.from({ length: 4 }, (_, i) => ({ detail: `step ${i + 1}`, section: "" })),
      caloriesText: "500",
      proteinText: "30",
      carbsText: "40",
      fatText: "15",
      prepTimeText: "10 min",
      cookTimeText: "20 min",
      servingsText: "4",
    })
  );
  assert.equal(gaps.recommendedMode, "none");
  assert.equal(gaps.gaps.length, 0);
});

test("analyzeGaps: ingredient-heavy + step-less → preservation mode", () => {
  const gaps = analyzeGaps(
    makeRecipe({
      title: "Smash burger",
      ingredientDrafts: Array.from({ length: 8 }, (_, i) => ({
        amount: "", unit: "", name: `ingredient ${i}`, nutritionQuery: "", group: "",
      })),
      stepDrafts: [],
    })
  );
  assert.equal(gaps.recommendedMode, "preservation");
  assert.ok(gaps.needsSteps);
});

test("analyzeGaps: 3 ingredients + 1 step → preservation mode (nutrition gap)", () => {
  const gaps = analyzeGaps(
    makeRecipe({
      title: "Omelette",
      ingredientDrafts: [
        { amount: "3", unit: "", name: "oeufs", nutritionQuery: "", group: "" },
        { amount: "1", unit: "c. à s.", name: "beurre", nutritionQuery: "", group: "" },
        { amount: "1", unit: "pincée", name: "sel", nutritionQuery: "", group: "" },
      ],
      stepDrafts: [{ detail: "Battre les oeufs et cuire à la poêle", section: "" }],
    })
  );
  assert.equal(gaps.recommendedMode, "preservation");
  assert.ok(gaps.needsNutrition);
});

test("analyzeGaps: 2 ingredients → full reconstruction (too sparse)", () => {
  const gaps = analyzeGaps(
    makeRecipe({
      ingredientDrafts: [
        { amount: "1", unit: "", name: "oeuf", nutritionQuery: "", group: "" },
        { amount: "1", unit: "", name: "lait", nutritionQuery: "", group: "" },
      ],
      stepDrafts: [],
    })
  );
  assert.equal(gaps.recommendedMode, "full");
});

test("analyzeGaps: single-word title flagged generic", () => {
  const gaps = analyzeGaps(makeRecipe({ title: "Sandwich" }));
  assert.ok(gaps.needsTitle);
});

test("analyzeGaps: multi-word title is not flagged", () => {
  const gaps = analyzeGaps(makeRecipe({ title: "Sandwich au pastrami" }));
  assert.equal(gaps.needsTitle, false);
});

test("analyzeGaps: section count reflects group diversity", () => {
  const gaps = analyzeGaps(
    makeRecipe({
      ingredientDrafts: [
        { amount: "", unit: "", name: "a", nutritionQuery: "", group: "Marinade" },
        { amount: "", unit: "", name: "b", nutritionQuery: "", group: "Marinade" },
        { amount: "", unit: "", name: "c", nutritionQuery: "", group: "Sauce" },
        { amount: "", unit: "", name: "d", nutritionQuery: "", group: "" },
      ],
    })
  );
  assert.equal(gaps.sectionCount, 3);
});
