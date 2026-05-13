import { z } from "zod";

import { enrichRecipeNutrition } from "./usdaNutritionService.js";
import {
  hasCookabilityGaps,
  sanitizeRecipeImport,
  type ImportDebug,
  type RecipeImportResult,
  type RecipeIngredientDraft
} from "../types/recipe.js";
import { normalizeWhitespace } from "../utils/text.js";

const URL_IMPORT_FAILURE_MESSAGE = "Impossible de générer la recette";
const RECIPE_IMAGE_FALLBACK_URL = "https://placehold.co/1200x900/png?text=Cooksy+Recipe";

const apiIngredientSchema = z.object({
  name: z.string(),
  quantity: z.string(),
  unit: z.string(),
  quantityValue: z.number().optional(),
  display: z.string().optional(),
  nutritionQuery: z.string().optional()
});

const apiStepSchema = z.object({
  stepNumber: z.number().int().positive(),
  description: z.string(),
  section: z.string().optional(),
  ingredientRefs: z.array(z.string()).optional()
});

const apiNutritionSchema = z.object({
  calories: z.number().finite().min(0),
  protein: z.number().finite().min(0),
  carbs: z.number().finite().min(0),
  fat: z.number().finite().min(0)
});

const apiDebugSchema = z.object({
  strategy: z.string(),
  durationMs: z.number().int(),
  ingredientsCount: z.number().int(),
  stepsCount: z.number().int(),
  isLikelyValid: z.boolean(),
  usedApify: z.boolean(),
  usedTranscription: z.boolean(),
  usedWebFallback: z.boolean(),
  missing: z.array(z.string()),
  failureReason: z.string().optional(),
  needsReview: z.boolean().optional()
});

const apiSuccessSchema = z.object({
  success: z.literal(true),
  data: z.object({
    title: z.string(),
    creatorHandle: z.string().optional(),
    externalRating: z.number().min(0).max(5).optional(),
    externalRatingCount: z.number().int().positive().optional(),
    ingredients: z.array(apiIngredientSchema).min(1),
    steps: z.array(apiStepSchema).min(1),
    nutrition: apiNutritionSchema,
    image: z.string().url(),
    sourceUrl: z.string().url(),
    prepTimeText: z.string().optional(),
    cookTimeText: z.string().optional(),
    servingsText: z.string().optional(),
    notesText: z.string().optional()
  }),
  debug: apiDebugSchema.optional()
});

const apiFailureSchema = z.object({
  success: z.literal(false),
  error: z.string()
});

export type URLImportSuccessResponse = z.infer<typeof apiSuccessSchema>;
export type URLImportFailureResponse = z.infer<typeof apiFailureSchema>;

export async function buildURLImportResponse(input: {
  recipe: RecipeImportResult;
  sourceUrl: string;
  debug?: ImportDebug;
}): Promise<URLImportSuccessResponse | URLImportFailureResponse> {
  const normalizedSourceUrl = normalizeUrl(input.sourceUrl);
  if (!normalizedSourceUrl) {
    return buildURLImportFailureResponse();
  }

  try {
    const repairedRecipe = roundCountableIngredientQuantities(repairPerPortionRecipe(input.recipe));
    const recipeWithNutrition = await ensureRecipeNutrition(repairedRecipe);
    const title = stableTitle(recipeWithNutrition.title);
    let ingredients = normalizeIngredients(recipeWithNutrition.ingredientDrafts, title);
    let steps = ensureCompleteSteps(recipeWithNutrition, title, ingredients);
    // Anti-hallucination: drop ingredients that aren't referenced in ANY
    // step (unless protected by an explicit group). This catches the
    // pattern seen in production where the LLM mixes ingredients from a
    // sub-recipe mentioned in the description but not actually cooked
    // (e.g. Chepalgash flatbread ingredients leaking into a Poulet Wrap).
    const droppedNames = dropUnreferencedIngredients(ingredients, steps);
    if (droppedNames.size > 0) {
      ingredients = ingredients.filter((ing) => !droppedNames.has(ing.name));
      steps = steps.map((step) => {
        if (!step.ingredientRefs?.length) return step;
        const filtered = step.ingredientRefs.filter((ref) => !droppedNames.has(ref));
        return { ...step, ingredientRefs: filtered.length ? filtered : undefined };
      });
    }
    const nutrition = resolveNutrition(recipeWithNutrition);

    if (!title || !ingredients.length || !steps.length) {
      return buildURLImportFailureResponse();
    }

    const response = apiSuccessSchema.parse({
      success: true,
      data: {
        title,
        creatorHandle: recipeWithNutrition.creatorHandle || undefined,
        externalRating: recipeWithNutrition.externalRating,
        externalRatingCount: recipeWithNutrition.externalRatingCount,
        ingredients,
        steps,
        nutrition,
        image: stableImageUrl(recipeWithNutrition.remoteImageUrl),
        sourceUrl: normalizedSourceUrl,
        prepTimeText: recipeWithNutrition.prepTimeText || undefined,
        cookTimeText: recipeWithNutrition.cookTimeText || undefined,
        servingsText: recipeWithNutrition.servingsText || undefined,
        notesText: recipeWithNutrition.notesText || undefined
      },
      debug: input.debug
    });

    return response;
  } catch {
    return buildURLImportFailureResponse();
  }
}

export function buildURLImportFailureResponse(): URLImportFailureResponse {
  return apiFailureSchema.parse({
    success: false,
    error: URL_IMPORT_FAILURE_MESSAGE
  });
}

async function ensureRecipeNutrition(recipe: RecipeImportResult): Promise<RecipeImportResult> {
  const sanitizedRecipe = sanitizeRecipeImport(recipe);
  if (hasUsableNutrition(sanitizedRecipe)) {
    return sanitizedRecipe;
  }

  const enrichedRecipe = sanitizeRecipeImport((await enrichRecipeNutrition(sanitizedRecipe)).recipe);
  if (hasUsableNutrition(enrichedRecipe)) {
    return enrichedRecipe;
  }

  const genericNutrition = genericNutritionFallback(enrichedRecipe);
  return {
    ...enrichedRecipe,
    caloriesText: String(genericNutrition.calories),
    proteinText: String(genericNutrition.protein),
    carbsText: String(genericNutrition.carbs),
    fatText: String(genericNutrition.fat)
  };
}

