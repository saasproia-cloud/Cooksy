import { z } from "zod";

import { normalizeWhitespace } from "../utils/text.js";
import {
  cleanIngredientNameField,
  normalizeFrenchIngredientName,
  normalizeFrenchUnit,
} from "../services/ingredientNormalization.js";
import {
  containsFoodSignal,
  hasPlausibleIngredientShape,
} from "../services/foodTermGate.js";

export const recipeIngredientSchema = z.object({
  amount: z.string().default(""),
  unit: z.string().default(""),
  name: z.string().default(""),
  nutritionQuery: z.string().default(""),
  group: z.string().optional()
});

export const recipeStepSchema = z.object({
  detail: z.string().default(""),
  section: z.string().optional()
});

export const recipeImportFlagsSchema = z.object({
  usedExplicitIngredients: z.boolean().default(false),
  usedInferredIngredients: z.boolean().default(false),
  generatedSteps: z.boolean().default(false),
  generatedNutrition: z.boolean().default(false),
  needsReview: z.boolean().default(false)
});

export const recipeImportSchema = z.object({
  title: z.string().default(""),
  sourceUrl: z.string().default(""),
  creatorHandle: z.string().optional(),
  externalRating: z.number().min(0).max(5).optional(),
  externalRatingCount: z.number().int().positive().optional(),
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
  confidenceScore: z.number().min(0).max(1).optional(),
  needsWebFallback: z.boolean().default(false),
  searchQuery: z.string().default(""),
  inferredFromPhoto: z.boolean().default(false),
  flags: recipeImportFlagsSchema.optional()
});

export type RecipeIngredientDraft = z.infer<typeof recipeIngredientSchema>;
export type RecipeImportResult = z.infer<typeof recipeImportSchema>;
export type RecipeImportFlags = z.infer<typeof recipeImportFlagsSchema>;
export type RecipeCookabilitySignals = {
  majorIngredientCount: number;
  uncoveredMajorIngredientCount: number;
  majorIngredientCoverage: number;
};

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
  needsReview?: boolean;
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
  transcriptDigest?: string;
  imageDataUrl?: string;
  /**
   * True when the social caption is empty/sparse and the audio
   * transcript is the only meaningful source of recipe content. The
   * normalizer uses this to forbid template-completion behavior and
   * stick strictly to what was actually spoken.
   */
  audioIsPrimarySource?: boolean;
};

export function hasSuspiciousRecipeTitle(value: string): boolean {
  const cleanedValue = clean(value);
  if (!cleanedValue) {
    return false;
  }

  const normalized = normalizeLookup(cleanedValue);
  if (!normalized) {
    return false;
  }

  if (isLikelyArticleTitle(cleanedValue)) {
    return true;
  }

  if (/@[\p{L}\p{N}._-]+/u.test(cleanedValue) && !containsLikelyFoodTitleTerm(normalized)) {
    return true;
  }

  if (
    socialHookTitlePatterns.some((pattern) => pattern.test(normalized)) &&
    (!containsLikelyFoodTitleTerm(normalized) || normalized.length > 48)
  ) {
    return true;
  }

  if (normalized.split(" ").length > 10 && !containsLikelyFoodTitleTerm(normalized)) {
    return true;
  }

  return false;
}

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

export function normalizeRecipeImportFlags(flags?: Partial<RecipeImportFlags> | null): RecipeImportFlags {
  return {
    usedExplicitIngredients: flags?.usedExplicitIngredients === true,
    usedInferredIngredients: flags?.usedInferredIngredients === true,
    generatedSteps: flags?.generatedSteps === true,
    generatedNutrition: flags?.generatedNutrition === true,
    needsReview: flags?.needsReview === true
  };
}

export function sanitizeRecipeImport(input: RecipeImportResult): RecipeImportResult {
  const rawTitle = clean(input.title);
  const title = sanitizeTitle(input.title);
  const ingredientDrafts = dedupeIngredients(
    input.ingredientDrafts
      .flatMap(sanitizeIngredientDraft)
  );
  const stepDrafts = dedupeSteps(
    input.stepDrafts
      .map((step) => ({
        detail: sanitizeStepDetail(step.detail),
        ...(step.section ? { section: normalizeWhitespace(step.section) } : {})
      }))
      .filter((step) => isPlausibleCookingStep(step.detail) && !looksLikeIncompleteStepFragment(step.detail))
  );
  const titleLooksArticleLike = (rawTitle.length > 0 && hasSuspiciousRecipeTitle(rawTitle)) ||
    (title.length > 0 && hasSuspiciousRecipeTitle(title));
  const cookabilitySignals = recipeCookabilitySignals({
    ...input,
    ingredientDrafts,
    stepDrafts
  });
  const flags = normalizeRecipeImportFlags(input.flags);
  const normalizedConfidence = clampConfidence(
    input.confidence,
    ingredientDrafts.length,
    stepDrafts.length,
    titleLooksArticleLike,
    cookabilitySignals
  );
  const confidenceScore = clampConfidenceScore(
    input.confidenceScore,
    normalizedConfidence,
    title,
    ingredientDrafts.length,
    stepDrafts.length,
    titleLooksArticleLike,
    cookabilitySignals,
    flags
  );
  const thinStructure = hasThinRecipeStructure({
    title,
    ingredientDrafts,
    stepDrafts,
    confidence: normalizedConfidence
  });
  const cookabilityGap = cookabilitySignals.majorIngredientCount >= 4 &&
    (
      cookabilitySignals.majorIngredientCoverage < 0.55 ||
      cookabilitySignals.uncoveredMajorIngredientCount >= 2
    );
  const strongStructuredImport = !titleLooksArticleLike &&
    title.length > 2 &&
    ingredientDrafts.length >= 6 &&
    stepDrafts.length >= 4 &&
    confidenceScore >= 0.78;
  const shouldFallback = titleLooksArticleLike ||
    normalizedConfidence === "low" ||
    thinStructure ||
    (cookabilityGap && !strongStructuredImport) ||
    (input.needsWebFallback && !strongStructuredImport);

  return {
    ...input,
    title,
    sourceUrl: normalizeUrl(input.sourceUrl),
    creatorHandle: normalizeCreatorHandle(input.creatorHandle, input.sourceUrl),
    externalRating: normalizeRatingValue(input.externalRating),
    externalRatingCount: normalizeRatingCount(input.externalRatingCount),
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
    confidenceScore,
    needsWebFallback: shouldFallback,
    searchQuery: clean(input.searchQuery),
    flags
  };
}

function normalizeCreatorHandle(value?: string, sourceUrl?: string): string | undefined {
  const trimmed = clean(value);
  if (trimmed) {
    const sanitized = (trimmed.startsWith("@") ? trimmed : `@${trimmed}`)
      .replace(/[^@A-Za-z0-9._]/g, "");
    return sanitized.length > 1 ? sanitized : undefined;
  }

  const parsedFromSource = extractCreatorHandleFromUrl(sourceUrl);
  return parsedFromSource ? normalizeCreatorHandle(parsedFromSource) : undefined;
}

function normalizeRatingValue(value?: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  if (value < 0 || value > 5) {
    return undefined;
  }

  return Math.round(value * 10) / 10;
}

