import test from "node:test";
import assert from "node:assert/strict";

import {
  makeSnapshot,
  buildCleanedPrimarySnapshot,
  selectBestSnapshot,
  type PipelineSnapshot,
} from "./pipelineSnapshots.js";
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

function cleanRecipe(): RecipeImportResult {
  return makeRecipe({
    title: "Poulet au curry coco",
    ingredientDrafts: [
      { amount: "400", unit: "g", name: "blanc de poulet", nutritionQuery: "", group: "" },
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "", group: "" },
      { amount: "2", unit: "c. à s.", name: "curry", nutritionQuery: "", group: "" },
    ],
    stepDrafts: [{ detail: "Faire revenir le poulet", section: "" }],
  });
}

test("buildCleanedPrimarySnapshot: tagged as baseline", () => {
  const snap = buildCleanedPrimarySnapshot(cleanRecipe());
  assert.equal(snap.stage, "cleaned_primary");
  assert.equal(snap.isBaseline, true);
  assert.equal(snap.ingredientCount, 3);
});

test("selectBestSnapshot: baseline-only input returns baseline", () => {
  const baseline = buildCleanedPrimarySnapshot(cleanRecipe());
  const chosen = selectBestSnapshot([baseline]);
  assert.equal(chosen, baseline);
});

test("selectBestSnapshot: candidate that degrades food coverage is filtered → baseline wins", () => {
  const baseline = buildCleanedPrimarySnapshot(cleanRecipe());
  const degraded = makeSnapshot(
    "llm_full",
    makeRecipe({
      title: "Poulet",
      ingredientDrafts: [
        { amount: "", unit: "", name: "stuff", nutritionQuery: "", group: "" },
        { amount: "", unit: "", name: "thing", nutritionQuery: "", group: "" },
        { amount: "", unit: "", name: "other", nutritionQuery: "", group: "" },
      ],
      stepDrafts: [{ detail: "Do something", section: "" }],
    })
  );
  const chosen = selectBestSnapshot([baseline, degraded]);
  assert.equal(chosen.isBaseline, true);
});

test("selectBestSnapshot: candidate that beats baseline on every axis wins", () => {
  const baseline = buildCleanedPrimarySnapshot(cleanRecipe());
  const enriched = makeSnapshot(
    "llm_preservation",
    makeRecipe({
      title: "Poulet au curry coco",
      ingredientDrafts: [
        { amount: "400", unit: "g", name: "blanc de poulet", nutritionQuery: "", group: "" },
        { amount: "1", unit: "", name: "oignon rouge", nutritionQuery: "", group: "" },
        { amount: "2", unit: "c. à s.", name: "curry", nutritionQuery: "", group: "" },
        { amount: "200", unit: "ml", name: "lait de coco", nutritionQuery: "", group: "" },
      ],
      stepDrafts: [
        { detail: "Couper le poulet", section: "" },
        { detail: "Faire revenir le poulet", section: "" },
        { detail: "Ajouter le lait de coco", section: "" },
      ],
    })
  );
  const chosen = selectBestSnapshot([baseline, enriched]);
  assert.equal(chosen.stage, "llm_preservation");
});

test("selectBestSnapshot: ingredient count 10% slack allows legitimate dedupe", () => {
  const baseline = buildCleanedPrimarySnapshot(
    makeRecipe({
      ingredientDrafts: Array.from({ length: 10 }, (_, i) => ({
        amount: "1", unit: "", name: `poulet ${i}`, nutritionQuery: "", group: "",
      })),
    })
  );
  const dedup = makeSnapshot(
    "compiler_enriched",
    makeRecipe({
      ingredientDrafts: Array.from({ length: 9 }, (_, i) => ({
        amount: "1", unit: "", name: `poulet ${i}`, nutritionQuery: "", group: "",
      })),
    })
  );
  const chosen = selectBestSnapshot([baseline, dedup]);
  assert.equal(chosen.stage, "compiler_enriched");
});

test("selectBestSnapshot: more-than-10% ingredient drop triggers baseline", () => {
  const baseline = buildCleanedPrimarySnapshot(
    makeRecipe({
      ingredientDrafts: Array.from({ length: 10 }, (_, i) => ({
        amount: "1", unit: "", name: `poulet ${i}`, nutritionQuery: "", group: "",
      })),
    })
  );
  const lossy = makeSnapshot(
    "llm_full",
    makeRecipe({
      ingredientDrafts: Array.from({ length: 7 }, (_, i) => ({
        amount: "1", unit: "", name: `poulet ${i}`, nutritionQuery: "", group: "",
      })),
    })
  );
  const chosen = selectBestSnapshot([baseline, lossy]);
  assert.equal(chosen.isBaseline, true);
});

test("selectBestSnapshot: later stage wins tiebreaker when all else equal", () => {
  const recipe = cleanRecipe();
  const baseline = buildCleanedPrimarySnapshot(recipe);
  const enriched = makeSnapshot("compiler_enriched", recipe);
  const validated = makeSnapshot("validated", recipe);
  const chosen = selectBestSnapshot([baseline, enriched, validated]);
  assert.equal(chosen.stage, "validated");
});

test("selectBestSnapshot: food coverage beats specificity in tiebreaker order", () => {
  const baseline = buildCleanedPrimarySnapshot(
    makeRecipe({
      ingredientDrafts: [
        { amount: "", unit: "", name: "poulet", nutritionQuery: "", group: "" },
      ],
    })
  );
  const highFood = makeSnapshot(
    "compiler_enriched",
    makeRecipe({
      ingredientDrafts: [
        { amount: "", unit: "", name: "blanc de poulet", nutritionQuery: "", group: "" },
        { amount: "", unit: "", name: "oignon rouge", nutritionQuery: "", group: "" },
      ],
    })
  );
  const chosen = selectBestSnapshot([baseline, highFood]);
  assert.equal(chosen.stage, "compiler_enriched");
});

test("selectBestSnapshot: defensive — no baseline returns first", () => {
  const a = makeSnapshot("compiler_enriched", cleanRecipe());
  const chosen = selectBestSnapshot([a]);
  assert.equal(chosen, a);
});