function hasUsableNutrition(recipe: RecipeImportResult): boolean {
  const nutrition = [
    parseNumericValue(recipe.caloriesText),
    parseNumericValue(recipe.proteinText),
    parseNumericValue(recipe.carbsText),
    parseNumericValue(recipe.fatText)
  ];

  return nutrition.every((value) => value !== null) && (nutrition[0] ?? 0) > 0;
}

function normalizeIngredients(
  ingredients: RecipeIngredientDraft[],
  title: string
): URLImportSuccessResponse["data"]["ingredients"] {
  const seen = new Set<string>();

  return ingredients
    .map((ingredient) => {
      const name = normalizeIngredientName(ingredient.name);
      const quantity = cleanIngredientText(ingredient.amount);
      return {
        name,
        quantity,
        unit: normalizeUnitLabel(ingredient.unit),
        quantityValue: parseQuantityValue(quantity) ?? undefined,
        display: capitalizeDisplay(name) || undefined,
        nutritionQuery: ingredient.nutritionQuery?.trim() || undefined
      };
    })
    .filter((ingredient) => isUsableIngredientName(ingredient.name, title))
    .filter((ingredient) => {
      const key = normalizeIngredientKey(ingredient.name);
      if (!key || seen.has(key)) {
        return false;
      }

      seen.add(key);
      return true;
    });
}

/**
 * Detect and repair per-portion quantities. The LLM is instructed to emit
 * total recipe quantities, but occasionally slips and divides by the portion
 * count (typically 3). The signature is multiple ingredients with fractional
 * parts ≈ 1/3 or 2/3 (0.3, 13.3, 33.3, 66.7, 83.3, etc.). When we see this
 * pattern across ≥3 ingredients we multiply by the inferred factor and round
 * to natural cooking quantities. We also patch `servingsText` so the
 * downstream nutrition divisor stays in sync.
 */
function repairPerPortionRecipe(recipe: RecipeImportResult): RecipeImportResult {
  const factor = detectPerPortionFactor(
    recipe.ingredientDrafts,
    parseLeadingInteger(recipe.servingsText)
  );
  if (factor === null) {
    return recipe;
  }

  console.warn(
    `[repairPerPortionRecipe] Detected /${factor} per-portion division across ingredients; multiplying by ${factor} and patching servingsText.`
  );

  const repairedDrafts = recipe.ingredientDrafts.map((ing) => {
    const value = parseRawAmount(ing.amount);
    if (value === null) return ing;
    const repaired = roundToNaturalQuantity(value * factor, ing.unit);
    return { ...ing, amount: formatNaturalAmount(repaired) };
  });

  const currentServings = parseLeadingInteger(recipe.servingsText);
  const repairedServingsText =
    currentServings === null || currentServings <= 1
      ? `${factor} personnes`
      : recipe.servingsText;

  return {
    ...recipe,
    ingredientDrafts: repairedDrafts,
    servingsText: repairedServingsText
  };
}

/**
 * Countable ingredients (œuf, citron, oignon, gousse, tortilla, etc.)
 * never make sense as fractions when no weight/volume unit is attached.
 * After /3 repair we sometimes still see legacy decimals like `Tenders 1.3`
 * — clamp them to integers (minimum 1) to avoid kitchen-impossible amounts.
 */
const COUNTABLE_INGREDIENT_PATTERNS: RegExp[] = [
  /\boeufs?\b/i,
  /\bœufs?\b/i,
  /\bcitrons?\b/i,
  /\boignons?\b/i,
  /\btomates?\b/i,
  /\bpommes?\b/i,
  /\b[ée]chalotes?\b/i,
  /\bgousses?\b/i,
  /\btranches?\b/i,
  /\btortillas?\b/i,
  /\bbuns?\b/i,
  /\bpains?\s+burger\b/i,
  /\bpains?\s+brioch[eé]\b/i,
  /\bescalopes?\b/i,
  /\bfilets?\b/i,
  /\bblancs?\s+de\s+poulet\b/i,
  /\btenders?\b/i,
  /\bnuggets?\b/i,
];

const WEIGHT_VOLUME_UNIT_RE = /\b(g|gr|gramme|grammes|kg|mg|ml|cl|dl|l|litre|tasse|cup|oz|lb)\b/i;

function roundCountableIngredientQuantities(recipe: RecipeImportResult): RecipeImportResult {
  let mutated = false;
  const drafts = recipe.ingredientDrafts.map((ing) => {
    const value = parseRawAmount(ing.amount);
    if (value === null) return ing;
    if (value === Math.round(value)) return ing;

    const unit = (ing.unit ?? "").toLowerCase().trim();
    if (WEIGHT_VOLUME_UNIT_RE.test(unit)) return ing;

    const name = ing.name ?? "";
    const isCountable = COUNTABLE_INGREDIENT_PATTERNS.some((re) => re.test(name));
    if (!isCountable) return ing;

    const rounded = Math.max(1, Math.round(value));
    if (rounded === value) return ing;

    mutated = true;
    return { ...ing, amount: String(rounded) };
  });

  if (!mutated) return recipe;
  console.warn(
    "[roundCountableIngredientQuantities] Rounded one or more countable ingredient quantities to integers."
  );
  return { ...recipe, ingredientDrafts: drafts };
}

function detectPerPortionFactor(
  ingredients: RecipeIngredientDraft[],
  declaredServings: number | null
): number | null {
  // Count fractional signatures for each plausible divisor. Each pattern
  // votes only when the value is small enough to plausibly be a
  // per-portion amount (a 200 g ingredient with `.5` is just `200.5` —
  // not the result of dividing).
  let thirdSignals = 0;
  let halfSignals = 0;
  let quarterSignals = 0;

  for (const ing of ingredients) {
    const value = parseRawAmount(ing.amount);
    if (value === null) continue;
    if (looksLikeThirdDivision(value)) thirdSignals++;
    if (looksLikeHalfDivision(value)) halfSignals++;
    if (looksLikeQuarterDivision(value)) quarterSignals++;
  }

  if (thirdSignals >= 3) return 3;

  // Halves are noisier — `0.5` legitimately appears in single-portion
  // recipes ("1.5 c. à soupe", "0.5 citron"). Strong signal threshold is
  // 4, but if the recipe explicitly says "1 portion" we relax to 3 since
  // it's a strong tell that the AI per-portioned everything.
  const halfThreshold = declaredServings !== null && declaredServings <= 1 ? 3 : 4;
  if (halfSignals >= halfThreshold) return 2;

  if (quarterSignals >= 3) return 4;
  return null;
}

