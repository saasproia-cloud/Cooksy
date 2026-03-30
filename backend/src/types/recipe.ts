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

export const recipeImportFlagsSchema = z.object({
  usedExplicitIngredients: z.boolean().default(false),
  usedInferredIngredients: z.boolean().default(false),
  generatedSteps: z.boolean().default(false),
  generatedNutrition: z.boolean().default(false)
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
    generatedNutrition: flags?.generatedNutrition === true
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
        detail: sanitizeStepDetail(step.detail)
      }))
      .filter((step) => isPlausibleCookingStep(step.detail))
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
      cookabilitySignals.majorIngredientCoverage < 0.45 ||
      cookabilitySignals.uncoveredMajorIngredientCount >= 3
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

  return recipe.ingredientDrafts.length * 6 +
    recipe.stepDrafts.length * 7 +
    (recipe.title.length > 0 ? 10 : 0) +
    (recipe.notesText.length > 0 ? 2 : 0) +
    (recipe.remoteImageUrl.length > 0 ? 2 : 0) +
    nutritionScore +
    (recipe.confidence === "high" ? 8 : recipe.confidence === "medium" ? 4 : 0) +
    cookabilityBonus +
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
  const hasCompactRecipe = hasCompactCompleteStructure(recipe);

  if (recipe.ingredientDrafts.length < 3 && !hasCompactRecipe) {
    missing.push("ingredients");
  }

  if (recipe.stepDrafts.length < 2) {
    missing.push("steps");
  }

  return missing;
}

function hasThinRecipeStructure(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "stepDrafts" | "confidence">
): boolean {
  if (hasCompactCompleteStructure(recipe)) {
    return recipe.confidence === "low" &&
      recipe.ingredientDrafts.length < 4 &&
      recipe.stepDrafts.length < 3;
  }

  return recipe.stepDrafts.length < 2 ||
    (recipe.ingredientDrafts.length < 4 && recipe.confidence !== "high") ||
    (
      recipe.ingredientDrafts.length < 5 &&
      recipe.stepDrafts.length < 4 &&
      recipe.confidence === "low"
    );
}

function hasCompactCompleteStructure(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "stepDrafts">
): boolean {
  const normalizedTitle = clean(recipe.title);
  if (
    normalizedTitle.length <= 2 ||
    hasSuspiciousRecipeTitle(normalizedTitle) ||
    recipe.stepDrafts.length < 2
  ) {
    return false;
  }

  const substantialIngredientCount = recipe.ingredientDrafts
    .filter((ingredient) => isLikelyMajorIngredient(ingredient.name))
    .length;

  return substantialIngredientCount >= 2;
}

