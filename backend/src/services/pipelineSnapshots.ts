// =====================================================================
// pipelineSnapshots — non-degradation guarantee (plan §10).
//
// At each stage transition the pipeline can emit a PipelineSnapshot.
// Before returning a final recipe, selectBestSnapshot() picks the
// strongest candidate whose critical metrics are at least as good as
// the mandatory cleaned_primary baseline on every dimension that
// matters: food-signal coverage, specificity, section count, and
// ingredient retention. If no candidate beats the baseline on every
// dimension, the baseline itself is returned — guaranteeing the final
// output is never worse than the cleaned source.
// =====================================================================

import type { RecipeImportResult } from "../types/recipe.js";
import { containsFoodSignal } from "./foodTermGate.js";

export type SnapshotStage =
  | "cleaned_primary"
  | "compiler_raw"
  | "compiler_enriched"
  | "llm_preservation"
  | "llm_full"
  | "validated";

export interface PipelineSnapshot {
  stage: SnapshotStage;
  recipe: RecipeImportResult;
  /** Overall 0..1 quality heuristic (coarse; used as tiebreaker). */
  quality: number;
  ingredientCount: number;
  stepCount: number;
  sectionCount: number;
  /** Mean token-count of ingredient names — higher = more specific. */
  specificityScore: number;
  /** Fraction of ingredients whose name passes the food-term gate. */
  foodSignalCoverage: number;
  /** True ONLY for cleaned_primary — the mandatory baseline. */
  isBaseline: boolean;
}

function sectionCountOf(recipe: RecipeImportResult): number {
  const names = new Set<string>();
  for (const ing of recipe.ingredientDrafts) {
    names.add((ing.group ?? "").trim());
  }
  return names.size;
}

function specificityOf(recipe: RecipeImportResult): number {
  if (recipe.ingredientDrafts.length === 0) return 0;
  let total = 0;
  for (const ing of recipe.ingredientDrafts) {
    total += (ing.name ?? "").trim().split(/\s+/).filter(Boolean).length;
  }
  return total / recipe.ingredientDrafts.length;
}

function foodCoverageOf(recipe: RecipeImportResult): number {
  if (recipe.ingredientDrafts.length === 0) return 0;
  let hits = 0;
  for (const ing of recipe.ingredientDrafts) {
    if (containsFoodSignal(ing.name ?? "")) hits += 1;
  }
  return hits / recipe.ingredientDrafts.length;
}

/**
 * Lightweight 0..1 quality heuristic used only as a final tiebreaker.
 * The primary selection axis is the baseline-comparison filter.
 */
function qualityOf(recipe: RecipeImportResult): number {
  const ingredients = Math.min(recipe.ingredientDrafts.length / 8, 1);
  const steps = Math.min(recipe.stepDrafts.length / 6, 1);
  const hasTitle = (recipe.title ?? "").trim().length >= 3 ? 1 : 0;
  const hasMacros = Boolean(
    recipe.caloriesText?.trim() &&
      recipe.proteinText?.trim() &&
      recipe.carbsText?.trim() &&
      recipe.fatText?.trim()
  )
    ? 1
    : 0;
  return ingredients * 0.4 + steps * 0.3 + hasTitle * 0.15 + hasMacros * 0.15;
}

export function makeSnapshot(
  stage: SnapshotStage,
  recipe: RecipeImportResult,
  options: { isBaseline?: boolean } = {}
): PipelineSnapshot {
  return {
    stage,
    recipe,
    quality: qualityOf(recipe),
    ingredientCount: recipe.ingredientDrafts.length,
    stepCount: recipe.stepDrafts.length,
    sectionCount: sectionCountOf(recipe),
    specificityScore: specificityOf(recipe),
    foodSignalCoverage: foodCoverageOf(recipe),
    isBaseline: Boolean(options.isBaseline),
  };
}

export function buildCleanedPrimarySnapshot(
  cleanedPrimaryRecipe: RecipeImportResult
): PipelineSnapshot {
  return makeSnapshot("cleaned_primary", cleanedPrimaryRecipe, { isBaseline: true });
}

/**
 * Non-degradation selection (plan §10).
 *
 * Candidates that fail to match the baseline on EVERY critical
 * dimension are dropped. If no candidate beats the baseline, the
 * baseline itself wins.
 *
 * Tiebreakers, in order:
 *   1. higher foodSignalCoverage
 *   2. higher specificityScore
 *   3. higher sectionCount
 *   4. higher overall quality
 *   5. later stage wins (more processing completed)
 */
export function selectBestSnapshot(
  candidates: PipelineSnapshot[]
): PipelineSnapshot {
  const baseline = candidates.find((c) => c.isBaseline);
  if (!baseline) {
    // Defensive: if no baseline was provided, fall back to the first
    // candidate. Callers are expected to always include a baseline but
    // we don't want to throw in production.
    return candidates[0];
  }

  // Filter by the non-degradation contract. Ingredient retention is
  // permitted a 10% slack so normalization that legitimately merges
  // duplicates does not force the baseline to win.
  const kept = candidates.filter(
    (c) =>
      c.foodSignalCoverage >= baseline.foodSignalCoverage &&
      c.specificityScore >= baseline.specificityScore &&
      c.sectionCount >= baseline.sectionCount &&
      c.ingredientCount >= baseline.ingredientCount * 0.9
  );

  if (kept.length === 0) return baseline;

  const stageOrder: SnapshotStage[] = [
    "cleaned_primary",
    "compiler_raw",
    "compiler_enriched",
    "llm_preservation",
    "llm_full",
    "validated",
  ];

  kept.sort((a, b) => {
    if (a.foodSignalCoverage !== b.foodSignalCoverage) {
      return b.foodSignalCoverage - a.foodSignalCoverage;
    }
    if (a.specificityScore !== b.specificityScore) {
      return b.specificityScore - a.specificityScore;
    }
    if (a.sectionCount !== b.sectionCount) {
      return b.sectionCount - a.sectionCount;
    }
    if (a.quality !== b.quality) {
      return b.quality - a.quality;
    }
    return stageOrder.indexOf(b.stage) - stageOrder.indexOf(a.stage);
  });

  return kept[0];
}