function looksLikeHalfDivision(value: number): boolean {
  if (value <= 0 || value > 10_000) return false;
  const fractional = value - Math.floor(value);
  return Math.abs(fractional - 0.5) < 0.02;
}

function looksLikeQuarterDivision(value: number): boolean {
  if (value <= 0 || value > 10_000) return false;
  const fractional = value - Math.floor(value);
  return (
    Math.abs(fractional - 0.25) < 0.02 ||
    Math.abs(fractional - 0.75) < 0.02
  );
}

function parseLeadingInteger(value: string | undefined): number | null {
  if (!value) return null;
  const match = value.trim().match(/^(\d+)/);
  if (!match) return null;
  const parsed = Number(match[1]);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function parseRawAmount(value: string | undefined): number | null {
  if (!value) return null;
  const match = value.replace(",", ".").trim().match(/^(\d+(?:\.\d+)?)/);
  if (!match) return null;
  const parsed = Number(match[1]);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function looksLikeThirdDivision(value: number): boolean {
  if (value <= 0 || value > 10_000) return false;
  const fractional = value - Math.floor(value);
  const tol = 0.05;
  return (
    Math.abs(fractional - 1 / 3) < tol ||
    Math.abs(fractional - 2 / 3) < tol ||
    Math.abs(fractional - 0.3) < tol ||
    Math.abs(fractional - 0.7) < tol
  );
}

function roundToNaturalQuantity(value: number, rawUnit: string | undefined): number {
  const unit = (rawUnit ?? "").toLowerCase().trim();

  const isWeightOrVolume = /\b(g|gr|gramme|grammes|kg|mg|ml|cl|dl|l|litre|tasse|cup)\b/.test(unit);
  if (isWeightOrVolume) {
    if (value < 1) return Math.round(value * 10) / 10;
    if (value < 5) return Math.round(value * 2) / 2;
    if (value < 50) return Math.round(value / 5) * 5;
    if (value < 250) return Math.round(value / 10) * 10;
    if (value < 500) return Math.round(value / 25) * 25;
    return Math.round(value / 50) * 50;
  }

  const isSpoonOrPinch = /(c\.?\s*[àa]\s*(?:soupe|caf[ée])|cuill|c\.s|c\.c|cas|cac|tbsp|tsp|pinc|trait|filet)/.test(unit);
  if (isSpoonOrPinch) {
    if (value < 1) return Math.round(value * 2) / 2 || 0.5;
    return Math.round(value * 2) / 2;
  }

  return Math.max(1, Math.round(value));
}

function formatNaturalAmount(value: number): string {
  if (!Number.isFinite(value) || value <= 0) return "";
  if (Number.isInteger(value)) return String(value);
  return String(Math.round(value * 10) / 10);
}

function normalizeSteps(
  recipe: RecipeImportResult,
  ingredientNames?: string[]
): URLImportSuccessResponse["data"]["steps"] {
  return recipe.stepDrafts
    .map((step) => ({
      description: cleanStepDescription(step.detail),
      section: step.section?.trim() || undefined
    }))
    .filter((step) => isUsableCookingInstruction(step.description))
    .filter((step) => Boolean(step.description))
    .map((step, index) => ({
      stepNumber: index + 1,
      description: step.description,
      section: step.section,
      ingredientRefs: ingredientNames?.length
        ? ingredientNamesForStep(step.description, ingredientNames)
        : undefined
    }));
}

function ensureCompleteSteps(
  recipe: RecipeImportResult,
  title: string,
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): URLImportSuccessResponse["data"]["steps"] {
  const ingredientNames = ingredients.map((i) => i.name);
  const explicitSteps = normalizeSteps(recipe, ingredientNames);
  const requiredStepCount = minimumGeneratedStepCount(title, ingredients);
  const needsCookabilityUpgrade = hasCookabilityGaps({
    ingredientDrafts: recipe.ingredientDrafts,
    stepDrafts: explicitSteps.map((step) => ({ detail: step.description }))
  });

  let steps: URLImportSuccessResponse["data"]["steps"];

  if (explicitSteps.length >= requiredStepCount && !needsCookabilityUpgrade) {
    steps = explicitSteps;
  } else {
    const rebuiltSteps = dedupeStepDescriptions([
      ...generatedStepsForRecipe(title, ingredients),
      ...explicitSteps.map((step) => step.description)
    ])
      .filter((description) => isUsableCookingInstruction(description))
      .slice(0, 20)
      .map((description, index) => ({
        stepNumber: index + 1,
        description,
        ingredientRefs: ingredientNamesForStep(description, ingredientNames) || undefined
      }));

    if (rebuiltSteps.length >= requiredStepCount) {
      steps = rebuiltSteps;
    } else {
      steps = generatedStepsForRecipe(title, ingredients).map((description, index) => ({
        stepNumber: index + 1,
        description,
        ingredientRefs: ingredientNamesForStep(description, ingredientNames) || undefined
      }));
    }
  }

  steps = splitLongSteps(steps, ingredientNames);
  steps = ensureIngredientStepCoverage(steps, ingredients);

  return steps;
}

function resolveNutrition(recipe: RecipeImportResult): URLImportSuccessResponse["data"]["nutrition"] {
  const fallback = genericNutritionFallback(recipe);

  return {
    calories: parseNumericValue(recipe.caloriesText) ?? fallback.calories,
    protein: parseNumericValue(recipe.proteinText) ?? fallback.protein,
    carbs: parseNumericValue(recipe.carbsText) ?? fallback.carbs,
    fat: parseNumericValue(recipe.fatText) ?? fallback.fat
  };
}

function stableTitle(value: string): string {
  const cleaned = normalizeWhitespace(value)
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_-]+/gu, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();

  return cleaned || "Recette importée";
}

function cleanIngredientText(value: string): string {
  return normalizeWhitespace(value)
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_-]+/gu, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/\b(?:read more|view post)\b/gi, " ")
    .replace(/[()]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeIngredientName(value: string): string {
  return cleanIngredientText(value)
    .replace(/^\s*(?:[-•*]|\d+[\).:\-\s]+)\s*/u, "")
    .replace(/^\s*(?:une?\s+)?\d+\s*(?:e|eme|ème|aine)\s+de\s+/i, "")
    .replace(/^\s*(?:c\.?\s*[aà]\.?\s*(?:soupe|caf[ée]|s\.?|c\.?)\.?)\s+(?:de?\s+)?/i, "")
    .replace(/^\s*(?:\d+\s*)?(?:g|kg|ml|cl|l|dl)\s+(?:de?\s+)?/i, "")
    .replace(/^\s*[aà]\s+soupe\s+(?:de?\s+)?/i, "")
    .replace(/^\s*[aà]\s+caf[ée]\s+(?:de?\s+)?/i, "")
    .replace(/\s*\((?:ici|comme ici|optional|facultatif|to taste)\)$/i, "")
    .replace(/\b(?:to serve|for serving|pour servir)\b.*$/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeIngredientKey(value: string): string {
  return normalizeWhitespace(value)
    .toLowerCase()
    .replace(/[’']/g, "'")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isUsableIngredientName(value: string, title: string): boolean {
  const cleaned = normalizeIngredientName(value);
  if (!cleaned) {
    return false;
  }

  const normalized = normalizeIngredientKey(cleaned);
  const normalizedTitle = normalizeIngredientKey(title);
  const wordCount = normalized.split(" ").filter(Boolean).length;

  if (!normalized || wordCount < 1 || wordCount > 6) {
    return false;
  }

  if (
    normalizedTitle &&
    normalizedTitle.length >= 8 &&
    (normalized === normalizedTitle || normalized.includes(normalizedTitle))
  ) {
    return false;
  }

  if (
    ingredientNarrativePattern.test(normalized) ||
    ingredientBadStartPattern.test(normalized) ||
    instructionVerbPattern.test(normalized)
  ) {
    return false;
  }

  if (/\b(?:je|j|tu|vous|on|nous|c|ca|ça)\b/.test(normalized)) {
    return false;
  }

  if (ingredientFoodPattern.test(normalized)) {
    return true;
  }

  return wordCount <= 4 && !/[.!?]/.test(cleaned);
}

function cleanStepDescription(value: string): string {
  const cleaned = normalizeWhitespace(value)
    .replace(/^\s*\d+\s*[.)-]?\s*/u, "")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_-]+/gu, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/\b(?:read more|view post)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!cleaned) {
    return "";
  }

  return cleaned[0].toUpperCase() + cleaned.slice(1);
}

function isUsableCookingInstruction(value: string): boolean {
  const cleaned = cleanStepDescription(value);
  if (!cleaned) {
    return false;
  }

  const normalized = normalizeWhitespace(cleaned)
    .toLowerCase()
    .replace(/[’']/g, "'")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  const wordCount = normalized.split(" ").filter(Boolean).length;

  if (wordCount < 4 || wordCount > 36) {
    return false;
  }

  if (
    /\b(?:je vais|on va|tu vas|vous allez)\b/.test(normalized) &&
    /\b(?:prendre|faire|mettre|voir|montrer|rajouter|ajouter)\b/.test(normalized)
  ) {
    return false;
  }

  if (
    /^(?:ensuite|puis|apres|et apres|comme ca|voila|du coup|alors)\b/.test(normalized) &&
    !instructionVerbPattern.test(normalized)
  ) {
    return false;
  }

  if (/^(?:comme ca|voila|et voila)\b/.test(normalized)) {
    return false;
  }

  if (
    /\b(?:c est super simple|c est delicieux|en plusieurs fois|fois en tout|toute petite louche|on a)\b/.test(normalized)
  ) {
    return false;
  }

  if (/\b(?:read more|view post|link in bio|lien en bio|lien bio|en bio)\b/.test(normalized)) {
    return false;
  }

  if (/\b(?:abonne|abonnez|follow|like|partage|partagez|commente|commentez|rejoins|rejoignez|sauvegarde|sauvegardez|clique|cliquez|notification|instagram|tiktok|pinterest|youtube)\b/.test(normalized)) {
    return false;
  }

  return instructionVerbPattern.test(normalized);
}

function normalizeUnitLabel(value: string): string {
  const cleaned = cleanIngredientText(value).toLowerCase();
  if (!cleaned) {
    return "";
  }

  const normalized = cleaned
    .replace(/\bc\.?\s*a\.?\s*s\.?\b/gi, "c. à soupe")
    .replace(/\bc\.?\s*a\.?\s*c\.?\b/gi, "c. à café")
    .replace(/\bc(?:uill[eè]?re)?s?\.?\s*[aà]\s*soupe\b/gi, "c. à soupe")
    .replace(/\bc(?:uill[eè]?re)?s?\.?\s*[aà]\s*caf[ée]\b/gi, "c. à café")
    .replace(/\bcas\b/gi, "c. à soupe")
    .replace(/\bcac\b/gi, "c. à café")
    .replace(/\btbsp\b/gi, "c. à soupe")
    .replace(/\btsp\b/gi, "c. à café")
    .replace(/\btablespoons?\b/gi, "c. à soupe")
    .replace(/\bteaspoons?\b/gi, "c. à café")
    .replace(/\bgrammes?\b/gi, "g")
    .replace(/\bgr\b/gi, "g")
    .replace(/\bkilogrammes?\b/gi, "kg")
    .replace(/\bmillilit(?:er|re)s?\b/gi, "ml")
    .replace(/\bcentilitres?\b/gi, "cl")
    .replace(/\bd[ée]cilitres?\b/gi, "dl")
    .replace(/\blitres?\b/gi, "l")
    .replace(/\bpieces?\b/gi, "")
    .replace(/\bcups?\b/gi, "tasse")
    .replace(/\s+/g, " ")
    .trim();

  return normalized;
}

function dedupeStepDescriptions(steps: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const step of steps) {
    const key = normalizeWhitespace(step)
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^\p{L}\p{N}\s]/gu, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (!key || seen.has(key)) {
      continue;
    }

    seen.add(key);
    result.push(step);
  }

  return result;
}

function stableImageUrl(remoteImageUrl: string): string {
  return normalizeUrl(remoteImageUrl) || RECIPE_IMAGE_FALLBACK_URL;
}

function parseNumericValue(value: string): number | null {
  const match = value.replace(",", ".").match(/(\d+(?:\.\d+)?)/);
  if (!match) {
    return null;
  }

  const parsed = Number(match[1]);
  if (!Number.isFinite(parsed)) {
    return null;
  }

  return Math.max(0, Math.round(parsed * 10) / 10);
}

function normalizeUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }

  try {
    return new URL(trimmed).toString();
  } catch {
    return "";
  }
}

