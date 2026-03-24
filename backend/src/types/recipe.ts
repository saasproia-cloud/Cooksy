import { z } from "zod";

import { normalizeWhitespace } from "../utils/text.js";

export const recipeIngredientSchema = z.object({
  amount: z.string().default(""),
  unit: z.string().default(""),
  name: z.string().default(""),
  nutritionQuery: z.string().default("")
});

export const recipeStepSchema = z.object({
  detail: z.string().default("")
});

export const recipeImportSchema = z.object({
  title: z.string().default(""),
  sourceUrl: z.string().default(""),
  remoteImageUrl: z.string().default(""),
  ingredientDrafts: z.array(recipeIngredientSchema).default([]),
  stepDrafts: z.array(recipeStepSchema).default([]),
  notesText: z.string().default(""),
  prepTimeText: z.string().default(""),
  cookTimeText: z.string().default(""),
  servingsText: z.string().default(""),
  caloriesText: z.string().default(""),
  proteinText: z.string().default(""),
  carbsText: z.string().default(""),
  fatText: z.string().default(""),
  confidence: z.enum(["low", "medium", "high"]).default("medium"),
  needsWebFallback: z.boolean().default(false),
  searchQuery: z.string().default(""),
  inferredFromPhoto: z.boolean().default(false)
});

export type RecipeIngredientDraft = z.infer<typeof recipeIngredientSchema>;
export type RecipeImportResult = z.infer<typeof recipeImportSchema>;

export type ImportDebugMissing = "ingredients" | "steps";
export type ImportFailureReason =
  | "no_recipe_detected"
  | "not_enough_ingredients"
  | "not_enough_steps"
  | "weak_tiktok_metadata"
  | "import_too_slow"
  | "invalid_recipe_result";

export type ImportDebug = {
  platform?: string;
  usedApify: boolean;
  usedTranscription: boolean;
  usedWebFallback: boolean;
  usedUsda?: boolean;
  nutritionCoverage?: number;
  matchedNutritionIngredients?: number;
  sourceKind: "url" | "text" | "photo";
  ingredientsCount: number;
  stepsCount: number;
  strategy: string;
  durationMs: number;
  isLikelyValid: boolean;
  missing: ImportDebugMissing[];
  failureReason?: ImportFailureReason;
};

export type NormalizerInput = {
  mode: "url" | "text" | "photo";
  sourceUrl?: string;
  remoteImageUrl?: string;
  sharedText?: string;
  pageTitle?: string;
  pageDescription?: string;
  pageTextContent?: string;
  pageStructuredData?: string[];
  socialTitle?: string;
  socialCaption?: string;
  socialDescription?: string;
  socialPageText?: string;
  socialAuthor?: string;
  socialSubtitles?: string;
  transcript?: string;
  imageDataUrl?: string;
};

function clean(value?: string | null): string {
  return normalizeWhitespace(value ?? "");
}

function normalizeUrl(value?: string): string {
  const trimmed = clean(value);
  if (!trimmed) {
    return "";
  }

  try {
    return new URL(trimmed).toString();
  } catch {
    return "";
  }
}

export function sanitizeRecipeImport(input: RecipeImportResult): RecipeImportResult {
  const title = sanitizeTitle(input.title);
  const ingredientDrafts = dedupeIngredients(
    input.ingredientDrafts
      .map(sanitizeIngredientDraft)
      .filter((ingredient): ingredient is RecipeIngredientDraft => Boolean(ingredient))
  );
  const stepDrafts = dedupeSteps(
    input.stepDrafts
      .map((step) => ({
        detail: sanitizeStepDetail(step.detail)
      }))
      .filter((step) => isPlausibleCookingStep(step.detail))
  );
  const titleLooksArticleLike = isLikelyArticleTitle(title);
  const normalizedConfidence = clampConfidence(
    input.confidence,
    ingredientDrafts.length,
    stepDrafts.length,
    titleLooksArticleLike
  );

  return {
    ...input,
    title,
    sourceUrl: normalizeUrl(input.sourceUrl),
    remoteImageUrl: normalizeUrl(input.remoteImageUrl),
    ingredientDrafts,
    stepDrafts,
    notesText: sanitizeNotes(input.notesText),
    prepTimeText: clean(input.prepTimeText),
    cookTimeText: clean(input.cookTimeText),
    servingsText: clean(input.servingsText),
    caloriesText: sanitizeNutritionText(input.caloriesText, "calories"),
    proteinText: sanitizeNutritionText(input.proteinText, "macro"),
    carbsText: sanitizeNutritionText(input.carbsText, "macro"),
    fatText: sanitizeNutritionText(input.fatText, "macro"),
    confidence: normalizedConfidence,
    needsWebFallback: input.needsWebFallback ||
      titleLooksArticleLike ||
      ingredientDrafts.length < 3 ||
      stepDrafts.length < 2,
    searchQuery: clean(input.searchQuery)
  };
}

