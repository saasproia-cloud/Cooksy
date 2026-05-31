import type { NutritionPatch, RecipeContext } from "./chatTypes.js";

/**
 * Lightweight nutrition recalculation for an ingredient swap.
 *
 * The LLM already proposes a `nutritionAfter` block in its diff (it sees
 * the current per-serving values and the swap). This helper guards the
 * model output:
 *  - drops absurd deltas (>50% change in calories without a sane reason)
 *  - keeps the original numbers when the model returns nothing
 *
 * A future iteration can plug the existing USDA pipeline here to ground
 * the deltas on real per-ingredient nutrient values; the public shape
 * stays identical so the iOS contract is forward-compatible.
 */

const MAX_RELATIVE_DELTA = 0.5;

export function reconcileNutritionForSwap(
  context: RecipeContext,
  proposedAfter: NutritionPatch | null | undefined
): NutritionPatch | null {
  const baseline = context.nutritionPerServing;
  if (!baseline) {
    return proposedAfter ?? null;
  }
  if (!proposedAfter) {
    return baseline;
  }

  return {
    calories: clampMacroChange(baseline.calories ?? null, proposedAfter.calories ?? null),
    protein: clampMacroChange(baseline.protein ?? null, proposedAfter.protein ?? null),
    carbs: clampMacroChange(baseline.carbs ?? null, proposedAfter.carbs ?? null),
    fat: clampMacroChange(baseline.fat ?? null, proposedAfter.fat ?? null),
    fiber: proposedAfter.fiber ?? baseline.fiber ?? null,
    sugar: proposedAfter.sugar ?? baseline.sugar ?? null,
    salt: proposedAfter.salt ?? baseline.salt ?? null,
    saturatedFat: proposedAfter.saturatedFat ?? baseline.saturatedFat ?? null
  };
}

/**
 * Caps the relative drift between `baseline` and `proposed`. If the model
 * suggests a per-serving calorie change of more than 50 % from a single
 * ingredient swap, we treat it as a hallucination and stick with the
 * original number. Stops a bad suggestion from spraying garbage onto the
 * recipe card.
 */
function clampMacroChange(baseline: string | null, proposed: string | null): string | null {
  if (proposed == null) return baseline;
  if (baseline == null) return proposed;

  const baselineNumeric = parseLeadingNumber(baseline);
  const proposedNumeric = parseLeadingNumber(proposed);
  if (baselineNumeric == null || proposedNumeric == null) {
    return proposed;
  }
  if (baselineNumeric <= 0) {
    return proposed;
  }

  const relativeDelta = Math.abs(proposedNumeric - baselineNumeric) / baselineNumeric;
  if (relativeDelta > MAX_RELATIVE_DELTA) {
    return baseline;
  }
  return proposed;
}

function parseLeadingNumber(value: string): number | null {
  const match = value.match(/-?\d+(?:[\.,]\d+)?/);
  if (!match) return null;
  const numeric = Number.parseFloat(match[0].replace(",", "."));
  return Number.isFinite(numeric) ? numeric : null;
}
