import test from "node:test";
import assert from "node:assert/strict";

import type { RecipeImportResult } from "../types/recipe.js";
import {
  summarizeIssuesForRepairPrompt,
  validateStrictRecipe,
} from "./strictRecipeValidator.js";

function makeRecipe(overrides: Partial<RecipeImportResult> = {}): RecipeImportResult {
  const base: RecipeImportResult = {
    title: "Philly Cheesesteak maison",
    sourceUrl: "https://www.tiktok.com/@cooksy/video/1",
    remoteImageUrl: "",
    ingredientDrafts: [
      { amount: "400", unit: "g", name: "Ribeye", nutritionQuery: "ribeye" },
      { amount: "2", unit: "piece", name: "Pain hoagie", nutritionQuery: "hoagie" },
      { amount: "120", unit: "g", name: "Provolone", nutritionQuery: "provolone" },
      { amount: "1", unit: "piece", name: "Oignon jaune", nutritionQuery: "onion" },
      { amount: "2", unit: "c. à soupe", name: "Beurre", nutritionQuery: "butter" },
      { amount: "1", unit: "c. à café", name: "Sel fin", nutritionQuery: "salt" },
    ],
    stepDrafts: [
      { detail: "Émincez le ribeye en tranches très fines." },
      { detail: "Faites suer l'oignon jaune dans le beurre 5 minutes." },
      { detail: "Saisissez le ribeye à feu vif 2 minutes." },
      { detail: "Salez avec le sel fin et mélangez avec les oignons." },
      { detail: "Couvrez avec des tranches de provolone et laissez fondre." },
      { detail: "Garnissez le pain hoagie avec la viande et servez." },
    ],
    notesText: "",
    prepTimeText: "10",
    cookTimeText: "10",
    servingsText: "2",
    caloriesText: "780",
    proteinText: "48",
    carbsText: "52",
    fatText: "38",
    confidence: "high",
    needsWebFallback: false,
    searchQuery: "",
    inferredFromPhoto: false,
  };
  return { ...base, ...overrides };
}

test("validateStrictRecipe accepts a clean cheesesteak recipe", () => {
  const report = validateStrictRecipe(makeRecipe());
  assert.equal(report.ok, true);
  assert.equal(report.hardIssues.length, 0);
});

test("TITLE_GENERIC fires on suspicious titles", () => {
  const report = validateStrictRecipe(makeRecipe({ title: "Recette à essayer absolument @cooksy" }));
  const codes = report.hardIssues.map((i) => i.code);
  assert.ok(codes.includes("TITLE_GENERIC"));
});

test("STEPS_TOO_FEW fires when step count below minimum", () => {
  const report = validateStrictRecipe(
    makeRecipe({
      stepDrafts: [{ detail: "Mélangez tout et servez." }],
    })
  );
  assert.ok(report.hardIssues.some((i) => i.code === "STEPS_TOO_FEW"));
});

test("INGREDIENTS_TOO_FEW fires on empty list", () => {
  const report = validateStrictRecipe(makeRecipe({ ingredientDrafts: [] }));
  assert.ok(report.hardIssues.some((i) => i.code === "INGREDIENTS_TOO_FEW"));
});

test("STEP_FRAGMENT_NOISE fires on social CTAs", () => {
  const recipe = makeRecipe();
  recipe.stepDrafts = [
    ...recipe.stepDrafts.slice(0, 5),
    { detail: "Abonne-toi pour plus de recettes #cheesesteak" },
  ];
  const report = validateStrictRecipe(recipe);
  assert.ok(report.hardIssues.some((i) => i.code === "STEP_FRAGMENT_NOISE"));
});

test("NUTRITION_INCOMPLETE fires when any macro missing", () => {
  const report = validateStrictRecipe(makeRecipe({ proteinText: "" }));
  assert.ok(report.hardIssues.some((i) => i.code === "NUTRITION_INCOMPLETE"));
});

test("INGREDIENT_NOT_USED_IN_STEPS fires when major ingredient absent from steps", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "100",
    unit: "g",
    name: "Champignons de Paris",
    nutritionQuery: "mushrooms",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(
    report.hardIssues.some((i) => i.code === "INGREDIENT_NOT_USED_IN_STEPS")
  );
});