export function scoreRecipe(recipe: RecipeImportResult): number {
  const nutritionScore = [recipe.caloriesText, recipe.proteinText, recipe.carbsText, recipe.fatText]
    .filter((value) => value.length > 0)
    .length * 2;
  const titlePenalty = isLikelyArticleTitle(recipe.title) ? -18 : 0;

  return recipe.ingredientDrafts.length * 6 +
    recipe.stepDrafts.length * 7 +
    (recipe.title.length > 0 ? 10 : 0) +
    (recipe.notesText.length > 0 ? 2 : 0) +
    (recipe.remoteImageUrl.length > 0 ? 2 : 0) +
    nutritionScore +
    (recipe.confidence === "high" ? 8 : recipe.confidence === "medium" ? 4 : 0) +
    titlePenalty;
}

export function shouldFallbackToSearch(recipe: RecipeImportResult): boolean {
  return recipe.needsWebFallback ||
    recipe.confidence === "low" ||
    recipe.ingredientDrafts.length < 3 ||
    recipe.stepDrafts.length < 2 ||
    isLikelyArticleTitle(recipe.title);
}

export function importMissingParts(recipe: RecipeImportResult): ImportDebugMissing[] {
  const missing: ImportDebugMissing[] = [];

  if (recipe.ingredientDrafts.length < 3) {
    missing.push("ingredients");
  }

  if (recipe.stepDrafts.length < 2) {
    missing.push("steps");
  }

  return missing;
}

export function isLikelyValidRecipe(recipe: RecipeImportResult): boolean {
  const normalizedTitle = clean(recipe.title);
  return normalizedTitle.length > 2 &&
    normalizedTitle.length <= 90 &&
    !isLikelyArticleTitle(normalizedTitle) &&
    importMissingParts(recipe).length === 0;
}

export function importFailureReason(
  recipe: RecipeImportResult,
  options?: {
    preferWeakMetadata?: boolean;
    timedOut?: boolean;
  }
): ImportFailureReason | undefined {
  if (options?.timedOut) {
    return "import_too_slow";
  }

  const missing = importMissingParts(recipe);
  if (!missing.length) {
    if (isLikelyArticleTitle(recipe.title)) {
      return "invalid_recipe_result";
    }
    return undefined;
  }

  if (options?.preferWeakMetadata) {
    return "weak_tiktok_metadata";
  }

  if (missing.length === 2) {
    return "no_recipe_detected";
  }

  if (missing.includes("ingredients")) {
    return "not_enough_ingredients";
  }

  if (missing.includes("steps")) {
    return "not_enough_steps";
  }

  return "invalid_recipe_result";
}

function sanitizeTitle(value: string): string {
  let cleaned = clean(value)
    .replace(/^(?:recipe|recette|titre|title)\s*:\s*/i, "")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .replace(/\p{Extended_Pictographic}/gu, " ")
    .replace(/\s+[|•·]\s+.+$/, "")
    .trim();

  for (const pattern of titleCutoffPatterns) {
    const match = cleaned.match(pattern);
    if (match && typeof match.index === "number" && match.index >= 8) {
      cleaned = cleaned.slice(0, match.index).trim();
      break;
    }
  }

  cleaned = clean(
    cleaned
      .split(/\n+/)[0] ?? cleaned
  )
    .replace(/\s*[:\-–]\s*$/u, "")
    .trim();

  const inlineIngredientMatch = cleaned.match(/\b\d+(?:[.,]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup|egg|eggs|packet|packets?|steak|steaks|tranche|tranches|pain|pains|bun|buns)\b/i);
  if (inlineIngredientMatch && typeof inlineIngredientMatch.index === "number" && inlineIngredientMatch.index >= 8) {
    cleaned = cleaned.slice(0, inlineIngredientMatch.index).trim();
  }

  if (cleaned.length > 80) {
    cleaned = clean(cleaned.split(/[.!?]/)[0] ?? cleaned);
  }

  if (cleaned === cleaned.toUpperCase() && /[A-ZÀ-ÿ]/.test(cleaned)) {
    cleaned = cleaned
      .toLowerCase()
      .replace(/\b\p{L}/gu, (character) => character.toUpperCase());
  }

  return cleaned;
}