function genericNutritionFallback(
  recipe: RecipeImportResult
): URLImportSuccessResponse["data"]["nutrition"] {
  const title = `${recipe.title} ${recipe.searchQuery}`.toLowerCase();
  const ingredientCount = Math.max(1, recipe.ingredientDrafts.filter((ingredient) => cleanIngredientText(ingredient.name).length > 0).length);
  const densityBoost = Math.max(0, ingredientCount - 5) * 18;

  if (/\b(burger|sandwich|wrap|naan|taco)\b/.test(title)) {
    return {
      calories: 560 + densityBoost,
      protein: 28 + Math.min(10, ingredientCount),
      carbs: 36 + Math.min(18, ingredientCount * 2),
      fat: 26 + Math.min(12, Math.round(ingredientCount * 1.2))
    };
  }

  if (/\b(pasta|pates?|curry|risotto)\b/.test(title)) {
    return {
      calories: 520 + densityBoost,
      protein: 24 + Math.min(10, ingredientCount),
      carbs: 48 + Math.min(20, ingredientCount * 2),
      fat: 18 + Math.min(10, ingredientCount)
    };
  }

  if (/\b(pizza|flatbread)\b/.test(title)) {
    return {
      calories: 640 + densityBoost,
      protein: 26 + Math.min(10, ingredientCount),
      carbs: 58 + Math.min(16, ingredientCount * 2),
      fat: 24 + Math.min(12, ingredientCount)
    };
  }

  if (/\b(salade|salad|bowl)\b/.test(title)) {
    return {
      calories: 340 + Math.round(densityBoost * 0.4),
      protein: 18 + Math.min(10, ingredientCount),
      carbs: 18 + Math.min(14, ingredientCount),
      fat: 18 + Math.min(12, ingredientCount)
    };
  }

  if (/\b(tiramisu|cake|gateau|gâteau|dessert|cookie|brownie)\b/.test(title)) {
    return {
      calories: 430 + Math.round(densityBoost * 0.6),
      protein: 7 + Math.min(4, Math.round(ingredientCount / 2)),
      carbs: 44 + Math.min(20, ingredientCount * 2),
      fat: 22 + Math.min(10, ingredientCount)
    };
  }

  return {
    calories: 470 + Math.round(densityBoost * 0.5),
    protein: 22 + Math.min(10, ingredientCount),
    carbs: 30 + Math.min(18, ingredientCount * 2),
    fat: 20 + Math.min(10, ingredientCount)
  };
}