export function isLikelyValidRecipe(recipe: RecipeImportResult): boolean {
  const normalizedTitle = clean(recipe.title);
  return hasMeaningfulFoodSignal(recipe) &&
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
  }
): ImportFailureReason | undefined {
  if (options?.timedOut) {
    return "import_too_slow";
  }

  if (!hasMeaningfulFoodSignal(recipe)) {
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
  const amount = clean(ingredient.amount);
  const unit = clean(ingredient.unit);
  const originalName = clean(ingredient.name);
  const isServeOnlyIngredient = /\b(?:to serve|for serving|pour servir|optional|facultatif)\b/i.test(originalName);
  const nameSegments = splitCompoundIngredientText(ingredient.name);
  const nutritionQuerySegments = splitCompoundIngredientText(ingredient.nutritionQuery);
  const sanitized: RecipeIngredientDraft[] = [];

  for (const [index, rawName] of nameSegments.entries()) {
    const name = sanitizeIngredientName(rawName);
    const nutritionQuery = sanitizeNutritionQuery(
      nutritionQuerySegments[index] ?? nutritionQuerySegments[0] ?? name,
      name
    );

    if (!isPlausibleIngredientName(name) || containsSocialNoise(name)) {
      continue;
    }

    if (isServeOnlyIngredient && !amount && !unit) {
      continue;
    }

    sanitized.push({
      amount: index === 0 ? amount : "",
      unit: index === 0 ? unit : "",
      name,
      nutritionQuery
    });
  }

  return sanitized;
}

function sanitizeIngredientName(value: string): string {
  return stripLeadingIngredientMeasurement(
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
}

function stripIngredientNarrativeFragments(value: string): string {
  return clean(value)
    .replace(/^(?:j['’]?ai\s+utilis[eé]|i\s+used)\s+/i, "")
    .replace(/^(?:j['’]?utilise|utilis[eé]e?s?)\s+/i, "")
    .replace(/^(?:comme\s+ici|ici)\s+/i, "")
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

  if (containsArticleNoise(name) || containsSocialNoise(name)) {
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
  if (!detail || containsArticleNoise(detail) || containsSocialNoise(detail)) {
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
  if (
    /\b(?:dans les commentaires|je t explique|je vous explique|pas de souci|si t en as pas|mix maison|lien en bio|code promo|abonne toi|abonnez vous)\b/.test(normalized)
  ) {
    return false;
  }
  if (/^(?:pour|for)\s+\d+\s+(?:portion|portions|serving|servings)\b/.test(normalized)) {
    return false;
  }
  const wordCount = normalized.split(" ").filter(Boolean).length;
  const startsLikeProcedure = /^(?:puis|ensuite|d abord|commencer|faire|ajouter|mettre|melanger|verser|laisser|couper|cuire|servir|incorporer|assaisonner|saisir|griller|carameliser|retourner|garnir|napper|finir|degazer|dégazer|former|aplatir|etaler|étaler|proceder|procéder|enrober|diluer|petrir|pétrir|disposez|disposer|rechauffez|rechauffer|roulez|rouler|rabattez|rabattre)\b/.test(normalized);
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

function containsLikelyFoodTitleTerm(normalized: string): boolean {
  return likelyFoodTitlePatterns.some((pattern) => pattern.test(normalized));
}

export function hasMeaningfulFoodSignal(
  recipe: Pick<RecipeImportResult, "title" | "ingredientDrafts" | "searchQuery" | "flags" | "confidenceScore">
): boolean {
  const titleCandidates = [clean(recipe.title), clean(recipe.searchQuery)];
  for (const candidate of titleCandidates) {
    if (!candidate || hasSuspiciousRecipeTitle(candidate)) {
      continue;
    }

    if (containsLikelyFoodTitleTerm(normalizeLookup(candidate))) {
      return true;
    }
  }

  const plausibleIngredients = recipe.ingredientDrafts
    .filter((ingredient) => isPlausibleIngredientName(ingredient.name))
    .length;
  if (plausibleIngredients >= 2) {
    return true;
  }

  const flags = normalizeRecipeImportFlags(recipe.flags);
  return flags.usedExplicitIngredients ||
    flags.usedInferredIngredients ||
    (recipe.confidenceScore ?? 0) >= 0.45;
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

function isLikelyMajorIngredient(name: string): boolean {
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
  /\bkebab\b/
];

const cookingVerbPatterns = [
  /\b(?:preheat|heat|mix|stir|add|combine|cook|bake|roast|fry|boil|simmer|whisk|blend|serve|set|put|wipe|keep|rest|pour|flip)\b/,
  /\b(?:prechauffez|faites|melangez|melanger|ajoutez|ajouter|versez|verser|cuisez|cuire|laissez|laisser|deposez|deposer|disposez|disposer|fouettez|fouetter|diluez|diluer|petrissez|petrir|pétrir|rechauffez|rechauffer|roulez|rouler|rabattez|rabattre)\b/,
  /\b(?:incorporez|incorporer|faites revenir|repartissez|repartir|servez|servir|enfournez|enfourner|chauffez|chauffer|degazez|degazer|dégazer|formez|former)\b/,
  /\b(?:coupez|couper|grillez|griller|saisissez|saisir|caramelisez|carameliser|retournez|retourner|garnissez|garnir|nappez|napper|ecrasez|ecraser|aplatissez|aplatir|etalez|etaler|étaler|enrobez|enrober|procedez|proceder|procédez|procéder|fermez|fermer)\b/
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