function sanitizeIngredientDraft(ingredient: RecipeIngredientDraft): RecipeIngredientDraft | null {
  const amount = clean(ingredient.amount);
  const unit = clean(ingredient.unit);
  const originalName = clean(ingredient.name);
  const name = sanitizeIngredientName(ingredient.name);
  const nutritionQuery = sanitizeNutritionQuery(ingredient.nutritionQuery, name);
  const isServeOnlyIngredient = /\b(?:to serve|for serving|pour servir|optional|facultatif)\b/i.test(originalName);

  if (!isPlausibleIngredientName(name)) {
    return null;
  }

  if (isServeOnlyIngredient && !amount && !unit) {
    return null;
  }

  return {
    amount,
    unit,
    name,
    nutritionQuery
  };
}

function sanitizeIngredientName(value: string): string {
  return clean(value)
    .replace(/^\s*(?:[-•*]|\d+[\).\-\s]+)\s*/u, "")
    .replace(/\s*\((?:see note|optional|facultatif|to taste)\)$/i, "")
    .replace(/\s+(?:to serve|for serving|pour servir)\b.*$/i, "")
    .replace(/\s+plus\b.*$/i, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function sanitizeNutritionQuery(value: string, fallbackName: string): string {
  const cleaned = clean(value || fallbackName)
    .replace(/^\s*(?:[-•*]|\d+[\).\-\s]+)\s*/u, "")
    .replace(/\s+(?:to serve|for serving|pour servir)\b.*$/i, "")
    .replace(/\s+plus\b.*$/i, "")
    .replace(/[;,]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return cleaned.length > 60 ? cleaned.slice(0, 60).trim() : cleaned;
}

function sanitizeStepDetail(value: string): string {
  return clean(value)
    .replace(/^\s*(?:étape|step)\s*\d+[:.)\-\s]*/iu, "")
    .replace(/^\s*(?:[-•*]|\d+[\).\-\s]+)\s*/u, "")
    .replace(/\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/g, " ")
    .replace(/-->/g, " ")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .trim();
}

function sanitizeNotes(value: string): string {
  return (value ?? "")
    .split("\n")
    .map((line) => clean(line))
    .filter((line) => line && !containsArticleNoise(line))
    .filter((line) => !/^(?:titre|title)\s*:/i.test(line))
    .join("\n");
}

function sanitizeNutritionText(value: string, kind: "calories" | "macro"): string {
  const cleaned = clean(value);
  if (!cleaned) {
    return "";
  }

  const match = cleaned
    .replace(",", ".")
    .match(/(\d+(?:\.\d+)?)/);

  if (!match) {
    return "";
  }

  const numericValue = Number(match[1]);
  if (!Number.isFinite(numericValue)) {
    return "";
  }

  if (kind === "calories") {
    return numericValue > 0 ? `${Math.round(numericValue)} kcal` : "";
  }

  const rounded = Math.round(numericValue * 10) / 10;
  return rounded > 0 ? `${formatNumber(rounded)} g` : "";
}

function clampConfidence(
  current: RecipeImportResult["confidence"],
  ingredientCount: number,
  stepCount: number,
  titleLooksArticleLike: boolean
): RecipeImportResult["confidence"] {
  if (titleLooksArticleLike || ingredientCount < 2 || stepCount < 1) {
    return "low";
  }

  if (ingredientCount >= 5 && stepCount >= 3) {
    return current === "low" ? "medium" : current;
  }

  if (ingredientCount >= 3 && stepCount >= 2) {
    return current === "low" ? "medium" : current;
  }

  return "low";
}

function dedupeIngredients(ingredients: RecipeIngredientDraft[]): RecipeIngredientDraft[] {
  const seen = new Set<string>();
  const result: RecipeIngredientDraft[] = [];

  for (const ingredient of ingredients) {
    const key = normalizeLookup(ingredient.name);
    if (!key || seen.has(key)) {
      continue;
    }

    seen.add(key);
    result.push(ingredient);
  }

  return result;
}

function dedupeSteps(steps: Array<{ detail: string }>): Array<{ detail: string }> {
  const seen = new Set<string>();
  const result: Array<{ detail: string }> = [];

  for (const step of steps) {
    const key = normalizeLookup(step.detail);
    if (!key || seen.has(key)) {
      continue;
    }

    seen.add(key);
    result.push(step);
  }

  return result.slice(0, 16);
}