function generatedStepsForRecipe(
  title: string,
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): string[] {
  const normalizedTitle = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  const ingredientSignals = generatedIngredientSignals(ingredients);
  const protein = preferredIngredient(ingredients, [/\bpoulet\b/i, /\bboeuf\b/i, /\bburger\b/i, /\bviande\b/i, /\bpoisson\b/i], "garniture principale");
  const bread = preferredIngredient(ingredients, [/\bpain\b/i, /\bbun\b/i, /\bnaan\b/i, /\bwrap\b/i, /\btortilla\b/i, /\bflatbread\b/i], "support");
  const greens = preferredIngredient(ingredients, [/\bsalade\b/i, /\blaitue\b/i, /\bcabbage\b/i, /\bchou\b/i], "garniture");
  const sauce = preferredIngredient(ingredients, [/\bsauce\b/i, /\bcreme\b/i, /\bcrème\b/i, /\byaourt\b/i], "sauce");
  const aromatic = preferredIngredient(ingredients, [/\boignon\b/i, /\bail\b/i, /\btomate\b/i, /\bchampignon\b/i], "aromates");
  const flour = preferredIngredient(ingredients, [/\bfarine\b/i, /\bflour\b/i], "farine");
  const milk = preferredIngredient(ingredients, [/\blait\b/i, /\bmilk\b/i], "lait");
  const eggs = preferredIngredient(ingredients, [/\boeufs?\b/i, /\bœufs?\b/i, /\beggs?\b/i], "oeufs");
  const butter = preferredIngredient(ingredients, [/\bbeurre\b/i, /\bbutter\b/i], "beurre");
  const sugar = preferredIngredient(ingredients, [/\bsucre\b/i, /\bsugar\b/i, /\bvanille\b/i, /\bvanilla\b/i], "sucre");
  const yeast = preferredIngredient(ingredients, [/\blevure\b/i, /\byeast\b/i], "levure");
  const water = preferredIngredient(ingredients, [/\beau\b/i, /\bwater\b/i], "eau tiède");
  const yogurt = preferredIngredient(ingredients, [/\byaourt\b/i, /\byogurt\b/i, /\bfromage blanc\b/i], "yaourt");
  const cheese = preferredIngredient(ingredients, [/\bfromage\b/i, /\bcheddar\b/i, /\bmozzarella\b/i, /\bparmesan\b/i], "fromage");

  if (/\b(?:crepes?|crêpes?|pancakes?)\b/.test(normalizedTitle)) {
    return [
      `Versez le ${flour} et le ${sugar} dans un saladier, puis formez un puits au centre.`,
      `Incorporez les ${eggs}, puis fouettez en versant progressivement le ${milk} pour obtenir une pâte bien lisse.`,
      `Ajoutez le ${butter} fondu, mélangez une dernière fois et laissez reposer la pâte quelques minutes.`,
      "Chauffez une poêle légèrement beurrée, versez une louche de pâte et répartissez-la en une couche fine.",
      "Faites cuire la crêpe jusqu'à ce que les bords se décollent, retournez-la, puis répétez avec le reste de la pâte avant de servir."
    ];
  }

  if (/\b(?:burger|sandwich|naan|toast)\b/.test(normalizedTitle) && ingredientSignals.hasBreadDoughBase && ingredientSignals.hasProtein) {
    return [
      `Diluez la ${yeast} dans la ${water} avec un peu de ${sugar}, puis laissez mousser quelques minutes.`,
      `Mélangez le ${flour} avec l'assaisonnement, ajoutez le ${yogurt} et la levure diluée, puis pétrissez jusqu'à obtenir une pâte souple.`,
      `Incorporez le ${butter}, couvrez la pâte et laissez-la reposer jusqu'à ce qu'elle gonfle légèrement.`,
      "Divisez la pâte en portions, étalez-les en disques puis faites cuire les naans dans une poêle bien chaude jusqu'à ce qu'ils soient dorés par endroits.",
      `Préparez la garniture en éminçant le ${aromatic}, en lavant la ${greens} et en assaisonnant le ${protein}.`,
      `Faites cuire le ${protein} jusqu'à ce qu'il soit bien doré et cuit à cœur, puis ajoutez éventuellement le ${cheese} pour le faire fondre légèrement.`,
      `Garnissez chaque ${bread} ou naan avec la ${sauce}, la ${greens}, le ${protein} et les autres garnitures, puis servez aussitôt.`
    ];
  }

  if (/\b(?:burger|sandwich|naan|toast)\b/.test(normalizedTitle)) {
    return [
      `Préparez les garnitures en éminçant le ${aromatic} et en assaisonnant le ${protein}.`,
      `Faites cuire le ${protein} dans une poêle chaude jusqu'à ce qu'il soit bien doré et cuit à cœur.`,
      `Préparez les accompagnements en lavant la ${greens}, en ajoutant la ${sauce} et en gardant le ${bread} prêt à être garni.`,
      `Réchauffez ou toastez le ${bread} pour lui redonner du moelleux et un peu de croustillant.`,
      `Montez le ${title.toLocaleLowerCase()} avec le ${bread}, le ${protein}, les garnitures et la sauce, puis servez aussitôt.`
    ];
  }

  if (/\bwrap\b/.test(normalizedTitle)) {
    return [
      `Assaisonnez le ${protein} puis faites-le cuire jusqu'à ce qu'il soit bien doré.`,
      `Préparez la garniture en éminçant le ${aromatic} et en gardant la ${greens} et la ${sauce} à portée de main.`,
      `Réchauffez le ${bread} quelques secondes pour l'assouplir sans le dessécher.`,
      `Disposez la ${greens}, le ${protein}, le ${aromatic} et la ${sauce} au centre du ${bread}.`,
      `Rabattez les côtés, roulez le ${title.toLocaleLowerCase()} bien serré et servez immédiatement.`
    ];
  }

  if (/\b(?:pasta|pates?|curry|risotto)\b/.test(normalizedTitle)) {
    return [
      `Préparez tous les ingrédients en coupant le ${aromatic} et en assaisonnant le ${protein}.`,
      `Faites revenir le ${aromatic} avec un peu de matière grasse, puis ajoutez le ${protein} et faites-le cuire.`,
      "Ajoutez l'élément principal de la recette, mélangez bien et laissez mijoter jusqu'à obtenir une texture liée.",
      `Rectifiez l'assaisonnement, dressez le ${title.toLocaleLowerCase()} bien chaud et servez sans attendre.`
    ];
  }

  if (/\bpizza\b/.test(normalizedTitle)) {
    return [
      `Étalez la pâte puis répartissez la sauce et les garnitures sur toute la surface.`,
      `Ajoutez le fromage et les éléments principaux du ${title.toLocaleLowerCase()}.`,
      "Faites cuire dans un four très chaud jusqu'à ce que la pâte soit dorée et la garniture bien fondante.",
      "Laissez reposer une minute, découpez en parts et servez immédiatement."
    ];
  }

  if (/\b(?:salade|salad|bowl)\b/.test(normalizedTitle)) {
    return [
      `Lavez et préparez les légumes, puis détaillez le ${aromatic} si nécessaire.`,
      `Faites cuire le ${protein} jusqu'à obtenir une belle coloration, puis laissez-le tiédir légèrement.`,
      `Assemblez les ingrédients dans un saladier avec la ${greens} et la ${sauce}.`,
      `Mélangez délicatement, rectifiez l'assaisonnement et servez le ${title.toLocaleLowerCase()}.`
    ];
  }

  if (/\b(?:cake|gateau|gâteau|brownie|cookie|dessert|tiramisu)\b/.test(normalizedTitle)) {
    return [
      "Préparez tous les ingrédients et préchauffez le four ou le matériel nécessaire selon la recette.",
      "Mélangez les ingrédients secs dans un premier récipient et les ingrédients humides dans un second.",
      "Réunissez les deux préparations sans trop travailler la pâte afin de conserver une texture homogène.",
      `Versez la préparation dans le moule ou le plat adapté, puis faites cuire jusqu'à ce que le ${title.toLocaleLowerCase()} soit pris.`,
      "Laissez tiédir quelques minutes avant de démouler, découper ou dresser, puis servez."
    ];
  }

  return [
    `Préparez les ingrédients du ${title.toLocaleLowerCase()} en détaillant le ${aromatic} et en assaisonnant la garniture principale.`,
    `Faites cuire les éléments principaux dans une poêle chaude jusqu'à obtenir une cuisson régulière et une bonne coloration.`,
    "Ajoutez les garnitures et mélangez jusqu'à obtenir une préparation bien liée et équilibrée.",
    `Rectifiez l'assaisonnement, dressez le ${title.toLocaleLowerCase()} et servez immédiatement.`
  ];
}