function normalizeRatingCount(value?: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  const rounded = Math.round(value);
  return rounded > 0 ? rounded : undefined;
}

function extractCreatorHandleFromUrl(sourceUrl?: string): string | undefined {
  const normalized = normalizeUrl(sourceUrl);
  if (!normalized) {
    return undefined;
  }

  try {
    const url = new URL(normalized);
    const host = url.host.toLowerCase();
    const pathSegments = url.pathname.split("/").filter(Boolean);

    if (host.includes("tiktok")) {
      return pathSegments.find((segment) => segment.startsWith("@"));
    }

    if (host.includes("instagram")) {
      const candidate = pathSegments[0];
      if (!candidate || ["reel", "p", "tv", "stories", "explore"].includes(candidate.toLowerCase())) {
        return undefined;
      }
      return `@${candidate}`;
    }
  } catch {
    return undefined;
  }

  return undefined;
}

export function recipeCookabilitySignals(
  recipe: Pick<RecipeImportResult, "ingredientDrafts" | "stepDrafts">
): RecipeCookabilitySignals {
  const steps = recipe.stepDrafts
    .map((step) => normalizeLookup(step.detail))
    .filter(Boolean);
  const majorIngredients = recipe.ingredientDrafts
    .filter((ingredient) => isLikelyMajorIngredient(ingredient.name))
    .map((ingredient) => ingredientConceptTokens(ingredient))
    .filter((tokens) => tokens.length > 0);

  if (!majorIngredients.length || !steps.length) {
    return {
      majorIngredientCount: majorIngredients.length,
      uncoveredMajorIngredientCount: majorIngredients.length,
      majorIngredientCoverage: 0
    };
  }

  let coveredIngredients = 0;
  for (const tokens of majorIngredients) {
    if (tokens.some((token) => steps.some((step) => containsWholeToken(step, token)))) {
      coveredIngredients += 1;
    }
  }

  const coverage = coveredIngredients / majorIngredients.length;

  return {
    majorIngredientCount: majorIngredients.length,
    uncoveredMajorIngredientCount: majorIngredients.length - coveredIngredients,
    majorIngredientCoverage: coverage
  };
}

export function hasCookabilityGaps(recipe: Pick<RecipeImportResult, "ingredientDrafts" | "stepDrafts">): boolean {
  const signals = recipeCookabilitySignals(recipe);

  if (signals.majorIngredientCount < 4 || recipe.stepDrafts.length < 2) {
    return false;
  }

  return signals.majorIngredientCoverage < 0.45 ||
    signals.uncoveredMajorIngredientCount >= 3;
}

export function scoreRecipe(recipe: RecipeImportResult): number {
  const nutritionScore = [recipe.caloriesText, recipe.proteinText, recipe.carbsText, recipe.fatText]
    .filter((value) => value.length > 0)
    .length * 2;
  const titlePenalty = hasSuspiciousRecipeTitle(recipe.title) ? -18 : 0;
  const cookability = recipeCookabilitySignals(recipe);
  const missingPenalty = importMissingParts(recipe).length * 16;
  const cookabilityBonus = Math.round(cookability.majorIngredientCoverage * 10);
  const uncoveredPenalty = cookability.uncoveredMajorIngredientCount * 3;
  const thinStructurePenalty = hasThinRecipeStructure(recipe) ? 8 : 0;
  const cookabilityGapPenalty = hasCookabilityGaps(recipe) ? 14 : 0;

  // Bonus for specific/compound dish titles (e.g., "Pizza Tartiflette à la Poêle"
  // scores higher than a generic "Pizza")
  const titleWords = clean(recipe.title).split(/\s+/).filter(Boolean).length;
  const titleSpecificityBonus = titleWords >= 3 ? Math.min(titleWords * 3, 15) : 0;

  return recipe.ingredientDrafts.length * 6 +
    recipe.stepDrafts.length * 7 +
    (recipe.title.length > 0 ? 10 : 0) +
    (recipe.notesText.length > 0 ? 2 : 0) +
    (recipe.remoteImageUrl.length > 0 ? 2 : 0) +
    nutritionScore +
    (recipe.confidence === "high" ? 8 : recipe.confidence === "medium" ? 4 : 0) +
    cookabilityBonus +
    titleSpecificityBonus +
    titlePenalty -
    missingPenalty -
    uncoveredPenalty -
    thinStructurePenalty -
    cookabilityGapPenalty;
}

export function shouldFallbackToSearch(recipe: RecipeImportResult): boolean {
  return recipe.needsWebFallback ||
    recipe.confidence === "low" ||
    importMissingParts(recipe).length > 0 ||
    hasThinRecipeStructure(recipe) ||
    hasCookabilityGaps(recipe) ||
    hasSuspiciousRecipeTitle(recipe.title);
}

export function importMissingParts(recipe: RecipeImportResult): ImportDebugMissing[] {
  const missing: ImportDebugMissing[] = [];
  const minimumIngredientCount = minimumIngredientCountForRecipeTitle(recipe.title);
  const minimumStepCount = minimumStepCountForRecipeTitle(recipe.title);

  if (recipe.ingredientDrafts.length < minimumIngredientCount) {
    missing.push("ingredients");
  }

  if (recipe.stepDrafts.length < minimumStepCount) {
    missing.push("steps");
  }

  return missing;
}

function hasThinRecipeStructure(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "stepDrafts" | "confidence">
): boolean {
  const minimumIngredientCount = minimumIngredientCountForRecipeTitle(recipe.title);
  const minimumStepCount = minimumStepCountForRecipeTitle(recipe.title);
  const ingredientSlack = recipe.confidence === "high" ? 1 : 0;
  const stepSlack = recipe.confidence === "high" ? 1 : 0;

  return recipe.ingredientDrafts.length + ingredientSlack < minimumIngredientCount ||
    recipe.stepDrafts.length + stepSlack < minimumStepCount;
}

function hasCompactCompleteStructure(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "stepDrafts">
): boolean {
  const normalizedTitle = clean(recipe.title);
  if (
    normalizedTitle.length <= 2 ||
    hasSuspiciousRecipeTitle(normalizedTitle) ||
    !isCompactSimpleRecipeTitle(normalizedTitle) ||
    recipe.stepDrafts.length < minimumStepCountForRecipeTitle(normalizedTitle)
  ) {
    return false;
  }

  const substantialIngredientCount = recipe.ingredientDrafts
    .filter((ingredient) => isLikelyMajorIngredient(ingredient.name))
    .length;

  return substantialIngredientCount >= minimumIngredientCountForRecipeTitle(normalizedTitle);
}

export function isLikelyValidRecipe(
  recipe: RecipeImportResult,
  options?: { transcript?: string }
): boolean {
  const normalizedTitle = clean(recipe.title);
  return hasMeaningfulFoodSignal(recipe, options) &&
    normalizedTitle.length > 2 &&
    normalizedTitle.length <= 90 &&
    !hasSuspiciousRecipeTitle(normalizedTitle) &&
    importMissingParts(recipe).length === 0;
}