function isPlausibleIngredientName(name: string): boolean {
  if (!name) {
    return false;
  }

  if (containsArticleNoise(name)) {
    return false;
  }

  if (name.length > 90) {
    return false;
  }

  if (name.split(" ").length > 12) {
    return false;
  }

  if ((name.match(/[.!?]/g)?.length ?? 0) > 1) {
    return false;
  }

  return /[a-zA-ZÀ-ÿ]/.test(name);
}

function isPlausibleCookingStep(detail: string): boolean {
  if (!detail || containsArticleNoise(detail)) {
    return false;
  }

  if (/\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/.test(detail) || detail.includes("-->")) {
    return false;
  }

  if (detail.length < 8 || detail.length > 220) {
    return false;
  }

  const normalized = normalizeLookup(detail);
  if (
    /^(?:j espere|j espere|bon app|bon appetit|oui j ose le dire|n hesite pas|abonne toi|like|follow|partage|commente)\b/.test(normalized)
  ) {
    return false;
  }
  if (/^(?:pour|for)\s+\d+\s+(?:portion|portions|serving|servings)\b/.test(normalized)) {
    return false;
  }
  const wordCount = normalized.split(" ").filter(Boolean).length;
  const startsLikeProcedure = /^(?:puis|ensuite|d abord|commencer|faire|ajouter|mettre|melanger|verser|laisser|couper|cuire|servir|incorporer|assaisonner|saisir|griller|carameliser|carameliser|retourner|garnir|napper)\b/.test(normalized);
  if (wordCount > 38 && !containsCookingVerb(normalized)) {
    return false;
  }

  return containsCookingVerb(normalized) || startsLikeProcedure;
}

function isLikelyArticleTitle(title: string): boolean {
  const normalized = normalizeLookup(title);
  if (!normalized) {
    return false;
  }

  if (containsArticleNoise(normalized)) {
    return true;
  }

  return /^(?:\d+\s+)?(?:best|top|easy|favorite|favourite|tiktok)\s+\w+\s+recipes?\b/.test(normalized) ||
    /\b(?:recipes?|ideas?)\b.*\b(?:that|to try|you need|for summer|for fall)\b/.test(normalized) ||
    /\b(?:roundup|list|listicle|news|celebrity|fashion|travel)\b/.test(normalized);
}

function containsArticleNoise(value: string): boolean {
  const normalized = normalizeLookup(value);
  return articleNoisePatterns.some((pattern) => pattern.test(normalized)) ||
    normalized.includes("http") ||
    normalized.includes("www.");
}

function containsCookingVerb(value: string): boolean {
  return cookingVerbPatterns.some((pattern) => pattern.test(value));
}

function normalizeLookup(value: string): string {
  return clean(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9/%+\s]/gi, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("fr-FR", {
    maximumFractionDigits: 1,
    minimumFractionDigits: 0
  }).format(value);
}

const articleNoisePatterns = [
  /\bread more\b/,
  /\bview post\b/,
  /\bnewsletter\b/,
  /\bsubscribe\b/,
  /\bfollow\b/,
  /\blike and comment\b/,
  /\bcelebrity\b/,
  /\bfashion\b/,
  /\btravel\b/,
  /\bbreaking news\b/,
  /\bshopping\b/,
  /\bwatch now\b/,
  /\btiktok\b.*\btrend\b/,
  /\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/,
  /-->/
];

const cookingVerbPatterns = [
  /\b(?:preheat|heat|mix|stir|add|combine|cook|bake|roast|fry|boil|simmer|whisk|blend|serve|set|put|wipe|keep|rest|pour|flip)\b/,
  /\b(?:prechauffez|faites|melangez|melanger|ajoutez|ajouter|versez|verser|cuisez|cuire|laissez|laisser|deposez|deposer|fouettez|fouetter)\b/,
  /\b(?:incorporez|incorporer|faites revenir|repartissez|repartir|servez|servir|enfournez|enfourner|chauffez|chauffer)\b/,
  /\b(?:coupez|couper|grillez|griller|saisissez|saisir|caramelisez|carameliser|retournez|retourner|garnissez|garnir|nappez|napper|ecrasez|ecraser)\b/
];

const titleCutoffPatterns = [
  /\b(?:ingredients?|ingrédients?)\b/i,
  /\b(?:pour réaliser|pour faire|tu auras besoin|il te faut)\b/i,
  /\b(?:instructions?|étapes?|etapes|dough|mixture|coating|marinade|serve with)\b/i,
  /\s[-–:]\s*(?=\d+(?:[.,/]\d+)?\s*(?:g|kg|ml|cl|l|cas|cac|cuill[eè]re?s?|steaks?|tranches?|pains?|buns?|oignons?|cheddar|cornichons?|beurre)\b)/i
];