function preferredIngredient(
  ingredients: URLImportSuccessResponse["data"]["ingredients"],
  patterns: RegExp[],
  fallback: string
): string {
  const match = ingredients.find((ingredient) =>
    patterns.some((pattern) => pattern.test(ingredient.name))
  );

  return match?.name || fallback;
}

function minimumGeneratedStepCount(
  title: string,
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): number {
  const normalizedTitle = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  const ingredientSignals = generatedIngredientSignals(ingredients);

  if (/\b(?:omelette|toast|croque|quesadilla|tartine)\b/.test(normalizedTitle)) {
    return 2;
  }

  if (/\b(?:crepes?|crêpes?|pancakes?)\b/.test(normalizedTitle)) {
    return 5;
  }

  if (/\b(?:burger|sandwich|naan|wrap|taco)\b/.test(normalizedTitle)) {
    if (ingredientSignals.hasBreadDoughBase && ingredientSignals.hasProtein) {
      return 7;
    }

    if (ingredientSignals.hasProtein || ingredientSignals.hasAssemblyFillings) {
      return 5;
    }
  }

  if (/\b(?:cake|gateau|gâteau|brownie|cookie|dessert|tiramisu)\b/.test(normalizedTitle)) {
    return 5;
  }

  return 4;
}

function generatedIngredientSignals(
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): {
  hasBreadDoughBase: boolean;
  hasProtein: boolean;
  hasAssemblyFillings: boolean;
} {
  const hasFlour = ingredients.some((ingredient) => /\bfarine\b|\bflour\b/i.test(ingredient.name));
  const hasLeavening = ingredients.some((ingredient) => /\blevure\b|\byeast\b|\bbaking powder\b|\blevure chimique\b/i.test(ingredient.name));
  const hasDairyOrWater = ingredients.some((ingredient) => /\byaourt\b|\byogurt\b|\blait\b|\bmilk\b|\beau\b|\bwater\b/i.test(ingredient.name));
  const hasProtein = ingredients.some((ingredient) => /\bpoulet\b|\bchicken\b|\bboeuf\b|\bburger\b|\bviande\b|\bpoisson\b|\bfish\b|\bsaumon\b|\btofu\b/i.test(ingredient.name));
  const hasAssemblyFillings = ingredients.some((ingredient) => /\bsalade\b|\blettuce\b|\boignon\b|\bonion\b|\bfromage\b|\bcheddar\b|\bsauce\b|\btomate\b/i.test(ingredient.name));

  return {
    hasBreadDoughBase: hasFlour && hasLeavening && hasDairyOrWater,
    hasProtein,
    hasAssemblyFillings
  };
}