export function importFailureReason(
  recipe: RecipeImportResult,
  options?: {
    preferWeakMetadata?: boolean;
    timedOut?: boolean;
    transcript?: string;
  }
): ImportFailureReason | undefined {
  if (options?.timedOut) {
    return "import_too_slow";
  }

  if (!hasMeaningfulFoodSignal(recipe, { transcript: options?.transcript })) {
    return options?.preferWeakMetadata
      ? "weak_tiktok_metadata"
      : "no_recipe_detected";
  }

  const missing = importMissingParts(recipe);
  if (!missing.length) {
    if (hasSuspiciousRecipeTitle(recipe.title)) {
      return "invalid_recipe_result";
    }
    return undefined;
  }

  if (options?.preferWeakMetadata) {
    return "weak_tiktok_metadata";
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

  cleaned = trimRepeatedLeadPhrase(cleaned);

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
    .replace(/\b(?:les|le|la|des|un|une)\s*$/iu, "")
    .replace(/\s*[:\-–]\s*$/u, "")
    .trim();

  const inlineIngredientMatch = cleaned.match(/\b\d+(?:[.,]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup|egg|eggs|packet|packets?|steak|steaks|tranche|tranches|pain|pains|bun|buns)\b/i);
  if (inlineIngredientMatch && typeof inlineIngredientMatch.index === "number" && inlineIngredientMatch.index >= 8) {
    cleaned = cleaned.slice(0, inlineIngredientMatch.index).trim();
  }

  const explanatoryClauseMatch = cleaned.match(/\b(?:avec|mais|sans|version|qui|qu['’]|pour)\b/i);
  if (cleaned.length > 56 && explanatoryClauseMatch && typeof explanatoryClauseMatch.index === "number" && explanatoryClauseMatch.index >= 16) {
    cleaned = cleaned.slice(0, explanatoryClauseMatch.index).trim();
  }

  if (cleaned.length > 80) {
    cleaned = clean(cleaned.split(/[.!?]/)[0] ?? cleaned);
  }

  if (cleaned === cleaned.toUpperCase() && /[A-ZÀ-ÿ]/.test(cleaned)) {
    cleaned = cleaned
      .toLowerCase()
      .replace(/\b\p{L}/gu, (character) => character.toUpperCase());
  }

  if (hasSuspiciousRecipeTitle(cleaned)) {
    return "";
  }

  if (containsSocialNoise(cleaned)) {
    return "";
  }

  return cleaned;
}

function sanitizeIngredientDraft(ingredient: RecipeIngredientDraft): RecipeIngredientDraft[] {
  let amount = clean(ingredient.amount);
  let unit = normalizeFrenchUnit(clean(ingredient.unit));
  const originalName = clean(ingredient.name);
  const isServeOnlyIngredient = /\b(?:to serve|for serving|pour servir|optional|facultatif)\b/i.test(originalName);
  const nameSegments = splitCompoundIngredientText(ingredient.name);
  const nutritionQuerySegments = splitCompoundIngredientText(ingredient.nutritionQuery);
  const sanitized: RecipeIngredientDraft[] = [];

  for (const [index, rawName] of nameSegments.entries()) {
    const cleanedName = sanitizeIngredientName(rawName);
    // Universal ASR-artifact pass: extract any unit/amount tokens that
    // leaked into the name field (e.g. "à soupe huile" -> name "Huile"
    // + unit "c. à soupe") and collapse duplicated head words ("Oeufs
    // Oeufs" -> "Œufs"). Back-fills empty amount/unit fields on the
    // first segment only, so compound ingredients don't duplicate.
    const asrCleaned = cleanIngredientNameField(cleanedName, unit || undefined, amount || undefined);
    if (asrCleaned.dropped) {
      continue;
    }
    if (index === 0) {
      if (!amount && asrCleaned.extractedAmount) {
        amount = asrCleaned.extractedAmount;
      }
      if (!unit && asrCleaned.extractedUnit) {
        unit = normalizeFrenchUnit(asrCleaned.extractedUnit);
      }
    }
    const preNormalized = asrCleaned.name || cleanedName;
    // Apply the normalization table AFTER the ASR cleanup so noisy
    // spoken forms ("oeufs", "blanc de poulet", "tomates cerises") get
    // a canonical display. The normalizer is non-generifying by design
    // and falls back to cleaned raw input when no match is found.
    const name = preNormalized
      ? (normalizeFrenchIngredientName(preNormalized).displayName || preNormalized)
      : preNormalized;
    const nutritionQuery = sanitizeNutritionQuery(
      nutritionQuerySegments[index] ?? nutritionQuerySegments[0] ?? name,
      name
    );

    if (!isPlausibleIngredientName(name) || containsSocialNoise(name) || containsNarrativeIngredientNoise(name)) {
      continue;
    }

    if (isServeOnlyIngredient && !amount && !unit) {
      continue;
    }

    sanitized.push({
      amount: index === 0 ? amount : "",
      unit: index === 0 ? unit : "",
      name,
      nutritionQuery,
      group: clean(ingredient.group ?? "")
    });
  }

  return sanitized;
}

function sanitizeIngredientName(value: string): string {
  const stripped = stripLeadingIngredientMeasurement(
    stripIngredientNarrativeFragments(
      clean(value)
        .replace(/^\s*(?:[-•*]|\d+[\).\-\s]+)\s*/u, "")
        .replace(/^\s*(?:une?\s+)?\d+\s*(?:e|eme|ème|ene|aine)\s+de\s+/i, "")
        .replace(/\s*\((?:see note|optional|facultatif|to taste)\)$/i, "")
        .replace(/\s*\((?:ici|comme ici)[^)]*\)/i, "")
        .replace(/\s+(?:to serve|for serving|pour servir)\b.*$/i, "")
        .replace(/\s+plus\b.*$/i, "")
        .replace(/\s{2,}/g, " ")
        .trim()
    )
  );

  // Collapse accidental word duplication from noisy transcripts, e.g. "Oeufs oeufs",
  // "Farine farine", "Poulet poulet".
  return stripped
    .replace(/\b(\p{L}+)\s+\1\b/giu, "$1")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function stripIngredientNarrativeFragments(value: string): string {
  return clean(value)
    .replace(/^(?:j['’]?ai\s+utilis[eé]|i\s+used)\s+/i, "")
    .replace(/^(?:j['’]?utilise|utilis[eé]e?s?)\s+/i, "")
    .replace(/^(?:comme\s+ici|ici)\s+/i, "")
    .replace(/\b(?:je vais|on va|tu vas|vous allez)\b.*$/i, "")
    .replace(/\b(?:en plusieurs fois|fois en tout|toute petite louche)\b.*$/i, "")
    .replace(/\b(?:c['’]?est\s+super\s+simple(?:\s+a\s+faire)?|c['’]?est\s+d[eé]licieux)\b.*$/i, "")
    .replace(/^(?:et ensuite|ensuite|puis|alors|du coup|on a)\b.*$/i, "")
    .replace(/\bque j['’]?ai\b.*$/i, "")
    .replace(/\b(?:j['’]?ai\s+coup[eé]|j['’]?ai\s+d[eé]coup[eé]|i\s+cut)\b.*$/i, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function stripLeadingIngredientMeasurement(value: string): string {
  const cleaned = clean(value);
  if (!cleaned) {
    return "";
  }

  return cleaned
    .replace(
      /^\s*(?:\d+(?:[.,]\d+)?|\d+\/\d+|[¼½¾⅓⅔⅛]|a|an|one|un|une|two|deux|three|trois|half|demi)\s+(?:(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup|pinch|egg|eggs|piece|pieces|slice|slices|tranche|tranches|steak|steaks|bun|buns|pain|pains|packet|packets?|sachet|sachets?|gousse|gousses|clove|cloves)\s+)?/i,
      ""
    )
    .replace(/^\s*(?:\d+(?:[.,]\d+)?|\d+\/\d+|[¼½¾⅓⅔⅛]|a|an|one|un|une|two|deux|three|trois|half|demi)\s+/i, "")
    // Note: orphan French measurement phrases ("À café Sel", "À soupe huile",
    // "Une pincée de paprika") used to be stripped here, but stripping
    // discards the unit information entirely. We now leave them in place so
    // cleanIngredientNameField (called next in sanitizeIngredientDraft) can
    // both strip the prefix AND extract it as a unit value.
    .replace(/^\s*(?:de|du|des|d['’])\s+/i, "")
    .trim();
}

function splitCompoundIngredientText(value: string): string[] {
  const cleaned = clean(value)
    .replace(/\s*(?:\.\.\.|…)\s*/g, " / ")
    .replace(/\s*(?:\/|\||;|•|·|\+|&)\s*/g, " / ")
    .trim();

  if (!cleaned) {
    return [];
  }

  const slashSegments = splitIngredientSegments(cleaned, /\s+\/\s+/);
  if (slashSegments.length >= 2) {
    return slashSegments;
  }

  const commaSegments = splitIngredientSegments(cleaned, /\s*,\s*/);
  if (commaSegments.length >= 2) {
    return commaSegments;
  }

  for (const conjunctionPattern of compoundIngredientConjunctionPatterns) {
    const conjunctionSegments = splitIngredientSegments(cleaned, conjunctionPattern);
    if (conjunctionSegments.length >= 2) {
      return conjunctionSegments;
    }
  }

  const runOnSegments = splitRunOnIngredientText(cleaned);
  if (runOnSegments.length >= 2) {
    return runOnSegments;
  }

  return [value];
}

function splitIngredientSegments(value: string, delimiter: RegExp): string[] {
  const segments = value
    .split(delimiter)
    .map((segment) => sanitizeIngredientName(segment))
    .filter(Boolean);

  return segments.length >= 2 && segments.every(isPlausibleSplitIngredientSegment)
    ? segments
    : [];
}

function isPlausibleSplitIngredientSegment(value: string): boolean {
  if (!value || /\d/.test(value)) {
    return false;
  }

  const wordCount = value.split(" ").filter(Boolean).length;
  return wordCount >= 1 && wordCount <= 6 && /[a-zA-ZÀ-ÿ]/.test(value);
}

function splitRunOnIngredientText(value: string): string[] {
  const cleaned = clean(value);
  if (!cleaned || /\d/.test(cleaned) || /[/:;]/.test(cleaned)) {
    return [];
  }

  const rawTokens = cleaned.split(/\s+/).filter(Boolean);
  if (rawTokens.length < 3 || rawTokens.length > 10) {
    return [];
  }

  const normalizedTokens = rawTokens.map((token) => normalizeLookup(token));
  const result: string[] = [];
  let index = 0;

  while (index < normalizedTokens.length) {
    let matchedLength = 0;

    for (const phrase of runOnIngredientPhraseTokens) {
      const candidate = normalizedTokens.slice(index, index + phrase.length);
      if (candidate.length === phrase.length && candidate.every((token, tokenIndex) => token === phrase[tokenIndex])) {
        result.push(rawTokens.slice(index, index + phrase.length).join(" "));
        index += phrase.length;
        matchedLength = phrase.length;
        break;
      }
    }

    if (matchedLength > 0) {
      continue;
    }

    const token = normalizedTokens[index] ?? "";
    if (!runOnIngredientSingleTokens.has(token)) {
      return [];
    }

    result.push(rawTokens[index] ?? "");
    index += 1;
  }

  return result.length >= 2 ? result : [];
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
    .filter((line) => line && !containsArticleNoise(line) && !containsSocialNoise(line))
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
  titleLooksArticleLike: boolean,
  cookabilitySignals: RecipeCookabilitySignals
): RecipeImportResult["confidence"] {
  if (titleLooksArticleLike || ingredientCount < 2 || stepCount < 1) {
    return "low";
  }

  if (
    cookabilitySignals.majorIngredientCount >= 4 &&
    cookabilitySignals.majorIngredientCoverage < 0.35
  ) {
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

function clampConfidenceScore(
  current: number | undefined,
  confidence: RecipeImportResult["confidence"],
  title: string,
  ingredientCount: number,
  stepCount: number,
  titleLooksArticleLike: boolean,
  cookabilitySignals: RecipeCookabilitySignals,
  flags: RecipeImportFlags
): number {
  let score = Number.isFinite(current)
    ? Number(current)
    : confidence === "high"
      ? 0.82
      : confidence === "medium"
        ? 0.64
        : 0.34;

  if (!title.trim() || titleLooksArticleLike) {
    score -= 0.3;
  } else {
    score += 0.06;
  }

  if (ingredientCount >= 6) {
    score += 0.08;
  } else if (ingredientCount >= 3) {
    score += 0.04;
  } else {
    score -= 0.15;
  }

  if (stepCount >= 4) {
    score += 0.08;
  } else if (stepCount >= 2) {
    score += 0.04;
  } else {
    score -= 0.16;
  }

  if (flags.usedExplicitIngredients) {
    score += 0.05;
  }
  if (flags.usedInferredIngredients) {
    score -= 0.04;
  }
  if (flags.generatedSteps) {
    score -= 0.02;
  }

  if (cookabilitySignals.majorIngredientCount >= 3) {
    score += Math.min(0.08, cookabilitySignals.majorIngredientCoverage * 0.12);
    score -= Math.min(0.12, cookabilitySignals.uncoveredMajorIngredientCount * 0.03);
  }

  return Math.max(0, Math.min(0.99, Math.round(score * 100) / 100));
}

// Small seed map of French/English ingredient synonyms that should be merged
// during deduplication. Keys are canonical tokens, values are arrays of
// alternative spellings (already passed through normalizeLookup, so no
// accents, lowercase, ascii).
const ingredientSynonymGroups: readonly (readonly string[])[] = [
  ["pain plat", "pain plat", "pains plats", "flatbread", "flat bread", "naan", "naans", "pain naan", "pita", "pitas", "tortilla", "tortillas", "wrap", "wraps", "galette", "galettes"],
  ["oeuf", "oeufs", "egg", "eggs", "oeufs oeufs"],
  ["poulet", "blanc de poulet", "blancs de poulet", "escalope de poulet", "escalopes de poulet", "filet de poulet", "filets de poulet", "poitrine de poulet", "chicken", "chicken breast"],
  ["farine", "flour", "farine de ble", "farine ble", "farine de blé"],
  ["sucre", "sugar"],
  ["sel", "salt"],
  ["poivre", "pepper", "poivre noir", "black pepper"],
  ["beurre", "butter"],
  ["huile d olive", "huile olive", "olive oil", "extra virgin olive oil"],
  ["huile", "oil", "huile vegetale", "huile neutre", "huile de tournesol"],
  ["yaourt", "yaourt grec", "greek yogurt", "yogurt", "yoghurt"],
  ["kiri", "fromage kiri", "vache qui rit", "laughing cow"],
  ["chapelure", "panko", "breadcrumbs", "bread crumbs"],
  ["oignon", "oignons", "onion", "onions"],
  ["oignons rouges", "oignon rouge", "red onion", "red onions"],
  ["ail", "garlic", "gousse d ail", "gousses d ail"],
  ["paprika", "paprika doux"],
  ["paprika fume", "smoked paprika"],
  ["sriracha", "sauce sriracha"],
  ["miel", "honey"],
  ["mayonnaise", "mayo"],
  ["tomate", "tomates", "tomato", "tomatoes"],
  ["tomates cerises", "cherry tomato", "cherry tomatoes"],
  ["salade", "laitue", "lettuce"],
  ["fromage rape", "cheese", "grated cheese", "shredded cheese"],
  ["levure", "levure boulangere", "levure de boulanger", "yeast", "dried yeast", "instant yeast"],
  ["eau", "water"]
];

const ingredientSynonymIndex: Map<string, string> = (() => {
  const index = new Map<string, string>();
  for (const group of ingredientSynonymGroups) {
    const canonical = group[0];
    for (const variant of group) {
      index.set(normalizeLookup(variant), canonical);
    }
  }
  return index;
})();

function canonicalIngredientKey(name: string): string {
  const normalized = normalizeLookup(name);
  if (!normalized) {
    return "";
  }

  const direct = ingredientSynonymIndex.get(normalized);
  if (direct) {
    return direct;
  }

  // Fall back to a fuzzier match: if the full normalized name *contains*
  // a known synonym as a whole token, use its canonical form. This catches
  // things like "farine de ble t45" -> "farine".
  for (const [variant, canonical] of ingredientSynonymIndex.entries()) {
    if (variant.length < 4) {
      continue;
    }
    if (normalized === variant || normalized.startsWith(`${variant} `) || normalized.endsWith(` ${variant}`) || normalized.includes(` ${variant} `)) {
      return canonical;
    }
  }

  return normalized;
}

function parseAmountNumber(amount?: string): number | null {
  if (!amount) {
    return null;
  }
  const cleaned = amount.trim().replace(",", ".");
  const match = cleaned.match(/-?\d+(?:\.\d+)?/);
  if (!match) {
    return null;
  }
  const value = Number.parseFloat(match[0]);
  return Number.isFinite(value) ? value : null;
}

function mergeIngredientDrafts(
  existing: RecipeIngredientDraft,
  incoming: RecipeIngredientDraft
): RecipeIngredientDraft {
  // Merge quantities when both sides have the same unit and a numeric amount.
  // Otherwise keep whichever side has richer data.
  const existingAmount = parseAmountNumber(existing.amount);
  const incomingAmount = parseAmountNumber(incoming.amount);
  const existingUnit = (existing.unit ?? "").trim().toLowerCase();
  const incomingUnit = (incoming.unit ?? "").trim().toLowerCase();
  const unitsMatch = existingUnit === incomingUnit;

  let mergedAmount = existing.amount;
  let mergedUnit = existing.unit;

  if (unitsMatch && existingAmount != null && incomingAmount != null) {
    const total = existingAmount + incomingAmount;
    mergedAmount = Number.isInteger(total) ? String(total) : total.toFixed(2).replace(/\.?0+$/, "");
  } else if (!existingAmount && incomingAmount != null) {
    mergedAmount = incoming.amount;
    mergedUnit = incoming.unit;
  }

  // Prefer the longer / more descriptive name, and keep the richer nutrition query.
  const mergedName = existing.name.length >= incoming.name.length ? existing.name : incoming.name;
  const mergedQuery = (existing.nutritionQuery?.length ?? 0) >= (incoming.nutritionQuery?.length ?? 0)
    ? existing.nutritionQuery
    : incoming.nutritionQuery;

  // Prefer the non-empty group label so dedupe across a linear + grouped
  // variant keeps the section assignment.
  const mergedGroup = (existing.group?.trim() ? existing.group : incoming.group) ?? "";

  return {
    amount: mergedAmount,
    unit: mergedUnit,
    name: mergedName,
    nutritionQuery: mergedQuery,
    group: mergedGroup
  };
}

function dedupeIngredients(ingredients: RecipeIngredientDraft[]): RecipeIngredientDraft[] {
  const canonicalOrder: string[] = [];
  const byKey = new Map<string, RecipeIngredientDraft>();

  // Section-aware dedup: when ANY ingredient has a non-empty group, we
  // never merge across groups. Cross-group same ingredient is VALID
  // (e.g. crème fraîche in "Sauce" and "Salade" as separate entries).
  //
  // Bug fix (plan §5 Fix S4): in the previous implementation, ingredients
  // without a group shared a single "__ungrouped__" namespace — meaning
  // two un-grouped ingredients with the same name (one between two
  // distinct groups, another at the head of the list) would incorrectly
  // merge, and position-based identity was lost. We now assign each
  // ungrouped entry its own position-based pseudo-group so dedup keys
  // are unique unless they truly share an adjacent grouping intent.
  const hasAnyGroup = ingredients.some((i) => (i.group ?? "").trim().length > 0);

  // Precompute pseudo-groups for ungrouped items based on proximity to
  // the nearest preceding grouped ingredient. All ungrouped items after
  // "Sauce" and before "Salade" are co-grouped under "__before::Salade"
  // (or, if there is no following group, under "__after::<lastGroup>").
  const pseudoGroupByIndex: string[] = new Array(ingredients.length);
  if (hasAnyGroup) {
    let lastGroup = "";
    let seenAnyGroup = false;
    for (let i = 0; i < ingredients.length; i += 1) {
      const g = (ingredients[i].group ?? "").trim();
      if (g) {
        pseudoGroupByIndex[i] = g;
        lastGroup = g;
        seenAnyGroup = true;
        continue;
      }
      // Look forward for the next grouped ingredient to bracket this run.
      if (!seenAnyGroup) {
        pseudoGroupByIndex[i] = "__pre__";
      } else {
        let next = "";
        for (let j = i + 1; j < ingredients.length; j += 1) {
          const g2 = (ingredients[j].group ?? "").trim();
          if (g2) { next = g2; break; }
        }
        pseudoGroupByIndex[i] = next
          ? `__between::${lastGroup}::${next}`
          : `__after::${lastGroup}`;
      }
    }
  }

  for (let i = 0; i < ingredients.length; i += 1) {
    const ingredient = ingredients[i];
    const nameKey = canonicalIngredientKey(ingredient.name);
    if (!nameKey) {
      continue;
    }

    let key: string;
    if (hasAnyGroup) {
      const groupKey = normalizeLookup(ingredient.group ?? "") || pseudoGroupByIndex[i];
      key = `${groupKey}::${nameKey}`;
    } else {
      // No sections at all — dedupe purely by name (backward compat).
      key = nameKey;
    }

    const existing = byKey.get(key);
    if (existing) {
      byKey.set(key, mergeIngredientDrafts(existing, ingredient));
      continue;
    }

    byKey.set(key, ingredient);
    canonicalOrder.push(key);
  }

  return canonicalOrder.map((key) => byKey.get(key)!).filter(Boolean);
}

function dedupeSteps<T extends { detail: string }>(steps: T[]): T[] {
  const seen = new Set<string>();
  const result: T[] = [];

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

  if (containsArticleNoise(name) || containsSocialNoise(name) || containsNarrativeIngredientNoise(name)) {
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

  if (!/[a-zA-ZÀ-ÿ]/.test(name)) {
    return false;
  }

  // Dual-gate floor — reject title-like, brand-like, or non-food names
  // that slipped past the blocklists (e.g. "PC", "Photo editor",
  // "Kiri Studio Pro Edition"). We require the name to both:
  //   - match a plausible ingredient shape (short, non-narrative,
  //     non-product-name, non-article-title)
  //   - contain at least one known food token.
  //
  // We still allow the existing upstream blocklists to run first so
  // their specific error signals (article/social/narrative noise) are
  // preserved.
  if (!hasPlausibleIngredientShape(name)) {
    return false;
  }
  if (!containsFoodSignal(name)) {
    return false;
  }

  return true;
}

function isPlausibleCookingStep(detail: string): boolean {
  if (!detail || containsArticleNoise(detail) || containsSocialNoise(detail) || containsNarrativeStepNoise(detail)) {
    return false;
  }

  if (/\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/.test(detail) || detail.includes("-->")) {
    return false;
  }

  if (detail.length < 8 || detail.length > 220) {
    return false;
  }

  // Raw transcript chunks often contain "à ce moment-là" (temporal marker) and
  // double-comma artifacts like "Ajoutez À ce moment-là,, pain, farine".
  // Reject those — they are never legitimate cooking instructions.
  if (/\bà\s+ce\s+moment(?:\s*[-\s]*là)?\b/i.test(detail) || /,,/.test(detail)) {
    return false;
  }

  // Steps whose content is mostly a comma-separated shopping list
  // ("ajoutez pain, farine, sucre, paprika, œufs, mayonnaise et mélangez")
  // are transcript paraphrase artifacts, not real cooking actions. Drop them
  // when the comma list dominates the sentence.
  const commaFragments = detail.split(",").map((fragment) => fragment.trim()).filter(Boolean);
  if (commaFragments.length >= 4) {
    const shortFragments = commaFragments.filter((fragment) => fragment.split(" ").length <= 3).length;
    if (shortFragments >= commaFragments.length - 1) {
      return false;
    }
  }

  const normalized = normalizeLookup(detail);
  if (looksLikeIncompleteStepFragment(normalized)) {
    return false;
  }
  if (
    /^(?:j espere|j espere|bon app|bon appetit|oui j ose le dire|n hesite pas|abonne toi|like|follow|partage|commente)\b/.test(normalized)
  ) {
    return false;
  }
  if (
    /\b(?:dans les commentaires|je t explique|je vous explique|pas de souci|si t en as pas|mix maison|lien en bio|code promo|abonne toi|abonnez vous)\b/.test(normalized)
  ) {
    return false;
  }
  if (/^(?:pour|for)\s+\d+\s+(?:portion|portions|serving|servings)\b/.test(normalized)) {
    return false;
  }
  const wordCount = normalized.split(" ").filter(Boolean).length;
  const startsLikeProcedure = /^(?:puis|ensuite|d abord|commencer|faire|ajouter|mettre|melanger|verser|laisser|couper|cuire|servir|incorporer|assaisonner|saisir|griller|carameliser|retourner|garnir|napper|finir|degazer|dégazer|former|aplatir|etaler|étaler|proceder|procéder|enrober|diluer|petrir|pétrir|disposez|disposer|rechauffez|rechauffer|roulez|rouler|rabattez|rabattre|preparer|préparer|eplucher|éplucher|mariner|emincer|émincer|hacher|rincer|egoutter|égoutter|dresser|decorer|décorer|laver|beurrer|huiler|saler|poivrer|reduire|réduire|deglacer|déglacer|flamber|rotir|rôtir|sauter|mijoter|bouillir|dorer|tailler|tamiser|infuser|parsemer|tartiner|battre|fouetter|monter|assembler|enfourner)\b/.test(normalized);
  if (wordCount > 38 && !containsCookingVerb(normalized)) {
    return false;
  }

  return containsCookingVerb(normalized) || startsLikeProcedure;
}

function looksLikeIncompleteStepFragment(value: string): boolean {
  const normalized = normalizeLookup(value);
  if (!normalized) {
    return false;
  }

  if (containsNarrativeStepNoise(normalized)) {
    return true;
  }

  if (containsCookingVerb(normalized)) {
    return false;
  }

  if (
    /\b(?:je vais|on va|tu vas|vous allez)\b/.test(normalized) &&
    /\b(?:prendre|faire|mettre|voir|montrer|rajouter|ajouter)\b/.test(normalized)
  ) {
    return true;
  }

  if (
    /^(?:ensuite|puis|apres|après|et apres|et après|du coup|alors|comme ca|comme ça|voila|voilà)\b/.test(normalized)
  ) {
    return true;
  }

  if (/^(?:comme ca|comme ça|voila|voilà|et voila|et voilà)\b/.test(normalized)) {
    return true;
  }

  return normalized.split(" ").filter(Boolean).length <= 4 &&
    /^(?:prendre|mettre|faire|voir|voila|voilà|ensuite|puis|apres|après)\b/.test(normalized);
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

export function containsLikelyFoodTitleTerm(normalized: string): boolean {
  return likelyFoodTitlePatterns.some((pattern) => pattern.test(normalized));
}

export function hasMeaningfulFoodSignal(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "searchQuery" | "flags" | "confidenceScore">,
  options?: { transcript?: string }
): boolean {
  const titleCandidates = [clean(recipe.title), clean(recipe.searchQuery)];
  let titleHasContent = false;

  for (const candidate of titleCandidates) {
    if (!candidate || hasSuspiciousRecipeTitle(candidate)) {
      continue;
    }

    if (containsLikelyFoodTitleTerm(normalizeLookup(candidate))) {
      return true;
    }

    titleHasContent = titleHasContent || candidate.length > 3;
  }

  const plausibleIngredients = recipe.ingredientDrafts
    .filter((ingredient) => isPlausibleIngredientName(ingredient.name))
    .length;
  if (plausibleIngredients >= 2) {
    return true;
  }

  // A single plausible ingredient combined with a non-trivial title is enough
  if (plausibleIngredients >= 1 && titleHasContent) {
    return true;
  }

  // Check transcript for food terms when other signals are weak
  if (options?.transcript) {
    const normalizedTranscript = normalizeLookup(clean(options.transcript));
    if (normalizedTranscript && containsLikelyFoodTitleTerm(normalizedTranscript)) {
      return true;
    }
  }

  const flags = normalizeRecipeImportFlags(recipe.flags);
  return flags.usedExplicitIngredients ||
    flags.usedInferredIngredients ||
    (recipe.confidenceScore ?? 0) >= 0.35;
}

function containsArticleNoise(value: string): boolean {
  const normalized = normalizeLookup(value);
  return articleNoisePatterns.some((pattern) => pattern.test(normalized)) ||
    normalized.includes("http") ||
    normalized.includes("www.");
}

function containsSocialNoise(value: string): boolean {
  const raw = clean(value);
  const normalized = normalizeLookup(value);
  if (!normalized) {
    return false;
  }

  if (raw.trim().startsWith("@")) {
    return true;
  }

  if (normalized.includes("suivre") || normalized.includes("follow")) {
    return true;
  }

  if (
    normalized.includes("original sound") ||
    normalized.includes("son original") ||
    normalized.includes("the playful waltz")
  ) {
    return true;
  }

  const tokens = normalized.split(" ").filter(Boolean);
  if (
    tokens.length <= 5 &&
    (
      normalized.includes("waltz") ||
      normalized.includes("playlist") ||
      normalized.includes("soundtrack") ||
      normalized.includes("remix") ||
      normalized.includes("audio")
    )
  ) {
    return true;
  }

  return normalized.includes("ajouter un commentaire");
}

function containsCookingVerb(value: string): boolean {
  return cookingVerbPatterns.some((pattern) => pattern.test(value));
}

function containsNarrativeIngredientNoise(value: string): boolean {
  const normalized = normalizeLookup(value);
  if (!normalized) {
    return false;
  }

  // Hard blocklist for known transcript artifacts and non-food items that
  // slipped through as "ingredients" in previous imports.
  if (
    /^(?:a|à)\s+(?:cafe|café|soupe|the|thé)\b/.test(normalized) ||
    /^(?:ce|à ce|a ce)\s+moment(?:\s*la|\s*là)?\b/.test(normalized) ||
    /\bce\s+moment\s*la\b/.test(normalized) ||
    /^papier\s+(?:journal|cuisson|alu|aluminium|sulfurise|sulfurisé)\b/.test(normalized) ||
    /^(?:film\s+(?:alimentaire|plastique)|assiette|poele|poêle|casserole|bol|saladier|cuillere|cuillère|fourchette|couteau|planche|rouleau|spatule|fouet|passoire|verre|moule|plat)\b/.test(normalized) ||
    /^(?:ce|cet|cette|ces|celui|celle|ceux|celles)\s+/.test(normalized)
  ) {
    return true;
  }

  return /\b(?:je vais|on va|tu vas|vous allez|en plusieurs fois|fois en tout|toute petite louche|c est super simple|c est delicieux|et ensuite|on a|bien sur|bien sûr|franchement|tu sais|vous savez|en fait|tout simplement|c est parti|allez|allons y|c est bon|parfait|exactement|attention|normalement|genial|trop bon|incroyable|magnifique|regardez|ecoutez|n hesitez pas|abonnez vous|likez|partagez|commentez|suivez moi)\b/.test(normalized) ||
    /^(?:et|ensuite|puis|alors|du coup|on a|voila|voilà|hop|bon|bref|donc|ok|ouais|hein|quoi)\b/.test(normalized);
}

function containsNarrativeStepNoise(value: string): boolean {
  const normalized = normalizeLookup(value);
  if (!normalized) {
    return false;
  }

  return /\b(?:c est super simple|c est delicieux|bon appetit|en plusieurs fois|fois en tout|toute petite louche)\b/.test(normalized) ||
    /^(?:et ensuite|ensuite|puis|alors|du coup|on a|voila|voilà|comme ca|comme ça)\b/.test(normalized);
}

function isCompactSimpleRecipeTitle(title: string): boolean {
  const normalized = normalizeLookup(title);
  return /\b(?:omelette|toast|croque|quesadilla|tartine)\b/.test(normalized);
}

function minimumIngredientCountForRecipeTitle(title: string): number {
  const normalized = normalizeLookup(title);

  if (isCompactSimpleRecipeTitle(normalized)) {
    return 2;
  }

  if (/\b(?:salade|salad|bowl)\b/.test(normalized)) {
    return 4;
  }

  return 5;
}

export function minimumStepCountForRecipeTitle(title: string): number {
  const normalized = normalizeLookup(title);

  if (isCompactSimpleRecipeTitle(normalized)) {
    return 2;
  }

  if (/\b(?:salade|salad|bowl)\b/.test(normalized)) {
    return 4;
  }

  return 5;
}

export function isLikelyMajorIngredient(name: string): boolean {
  const normalized = normalizeLookup(name);
  if (!normalized) {
    return false;
  }

  if (/\b(?:sel|poivre|pepper|water|eau|ice|glacons?|glaçons?|basilic|parsley|persil|coriandre|mint|menthe|thyme|thym|oregano|origan)\b/.test(normalized)) {
    return false;
  }

  return true;
}

function ingredientConceptTokens(ingredient: RecipeIngredientDraft): string[] {
  const normalized = normalizeLookup(`${ingredient.name} ${ingredient.nutritionQuery}`)
    .replace(/\b(?:fresh|frais|fraiche|fraîche|optional|facultatif|to|taste|all|purpose|large|medium|small|grated|rape|râpé|sliced|tranche|tranches|minced|mince|mincé|diced|chopped|hach[eé]|hache|cooked|raw|whole)\b/g, " ");

  const baseTokens = normalized
    .split(" ")
    .map((token) => singularizeConceptToken(token))
    .filter((token) =>
      token.length >= 3 &&
      !ingredientStopWords.has(token)
    );

  const extraTokens: string[] = [];
  if (/\b(?:emmental|gruyere|gruyere|mozzarella|cheddar|parmesan|fromage|cheese)\b/.test(normalized)) {
    extraTokens.push("fromage", "cheese");
  }
  if (/\b(?:cornichon|cornichons|pickle|pickles)\b/.test(normalized)) {
    extraTokens.push("cornichon", "pickle");
  }
  if (/\b(?:pain burger|bun|buns|burger)\b/.test(normalized)) {
    extraTokens.push("bun", "pain", "burger");
  }

  return Array.from(new Set([...baseTokens, ...extraTokens]));
}

function singularizeConceptToken(token: string): string {
  if (token.endsWith("ies") && token.length > 4) {
    return `${token.slice(0, -3)}y`;
  }

  if (token.endsWith("es") && token.length > 4) {
    return token.slice(0, -2);
  }

  if (token.endsWith("s") && token.length > 3) {
    return token.slice(0, -1);
  }

  return token;
}

function containsWholeToken(text: string, token: string): boolean {
  return new RegExp(`(?:^|\\s)${escapeRegExp(token)}(?:$|\\s)`).test(text);
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function normalizeLookup(value: string): string {
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

function trimRepeatedLeadPhrase(value: string): string {
  const words = value.match(/[\p{L}\p{N}]+/gu) ?? [];
  const lowercased = value.toLocaleLowerCase();

  for (const phraseLength of [3, 2]) {
    if (words.length < phraseLength * 2) {
      continue;
    }

    const phrase = words.slice(0, phraseLength).join(" ").toLocaleLowerCase();
    if (phrase.length < 8) {
      continue;
    }

    const secondIndex = lowercased.indexOf(phrase, phrase.length + 1);
    if (secondIndex < 8) {
      continue;
    }

    const trimmed = value.slice(0, secondIndex).trim();
    if (trimmed.length >= 6) {
      return trimmed;
    }
  }

  return value;
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

const socialHookTitlePatterns = [
  /^reponse a\b/,
  /^reply to\b/,
  /^pov\b/,
  /^part(?:ie)?\s+\d+\b/,
  /^episode\s+\d+\b/,
  /^maintenant\b.*\bexcuses\b/,
  /\bplus d excuses\b/,
  /\bn avez plus d excuses\b/,
  /\btu n as plus d excuses\b/,
  /^si tu\b/,
  /^quand\b/,
  /^je te\b/,
  /^on se retrouve\b/,
  /^regarde\b/,
  /^watch\b/,
  /^voici\b/,
  /^this is why\b/,
  /^you have no excuse\b/,
  /\bcommentaire\b/
];

const compoundIngredientConjunctionPatterns = [
  /\s+\b(?:et|and)\b\s+/i
];

const likelyFoodTitlePatterns = [
  /\bburger\b/,
  /\bnaan\b/,
  /\btacos?\b/,
  /\bpizza\b/,
  /\bpasta\b/,
  /\bpates?\b/,
  /\bpâtes?\b/,
  /\blasan(?:e|es|a|as|gnes?)\b/,
  /\bomelette\b/,
  /\bquiche\b/,
  /\bsalade\b/,
  /\bsalad\b/,
  /\bsandwich\b/,
  /\bwrap\b/,
  /\bbowl\b/,
  /\brisotto\b/,
  /\bramen\b/,
  /\bcurry\b/,
  /\bsoupe\b/,
  /\bsoup\b/,
  /\bgratin\b/,
  /\bgateau\b/,
  /\bgâteau\b/,
  /\bcake\b/,
  /\bbrownie\b/,
  /\bcookie\b/,
  /\bcookies\b/,
  /\bpancakes?\b/,
  /\bcrepes?\b/,
  /\bcrêpes?\b/,
  /\btarte\b/,
  /\bcroissant\b/,
  /\bmuffins?\b/,
  /\bchicken\b/,
  /\bpoulet\b/,
  /\bbeef\b/,
  /\bboeuf\b/,
  /\bbœuf\b/,
  /\bfish\b/,
  /\bpoisson\b/,
  /\bsaumon\b/,
  /\bsalmon\b/,
  /\bthon\b/,
  /\btuna\b/,
  /\bcrevette\b/,
  /\bshrimp\b/,
  /\bcheddar\b/,
  /\bmozzarella\b/,
  /\bfromage\b/,
  /\bcheese\b/,
  /\bcabillaud\b/,
  /\bfalafel\b/,
  /\bshawarma\b/,
  /\bkebab\b/,
  /\bbruschetta\b/,
  /\bfocaccia\b/,
  /\btartare\b/,
  /\bcarpaccio\b/,
  /\bcrostini\b/,
  /\bpoke\b/,
  /\bbibimbap\b/,
  /\bgnocchi\b/,
  /\bhummus\b/,
  /\bcouscous\b/,
  /\bgyoza\b/
];

const cookingVerbPatterns = [
  /\b(?:preheat|heat|mix|stir|add|combine|cook|bake|roast|fry|boil|simmer|whisk|blend|serve|set|put|wipe|keep|rest|pour|flip|marinate|season|sear|drain|rinse|peel|chill|refrigerate|cool|top|cover|sprinkle|drizzle|toss|fold|knead|chop|dice|mince|slice)\b/,
  /\b(?:prechauffez|faites|melangez|melanger|ajoutez|ajouter|versez|verser|cuisez|cuire|laissez|laisser|deposez|deposer|disposez|disposer|fouettez|fouetter|diluez|diluer|petrissez|petrir|pétrir|rechauffez|rechauffer|roulez|rouler|rabattez|rabattre|preparer|préparer|preparez|préparez)\b/,
  /\b(?:incorporez|incorporer|faites revenir|faire revenir|repartissez|repartir|servez|servir|enfournez|enfourner|chauffez|chauffer|degazez|degazer|dégazer|formez|former|montez|monter|assemblez|assembler)\b/,
  /\b(?:coupez|couper|grillez|griller|saisissez|saisir|caramelisez|carameliser|retournez|retourner|garnissez|garnir|nappez|napper|ecrasez|ecraser|aplatissez|aplatir|etalez|etaler|étaler|enrobez|enrober|procedez|proceder|procédez|procéder|fermez|fermer)\b/,
  /\b(?:marinez|mariner|émincez|emincez|émincer|emincer|hachez|hacher|rincez|rincer|egouttez|égouttez|egoutter|égoutter|dressez|dresser|decorez|décorez|decorer|décorer|epluchez|épluchez|eplucher|éplucher|lavez|laver|beurrez|beurrer|huilez|huiler|salez|saler|poivrez|poivrer|reduisez|réduisez|reduire|réduire|deglacez|déglacez|deglacer|déglacer|flambez|flamber|rotissez|rôtissez|rotir|rôtir|sautez|sauter|mijotez|mijoter|bouillez|bouillir|dorez|dorer|taillez|tailler|tamisez|tamiser|infusez|infuser|parsemez|parsemer|tartinez|tartiner|battez|battre)\b/
];

const titleCutoffPatterns = [
  /\b(?:ingredients?|ingrédients?)\b/i,
  /\b(?:pour réaliser|pour faire|tu auras besoin|il te faut)\b/i,
  /\b(?:instructions?|étapes?|etapes|dough|mixture|coating|marinade|serve with)\b/i,
  /\s[-–:]\s*(?=\d+(?:[.,/]\d+)?\s*(?:g|kg|ml|cl|l|cas|cac|cuill[eè]re?s?|steaks?|tranches?|pains?|buns?|oignons?|cheddar|cornichons?|beurre)\b)/i
];

const ingredientStopWords = new Set([
  "de",
  "des",
  "du",
  "d",
  "la",
  "le",
  "les",
  "un",
  "une",
  "and",
  "with",
  "for",
  "sur",
  "pour",
  "aux",
  "the",
  "all",
  "purpose"
]);

const runOnIngredientPhraseTokens = [
  ["epices", "poulet"],
  ["corn", "flakes"],
  ["sauce", "soja"],
  ["persil", "seche"],
  ["persil", "sechee"],
  ["fromage", "qui", "rit"],
  ["poivre", "noir"]
];

const runOnIngredientSingleTokens = new Set([
  "ail",
  "chapelure",
  "farine",
  "paprika",
  "poivre",
  "poulet",
  "sel",
  "semoule",
  "sucre"
]);
