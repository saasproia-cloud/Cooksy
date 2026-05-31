import type { RecipeContext, RecipeContextIngredient, RecipeContextStep } from "./chatTypes.js";

/**
 * Turns a `recipes` row + the active `recipe_modifications` rows into the
 * compact projection sent to the model.
 *
 * Why a projection rather than the raw jsonb?
 *  - The raw recipe row carries fields the model does not need (heroStyle,
 *    creatorHandle, externalRating…) — that's pure token waste.
 *  - We need to surface `isSwapped` + `originName` so the model can talk
 *    naturally about modifications already applied (and refuse to undo
 *    them silently).
 *  - We cap each step at ~280 chars to keep the system block under a
 *    predictable token budget and let prompt caching pay off.
 */

const STEP_DETAIL_MAX_CHARS = 280;

type RawIngredient = {
  id?: string;
  name?: string;
  amount?: string | null;
  unit?: string | null;
  originIngredientId?: string | null;
  originName?: string | null;
  originAmount?: string | null;
  originUnit?: string | null;
};

type RawStep = {
  id?: string;
  title?: string | null;
  detail?: string;
};

type RawRecipeRow = {
  id: string;
  title: string;
  details?: {
    servings?: string | null;
    prepTimeMinutes?: number | null;
    cookTimeMinutes?: number | null;
  } | null;
  nutrition?: Record<string, string | null | undefined> | null;
  ingredients?: RawIngredient[] | null;
  steps?: RawStep[] | null;
  allergens?: string[] | null;
};

type AppliedModificationRow = {
  id: string;
  kind: string;
  summary: string;
  applied_at: string;
};

export function buildRecipeContext(
  row: RawRecipeRow,
  appliedModifications: AppliedModificationRow[] = []
): RecipeContext {
  const ingredients: RecipeContextIngredient[] = (row.ingredients ?? [])
    .filter((ing): ing is RawIngredient & { id: string; name: string } =>
      typeof ing.id === "string" && typeof ing.name === "string"
    )
    .map((ing) => ({
      id: ing.id,
      name: ing.name,
      amount: ing.amount ?? null,
      unit: ing.unit ?? null,
      isSwapped: Boolean(ing.originIngredientId || ing.originName),
      originName: ing.originName ?? null
    }));

  const steps: RecipeContextStep[] = (row.steps ?? [])
    .filter((step): step is RawStep & { id: string; detail: string } =>
      typeof step.id === "string" && typeof step.detail === "string"
    )
    .map((step) => ({
      id: step.id,
      title: step.title ?? null,
      detail: truncateForContext(step.detail, STEP_DETAIL_MAX_CHARS)
    }));

  const nutrition = row.nutrition
    ? {
        calories: nullableString(row.nutrition.calories),
        protein: nullableString(row.nutrition.protein),
        carbs: nullableString(row.nutrition.carbs),
        fat: nullableString(row.nutrition.fat),
        fiber: nullableString(row.nutrition.fiber),
        sugar: nullableString(row.nutrition.sugar),
        salt: nullableString(row.nutrition.salt),
        saturatedFat: nullableString(row.nutrition.saturatedFat)
      }
    : null;

  return {
    recipeId: row.id,
    title: row.title,
    servings: row.details?.servings ?? null,
    prepTimeMinutes: row.details?.prepTimeMinutes ?? null,
    cookTimeMinutes: row.details?.cookTimeMinutes ?? null,
    ingredients,
    steps,
    nutritionPerServing: nutrition,
    allergens: Array.isArray(row.allergens) ? row.allergens : [],
    appliedModifications: appliedModifications.map((mod) => ({
      id: mod.id,
      summary: mod.summary,
      kind: mod.kind,
      appliedAt: mod.applied_at
    }))
  };
}

/**
 * Serializes the recipe context into the text block sent to the model.
 * Compact, deterministic, and friendly to prompt caching (the same recipe
 * row produces the same string until updated_at changes).
 */
export function serializeRecipeContext(context: RecipeContext): string {
  const lines: string[] = [];
  lines.push("RECETTE ACTIVE");
  lines.push(`Titre: ${context.title}`);
  lines.push(`Portions: ${context.servings ?? "non précisé"}`);
  if (context.prepTimeMinutes != null) {
    lines.push(`Préparation: ${context.prepTimeMinutes} min`);
  }
  if (context.cookTimeMinutes != null) {
    lines.push(`Cuisson: ${context.cookTimeMinutes} min`);
  }

  lines.push("");
  lines.push("INGRÉDIENTS (id | quantité unité nom):");
  for (const ing of context.ingredients) {
    const qty = [ing.amount, ing.unit].filter(Boolean).join(" ") || "—";
    const swap = ing.isSwapped && ing.originName
      ? `  [SWAPPÉ depuis: ${ing.originName}]`
      : "";
    lines.push(`- ${ing.id} | ${qty} ${ing.name}${swap}`);
  }

  lines.push("");
  lines.push("ÉTAPES (id | texte):");
  for (const step of context.steps) {
    const title = step.title ? ` ${step.title} —` : "";
    lines.push(`- ${step.id} |${title} ${step.detail}`);
  }

  if (context.nutritionPerServing) {
    const n = context.nutritionPerServing;
    const parts: string[] = [];
    if (n.calories) parts.push(`kcal:${n.calories}`);
    if (n.protein) parts.push(`P:${n.protein}`);
    if (n.carbs) parts.push(`G:${n.carbs}`);
    if (n.fat) parts.push(`L:${n.fat}`);
    if (n.fiber) parts.push(`fibre:${n.fiber}`);
    if (n.sugar) parts.push(`sucre:${n.sugar}`);
    if (n.salt) parts.push(`sel:${n.salt}`);
    if (n.saturatedFat) parts.push(`AGS:${n.saturatedFat}`);
    if (parts.length > 0) {
      lines.push("");
      lines.push(`NUTRITION (par portion): ${parts.join(" | ")}`);
    }
  }

  if (context.allergens.length > 0) {
    lines.push("");
    lines.push(`ALLERGÈNES connus: ${context.allergens.join(", ")}`);
  }

  if (context.appliedModifications.length > 0) {
    lines.push("");
    lines.push("MODIFICATIONS DÉJÀ APPLIQUÉES (ne pas les défaire sans demande explicite):");
    for (const mod of context.appliedModifications) {
      lines.push(`- ${mod.summary}`);
    }
  }

  return lines.join("\n");
}

function truncateForContext(value: string, max: number): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1).trimEnd()}…`;
}

function nullableString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