function parseQuantityValue(value: string): number | null {
  const cleaned = value.replace(",", ".").trim();
  if (!cleaned) {
    return null;
  }

  const mixedMatch = cleaned.match(/^(\d+)\s+(\d+)\s*\/\s*(\d+)$/);
  if (mixedMatch) {
    const whole = Number(mixedMatch[1]);
    const num = Number(mixedMatch[2]);
    const den = Number(mixedMatch[3]);
    if (den > 0) {
      return Math.round((whole + num / den) * 100) / 100;
    }
  }

  const fractionMatch = cleaned.match(/^(\d+)\s*\/\s*(\d+)$/);
  if (fractionMatch) {
    const num = Number(fractionMatch[1]);
    const den = Number(fractionMatch[2]);
    if (den > 0) {
      return Math.round((num / den) * 100) / 100;
    }
  }

  const rangeMatch = cleaned.match(/^(\d+(?:\.\d+)?)\s*[-–à]\s*(\d+(?:\.\d+)?)$/);
  if (rangeMatch) {
    const low = Number(rangeMatch[1]);
    const high = Number(rangeMatch[2]);
    if (Number.isFinite(low) && Number.isFinite(high)) {
      return Math.round(((low + high) / 2) * 100) / 100;
    }
  }

  const simpleMatch = cleaned.match(/^(\d+(?:\.\d+)?)$/);
  if (simpleMatch) {
    const val = Number(simpleMatch[1]);
    return Number.isFinite(val) ? val : null;
  }

  return null;
}

function capitalizeDisplay(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) {
    return "";
  }

  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
}

/**
 * Drop ingredients that are not referenced in ANY recipe step. The LLM
 * occasionally inflates the ingredient list with items from a parallel
 * sub-recipe mentioned in the social caption (e.g. the bread recipe
 * mentioned alongside the wrap it accompanies) and the validator
 * downstream only FLAGS this — it never removes. We remove
 * defensively here, with two protections:
 *   1. Ingredients tagged with a non-empty `display` text shorter than 4
 *      chars are kept (they are usually salt/pepper/oil seasoning that
 *      may be used implicitly).
 *   2. We never drop more than a third of the ingredient list, to avoid
 *      pathological cases where the steps are themselves wrong.
 */
function dropUnreferencedIngredients(
  ingredients: URLImportSuccessResponse["data"]["ingredients"],
  steps: URLImportSuccessResponse["data"]["steps"]
): Set<string> {
  if (!ingredients.length || !steps.length) return new Set();

  const allStepText = steps
    .map((step) => normalizeIngredientKey(step.description))
    .join(" | ");
  if (!allStepText) return new Set();

  // Whitelist short basic seasonings that often go unmentioned in steps.
  const BASIC_SEASONINGS = new Set([
    "sel",
    "poivre",
    "salt",
    "pepper",
    "huile",
    "oil",
    "beurre",
    "butter",
    "sucre",
    "sugar",
    "eau",
    "water"
  ]);

  const candidates: string[] = [];
  for (const ing of ingredients) {
    const normalized = normalizeIngredientKey(ing.name);
    if (!normalized || BASIC_SEASONINGS.has(normalized)) continue;

    const tokens = normalized.split(" ").filter((t) => t.length >= 4);
    if (tokens.length === 0) continue;
    const referenced = tokens.some((token) => allStepText.includes(token));
    if (!referenced) {
      candidates.push(ing.name);
    }
  }

  // Cap the dropped set at one third of the ingredient list to avoid
  // wiping out a legitimate recipe when the steps are themselves
  // mismatched.
  const cap = Math.max(1, Math.floor(ingredients.length / 3));
  if (candidates.length > cap) {
    console.warn(
      `[dropUnreferencedIngredients] Found ${candidates.length} unreferenced ingredients but capping at ${cap}; steps may also be inaccurate.`
    );
    return new Set(candidates.slice(0, cap));
  }
  if (candidates.length > 0) {
    console.warn(
      `[dropUnreferencedIngredients] Removing ${candidates.length} unreferenced ingredient(s): ${candidates.join(", ")}`
    );
  }
  return new Set(candidates);
}

function ingredientNamesForStep(
  description: string,
  ingredientNames: string[]
): string[] | undefined {
  if (!ingredientNames.length) {
    return undefined;
  }

  const normalizedDesc = normalizeIngredientKey(description);
  const matches: string[] = [];

  for (const name of ingredientNames) {
    const normalizedName = normalizeIngredientKey(name);
    if (!normalizedName || normalizedName.length < 2) {
      continue;
    }

    const tokens = normalizedName.split(" ").filter(Boolean);
    const matched = tokens.some((token) =>
      token.length >= 3 && normalizedDesc.includes(token)
    );

    if (matched) {
      matches.push(name);
    }
  }

  return matches.length > 0 ? matches : undefined;
}

