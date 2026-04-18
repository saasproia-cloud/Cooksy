// =====================================================================
// gapAnalyzer — classifies what is MISSING from a compiled recipe so
// downstream code can pick the narrowest possible LLM mode (preservation
// vs full reconstruction) per plan §10 / Phase 4.
// =====================================================================

import type { RecipeImportResult } from "../types/recipe.js";

export interface GapReport {
  needsTitle: boolean;
  needsIngredients: boolean;
  needsSteps: boolean;
  needsNutrition: boolean;
  needsTimings: boolean;
  needsServings: boolean;

  ingredientCount: number;
  stepCount: number;
  sectionCount: number;

  /** Ordered list of short gap codes for logging / prompt construction. */
  gaps: string[];

  /**
   * Overall LLM mode recommendation. The importService can override but
   * this is the default pick given the gap profile.
   *
   *   "none"         → compiler output is complete, skip LLM entirely
   *   "preservation" → use normalizeRecipePreservationMode (plug gaps
   *                    without restructuring the existing recipe)
   *   "full"         → too thin to preserve; use full reconstruction
   */
  recommendedMode: "none" | "preservation" | "full";
}

const MIN_COMPLETE_INGREDIENTS = 5;
const MIN_COMPLETE_STEPS = 3;
const MIN_PRESERVABLE_INGREDIENTS = 3;
const MIN_PRESERVABLE_STEPS = 1;

function isGeneric(title: string): boolean {
  const trimmed = title.trim();
  if (!trimmed) return true;
  const words = trimmed.split(/\s+/).filter(Boolean);
  // Single-word titles are usually category-level ("Sandwich", "Salade").
  if (words.length <= 1) return true;
  return false;
}

function hasMacroNumbers(r: RecipeImportResult): boolean {
  return Boolean(
    r.caloriesText?.trim() &&
      r.proteinText?.trim() &&
      r.carbsText?.trim() &&
      r.fatText?.trim()
  );
}

export function analyzeGaps(recipe: RecipeImportResult): GapReport {
  const ingredientCount = recipe.ingredientDrafts.length;
  const stepCount = recipe.stepDrafts.length;

  const sectionNames = new Set<string>();
  for (const ing of recipe.ingredientDrafts) {
    const g = (ing.group ?? "").trim();
    sectionNames.add(g);
  }
  const sectionCount = sectionNames.size;

  const needsTitle = isGeneric(recipe.title ?? "");
  const needsIngredients = ingredientCount < MIN_COMPLETE_INGREDIENTS;
  const needsSteps = stepCount < MIN_COMPLETE_STEPS;
  const needsNutrition = !hasMacroNumbers(recipe);
  const needsTimings = !recipe.prepTimeText?.trim() && !recipe.cookTimeText?.trim();
  const needsServings = !recipe.servingsText?.trim();

  const gaps: string[] = [];
  if (needsTitle) gaps.push("title");
  if (needsIngredients) gaps.push("ingredients");
  if (needsSteps) gaps.push("steps");
  if (needsNutrition) gaps.push("nutrition");
  if (needsTimings) gaps.push("timings");
  if (needsServings) gaps.push("servings");

  // Mode selection:
  //   - If we have nothing critical missing → no LLM needed.
  //   - If the compiler produced a preservable backbone (>= 3 ingredients
  //     AND at least 1 step) we use preservation mode even when steps
  //     are thin or nutrition is missing.
  //   - Below that threshold the compiler output is too sparse to
  //     preserve and we fall back to full LLM reconstruction.
  let recommendedMode: GapReport["recommendedMode"];
  if (gaps.length === 0) {
    recommendedMode = "none";
  } else if (
    ingredientCount >= MIN_PRESERVABLE_INGREDIENTS &&
    stepCount >= MIN_PRESERVABLE_STEPS
  ) {
    recommendedMode = "preservation";
  } else if (ingredientCount >= MIN_PRESERVABLE_INGREDIENTS) {
    // Ingredient-heavy but step-less (e.g. a caption listing 10
    // ingredients and no numbered steps). We can still preserve the
    // ingredient backbone and ask the LLM to add steps only.
    recommendedMode = "preservation";
  } else {
    recommendedMode = "full";
  }

  return {
    needsTitle,
    needsIngredients,
    needsSteps,
    needsNutrition,
    needsTimings,
    needsServings,
    ingredientCount,
    stepCount,
    sectionCount,
    gaps,
    recommendedMode,
  };
}