test("STEP_REFERENCES_MISSING_INGREDIENT fires when steps mention unknown ingredient", () => {
  const recipe = makeRecipe();
  recipe.stepDrafts.push({
    detail: "Ajoutez une cuillère de gochujang pour relever le tout.",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(
    report.hardIssues.some((i) => i.code === "STEP_REFERENCES_MISSING_INGREDIENT")
  );
});

test("INGREDIENT_VAGUE never fires on qualified two-word names", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts = [
    { amount: "1", unit: "", name: "Sauce soja", nutritionQuery: "soy" },
    { amount: "1", unit: "", name: "Fromage frais", nutritionQuery: "cheese" },
    { amount: "1", unit: "", name: "Pain burger", nutritionQuery: "bun" },
    { amount: "1", unit: "", name: "Oignon rouge", nutritionQuery: "onion" },
    ...recipe.ingredientDrafts,
  ];
  const report = validateStrictRecipe(recipe);
  const vague = report.softIssues.find((i) => i.code === "INGREDIENT_VAGUE");
  assert.equal(vague, undefined, `expected no INGREDIENT_VAGUE, got ${vague?.message}`);
});

test("INGREDIENT_VAGUE fires on bare category words", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "1",
    unit: "",
    name: "fromage",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.softIssues.some((i) => i.code === "INGREDIENT_VAGUE"));
});

test("summarizeIssuesForRepairPrompt is deterministic and includes hint", () => {
  const report = validateStrictRecipe(makeRecipe({ proteinText: "" }));
  const summary = summarizeIssuesForRepairPrompt(report.hardIssues);
  assert.ok(summary.includes("NUTRITION_INCOMPLETE"));
  assert.ok(summary.includes("→"));
});

test("NON_FOOD_INGREDIENT fires on non-food entries", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "1",
    unit: "",
    name: "Photo editor",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.hardIssues.some((i) => i.code === "NON_FOOD_INGREDIENT"));
});

test("IMPLAUSIBLE_QUANTITY fires on '30 salade'", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "30",
    unit: "",
    name: "salade",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.hardIssues.some((i) => i.code === "IMPLAUSIBLE_QUANTITY"));
});

test("IMPLAUSIBLE_QUANTITY does NOT fire on '200 g farine'", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "200",
    unit: "g",
    name: "farine",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.equal(report.hardIssues.some((i) => i.code === "IMPLAUSIBLE_QUANTITY"), false);
});

test("DUPLICATE_CROSS_SECTION fires when same ingredient/quantity appears in two sections", () => {
  const recipe = makeRecipe({
    ingredientDrafts: [
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "", group: "Marinade" },
      { amount: "1", unit: "", name: "oignon", nutritionQuery: "", group: "Garniture" },
      { amount: "400", unit: "g", name: "Ribeye", nutritionQuery: "", group: "Marinade" },
      { amount: "2", unit: "piece", name: "Pain hoagie", nutritionQuery: "", group: "Garniture" },
      { amount: "120", unit: "g", name: "Provolone", nutritionQuery: "", group: "Garniture" },
      { amount: "2", unit: "c. à soupe", name: "Beurre", nutritionQuery: "", group: "Marinade" },
    ],
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.softIssues.some((i) => i.code === "DUPLICATE_CROSS_SECTION"));
});

test("INGREDIENT_UNIT_SWAP fires on leading-number name", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "",
    unit: "",
    name: "200 farine",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.hardIssues.some((i) => i.code === "INGREDIENT_UNIT_SWAP"));
});

test("INGREDIENT_UNIT_SWAP fires on orphan article prefix", () => {
  const recipe = makeRecipe();
  recipe.ingredientDrafts.push({
    amount: "",
    unit: "",
    name: "de la crème",
    nutritionQuery: "",
  });
  const report = validateStrictRecipe(recipe);
  assert.ok(report.hardIssues.some((i) => i.code === "INGREDIENT_UNIT_SWAP"));
});