function splitLongSteps(
  steps: URLImportSuccessResponse["data"]["steps"],
  ingredientNames: string[]
): URLImportSuccessResponse["data"]["steps"] {
  const result: URLImportSuccessResponse["data"]["steps"] = [];
  const splitPatterns = [", puis ", ", ensuite ", ". Ensuite, ", ". Puis, "];

  for (const step of steps) {
    const desc = step.description;
    if (desc.length <= 200) {
      result.push(step);
      continue;
    }

    let wasSplit = false;
    for (const pattern of splitPatterns) {
      const index = desc.toLowerCase().indexOf(pattern.toLowerCase());
      if (index > 20 && index < desc.length - 20) {
        const first = desc.slice(0, index).trim();
        const rest = desc.slice(index + pattern.length).trim();
        const capitalizedRest = rest.charAt(0).toUpperCase() + rest.slice(1);

        result.push({
          stepNumber: 0,
          description: first,
          section: step.section,
          ingredientRefs: ingredientNamesForStep(first, ingredientNames)
        });
        result.push({
          stepNumber: 0,
          description: capitalizedRest,
          ingredientRefs: ingredientNamesForStep(capitalizedRest, ingredientNames)
        });
        wasSplit = true;
        break;
      }
    }

    if (!wasSplit) {
      result.push(step);
    }
  }

  return result.map((step, index) => ({
    ...step,
    stepNumber: index + 1
  }));
}

function ensureIngredientStepCoverage(
  steps: URLImportSuccessResponse["data"]["steps"],
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): URLImportSuccessResponse["data"]["steps"] {
  const ingredientNames = ingredients.map((i) => i.name);
  const majorIngredientNames = ingredients
    .filter((i) => {
      const key = normalizeIngredientKey(i.name);
      return !/\b(?:sel|salt|poivre|pepper|huile|oil|eau|water|beurre|butter)\b/.test(key);
    })
    .map((i) => i.name);

  if (!majorIngredientNames.length) {
    return steps;
  }

  const coveredIngredients = new Set<string>();
  for (const step of steps) {
    const refs = ingredientNamesForStep(step.description, majorIngredientNames);
    if (refs) {
      for (const ref of refs) {
        coveredIngredients.add(normalizeIngredientKey(ref));
      }
    }
  }

  const uncoveredIngredients = majorIngredientNames.filter(
    (name) => !coveredIngredients.has(normalizeIngredientKey(name))
  );

  if (uncoveredIngredients.length <= 2) {
    return steps;
  }

  const batch1 = uncoveredIngredients.slice(0, 3);
  const extraSteps: URLImportSuccessResponse["data"]["steps"] = [];

  if (batch1.length > 0) {
    const ingredientList = batch1.join(", ");
    const desc = `Ajoutez ${ingredientList} et incorporez au reste de la préparation.`;
    extraSteps.push({
      stepNumber: 0,
      description: desc,
      ingredientRefs: batch1
    });
  }

  const batch2 = uncoveredIngredients.slice(3);
  if (batch2.length > 0) {
    const ingredientList = batch2.join(", ");
    const desc = `Ajoutez ${ingredientList} et mélangez bien.`;
    extraSteps.push({
      stepNumber: 0,
      description: desc,
      ingredientRefs: batch2
    });
  }

  const lastCookingStepIndex = steps.length > 1 ? steps.length - 1 : steps.length;
  const combined = [
    ...steps.slice(0, lastCookingStepIndex),
    ...extraSteps,
    ...steps.slice(lastCookingStepIndex)
  ];

  return combined.map((step, index) => ({
    ...step,
    stepNumber: index + 1
  }));
}

const instructionVerbPattern = /\b(?:preparez|préparez|assaisonnez|faites|chauffez|cuisez|ajoutez|melangez|mélangez|versez|disposez|repartissez|répartissez|montez|assemblez|rabattez|roulez|etalez|étalez|rechauffez|réchauffez|toastez|fouettez|incorporez|laissez|servez|garnissez|saisissez|rectifiez|poursuivez|dressez|enfournez|coupez|emincez|émincez|detaillez|détaillez|petrir|pétrir|façonnez|faconnez|formez|divisez|boulez|filmer|filmerz|saupoudrez|singer|degazez|dégazez|couvrez|decoupez|découpez|decouper|découper|former|former|plongez|portez|ebullition|ébullition|refroidir|refroidissez|egouttez|égouttez|saler|poivrer|dorez|dorez|griller|grillez|prechauffez|préchauffez|etalez|plier|pliez|farcir|farcissez|aplatir|aplatissez|mariner|marinez|deglacer|déglacer|deglacer|flamber|flambez|dresser|pocher|pochez|blanchir|blanchissez|saisir|faire revenir|revenir|depouillez|filtrez|assaisonner|reserver|réserver|reservez|réservez|sortez|retirer|retirez|ajouter|melanger|melangez|continuer|continuez|terminez|finir|finissez|couvrir)\b/;
const ingredientNarrativePattern = /\b(?:je vais|on va|tu vas|vous allez|en plusieurs fois|fois en tout|toute petite louche|c est super simple|c est delicieux|et ensuite|on a|regarde|video|abonne|abonnez|abonnes|follow|follower|followers|like|liker|likez|partage|partager|partagez|commente|commenter|commentez|rejoins|rejoignez|save|sauvegarde|sauvegarder|sauvegardez|clique|cliquer|cliquez|telecharg|télécharg|notification|notif|instagram|tiktok|pinterest|youtube|reels?|story|stories|hashtag|link in bio|en bio|lien en bio|lien bio)\b/;
const ingredientBadStartPattern = /^(?:et|ensuite|puis|alors|voila|voilà|du coup|on a|c est)\b/;
const ingredientFoodPattern = /\b(?:oeufs?|œufs?|eggs?|farine|flour|sucre|sugar|sel|lait|milk|beurre|butter|vanille|vanilla|rhum|fleur|orange|cheddar|oignon|onion|tomate|tomato|poulet|chicken|salade|lettuce|sauce|yaourt|yogurt|citron|lemon|huile|oil|chocolat|chocolate|creme|crème|cream|fromage|cheese|riz|rice|pates?|pâtes?|pasta|levure|yeast|eau|water|miel|honey|sirop|syrup|pain|bun|boeuf|bœuf|beef|poisson|fish|saumon|salmon|thon|tuna|crevette|shrimp|avocat|avocado|concombre|cucumber|carotte|carrot|champignon|mushroom)\b/;
