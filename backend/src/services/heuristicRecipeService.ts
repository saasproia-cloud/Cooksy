import {
  hasSuspiciousRecipeTitle,
  normalizeRecipeImportFlags,
  scoreRecipe,
  sanitizeRecipeImport,
  type NormalizerInput,
  type RecipeIngredientDraft,
  type RecipeImportResult
} from "../types/recipe.js";

type DishIntent = {
  dishName?: string;
  templateId: DishTemplateId;
  confidenceScore: number;
  foodSignalScore: number;
  matchedSource?: string;
};

type DishTemplateId =
  | "smash_burger"
  | "burger"
  | "crispy_chicken_tacos"
  | "tacos"
  | "chicken_curry_pasta"
  | "pasta"
  | "tiramisu"
  | "curry"
  | "generic";

type IngredientCatalogKey =
  | "ground_beef"
  | "white_fish"
  | "chicken_breast"
  | "chicken_thigh"
  | "chicken_tenders"
  | "hamburger_bun"
  | "bread"
  | "flatbread"
  | "cheddar"
  | "onion"
  | "pickles"
  | "burger_sauce"
  | "oil"
  | "olive_oil"
  | "salt"
  | "pepper"
  | "lettuce"
  | "tomato"
  | "cucumber"
  | "flour"
  | "paprika"
  | "cumin"
  | "garlic"
  | "tortilla"
  | "cabbage"
  | "lime"
  | "breadcrumbs"
  | "sour_cream"
  | "mayonnaise"
  | "pasta"
  | "curry_powder"
  | "cream"
  | "coconut_milk"
  | "parmesan"
  | "mozzarella"
  | "mascarpone"
  | "egg"
  | "sugar"
  | "coffee"
  | "ladyfinger"
  | "cocoa_powder"
  | "mushroom"
  | "truffle_oil"
  | "butter"
  | "yogurt"
  | "pizza_dough"
  | "tomato_sauce"
  | "basil"
  | "chocolate"
  | "baking_powder"
  | "chickpeas";

export function fallbackRecipeFromContext(input: NormalizerInput): RecipeImportResult {
  if (input.mode === "url") {
    const structuredRecipe = structuredRecipeFromBlocks(input.pageStructuredData ?? []);
    if (structuredRecipe) {
      return sanitizeRecipeImport({
        ...structuredRecipe,
        sourceUrl: input.sourceUrl ?? structuredRecipe.sourceUrl,
        remoteImageUrl: input.remoteImageUrl || structuredRecipe.remoteImageUrl
      });
    }
  }

  const combinedText = [
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles,
    input.socialTitle,
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n\n");

  const parsed = parseRecipeText(combinedText);
  const draft = input.mode === "url"
    ? reconstructDishFirstRecipe(input, parsed)
    : parsed;

  return sanitizeRecipeImport({
    ...draft,
    sourceUrl: input.sourceUrl ?? draft.sourceUrl ?? "",
    remoteImageUrl: input.remoteImageUrl ?? draft.remoteImageUrl ?? "",
    notesText: draft.notesText || buildFallbackNotes(input)
  });
}

export function strictRecipeFromContext(
  input: NormalizerInput,
  candidate?: RecipeImportResult
): RecipeImportResult | null {
  const baseCandidate = sanitizeRecipeImport(candidate ?? fallbackRecipeFromContext(input));
  const parsedContext = parseRecipeText(combinedContextRecipeText(input));
  const mergedBase = mergeStrictBaseRecipes(baseCandidate, parsedContext, input);
  const initialIntent = detectDishIntent(input, mergedBase);
  const resolvedDishName = initialIntent.dishName ?? fallbackDishNameFromSignals(input, mergedBase);

  if (!resolvedDishName) {
    return null;
  }

  const intent: DishIntent = {
    ...initialIntent,
    dishName: resolvedDishName,
    templateId: initialIntent.dishName
      ? initialIntent.templateId
      : templateIdForDishName(resolvedDishName),
    confidenceScore: Math.max(initialIntent.confidenceScore, 0.5)
  };

  const explicitIngredients = collectExplicitIngredients(input, mergedBase, resolvedDishName)
    .filter((ingredient) => isReliableExplicitIngredient(ingredient, resolvedDishName));
  const explicitSteps = collectExplicitCookingSteps(mergedBase, parsedContext);
  if (!hasStrictFoodIntent(intent, mergedBase, explicitIngredients, explicitSteps)) {
    return null;
  }

  const shouldFullReconstruct = explicitIngredients.length < 3 || explicitSteps.length < 2;
  let finalIngredients = mergeIngredientDraftLists(
    explicitIngredients,
    inferIngredientsForDish(intent, explicitIngredients)
  );
  finalIngredients = ensureMinimumIngredientCountForDish(intent, finalIngredients);

  const explicitStepRecipe = {
    ...mergedBase,
    ingredientDrafts: explicitIngredients,
    stepDrafts: explicitSteps
  };
  const shouldGenerateSteps = shouldFullReconstruct ||
    explicitSteps.length < 3 ||
    shouldRegenerateDishSteps(explicitStepRecipe, finalIngredients);
  let finalSteps = shouldGenerateSteps
    ? generateDishSteps(intent, finalIngredients)
    : explicitSteps;
  finalSteps = ensureMinimumDishSteps(intent, finalSteps, finalIngredients);

  const inferredCount = countInferredIngredients(finalIngredients, explicitIngredients);
  const confidenceScore = deriveStrictRecipeConfidence(intent, {
    explicitIngredientCount: explicitIngredients.length,
    inferredIngredientCount: inferredCount,
    ingredientCount: finalIngredients.length,
    stepCount: finalSteps.length,
    fullReconstruction: shouldFullReconstruct
  });
  const templateDefaults = defaultDishMetadataForIntent(intent);
  const baseFlags = normalizeRecipeImportFlags(mergedBase.flags);

  return sanitizeRecipeImport({
    ...mergedBase,
    title: resolvedDishName,
    ingredientDrafts: finalIngredients,
    stepDrafts: finalSteps,
    notesText: buildStrictReconstructionNotes(
      mergedBase.notesText,
      intent,
      explicitIngredients.length,
      inferredCount,
      shouldGenerateSteps,
      shouldFullReconstruct
    ),
    prepTimeText: mergedBase.prepTimeText || templateDefaults.prepTimeText,
    cookTimeText: mergedBase.cookTimeText || templateDefaults.cookTimeText,
    servingsText: mergedBase.servingsText || templateDefaults.servingsText,
    confidence: confidenceFromScore(confidenceScore),
    confidenceScore,
    needsWebFallback: false,
    searchQuery: resolvedDishName,
    flags: {
      ...baseFlags,
      usedExplicitIngredients: explicitIngredients.length > 0,
      usedInferredIngredients: inferredCount > 0,
      generatedSteps: shouldGenerateSteps || finalSteps.length > explicitSteps.length,
      generatedNutrition: baseFlags.generatedNutrition
    }
  });
}

function combinedContextRecipeText(input: NormalizerInput): string {
  return [
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles,
    input.socialTitle,
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent,
    input.transcript
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n\n");
}

function mergeStrictBaseRecipes(
  candidate: RecipeImportResult,
  parsedContext: RecipeImportResult,
  input: NormalizerInput
): RecipeImportResult {
  const bestBase = scoreRecipe(parsedContext) > scoreRecipe(candidate)
    ? parsedContext
    : candidate;
  const merged = sanitizeRecipeImport({
    ...bestBase,
    sourceUrl: input.sourceUrl ?? bestBase.sourceUrl ?? candidate.sourceUrl ?? parsedContext.sourceUrl,
    remoteImageUrl: input.remoteImageUrl ?? bestBase.remoteImageUrl ?? candidate.remoteImageUrl ?? parsedContext.remoteImageUrl,
    title: bestBase.title || candidate.title || parsedContext.title,
    ingredientDrafts: mergeIngredientDraftLists(
      bestBase.ingredientDrafts,
      bestBase === candidate ? parsedContext.ingredientDrafts : candidate.ingredientDrafts
    ),
    stepDrafts: collectExplicitCookingSteps(candidate, parsedContext),
    searchQuery: bestBase.searchQuery || candidate.searchQuery || parsedContext.searchQuery
  });

  return merged;
}

function fallbackDishNameFromSignals(
  input: NormalizerInput,
  recipe: RecipeImportResult
): string | undefined {
  const candidates = [
    recipe.title,
    recipe.searchQuery,
    input.socialTitle,
    input.pageTitle,
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.pageDescription,
    input.pageTextContent,
    input.transcript
  ];

  for (const candidate of candidates) {
    const extracted = candidate ? extractDishCandidate(candidate)?.dishName : undefined;
    if (extracted) {
      return extracted;
    }
  }

  return undefined;
}

function collectExplicitCookingSteps(
  primary: RecipeImportResult,
  secondary?: RecipeImportResult
): Array<{ detail: string }> {
  return sanitizeRecipeImport({
    ...emptyRecipe(),
    title: primary.title || secondary?.title || "",
    ingredientDrafts: primary.ingredientDrafts,
    stepDrafts: [
      ...primary.stepDrafts,
      ...(secondary?.stepDrafts ?? [])
    ],
    confidence: "high",
    needsWebFallback: false
  }).stepDrafts;
}

function hasStrictFoodIntent(
  intent: DishIntent,
  recipe: RecipeImportResult,
  explicitIngredients: RecipeIngredientDraft[],
  explicitSteps: Array<{ detail: string }>
): boolean {
  if (!intent.dishName) {
    return false;
  }

  if (intent.foodSignalScore >= 1) {
    return true;
  }

  if (explicitIngredients.length >= 2) {
    return true;
  }

  if (explicitIngredients.length >= 1 && explicitSteps.length >= 1) {
    return true;
  }

  return scoreRecipe(recipe) >= 24;
}

function ensureMinimumIngredientCountForDish(
  intent: DishIntent,
  ingredients: RecipeIngredientDraft[]
): RecipeIngredientDraft[] {
  const minimumCount = minimumIngredientCountForDish(intent.dishName ?? "", ingredients.length);
  if (ingredients.length >= minimumCount) {
    return ingredients;
  }

  const enriched = mergeIngredientDraftLists(
    ingredients,
    inferIngredientsForDish(intent, ingredients)
  );

  return enriched.length > ingredients.length
    ? enriched
    : ingredients;
}

function minimumIngredientCountForDish(dishName: string, currentCount: number): number {
  const normalizedDish = normalizeDishDetectionText(dishName);
  if (!normalizedDish) {
    return Math.max(4, currentCount);
  }

  if (/\b(?:omelette|toast)\b/.test(normalizedDish)) {
    return 3;
  }

  if (/\b(?:salad|salade)\b/.test(normalizedDish)) {
    return 4;
  }

  if (/\b(?:burger|sandwich|wrap|pizza|pasta|curry|taco|tacos|naan|brownie|cookie|cake|tiramisu|risotto|ramen|shawarma|kebab|falafel|bowl)\b/.test(normalizedDish)) {
    return 5;
  }

  return Math.max(4, currentCount);
}

function ensureMinimumDishSteps(
  intent: DishIntent,
  steps: Array<{ detail: string }>,
  ingredients: RecipeIngredientDraft[]
): Array<{ detail: string }> {
  if (steps.length >= 3) {
    return steps;
  }

  return generateDishSteps(intent, ingredients);
}

function deriveStrictRecipeConfidence(
  intent: DishIntent,
  input: {
    explicitIngredientCount: number;
    inferredIngredientCount: number;
    ingredientCount: number;
    stepCount: number;
    fullReconstruction: boolean;
  }
): number {
  let score = deriveDishConfidenceScore(intent, input);

  if (input.fullReconstruction) {
    score -= 0.05;
  }

  if (input.explicitIngredientCount >= 3 && input.stepCount >= 3) {
    score += 0.04;
  }

  return Math.max(0.55, Math.min(0.92, Math.round(score * 100) / 100));
}

function buildStrictReconstructionNotes(
  existingNotes: string,
  intent: DishIntent,
  explicitIngredientCount: number,
  inferredIngredientCount: number,
  generatedSteps: boolean,
  fullReconstruction: boolean
): string {
  const prefix = fullReconstruction
    ? `Recette reconstruite a partir du plat detecte (${intent.dishName}) pour remplacer une extraction trop faible.`
    : buildDishReconstructionNotes(
      existingNotes,
      intent,
      explicitIngredientCount,
      inferredIngredientCount,
      generatedSteps
    );

  if (!fullReconstruction) {
    return prefix;
  }

  const cleanedExistingNotes = existingNotes.trim();
  if (!cleanedExistingNotes || cleanedExistingNotes.length > 120) {
    return prefix;
  }

  return [prefix, cleanedExistingNotes]
    .filter(Boolean)
    .join("\n");
}

export function isOpenAIUnavailable(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return message.includes("insufficient_quota") ||
    message.includes("rate limit") ||
    message.includes("429") ||
    message.includes("openai normalization failed") ||
    message.includes("openai");
}

export function structuredRecipeFromBlocks(blocks: string[]): RecipeImportResult | null {
  return extractStructuredRecipe(blocks);
}

function parseRecipeText(input: string): RecipeImportResult {
  const lines = heuristicLines(input);
  if (!lines.length) {
    return emptyRecipe();
  }

  let title = explicitTitle(lines) || fallbackTitle(lines);
  let ingredientLines: string[] = [];
  let stepLines: string[] = [];
  let noteLines: string[] = [];
  let currentSection: "header" | "ingredients" | "steps" | "notes" = "header";

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    if (isIngredientsHeader(line)) {
      currentSection = "ingredients";
      continue;
    }

    if (isStepsHeader(line)) {
      currentSection = "steps";
      continue;
    }

    if (isNotesHeader(line)) {
      currentSection = "notes";
      continue;
    }

    if (isIngredientSubsectionHeader(line)) {
      currentSection = "ingredients";
      continue;
    }

    if (currentSection === "ingredients" && looksLikeStep(line) && !looksLikeIngredient(line)) {
      currentSection = "steps";
      stepLines.push(cleanedStepLine(line));
      continue;
    }

    if (currentSection === "steps" && looksLikeIngredient(line) && !looksLikeStep(line)) {
      currentSection = "ingredients";
      ingredientLines.push(...expandIngredientCandidates(line));
      continue;
    }

    if (currentSection === "header" && !title) {
      const candidateTitle = cleanedTitle(line);
      if (isLikelyRecipeTitle(candidateTitle)) {
        title = candidateTitle;
        continue;
      }
    }

    switch (currentSection) {
      case "ingredients": {
        const candidates = expandIngredientCandidates(line);
        const plausibleCandidates = candidates.filter(looksLikeIngredient);

        if (plausibleCandidates.length) {
          ingredientLines.push(...plausibleCandidates);
        } else if (looksLikeStep(line)) {
          currentSection = "steps";
          stepLines.push(cleanedStepLine(line));
        } else {
          noteLines.push(line);
        }
        break;
      }
      case "steps":
        stepLines.push(cleanedStepLine(line));
        break;
      case "notes":
        noteLines.push(line);
        break;
      default:
        noteLines.push(line);
        break;
    }
  }

  if (!ingredientLines.length && !stepLines.length) {
    const candidateLines = lines
      .filter((line) => cleanedTitle(line) !== title)
      .filter((line) => !isLikelyNoise(line));

    ingredientLines = candidateLines
      .flatMap(expandIngredientCandidates)
      .filter(looksLikeIngredient);
    stepLines = candidateLines
      .filter((line) => !looksLikeIngredient(line) && looksLikeStep(line))
      .map(cleanedStepLine);
  } else if (!ingredientLines.length) {
    ingredientLines = noteLines
      .flatMap(expandIngredientCandidates)
      .filter(looksLikeIngredient);
  }

  return sanitizeRecipeImport({
    title: title || "Recette importee",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: ingredientLines
      .filter((line) => !isDuplicateTitleIngredient(line, title))
      .map(parseIngredientLine)
      .filter((item) => item.name.length > 0),
    stepDrafts: stepLines.map((detail) => ({ detail })).filter((step) => step.detail.length > 0),
    notesText: noteLines.join("\n"),
    prepTimeText: extractTime(input, /(?:prep|preparation|préparation)[^\d]*(\d{1,3})\s*min/i),
    cookTimeText: extractTime(input, /(?:cuisson|cook)[^\d]*(\d{1,3})\s*min/i),
    servingsText: extractTime(input, /(?:portions?|servings?|pour)\s*(\d{1,2})/i),
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: ingredientLines.length >= 2 && stepLines.length >= 2 ? "medium" : "low",
    needsWebFallback: ingredientLines.length < 2 || stepLines.length < 2,
    searchQuery: title || "",
    inferredFromPhoto: false
  });
}

function reconstructDishFirstRecipe(
  input: NormalizerInput,
  parsed: RecipeImportResult
): RecipeImportResult {
  const baseFlags = normalizeRecipeImportFlags(parsed.flags);
  const intent = detectDishIntent(input, parsed);

  if (!intent.dishName) {
    return {
      ...parsed,
      title: "",
      ingredientDrafts: [],
      stepDrafts: [],
      confidence: "low",
      confidenceScore: Math.min(0.2, intent.confidenceScore),
      needsWebFallback: true,
      searchQuery: "",
      flags: {
        ...baseFlags,
        usedExplicitIngredients: false
      }
    };
  }

  const explicitIngredients = collectExplicitIngredients(input, parsed, intent.dishName);
  const inferredIngredients = inferIngredientsForDish(intent, explicitIngredients);
  const finalIngredients = mergeIngredientDraftLists(explicitIngredients, inferredIngredients);
  const shouldGenerateSteps = shouldRegenerateDishSteps(parsed, finalIngredients);
  const finalSteps = shouldGenerateSteps
    ? generateDishSteps(intent, finalIngredients)
    : parsed.stepDrafts;
  const inferredCount = countInferredIngredients(finalIngredients, explicitIngredients);
  const confidenceScore = deriveDishConfidenceScore(intent, {
    explicitIngredientCount: explicitIngredients.length,
    inferredIngredientCount: inferredCount,
    ingredientCount: finalIngredients.length,
    stepCount: finalSteps.length
  });
  const templateDefaults = defaultDishMetadataForIntent(intent);

  return {
    ...parsed,
    title: intent.dishName,
    ingredientDrafts: finalIngredients,
    stepDrafts: finalSteps,
    notesText: buildDishReconstructionNotes(
      parsed.notesText,
      intent,
      explicitIngredients.length,
      inferredCount,
      shouldGenerateSteps
    ),
    prepTimeText: parsed.prepTimeText || templateDefaults.prepTimeText,
    cookTimeText: parsed.cookTimeText || templateDefaults.cookTimeText,
    servingsText: parsed.servingsText || templateDefaults.servingsText,
    confidence: confidenceFromScore(confidenceScore),
    confidenceScore,
    needsWebFallback: explicitIngredients.length < 2 || confidenceScore < 0.58,
    searchQuery: intent.dishName,
    flags: {
      ...baseFlags,
      usedExplicitIngredients: explicitIngredients.length > 0,
      usedInferredIngredients: inferredCount > 0,
      generatedSteps: shouldGenerateSteps,
      generatedNutrition: baseFlags.generatedNutrition
    }
  };
}

function detectDishIntent(
  input: NormalizerInput,
  parsed: RecipeImportResult
): DishIntent {
  const candidates = buildDishIntentCandidates(input, parsed);
  let bestMatch: DishIntent | null = null;
  let foodSignalScore = 0;

  for (const candidate of candidates) {
    foodSignalScore = Math.max(foodSignalScore, foodSignalStrength(candidate.text));
    const match = extractDishCandidate(candidate.text);
    if (!match) {
      continue;
    }

    const confidenceScore = Math.min(
      0.92,
      match.baseScore + candidate.weight + Math.min(0.1, foodSignalScore * 0.02)
    );

    if (!bestMatch || confidenceScore > bestMatch.confidenceScore) {
      bestMatch = {
        dishName: match.dishName,
        templateId: match.templateId,
        confidenceScore: Math.round(confidenceScore * 100) / 100,
        foodSignalScore,
        matchedSource: candidate.source
      };
    }
  }

  if (bestMatch) {
    return bestMatch;
  }

  return {
    dishName: undefined,
    templateId: "generic",
    confidenceScore: Math.min(0.24, 0.08 + foodSignalScore * 0.03),
    foodSignalScore
  };
}

function buildDishIntentCandidates(
  input: NormalizerInput,
  parsed: RecipeImportResult
): Array<{ text: string; source: string; weight: number }> {
  return uniqueNonEmptyStringsWithMetadata([
    {
      text: isWeakRecipeTitle(parsed.title) ? "" : parsed.title,
      source: "parsed-title",
      weight: 0.28
    },
    {
      text: input.socialTitle,
      source: "social-title",
      weight: 0.24
    },
    {
      text: input.pageTitle,
      source: "page-title",
      weight: 0.22
    },
    {
      text: input.sharedText,
      source: "shared-text",
      weight: 0.18
    },
    {
      text: input.socialCaption,
      source: "social-caption",
      weight: 0.2
    },
    {
      text: input.socialDescription,
      source: "social-description",
      weight: 0.16
    },
    {
      text: input.socialPageText,
      source: "social-page",
      weight: 0.14
    },
    {
      text: input.pageDescription,
      source: "page-description",
      weight: 0.12
    },
    {
      text: input.pageTextContent,
      source: "page-text",
      weight: 0.1
    },
    {
      text: input.socialSubtitles,
      source: "subtitles",
      weight: 0.1
    },
    {
      text: input.transcript,
      source: "transcript",
      weight: 0.08
    }
  ]);
}

function extractDishCandidate(
  text: string
): { dishName: string; templateId: DishTemplateId; baseScore: number } | null {
  const normalized = normalizeDishDetectionText(text);
  if (!normalized) {
    return null;
  }

  for (const pattern of prioritizedDishPatterns) {
    const match = normalized.match(pattern.regex);
    if (!match?.[0]) {
      continue;
    }

    return {
      dishName: pattern.title ?? prettifyDishName(match[0]),
      templateId: pattern.templateId,
      baseScore: pattern.baseScore
    };
  }

  const genericPhrase = extractGenericDishPhrase(normalized);
  if (genericPhrase) {
    const dishName = prettifyDishName(genericPhrase);
    return {
      dishName,
      templateId: templateIdForDishName(dishName),
      baseScore: genericPhrase.split(" ").length >= 2 ? 0.5 : 0.42
    };
  }

  const genericMatch = normalized.match(genericDishPattern);
  if (!genericMatch?.[0]) {
    return null;
  }

  const dishName = prettifyDishName(genericMatch[0]);
  return {
    dishName,
    templateId: templateIdForDishName(dishName),
    baseScore: 0.42
  };
}

function collectExplicitIngredients(
  input: NormalizerInput,
  parsed: RecipeImportResult,
  dishName: string
): RecipeIngredientDraft[] {
  const explicitIngredients = parsed.ingredientDrafts.filter((ingredient) =>
    !looksLikeDishNameIngredient(ingredient.name, dishName)
  );

  for (const text of explicitIngredientSourceTexts(input)) {
    explicitIngredients.push(...scanCatalogIngredients(text));
  }

  return mergeIngredientDraftLists(explicitIngredients, []).slice(0, 18);
}

function isReliableExplicitIngredient(
  ingredient: RecipeIngredientDraft,
  dishName: string
): boolean {
  if (looksLikeDishNameIngredient(ingredient.name, dishName)) {
    return false;
  }

  const normalized = normalizeDishDetectionText(`${ingredient.name} ${ingredient.nutritionQuery}`);
  if (!normalized) {
    return false;
  }

  if (/\b(?:roll|serve|servir|ajouter|add|cook|cuire|mix|melanger|mélanger|wrap it up|step|instructions?)\b/.test(normalized)) {
    return false;
  }

  const normalizedDishName = normalizeDishDetectionText(dishName);
  const wordCount = normalized.split(" ").filter(Boolean).length;
  if (normalizedDishName && normalized.includes(normalizedDishName) && wordCount > 2) {
    return false;
  }

  return !(wordCount > 4 && ingredientCatalogKey(ingredient) === normalized);
}

function inferIngredientsForDish(
  intent: DishIntent,
  explicitIngredients: RecipeIngredientDraft[]
): RecipeIngredientDraft[] {
  const explicitKeys = new Set(explicitIngredients.map(ingredientCatalogKey).filter(Boolean));
  const inferred: RecipeIngredientDraft[] = [];

  switch (intent.templateId) {
    case "smash_burger":
      inferred.push(
        burgerProteinForDish(intent.dishName, explicitKeys),
        ingredientFromCatalog("hamburger_bun", { amount: "2", unit: "piece" }),
        ingredientFromCatalog("cheddar", { amount: "2", unit: "tranches" }),
        ingredientFromCatalog("onion", { amount: "1", unit: "piece" }),
        ingredientFromCatalog("pickles", { amount: "6", unit: "pieces" }),
        ingredientFromCatalog("burger_sauce", { amount: "2", unit: "c a soupe" }),
        ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "burger":
      inferred.push(
        burgerProteinForDish(intent.dishName, explicitKeys),
        ingredientFromCatalog("hamburger_bun", { amount: "2", unit: "piece" }),
        ingredientFromCatalog("cheddar", { amount: "2", unit: "tranches" }),
        ingredientFromCatalog("lettuce", { amount: "60", unit: "g" }),
        ingredientFromCatalog("pickles", { amount: "4", unit: "pieces" }),
        ingredientFromCatalog("burger_sauce", { amount: "2", unit: "c a soupe" }),
        ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "crispy_chicken_tacos":
      inferred.push(
        ingredientFromCatalog("chicken_thigh", { amount: "450", unit: "g" }),
        ingredientFromCatalog("flour", { amount: "80", unit: "g" }),
        ingredientFromCatalog("paprika", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("cumin", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("garlic", { amount: "2", unit: "gousses" }),
        ingredientFromCatalog("oil", { amount: "2", unit: "c a soupe" }),
        ingredientFromCatalog("tortilla", { amount: "6", unit: "piece" }),
        ingredientFromCatalog("cabbage", { amount: "180", unit: "g" }),
        ingredientFromCatalog("lime", { amount: "1", unit: "piece" }),
        ingredientFromCatalog("sour_cream", { amount: "120", unit: "g" }),
        ingredientFromCatalog("mayonnaise", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "tacos":
      inferred.push(
        tacoProteinForDish(intent.dishName, explicitKeys),
        ingredientFromCatalog("tortilla", { amount: "6", unit: "piece" }),
        ingredientFromCatalog("cabbage", { amount: "150", unit: "g" }),
        ingredientFromCatalog("lime", { amount: "1", unit: "piece" }),
        ingredientFromCatalog("sour_cream", { amount: "100", unit: "g" }),
        ingredientFromCatalog("paprika", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("cumin", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "chicken_curry_pasta":
      inferred.push(
        ingredientFromCatalog("pasta", { amount: "250", unit: "g" }),
        curryProteinForDish(intent.dishName, explicitKeys),
        ingredientFromCatalog("onion", { amount: "1", unit: "piece" }),
        ingredientFromCatalog("garlic", { amount: "2", unit: "gousses" }),
        ingredientFromCatalog("curry_powder", { amount: "2", unit: "c a soupe" }),
        ingredientFromCatalog(explicitKeys.has("coconut_milk") ? "coconut_milk" : "cream", {
          amount: explicitKeys.has("coconut_milk") ? "200" : "200",
          unit: explicitKeys.has("coconut_milk") ? "ml" : "ml"
        }),
        ingredientFromCatalog("parmesan", { amount: "40", unit: "g" }),
        ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "pasta":
      inferred.push(
        ingredientFromCatalog("pasta", { amount: "250", unit: "g" }),
        ingredientFromCatalog("garlic", { amount: "2", unit: "gousses" }),
        ingredientFromCatalog("olive_oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("parmesan", { amount: "30", unit: "g" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    case "tiramisu":
      inferred.push(
        ingredientFromCatalog("mascarpone", { amount: "250", unit: "g" }),
        ingredientFromCatalog("egg", { amount: "3", unit: "oeufs" }),
        ingredientFromCatalog("sugar", { amount: "80", unit: "g" }),
        ingredientFromCatalog("coffee", { amount: "240", unit: "ml" }),
        ingredientFromCatalog("ladyfinger", { amount: "200", unit: "g" }),
        ingredientFromCatalog("cocoa_powder", { amount: "2", unit: "c a soupe" })
      );
      break;
    case "curry":
      inferred.push(
        curryProteinForDish(intent.dishName, explicitKeys),
        ingredientFromCatalog("onion", { amount: "1", unit: "piece" }),
        ingredientFromCatalog("garlic", { amount: "2", unit: "gousses" }),
        ingredientFromCatalog("curry_powder", { amount: "2", unit: "c a soupe" }),
        ingredientFromCatalog("coconut_milk", { amount: "250", unit: "ml" }),
        ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
        ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
        ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
      );
      break;
    default:
      inferred.push(...genericSupportIngredientsForDish(intent, explicitKeys));
      break;
  }

  return mergeIngredientDraftLists(
    [],
    [
      ...inferred,
      ...inferredIngredientsForFlavorProfile(intent, explicitKeys)
    ]
  );
}

function generateDishSteps(
  intent: DishIntent,
  ingredients: RecipeIngredientDraft[]
): Array<{ detail: string }> {
  const steps = buildDishStepTexts(intent, ingredients);
  return steps.map((detail) => ({ detail }));
}

function buildDishStepTexts(
  intent: DishIntent,
  ingredients: RecipeIngredientDraft[]
): string[] {
  switch (intent.templateId) {
    case "smash_burger":
    case "burger":
      return burgerSteps(ingredients);
    case "crispy_chicken_tacos":
    case "tacos":
      return tacoSteps(ingredients);
    case "chicken_curry_pasta":
    case "pasta":
      return pastaSteps(ingredients);
    case "tiramisu":
      return tiramisuSteps(ingredients);
    case "curry":
      return currySteps(ingredients);
    default:
      return genericDishSteps(intent.dishName ?? "Recette", ingredients);
  }
}

function shouldRegenerateDishSteps(
  parsed: RecipeImportResult,
  finalIngredients: RecipeIngredientDraft[]
): boolean {
  if (parsed.stepDrafts.length < 2) {
    return true;
  }

  if (parsed.stepDrafts.length >= 6) {
    return false;
  }

  if (finalIngredients.length > parsed.ingredientDrafts.length && parsed.stepDrafts.length < 4) {
    return true;
  }

  return parsed.stepDrafts.some((step) =>
    /\b(?:tiktok|instagram|abonne|abonnez|like|commentaires?|link in bio|bon app)\b/i.test(step.detail)
  );
}

function buildDishReconstructionNotes(
  existingNotes: string,
  intent: DishIntent,
  explicitIngredientCount: number,
  inferredIngredientCount: number,
  generatedSteps: boolean
): string {
  const noteParts: string[] = [];

  if (inferredIngredientCount > 0) {
    noteParts.push(
      `Recette reconstituée autour du plat détecté (${intent.dishName}) avec les ingrédients explicitement cités et des compléments culinaires plausibles.`
    );
  } else if (generatedSteps) {
    noteParts.push(
      `Étapes réécrites proprement à partir du plat détecté (${intent.dishName}) et de la liste finale d'ingrédients.`
    );
  } else if (explicitIngredientCount > 0) {
    noteParts.push(`Plat détecté : ${intent.dishName}.`);
  }

  if (!existingNotes.trim()) {
    return noteParts.join("\n");
  }

  return [...noteParts, existingNotes].filter(Boolean).join("\n");
}

function deriveDishConfidenceScore(
  intent: DishIntent,
  input: {
    explicitIngredientCount: number;
    inferredIngredientCount: number;
    ingredientCount: number;
    stepCount: number;
  }
): number {
  let score = intent.confidenceScore;

  if (input.explicitIngredientCount >= 4) {
    score += 0.12;
  } else if (input.explicitIngredientCount >= 2) {
    score += 0.07;
  } else if (input.explicitIngredientCount === 0) {
    score -= 0.04;
  }

  if (input.inferredIngredientCount >= 4) {
    score -= 0.08;
  } else if (input.inferredIngredientCount > 0) {
    score -= 0.03;
  }

  if (input.ingredientCount >= 5) {
    score += 0.05;
  }
  if (input.stepCount >= 4) {
    score += 0.05;
  }

  return Math.max(0.28, Math.min(0.92, Math.round(score * 100) / 100));
}

function confidenceFromScore(score: number): RecipeImportResult["confidence"] {
  if (score >= 0.78) {
    return "high";
  }

  if (score >= 0.52) {
    return "medium";
  }

  return "low";
}

function defaultDishMetadata(templateId: DishTemplateId): {
  prepTimeText: string;
  cookTimeText: string;
  servingsText: string;
} {
  switch (templateId) {
    case "smash_burger":
    case "burger":
      return { prepTimeText: "15", cookTimeText: "15", servingsText: "2" };
    case "crispy_chicken_tacos":
    case "tacos":
      return { prepTimeText: "20", cookTimeText: "20", servingsText: "3" };
    case "chicken_curry_pasta":
    case "pasta":
      return { prepTimeText: "15", cookTimeText: "20", servingsText: "3" };
    case "tiramisu":
      return { prepTimeText: "25", cookTimeText: "0", servingsText: "6" };
    case "curry":
      return { prepTimeText: "15", cookTimeText: "25", servingsText: "3" };
    default:
      return { prepTimeText: "10", cookTimeText: "20", servingsText: "2" };
  }
}

function defaultDishMetadataForIntent(
  intent: Pick<DishIntent, "templateId" | "dishName">
): {
  prepTimeText: string;
  cookTimeText: string;
  servingsText: string;
} {
  if (intent.templateId !== "generic") {
    return defaultDishMetadata(intent.templateId);
  }

  const normalizedDish = normalizeDishDetectionText(intent.dishName ?? "");
  if (/\b(?:sandwich|wrap|naan|toast|shawarma|kebab)\b/.test(normalizedDish)) {
    return { prepTimeText: "15", cookTimeText: "15", servingsText: "2" };
  }
  if (/\bpizza\b/.test(normalizedDish)) {
    return { prepTimeText: "20", cookTimeText: "18", servingsText: "2" };
  }
  if (/\b(?:salad|salade|bowl)\b/.test(normalizedDish)) {
    return { prepTimeText: "15", cookTimeText: "10", servingsText: "2" };
  }
  if (/\bomelette\b/.test(normalizedDish)) {
    return { prepTimeText: "5", cookTimeText: "8", servingsText: "1" };
  }
  if (/\b(?:brownie|cookie|cake)\b/.test(normalizedDish)) {
    return { prepTimeText: "15", cookTimeText: "25", servingsText: "6" };
  }

  return defaultDishMetadata("generic");
}

function uniqueNonEmptyStringsWithMetadata(
  entries: Array<{ text?: string; source: string; weight: number }>
): Array<{ text: string; source: string; weight: number }> {
  const seen = new Set<string>();
  const result: Array<{ text: string; source: string; weight: number }> = [];

  for (const entry of entries) {
    const text = entry.text?.trim();
    if (!text) {
      continue;
    }

    const key = text.toLocaleLowerCase();
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    result.push({
      text,
      source: entry.source,
      weight: entry.weight
    });
  }

  return result;
}

function explicitIngredientSourceTexts(input: NormalizerInput): string[] {
  return [
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles,
    input.socialTitle,
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent
  ]
    .filter((value): value is string => Boolean(value?.trim()));
}

function scanCatalogIngredients(text: string): RecipeIngredientDraft[] {
  const normalized = normalizeDishDetectionText(text);
  if (!normalized) {
    return [];
  }

  const result: RecipeIngredientDraft[] = [];
  for (const entry of ingredientCatalog) {
    if (!entry.aliases.some((alias) => ingredientAliasMatches(normalized, alias))) {
      continue;
    }

    result.push(ingredientFromCatalog(entry.key));
  }

  return result;
}

function ingredientAliasMatches(text: string, alias: string): boolean {
  const compactAlias = alias.replace(/\s+/g, "\\s*");
  return new RegExp(`(?:^|\\s)${compactAlias}(?:$|\\s)`, "i").test(text);
}

function ingredientFromCatalog(
  key: IngredientCatalogKey,
  overrides?: Partial<RecipeIngredientDraft>
): RecipeIngredientDraft {
  const entry = ingredientCatalogByKey.get(key);
  if (!entry) {
    return {
      amount: overrides?.amount ?? "",
      unit: overrides?.unit ?? "",
      name: overrides?.name ?? "",
      nutritionQuery: overrides?.nutritionQuery ?? overrides?.name ?? ""
    };
  }

  return {
    amount: overrides?.amount ?? entry.amount ?? "",
    unit: overrides?.unit ?? entry.unit ?? "",
    name: overrides?.name ?? entry.name,
    nutritionQuery: overrides?.nutritionQuery ?? entry.nutritionQuery
  };
}

function mergeIngredientDraftLists(
  preferred: RecipeIngredientDraft[],
  secondary: RecipeIngredientDraft[]
): RecipeIngredientDraft[] {
  const result: RecipeIngredientDraft[] = [];
  const indexByKey = new Map<string, number>();

  for (const ingredient of [...preferred, ...secondary]) {
    const key = ingredientCatalogKey(ingredient);
    if (!key) {
      continue;
    }

    const existingIndex = indexByKey.get(key);
    if (existingIndex == null) {
      indexByKey.set(key, result.length);
      result.push({
        amount: ingredient.amount,
        unit: ingredient.unit,
        name: ingredient.name,
        nutritionQuery: ingredient.nutritionQuery
      });
      continue;
    }

    const existing = result[existingIndex]!;
    result[existingIndex] = {
      amount: existing.amount || ingredient.amount,
      unit: existing.unit || ingredient.unit,
      name: existing.name || ingredient.name,
      nutritionQuery: existing.nutritionQuery || ingredient.nutritionQuery
    };
  }

  return result.slice(0, 18);
}

function ingredientCatalogKey(ingredient: RecipeIngredientDraft): string {
  const normalized = normalizeDishDetectionText(`${ingredient.name} ${ingredient.nutritionQuery}`);
  for (const entry of ingredientCatalog) {
    if (entry.aliases.some((alias) => ingredientAliasMatches(normalized, alias))) {
      return entry.key;
    }
  }

  return normalized
    .replace(/\b(?:de|des|du|la|le|les|with|and)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function countInferredIngredients(
  finalIngredients: RecipeIngredientDraft[],
  explicitIngredients: RecipeIngredientDraft[]
): number {
  const explicitKeys = new Set(explicitIngredients.map(ingredientCatalogKey).filter(Boolean));
  return finalIngredients.reduce((count, ingredient) => (
    explicitKeys.has(ingredientCatalogKey(ingredient))
      ? count
      : count + 1
  ), 0);
}

function burgerProteinForDish(
  dishName: string | undefined,
  explicitKeys: Set<string>
): RecipeIngredientDraft {
  if (explicitKeys.has("chicken_tenders")) {
    return ingredientFromCatalog("chicken_tenders", { amount: "4", unit: "piece" });
  }
  if (explicitKeys.has("chicken_thigh") || explicitKeys.has("chicken_breast")) {
    return ingredientFromCatalog("chicken_breast", { amount: "320", unit: "g" });
  }

  const normalizedDish = normalizeDishDetectionText(dishName ?? "");
  if (normalizedDish.includes("fish") || normalizedDish.includes("filet o fish")) {
    return ingredientFromCatalog("white_fish", { amount: "320", unit: "g" });
  }
  if (normalizedDish.includes("chicken")) {
    return ingredientFromCatalog("chicken_breast", { amount: "320", unit: "g" });
  }

  return ingredientFromCatalog("ground_beef", { amount: "360", unit: "g" });
}

function tacoProteinForDish(
  dishName: string | undefined,
  explicitKeys: Set<string>
): RecipeIngredientDraft {
  if (explicitKeys.has("chicken_tenders")) {
    return ingredientFromCatalog("chicken_tenders", { amount: "6", unit: "piece" });
  }
  if (explicitKeys.has("chicken_thigh") || explicitKeys.has("chicken_breast")) {
    return ingredientFromCatalog("chicken_thigh", { amount: "450", unit: "g" });
  }

  const normalizedDish = normalizeDishDetectionText(dishName ?? "");
  if (normalizedDish.includes("fish")) {
    return ingredientFromCatalog("white_fish", { amount: "400", unit: "g" });
  }
  if (normalizedDish.includes("beef")) {
    return ingredientFromCatalog("ground_beef", { amount: "400", unit: "g" });
  }

  return ingredientFromCatalog("chicken_thigh", { amount: "450", unit: "g" });
}

function curryProteinForDish(
  dishName: string | undefined,
  explicitKeys: Set<string>
): RecipeIngredientDraft {
  if (explicitKeys.has("chicken_breast") || explicitKeys.has("chicken_thigh")) {
    return ingredientFromCatalog("chicken_breast", { amount: "300", unit: "g" });
  }

  const normalizedDish = normalizeDishDetectionText(dishName ?? "");
  if (normalizedDish.includes("chicken")) {
    return ingredientFromCatalog("chicken_breast", { amount: "300", unit: "g" });
  }

  return ingredientFromCatalog("chicken_breast", { amount: "300", unit: "g" });
}

function genericSupportIngredientsForDish(
  intent: DishIntent,
  explicitKeys: Set<string>
): RecipeIngredientDraft[] {
  const normalizedDish = normalizeDishDetectionText(intent.dishName ?? "");
  const inferred: RecipeIngredientDraft[] = [];

  if (/\b(?:sandwich|naan|toast)\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("bread", { amount: "4", unit: "tranches" }),
      ingredientFromCatalog("chicken_breast", { amount: "280", unit: "g" }),
      ingredientFromCatalog("lettuce", { amount: "50", unit: "g" }),
      ingredientFromCatalog("tomato", { amount: "1", unit: "piece" }),
      ingredientFromCatalog("mayonnaise", { amount: "2", unit: "c a soupe" }),
      ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
      ingredientFromCatalog("salt", { amount: "0.5", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.25", unit: "c a cafe" })
    );
  } else if (/\bwrap\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("flatbread", { amount: "2", unit: "piece" }),
      ingredientFromCatalog("chicken_breast", { amount: "280", unit: "g" }),
      ingredientFromCatalog("lettuce", { amount: "60", unit: "g" }),
      ingredientFromCatalog("tomato", { amount: "1", unit: "piece" }),
      ingredientFromCatalog("yogurt", { amount: "100", unit: "g" }),
      ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
      ingredientFromCatalog("salt", { amount: "0.5", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.25", unit: "c a cafe" })
    );
  } else if (/\bpizza\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("pizza_dough", { amount: "1", unit: "piece" }),
      ingredientFromCatalog("tomato_sauce", { amount: "120", unit: "g" }),
      ingredientFromCatalog("mozzarella", { amount: "150", unit: "g" }),
      ingredientFromCatalog("olive_oil", { amount: "1", unit: "c a soupe" }),
      ingredientFromCatalog("basil", { amount: "6", unit: "feuilles" }),
      ingredientFromCatalog("salt", { amount: "0.5", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.25", unit: "c a cafe" })
    );
  } else if (/\b(?:salad|salade|bowl)\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("lettuce", { amount: "120", unit: "g" }),
      ingredientFromCatalog("tomato", { amount: "2", unit: "piece" }),
      ingredientFromCatalog("cucumber", { amount: "0.5", unit: "piece" }),
      ingredientFromCatalog(explicitKeys.has("chicken_breast") ? "chicken_breast" : "chickpeas", {
        amount: explicitKeys.has("chicken_breast") ? "250" : "240",
        unit: explicitKeys.has("chicken_breast") ? "g" : "g"
      }),
      ingredientFromCatalog("olive_oil", { amount: "2", unit: "c a soupe" }),
      ingredientFromCatalog("salt", { amount: "0.5", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.25", unit: "c a cafe" })
    );
  } else if (/\bomelette\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("egg", { amount: "3", unit: "oeufs" }),
      ingredientFromCatalog("cheddar", { amount: "50", unit: "g" }),
      ingredientFromCatalog("butter", { amount: "15", unit: "g" }),
      ingredientFromCatalog("salt", { amount: "0.25", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.25", unit: "c a cafe" })
    );
  } else if (/\b(?:brownie|cookie|cake)\b/.test(normalizedDish)) {
    inferred.push(
      ingredientFromCatalog("flour", { amount: "180", unit: "g" }),
      ingredientFromCatalog("sugar", { amount: "120", unit: "g" }),
      ingredientFromCatalog("butter", { amount: "120", unit: "g" }),
      ingredientFromCatalog("egg", { amount: "2", unit: "oeufs" }),
      ingredientFromCatalog("chocolate", { amount: "180", unit: "g" }),
      ingredientFromCatalog("baking_powder", { amount: "1", unit: "c a cafe" })
    );
  } else {
    inferred.push(
      ingredientFromCatalog("oil", { amount: "1", unit: "c a soupe" }),
      ingredientFromCatalog("salt", { amount: "1", unit: "c a cafe" }),
      ingredientFromCatalog("pepper", { amount: "0.5", unit: "c a cafe" })
    );
  }

  return inferred;
}

function burgerSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const protein = preferredIngredientName(ingredients, ["ground_beef", "white_fish", "chicken_breast", "chicken_tenders"], "viande");
  const buns = preferredIngredientName(ingredients, ["hamburger_bun"], "pains burger");
  const cheese = preferredIngredientName(ingredients, ["cheddar", "parmesan"], "fromage");
  const onion = preferredIngredientName(ingredients, ["onion"], "oignon");
  const pickles = preferredIngredientName(ingredients, ["pickles"], "cornichons");
  const sauce = preferredIngredientName(ingredients, ["burger_sauce", "mayonnaise"], "sauce");
  const mushrooms = preferredIngredientName(ingredients, ["mushroom"], "champignons");
  const truffleOil = preferredIngredientName(ingredients, ["truffle_oil"], "huile de truffe");
  const hasMushrooms = hasIngredientMatching(ingredients, /\b(?:mushroom|champignon)\b/i);
  const hasTruffle = hasIngredientMatching(ingredients, /\b(?:truffle|truffe)\b/i);
  const hasHomemadeBuns = hasIngredientMatching(ingredients, /\b(?:milk|lait)\b/i) &&
    hasIngredientMatching(ingredients, /\b(?:flour|farine)\b/i) &&
    hasIngredientMatching(ingredients, /\b(?:yeast|levure)\b/i);
  const hasFishBurger = hasIngredientMatching(ingredients, /\b(?:cod|cabillaud|white fish|fish fillet|poisson)\b/i);
  const doughLiquid = ingredientNameMatching(ingredients, /\b(?:milk|lait)\b/i, "lait");
  const doughSweetener = ingredientNameMatching(ingredients, /\b(?:honey|miel|sugar|sucre)\b/i, "miel");
  const doughYeast = ingredientNameMatching(ingredients, /\b(?:yeast|levure)\b/i, "levure");
  const doughButter = ingredientNameMatching(ingredients, /\b(?:butter|beurre)\b/i, "beurre");
  const doughOil = ingredientNameMatching(ingredients, /\b(?:oil|huile)\b/i, "huile");
  const doughFlour = ingredientNameMatching(ingredients, /\b(?:flour|farine)\b/i, "farine");
  const doughEgg = ingredientNameMatching(ingredients, /\b(?:egg|oeuf)\b/i, "oeuf");
  const fishSeasoning = ingredientNameMatching(ingredients, /\b(?:mustard|moutarde|cayenne|paprika|onion powder)\b/i, "épices");
  const fishHeat = ingredientNameMatching(ingredients, /\b(?:cayenne|paprika|pepper|poivre)\b/i, "poivre");
  const sesame = ingredientNameMatching(ingredients, /\b(?:sesame|sésame)\b/i, "sésame");
  const lettuce = preferredIngredientName(ingredients, ["lettuce"], "salade");

  const steps: string[] = [];
  if (hasHomemadeBuns) {
    steps.push(
      `Mélangez le ${doughLiquid}, le ${doughSweetener} et la ${doughYeast}, puis incorporez le ${doughEgg}, le ${doughOil}, le ${doughButter} et la ${doughFlour} pour obtenir une pâte souple.`
    );
    steps.push(
      `Laissez lever la pâte, façonnez les ${buns}, ajoutez le ${sesame} si vous en avez et faites-les cuire jusqu'à ce qu'ils soient bien dorés.`
    );
  } else {
    steps.push(`Préparez les garnitures: émincez l'${onion} si besoin et gardez le ${sauce} prêt pour le montage.`);
  }

  if (hasMushrooms) {
    steps.push(
      `Faites revenir les ${mushrooms} dans un peu de matière grasse jusqu'à ce qu'ils soient bien dorés et concentrés en goût.`
    );
  }

  if (hasFishBurger) {
    steps.push(
      `Assaisonnez le ${protein} avec le ${fishSeasoning} et le ${fishHeat}, panez-le si besoin avec un peu de farine puis faites-le cuire jusqu'à ce qu'il soit bien doré et croustillant.`
    );
  } else {
    steps.push(
      `Divisez le ${protein} en portions, assaisonnez de sel et de poivre, puis saisissez-le dans une poêle très chaude en l'écrasant si vous faites un smash burger.`
    );
  }

  steps.push(
    `Faites légèrement griller les ${buns}, puis ajoutez le ${cheese} sur le ${protein} chaud pour le faire fondre.`
  );
  steps.push(
    `Préparez le montage avec le ${sauce}, la ${lettuce}, l'${onion}, les ${pickles}${hasMushrooms ? ` et les ${mushrooms}` : ""} afin d'avoir toutes les garnitures prêtes.`
  );
  steps.push(
    `Tartinez le ${sauce} sur les ${buns}, ajoutez la ${lettuce}, le ${protein}, l'${onion}, les ${pickles}${hasMushrooms ? ` et les ${mushrooms}` : ""}${hasTruffle ? `, puis terminez avec un filet de ${truffleOil}` : ""} avant de refermer et servir aussitôt.`
  );

  return steps;
}

function tacoSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const protein = preferredIngredientName(ingredients, ["chicken_thigh", "chicken_breast", "chicken_tenders", "ground_beef", "white_fish"], "poulet");
  const tortillas = preferredIngredientName(ingredients, ["tortilla"], "tortillas");
  const cabbage = preferredIngredientName(ingredients, ["cabbage", "lettuce"], "chou");
  const lime = preferredIngredientName(ingredients, ["lime"], "citron vert");
  const sauce = preferredIngredientName(ingredients, ["sour_cream", "mayonnaise"], "sauce");

  return [
    `Assaisonnez le ${protein} avec les épices, un peu de sel et de poivre, puis enrobez-le légèrement de farine si vous voulez une texture bien croustillante.`,
    `Faites cuire le ${protein} dans une poêle chaude avec un filet d'huile jusqu'à ce qu'il soit bien doré et cuit à cœur, puis détaillez-le en morceaux.`,
    `Mélangez le ${cabbage} avec un peu de ${lime} et une cuillère de ${sauce} pour obtenir une garniture fraîche.`,
    `Réchauffez les ${tortillas}, garnissez-les avec le ${protein}, le ${cabbage} et le reste de ${sauce}, puis servez immédiatement.`
  ];
}

function pastaSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const pasta = preferredIngredientName(ingredients, ["pasta"], "pâtes");
  const protein = preferredIngredientName(ingredients, ["chicken_breast", "chicken_thigh"], "poulet");
  const onion = preferredIngredientName(ingredients, ["onion"], "oignon");
  const garlic = preferredIngredientName(ingredients, ["garlic"], "ail");
  const curry = preferredIngredientName(ingredients, ["curry_powder"], "curry");
  const cream = preferredIngredientName(ingredients, ["cream", "coconut_milk"], "crème");
  const cheese = preferredIngredientName(ingredients, ["parmesan"], "parmesan");

  return [
    `Faites cuire les ${pasta} dans une grande casserole d'eau salée jusqu'à ce qu'elles soient al dente, puis réservez une petite louche d'eau de cuisson.`,
    `Faites revenir le ${protein} avec l'${onion} et l'${garlic} dans un peu d'huile jusqu'à ce que le tout soit bien doré.`,
    `Ajoutez le ${curry}, laissez-le torréfier quelques secondes, puis versez la ${cream} et laissez mijoter pour obtenir une sauce nappante.`,
    `Incorporez les ${pasta} à la sauce, détendez avec un peu d'eau de cuisson si besoin, ajoutez le ${cheese} et servez bien chaud.`
  ];
}

function tiramisuSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const eggs = preferredIngredientName(ingredients, ["egg"], "oeufs");
  const sugar = preferredIngredientName(ingredients, ["sugar"], "sucre");
  const mascarpone = preferredIngredientName(ingredients, ["mascarpone"], "mascarpone");
  const coffee = preferredIngredientName(ingredients, ["coffee"], "café");
  const biscuits = preferredIngredientName(ingredients, ["ladyfinger"], "biscuits cuillère");
  const cocoa = preferredIngredientName(ingredients, ["cocoa_powder"], "cacao");

  return [
    `Fouettez les ${eggs} avec le ${sugar} jusqu'à obtenir un mélange pâle et souple, puis incorporez délicatement le ${mascarpone}.`,
    `Versez le ${coffee} refroidi dans une assiette creuse et trempez rapidement les ${biscuits} pour qu'ils restent souples sans se défaire.`,
    `Alternez une couche de ${biscuits} imbibés et une couche de crème au ${mascarpone} dans un plat, puis lissez la surface.`,
    `Laissez prendre au frais plusieurs heures et saupoudrez de ${cocoa} juste avant de servir.`
  ];
}

function currySteps(ingredients: RecipeIngredientDraft[]): string[] {
  const protein = preferredIngredientName(ingredients, ["chicken_breast", "chicken_thigh", "white_fish"], "protéine");
  const onion = preferredIngredientName(ingredients, ["onion"], "oignon");
  const garlic = preferredIngredientName(ingredients, ["garlic"], "ail");
  const curry = preferredIngredientName(ingredients, ["curry_powder"], "curry");
  const coconutMilk = preferredIngredientName(ingredients, ["coconut_milk", "cream"], "lait de coco");

  return [
    `Faites revenir l'${onion} et l'${garlic} dans un peu d'huile jusqu'à ce qu'ils soient fondants.`,
    `Ajoutez le ${protein}, salez légèrement et faites-le dorer sur toutes les faces.`,
    `Incorporez le ${curry}, mélangez pendant quelques secondes, puis versez le ${coconutMilk} et laissez mijoter jusqu'à ce que la sauce épaississe.`,
    "Goûtez, rectifiez l'assaisonnement et servez le curry bien chaud avec l'accompagnement de votre choix."
  ];
}

function genericDishSteps(dishName: string, ingredients: RecipeIngredientDraft[]): string[] {
  const normalizedDish = normalizeDishDetectionText(dishName);
  if (/\b(?:sandwich|naan|toast)\b/.test(normalizedDish)) {
    return sandwichSteps(dishName, ingredients);
  }
  if (/\bwrap\b/.test(normalizedDish)) {
    return wrapSteps(dishName, ingredients);
  }
  if (/\bpizza\b/.test(normalizedDish)) {
    return pizzaSteps(ingredients);
  }
  if (/\b(?:salad|salade|bowl)\b/.test(normalizedDish)) {
    return saladSteps(dishName, ingredients);
  }
  if (/\bomelette\b/.test(normalizedDish)) {
    return omeletteSteps(ingredients);
  }
  if (/\b(?:brownie|cookie|cake)\b/.test(normalizedDish)) {
    return dessertSteps(dishName, ingredients);
  }

  const mainIngredients = ingredients
    .slice(0, 4)
    .map((ingredient) => ingredient.name)
    .filter(Boolean);
  const head = mainIngredients[0] ?? "ingrédients";
  const middle = mainIngredients[1] ?? "aromates";
  const tail = mainIngredients[2] ?? "garnitures";

  return [
    `Préparez les éléments du ${dishName.toLocaleLowerCase()} en détaillant le ${head} et le ${middle} selon la taille souhaitée.`,
    `Faites cuire le ${head} avec un peu de matière grasse jusqu'à obtenir une bonne coloration et une cuisson régulière.`,
    `Ajoutez le ${middle} puis le ${tail}, assaisonnez et poursuivez la cuisson jusqu'à ce que l'ensemble soit bien lié.`,
    `Rectifiez l'assaisonnement, dressez le ${dishName.toLocaleLowerCase()} et servez immédiatement.`
  ];
}

function sandwichSteps(dishName: string, ingredients: RecipeIngredientDraft[]): string[] {
  const bread = preferredIngredientName(ingredients, ["bread", "flatbread", "hamburger_bun"], "pain");
  const protein = preferredIngredientName(ingredients, ["chicken_breast", "ground_beef", "white_fish", "chickpeas"], "garniture principale");
  const greens = preferredIngredientName(ingredients, ["lettuce", "cabbage"], "salade");
  const tomato = preferredIngredientName(ingredients, ["tomato"], "tomate");
  const sauce = preferredIngredientName(ingredients, ["mayonnaise", "burger_sauce", "yogurt"], "sauce");

  return [
    `Assaisonnez le ${protein} puis faites-le cuire dans une poele chaude jusqu'a ce qu'il soit bien dore et cuit a coeur.`,
    `Coupez le ${bread} et faites-le griller legerement pour lui donner du croustillant.`,
    `Preparez la garniture avec la ${greens}, la ${tomato} et le ${sauce}.`,
    `Montez le ${dishName.toLocaleLowerCase()} avec le ${bread}, le ${protein}, les legumes et la sauce, puis servez aussitot.`
  ];
}

function wrapSteps(dishName: string, ingredients: RecipeIngredientDraft[]): string[] {
  const wrap = preferredIngredientName(ingredients, ["flatbread", "tortilla"], "wrap");
  const protein = preferredIngredientName(ingredients, ["chicken_breast", "chicken_tenders", "ground_beef"], "garniture principale");
  const greens = preferredIngredientName(ingredients, ["lettuce", "cabbage"], "salade");
  const tomato = preferredIngredientName(ingredients, ["tomato"], "tomate");
  const sauce = preferredIngredientName(ingredients, ["yogurt", "mayonnaise", "burger_sauce"], "sauce");

  return [
    `Assaisonnez le ${protein} et faites-le cuire jusqu'a ce qu'il soit bien dore, puis coupez-le en morceaux si besoin.`,
    `Rechauffez le ${wrap} quelques secondes pour l'assouplir sans le dessécher.`,
    `Disposez la ${greens}, la ${tomato}, le ${protein} et le ${sauce} au centre du ${wrap}.`,
    `Rabattez les cotes, roulez le ${dishName.toLocaleLowerCase()} bien serre et servez aussitot.`
  ];
}

function pizzaSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const dough = preferredIngredientName(ingredients, ["pizza_dough"], "pate a pizza");
  const sauce = preferredIngredientName(ingredients, ["tomato_sauce"], "sauce tomate");
  const cheese = preferredIngredientName(ingredients, ["mozzarella", "cheddar"], "mozzarella");
  const basil = preferredIngredientName(ingredients, ["basil"], "basilic");

  return [
    `Etalez la ${dough} sur une plaque ou une pierre chaude en laissant un leger rebord.`,
    `Repartissez la ${sauce} sur la pate puis ajoutez le ${cheese} et les garnitures principales.`,
    `Faites cuire la pizza dans un four tres chaud jusqu'a ce que la pate soit doree et le fromage bien fondu.`,
    `Ajoutez le ${basil} et un filet d'huile a la sortie du four, puis servez immediatement.`
  ];
}

function saladSteps(dishName: string, ingredients: RecipeIngredientDraft[]): string[] {
  const greens = preferredIngredientName(ingredients, ["lettuce", "cabbage"], "salade");
  const protein = preferredIngredientName(ingredients, ["chicken_breast", "chickpeas", "ground_beef"], "garniture principale");
  const tomato = preferredIngredientName(ingredients, ["tomato"], "tomate");
  const cucumber = preferredIngredientName(ingredients, ["cucumber"], "concombre");
  const dressing = preferredIngredientName(ingredients, ["olive_oil", "yogurt", "mayonnaise"], "assaisonnement");

  return [
    `Preparez la base du ${dishName.toLocaleLowerCase()} en lavant la ${greens} et en coupant la ${tomato} et le ${cucumber}.`,
    `Faites cuire le ${protein} si necessaire puis laissez-le tiedir quelques minutes.`,
    `Melangez les legumes avec le ${protein} et le ${dressing} jusqu'a obtenir un ensemble bien assaisonne.`,
    `Rectifiez le sel et le poivre, puis servez le ${dishName.toLocaleLowerCase()} bien frais ou tiede.`
  ];
}

function omeletteSteps(ingredients: RecipeIngredientDraft[]): string[] {
  const eggs = preferredIngredientName(ingredients, ["egg"], "oeufs");
  const butter = preferredIngredientName(ingredients, ["butter"], "beurre");
  const cheese = preferredIngredientName(ingredients, ["cheddar", "mozzarella", "parmesan"], "fromage");

  return [
    `Battez les ${eggs} avec une pincee de sel et de poivre jusqu'a obtenir un melange homogene.`,
    `Faites fondre le ${butter} dans une poele chaude puis versez les oeufs.`,
    `Ajoutez le ${cheese} quand l'omelette commence a prendre, puis repliez-la delicatement.`,
    "Poursuivez la cuisson quelques secondes et servez sans attendre."
  ];
}

function dessertSteps(dishName: string, ingredients: RecipeIngredientDraft[]): string[] {
  const flour = preferredIngredientName(ingredients, ["flour"], "farine");
  const sugar = preferredIngredientName(ingredients, ["sugar"], "sucre");
  const butter = preferredIngredientName(ingredients, ["butter"], "beurre");
  const eggs = preferredIngredientName(ingredients, ["egg"], "oeufs");
  const chocolate = preferredIngredientName(ingredients, ["chocolate", "cocoa_powder"], "chocolat");

  return [
    `Faites fondre le ${butter} avec le ${chocolate} puis laissez tiedir quelques instants.`,
    `Fouettez les ${eggs} avec le ${sugar}, puis incorporez le melange au chocolat et la ${flour}.`,
    `Versez la pate dans un moule ou formez des portions selon le ${dishName.toLocaleLowerCase()}.`,
    `Faites cuire jusqu'a ce que le dessert soit pris mais encore moelleux, puis laissez refroidir avant de servir.`
  ];
}

function preferredIngredientName(
  ingredients: RecipeIngredientDraft[],
  keys: string[],
  fallback: string
): string {
  for (const ingredient of ingredients) {
    const key = ingredientCatalogKey(ingredient);
    if (keys.includes(key)) {
      return ingredient.name;
    }
  }

  return fallback;
}

function ingredientNameMatching(
  ingredients: RecipeIngredientDraft[],
  pattern: RegExp,
  fallback: string
): string {
  for (const ingredient of ingredients) {
    if (pattern.test(`${ingredient.name} ${ingredient.nutritionQuery}`)) {
      return ingredient.name;
    }
  }

  return fallback;
}

function hasIngredientMatching(
  ingredients: RecipeIngredientDraft[],
  pattern: RegExp
): boolean {
  return ingredients.some((ingredient) => pattern.test(`${ingredient.name} ${ingredient.nutritionQuery}`));
}

function normalizeDishDetectionText(value: string): string {
  return value
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/[|•·]/g, " ")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s#-]/gu, " ")
    .replace(/[#_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractGenericDishPhrase(normalized: string): string | null {
  for (const pattern of genericDishPhrasePatterns) {
    const match = normalized.match(pattern);
    if (match?.[0]) {
      return match[0].trim();
    }
  }

  return null;
}

function prettifyDishName(value: string): string {
  const normalized = normalizeDishDetectionText(value);
  const compact = normalized
    .replace(/\b(?:recipe|recette|ingredients|ingredient|instructions|etapes|etape)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return compact
    .split(" ")
    .filter(Boolean)
    .map((word) => {
      if (["o", "a", "de", "du", "des", "au", "aux"].includes(word)) {
        return word;
      }

      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(" ");
}

function templateIdForDishName(value: string): DishTemplateId {
  const normalized = normalizeDishDetectionText(value);
  if (normalized.includes("smash burger")) {
    return "smash_burger";
  }
  if (normalized.includes("crispy chicken tacos")) {
    return "crispy_chicken_tacos";
  }
  if (normalized.includes("chicken curry pasta")) {
    return "chicken_curry_pasta";
  }
  if (normalized.includes("tiramisu")) {
    return "tiramisu";
  }
  if (normalized.includes("burger")) {
    return "burger";
  }
  if (normalized.includes("taco")) {
    return "tacos";
  }
  if (normalized.includes("pasta")) {
    return "pasta";
  }
  if (normalized.includes("curry")) {
    return "curry";
  }

  return "generic";
}

function inferredIngredientsForFlavorProfile(
  intent: DishIntent,
  explicitKeys: Set<string>
): RecipeIngredientDraft[] {
  const normalizedDish = normalizeDishDetectionText(intent.dishName ?? "");
  const inferred: RecipeIngredientDraft[] = [];

  if (
    (normalizedDish.includes("truffle") || normalizedDish.includes("truffe")) &&
    !explicitKeys.has("truffle_oil")
  ) {
    inferred.push(ingredientFromCatalog("truffle_oil", { amount: "1", unit: "c a cafe" }));
  }

  if (
    (normalizedDish.includes("truffle") ||
      normalizedDish.includes("truffe") ||
      normalizedDish.includes("mushroom") ||
      normalizedDish.includes("champignon")) &&
    !explicitKeys.has("mushroom")
  ) {
    inferred.push(ingredientFromCatalog("mushroom", { amount: "120", unit: "g" }));
  }

  return inferred;
}

function foodSignalStrength(text: string): number {
  const normalized = normalizeDishDetectionText(text);
  if (!normalized) {
    return 0;
  }

  return foodSignalPatterns.reduce((score, pattern) => (
    pattern.test(normalized)
      ? score + 1
      : score
  ), 0);
}

function isWeakRecipeTitle(value: string): boolean {
  const normalized = normalizeDishDetectionText(value);
  return normalized === "recette importee" ||
    normalized === "recette importeee" ||
    normalized === "recette";
}

function looksLikeDishNameIngredient(value: string, dishName: string): boolean {
  const normalizedValue = normalizeDishDetectionText(value);
  const normalizedDishName = normalizeDishDetectionText(dishName);
  if (!normalizedValue || !normalizedDishName) {
    return false;
  }

  return normalizedValue === normalizedDishName ||
    (genericDishWords.has(normalizedValue) && normalizedDishName.includes(normalizedValue));
}

function extractStructuredRecipe(blocks: string[]): RecipeImportResult | null {
  for (const block of blocks) {
    const parsed = parseStructuredRecipeBlock(block);
    if (parsed) {
      return parsed;
    }
  }

  return null;
}

function parseStructuredRecipeBlock(block: string): RecipeImportResult | null {
  const cleaned = block
    .replaceAll("<!--", "")
    .replaceAll("-->", "")
    .replaceAll("<![CDATA[", "")
    .replaceAll("]]>", "")
    .trim();

  if (!cleaned) {
    return null;
  }

  try {
    const object = JSON.parse(cleaned) as unknown;
    const recipeObject = findRecipeObject(object);
    if (!recipeObject) {
      return null;
    }

    return sanitizeRecipeImport({
      title: stringValue(recipeObject.name) ?? "Recette importee",
      sourceUrl: "",
      remoteImageUrl: imageUrl(recipeObject.image) ?? "",
      ingredientDrafts: stringArray(recipeObject.recipeIngredient).map(parseIngredientLine),
      stepDrafts: instructions(recipeObject.recipeInstructions)
        .map((detail) => ({ detail }))
        .filter((step) => step.detail.length > 0),
      notesText: stringValue(recipeObject.description) ?? "",
      prepTimeText: durationInMinutes(stringValue(recipeObject.prepTime)),
      cookTimeText: durationInMinutes(stringValue(recipeObject.cookTime)),
      servingsText: stringValue(recipeObject.recipeYield) ?? "",
      caloriesText: stringValue(recipeObject.nutrition?.calories) ?? "",
      proteinText: stringValue(recipeObject.nutrition?.proteinContent) ?? "",
      carbsText: stringValue(recipeObject.nutrition?.carbohydrateContent) ?? "",
      fatText: stringValue(recipeObject.nutrition?.fatContent) ?? "",
      confidence: "high",
      needsWebFallback: false,
      searchQuery: "",
      inferredFromPhoto: false
    });
  } catch {
    return null;
  }
}

function findRecipeObject(value: unknown): Record<string, any> | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const recipe = findRecipeObject(item);
      if (recipe) {
        return recipe;
      }
    }
    return null;
  }

  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, any>;
  if (isRecipeType(record["@type"])) {
    return record;
  }

  if (Array.isArray(record["@graph"])) {
    for (const item of record["@graph"]) {
      const recipe = findRecipeObject(item);
      if (recipe) {
        return recipe;
      }
    }
  }

  for (const child of Object.values(record)) {
    const recipe = findRecipeObject(child);
    if (recipe) {
      return recipe;
    }
  }

  return null;
}

function isRecipeType(value: unknown): boolean {
  if (typeof value === "string") {
    return value.toLowerCase() === "recipe";
  }

  if (Array.isArray(value)) {
    return value.some((entry) => typeof entry === "string" && entry.toLowerCase() === "recipe");
  }

  return false;
}

function stringValue(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || null;
  }

  if (typeof value === "number") {
    return String(value);
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const nested = stringValue(entry);
      if (nested) {
        return nested;
      }
    }
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return stringValue(record.value) ?? stringValue(record.text) ?? stringValue(record.name) ?? null;
  }

  return null;
}

function stringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map((entry) => stringValue(entry)).filter((entry): entry is string => Boolean(entry));
  }

  const single = stringValue(value);
  return single ? [single] : [];
}

function imageUrl(value: unknown): string | null {
  if (typeof value === "string") {
    return value.trim() || null;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const nested = imageUrl(entry);
      if (nested) {
        return nested;
      }
    }
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return stringValue(record.url) ?? stringValue(record.contentUrl) ?? stringValue(record.thumbnailUrl) ?? null;
  }

  return null;
}

function instructions(value: unknown): string[] {
  if (typeof value === "string") {
    const cleaned = cleanedStepLine(value);
    return cleaned ? [cleaned] : [];
  }

  if (Array.isArray(value)) {
    return value.flatMap((entry) => instructions(entry));
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (record.text) {
      return instructions(record.text);
    }
    if (record.itemListElement) {
      return instructions(record.itemListElement);
    }
    if (record.name) {
      return instructions(record.name);
    }
  }

  return [];
}

function durationInMinutes(value: string | null): string {
  if (!value) {
    return "";
  }

  const normalized = value.toUpperCase();
  const match = normalized.match(/P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?/);
  if (!match) {
    return "";
  }

  const days = Number(match[1] ?? 0);
  const hours = Number(match[2] ?? 0);
  const minutes = Number(match[3] ?? 0);
  const total = days * 24 * 60 + hours * 60 + minutes;
  return total > 0 ? String(total) : "";
}

function normalizedLines(input: string): string[] {
  return input
    .replaceAll("\r\n", "\n")
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

function heuristicLines(input: string): string[] {
  const preprocessedInput = preprocessRecipeNarrativeInput(input);
  const directLines = normalizedLines(preprocessedInput);
  const expandedInput = preprocessedInput
    .replaceAll("\r\n", "\n")
    .replace(/[•·▪◦●]/g, "\n- ")
    .replace(/\s*[|;]+\s*/g, "\n")
    .replace(
      /\b(ingredients?|ingrédients?|instructions?|étapes?|etapes|préparation|preparation|method|méthode|methode)\b\s*:/giu,
      "\n$1\n"
    )
    .replace(/(^|\n)\s*(\d+[).:-])\s*/g, "$1$2 ")
    .replace(
      /([.!?])\s+(?=(?:ajouter|mélanger|melanger|cuire|faire|verser|laisser|chauffer|mettre|servir|quand|maintenant|on va|add|mix|cook|stir|serve|ingredients?|instructions?|étapes?|etapes|préparation|preparation|\d+[.)-]))/giu,
      "$1\n"
    )
    .replace(
      /,\s+(?=(?:\d+(?:[.,]\d+)?|\d+\/\d+)\s*(?:g|kg|ml|cl|l|cas|cac|c\s*a\s*s|c\s*a\s*c|tablespoons?|teaspoons?|cups?|lb|lbs|oz)\b)/giu,
      "\n"
    );

  const expandedLines = normalizedLines(expandedInput);
  return uniqueNonEmptyLines(expandedLines.length >= directLines.length ? expandedLines : directLines);
}

function uniqueNonEmptyLines(lines: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const line of lines) {
    if (seen.has(line)) {
      continue;
    }

    seen.add(line);
    result.push(line);
  }

  return result;
}

function explicitTitle(lines: string[]): string | null {
  for (const line of lines) {
    if (/^(titre|title)\s*:/i.test(line)) {
      const cleaned = cleanedTitle(line);
      if (isLikelyRecipeTitle(cleaned)) {
        return cleaned;
      }
    }
  }
  return null;
}

function fallbackTitle(lines: string[]): string {
  for (const line of lines) {
    if (!isSectionHeader(line) && !isLikelyNoise(line)) {
      const cleaned = cleanedTitle(line);
      if (isLikelyRecipeTitle(cleaned)) {
        return cleaned;
      }
    }
  }
  return "";
}

function isSectionHeader(line: string): boolean {
  return isIngredientsHeader(line) || isStepsHeader(line) || isNotesHeader(line);
}

function isIngredientsHeader(line: string): boolean {
  return matches(line, ["ingredients", "ingrédients", "ingredient", "liste des ingrédients"]) ||
    /^(?:ingredients?|ingrédients?)(?:\s+.+)?[:：]\s*$/i.test(line);
}

function isStepsHeader(line: string): boolean {
  return matches(line, ["instructions", "étapes", "etapes", "préparation", "preparation", "méthode", "methode", "directions", "marche a suivre", "marche à suivre"]);
}

function isIngredientSubsectionHeader(line: string): boolean {
  const normalized = normalizedDecorativeText(line);

  if (!normalized || normalized.length > 40) {
    return false;
  }

  return [
    "assemblage",
    "cuisson",
    "dough",
    "extras",
    "extra",
    "mixture",
    "cod mixture",
    "flour mixture",
    "crispy coating",
    "coating",
    "marinade",
    "panure",
    "poulet pane",
    "sauce",
    "serve with",
    "garniture",
    "assemblage"
  ].some((header) => normalized === header || normalized.startsWith(`${header} `));
}

function isNotesHeader(line: string): boolean {
  return matches(line, ["notes", "astuces", "conseils"]);
}

function matches(line: string, patterns: string[]): boolean {
  const normalized = normalizedDecorativeText(line);
  return patterns.includes(normalized);
}

function cleanedTitle(line: string): string {
  const cleaned = line
    .replace(/^(titre|title)\s*:\s*/i, "")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .replace(/@[\p{L}\p{N}_.]+/gu, " ")
    .replace(/\+\s*(?:suivre|follow)\b.*$/i, " ")
    .replace(/\p{Extended_Pictographic}/gu, " ")
    .replace(/\b(?:ingredients?|ingrédients?|instructions?|étapes?|etapes|dough|mixture|coating|marinade|serve with)\b.*$/i, "")
    .replace(/^[^A-Za-zÀ-ÿ0-9]+|[^A-Za-zÀ-ÿ0-9]+$/gu, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
  const formatted = isMostlyUppercase(cleaned)
    ? cleaned.toLocaleLowerCase().replace(/\b\p{L}/gu, (character) => character.toUpperCase())
    : cleaned;
  return isGenericSocialTitle(formatted) || hasSuspiciousRecipeTitle(formatted) ? "" : formatted;
}

function isLikelyRecipeTitle(line: string): boolean {
  const cleaned = cleanedTitle(line);
  const normalized = normalizedDecorativeText(cleaned);
  if (!normalized) {
    return false;
  }
  if (isLikelyNoise(cleaned) || isSectionHeader(cleaned) || isIngredientSubsectionHeader(cleaned)) {
    return false;
  }

  const words = normalized.split(" ").filter(Boolean);
  if (!words.length || words.length > 8) {
    return false;
  }

  if (containsLikelyDishTerm(normalized)) {
    return true;
  }

  return isMostlyUppercase(cleaned) &&
    words.length >= 2 &&
    words.length <= 5 &&
    containsIngredientKeyword(normalized);
}

function cleanedListLine(line: string): string {
  return line.replace(/^\s*(?:[-•*]|[⭐✨👉👇☝️])+\s*/u, "").trim();
}

function cleanedStepLine(line: string): string {
  return line.replace(/^\s*(?:[⭐✨👉👇☝️]+\s*)*(?:\d+[).:-]\s+|[-•*]\s*)/u, "").trim();
}

function looksLikeIngredient(line: string): boolean {
  const cleaned = cleanedListLine(line);
  if (!cleaned) {
    return false;
  }
  if (isLikelyNoise(cleaned) || looksLikeMusicCredit(cleaned)) {
    return false;
  }
  if (isIngredientSubsectionHeader(cleaned)) {
    return false;
  }
  if (looksLikeIngredientMetaLine(cleaned)) {
    return false;
  }
  if (isTitleLikeFoodLine(cleaned)) {
    return false;
  }
  if (looksLikeStep(cleaned)) {
    return false;
  }
  const hasQuantity = /\b(?:\d+(?:[,./]\d+)?|\d+\/\d+|[¼½¾⅓⅔⅛])\b/.test(cleaned);
  if (/^\d+([,./]\d+)?/.test(cleaned)) {
    return true;
  }
  if (hasQuantity && containsIngredientKeyword(cleaned)) {
    return true;
  }

  const lower = cleaned.toLowerCase();
  const units = ["g", "kg", "ml", "l", "c a s", "cas", "cuillere", "tasse", "verre", "pincee"];
  return units.some((unit) => lower.includes(unit)) ||
    (containsIngredientKeyword(cleaned) && cleaned.split(" ").length <= 8);
}

function looksLikeIngredientMetaLine(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  return /\b(?:chacun|chacune|environ|conseille|conseil|portion|portions|anti adhesive|antiadhesive|poele|poelee|cuisson|video)\b/.test(normalized) ||
    normalized.startsWith("ici mes ") ||
    normalized.includes("au frais");
}

function looksLikeStep(line: string): boolean {
  const cleaned = cleanedStepLine(line).toLowerCase();
  if (!cleaned) {
    return false;
  }
  if (/\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/.test(cleaned) || cleaned.includes("-->")) {
    return false;
  }
  if (/^\s*(?:\d+[).:-]\s+|[-•*]\s*)/.test(line)) {
    return true;
  }

  const verbs = [
    "melanger", "mélanger", "ajouter", "faire", "cuire", "verser", "laisser",
    "chauffer", "former", "mettre", "fouetter", "mixer", "decouper", "découper",
    "rotir", "rôtir", "servir", "prechauffer", "préchauffer", "remuer", "incorporer",
    "puis", "ensuite", "etaler", "étaler", "etalez", "étalez", "rouler", "plier",
    "garnir", "repartir", "répartir", "napper", "saisir", "faire revenir", "laisser cuire",
    "on va", "quand", "maintenant",
    "add", "mix", "stir", "cook", "serve", "pour", "let", "knead", "shape",
    "spread", "flatten", "coat", "fold", "return", "heat", "place"
  ];
  return verbs.some((verb) => cleaned.startsWith(verb));
}

function isLikelyNoise(line: string): boolean {
  const rawLower = line.toLowerCase();
  const lower = normalizedDecorativeText(line);
  return rawLower.includes("http://") ||
    rawLower.includes("https://") ||
    rawLower.trim().startsWith("#") ||
    lower.includes("tiktok") ||
    lower.includes("instagram") ||
    looksLikeSocialHandleLine(line) ||
    looksLikeMusicCredit(line) ||
    lower.includes("ajouter un commentaire") ||
    lower.includes("watch more");
}

function normalizedDecorativeText(line: string): string {
  return line
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\p{Extended_Pictographic}/gu, " ")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function looksLikeSocialHandleLine(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  return line.trim().startsWith("@") ||
    normalized.includes("suivre") ||
    normalized.includes("follow");
}

function looksLikeMusicCredit(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  if (!normalized) {
    return false;
  }

  const words = normalized.split(" ").filter(Boolean);
  if (words.length > 6) {
    return false;
  }

  if (containsIngredientKeyword(normalized)) {
    return false;
  }

  return normalized.includes("original sound") ||
    normalized.includes("son original") ||
    normalized.includes("soundtrack") ||
    normalized.includes("playlist") ||
    normalized.includes("remix") ||
    normalized.includes("waltz") ||
    normalized.includes("audio");
}

function containsIngredientKeyword(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  return /\b(?:burger|naan|poulet|chicken|farine|flour|fromage|cheese|levure|yaourt|beurre|eau|sel|sucre|escalope|paprika|semoule|chapelure|panure|sauce|tortilla|tacos?|corn\s+flakes?|soja|soy)\b/.test(normalized);
}

function containsLikelyDishTerm(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  return genericDishWords.has(normalized) ||
    likelyDishTitlePatterns.some((pattern) => pattern.test(normalized)) ||
    containsIngredientKeyword(normalized);
}

function isTitleLikeFoodLine(line: string): boolean {
  const normalized = normalizedDecorativeText(line);
  if (!normalized) {
    return false;
  }

  const words = normalized.split(" ").filter(Boolean);
  if (words.length < 2 || words.length > 6) {
    return false;
  }

  return containsIngredientKeyword(normalized) && isMostlyUppercase(line);
}

function isMostlyUppercase(line: string): boolean {
  const letters = Array.from(line).filter((character) => /\p{L}/u.test(character));
  if (!letters.length) {
    return false;
  }

  const uppercaseCount = letters.filter((character) => character === character.toUpperCase()).length;
  return uppercaseCount / letters.length >= 0.7;
}

function isGenericSocialTitle(line: string): boolean {
  const normalized = line
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();

  return normalized === "tiktok - make your day" ||
    normalized === "make your day" ||
    normalized === "tiktok" ||
    normalized.endsWith(" sur tiktok") ||
    normalized.endsWith(" on tiktok") ||
    normalized.startsWith("watch more trending videos") ||
    normalized.startsWith("regarde plus de videos");
}

function parseIngredientLine(line: string): { amount: string; unit: string; name: string; nutritionQuery: string } {
  const cleaned = cleanedListLine(line);
  const tokens = cleaned.split(" ").filter(Boolean);

  if (!tokens.length) {
    return { amount: "", unit: "", name: "", nutritionQuery: "" };
  }

  if (tokens.length === 1) {
    return { amount: "", unit: "", name: cleaned, nutritionQuery: cleaned };
  }

  const compactQuantity = splitCompactQuantityAndUnit(tokens[0]);
  if (compactQuantity) {
    const name = cleanedIngredientName(tokens.slice(1).join(" "));
    return {
      amount: compactQuantity.amount,
      unit: compactQuantity.unit,
      name,
      nutritionQuery: name
    };
  }

  const quantity = leadingQuantity(tokens);
  if (!quantity) {
    return { amount: "", unit: "", name: cleaned, nutritionQuery: cleaned };
  }

  const unit = leadingUnit(tokens, quantity.nextIndex);
  const nameStartIndex = unit ? unit.nextIndex : quantity.nextIndex;
  const name = cleanedIngredientName(tokens.slice(nameStartIndex).join(" "));

  return {
    amount: quantity.amount,
    unit: unit?.unit ?? "",
    name,
    nutritionQuery: name
  };
}

function preprocessRecipeNarrativeInput(input: string): string {
  return input
    .replace(/\s*---+\s*(instructions?|étapes?|etapes|préparation|preparation|method|méthode|methode)\b\s*/giu, "\nInstructions:\n")
    .replace(/\b(?:SERVE WITH|EXTRAS|EXTRA|DOUGH|COD MIXTURE|FLOUR MIXTURE|CRISPY COATING|COATING|MARINADE|SAUCE)\b/gu, (match) => `\n${match}\n`)
    .replace(/([a-z)\]])\s+(?=(?:\d+(?:[.,]\d+)?|\d+\/\d+)\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup|egg|eggs|packet|packets?|steak|steaks|tranche|tranches|pain|pains|bun|buns|piece|pieces|oignon|oignons|onion|onions|clove|cloves|gousse|gousses)\b)/giu, "$1\n")
    .replace(/\)\s+(?=(?:sesame seeds?|breadcrumbs?|tartar sauce|cheddar cheese|salt|pepper|sel|poivre|beurre|butter)\b)/giu, ")\n");
}

function expandIngredientCandidates(line: string): string[] {
  const cleaned = cleanedListLine(line);
  if (!cleaned || isIngredientSubsectionHeader(cleaned)) {
    return [];
  }

  const serveWithMatch = cleaned.match(/^serve with[:\s-]*(.+)$/i);
  if (serveWithMatch?.[1]) {
    return serveWithMatch[1]
      .split(/(?:,|\band\b|&)/i)
      .map((entry) => normalizeIngredientCandidate(entry))
      .filter(Boolean);
  }

  const segments = splitInlineIngredientClusters(cleaned);
  return segments
    .flatMap(splitLooseIngredientTail)
    .map((entry) => normalizeIngredientCandidate(entry))
    .filter(Boolean);
}

function splitInlineIngredientClusters(line: string): string[] {
  const positions = ingredientClusterPositions(line);
  if (positions.length <= 1) {
    return [line];
  }

  const result: string[] = [];
  for (let index = 0; index < positions.length; index += 1) {
    const start = positions[index]!;
    const end = positions[index + 1] ?? line.length;
    result.push(line.slice(start, end).trim());
  }

  return mergeBrokenIngredientFragments(result);
}

function ingredientClusterPositions(line: string): number[] {
  const positions: number[] = [];
  const pattern = /(?:^|\s)(\d+(?:[.,]\d+)?(?:\s+\d+\/\d+)?|\d+\/\d+)\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup|egg|eggs|packet|packets?|steak|steaks|tranche|tranches|pain|pains|bun|buns|piece|pieces|oignon|oignons|onion|onions|clove|cloves|gousse|gousses)\b/giu;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(line)) !== null) {
    const leadingSpaceOffset = match[0].startsWith(" ") ? 1 : 0;
    positions.push(match.index + leadingSpaceOffset);
  }

  return Array.from(new Set(positions));
}

function splitLooseIngredientTail(line: string): string[] {
  const match = line.match(/^(.+?\([^)]*\))\s+([a-zà-ÿ][a-zà-ÿ\s-]{2,})$/iu);
  if (!match) {
    return [line];
  }

  const tail = match[2].trim();
  if (looksLikeStep(tail) || /\b(?:instructions?|étapes?|etapes)\b/i.test(tail)) {
    return [line];
  }

  return [match[1].trim(), tail];
}

function normalizeIngredientCandidate(line: string): string {
  return line
    .replace(/^[-•*]\s*/u, "")
    .replace(/\p{Extended_Pictographic}/gu, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function mergeBrokenIngredientFragments(segments: string[]): string[] {
  const merged: string[] = [];

  for (const segment of segments) {
    const previous = merged[merged.length - 1];
    if (
      previous &&
      previous.includes("(") &&
      !previous.includes(")") &&
      /^\d+\s+(?:packet|packets?|tablespoon|tablespoons?|teaspoon|teaspoons?|tbsp|tsp)\)?$/i.test(segment)
    ) {
      merged[merged.length - 1] = `${previous} ${segment}`.trim();
      continue;
    }

    if (
      previous &&
      /\b(?:or|ou)$/i.test(previous) &&
      /^\d+\s+(?:packet|packets?|sachet|sachets?|tablespoon|tablespoons?|teaspoon|teaspoons?|tbsp|tsp)\)?$/i.test(segment)
    ) {
      merged[merged.length - 1] = `${previous} ${segment}`.trim();
      continue;
    }

    merged.push(segment);
  }

  return merged;
}

function isDuplicateTitleIngredient(line: string, title: string): boolean {
  const cleanedLine = cleanedTitle(line);
  const cleanedTitleValue = cleanedTitle(title);
  if (!cleanedLine || !cleanedTitleValue) {
    return false;
  }

  if (/^\d/.test(line.trim())) {
    return false;
  }

  return cleanedLine.localeCompare(cleanedTitleValue, undefined, { sensitivity: "accent" }) == 0;
}

function splitCompactQuantityAndUnit(token: string): { amount: string; unit: string } | null {
  const compactMatch = token.match(/^(\d+(?:[.,]\d+)?)([a-zA-Z]+)$/);
  if (!compactMatch) {
    return null;
  }

  const [, amount, rawUnit] = compactMatch;
  const normalizedUnit = normalizeUnit(rawUnit);
  if (!normalizedUnit || !knownIngredientUnits.has(normalizedUnit)) {
    return null;
  }

  return { amount, unit: rawUnit };
}

function leadingQuantity(tokens: string[]): { amount: string; nextIndex: number } | null {
  const first = tokens[0] ?? "";
  const second = tokens[1] ?? "";

  if (isSimpleQuantity(first)) {
    if (isFraction(second)) {
      return { amount: `${first} ${second}`, nextIndex: 2 };
    }
    return { amount: first, nextIndex: 1 };
  }

  if (isFraction(first)) {
    return { amount: first, nextIndex: 1 };
  }

  return null;
}

function leadingUnit(tokens: string[], startIndex: number): { unit: string; nextIndex: number } | null {
  const first = tokens[startIndex] ?? "";
  const second = tokens[startIndex + 1] ?? "";
  const third = tokens[startIndex + 2] ?? "";

  const threeTokenCandidate = normalizeUnit(`${first} ${second} ${third}`);
  if (threeTokenCandidate && knownIngredientUnits.has(threeTokenCandidate)) {
    return {
      unit: [first, second, third].join(" "),
      nextIndex: startIndex + 3
    };
  }

  const twoTokenCandidate = normalizeUnit(`${first} ${second}`);
  if (twoTokenCandidate && knownIngredientUnits.has(twoTokenCandidate)) {
    return {
      unit: [first, second].join(" "),
      nextIndex: startIndex + 2
    };
  }

  const oneTokenCandidate = normalizeUnit(first);
  if (oneTokenCandidate && knownIngredientUnits.has(oneTokenCandidate)) {
    return {
      unit: first,
      nextIndex: startIndex + 1
    };
  }

  return null;
}

function cleanedIngredientName(name: string): string {
  return name
    .replace(/^(?:d'|d’)/i, "")
    .replace(/^(?:de|du|des|a|à)\s+/i, "")
    .replace(/^(?:la|le|les|un|une)\s+/i, "")
    .trim();
}

function isSimpleQuantity(token: string): boolean {
  return /^\d+(?:[.,]\d+)?$/.test(token);
}

function isFraction(token: string): boolean {
  return /^\d+\/\d+$/.test(token);
}

function normalizeUnit(token: string): string {
  return token
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[().]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const knownIngredientUnits = new Set([
  "g",
  "kg",
  "mg",
  "ml",
  "cl",
  "dl",
  "l",
  "oz",
  "lb",
  "lbs",
  "cup",
  "cups",
  "tbsp",
  "tsp",
  "c a s",
  "c a c",
  "c a soupe",
  "c a cafe",
  "cas",
  "cac",
  "cuil",
  "cuill",
  "cuillere",
  "cuilleres",
  "cuilleree",
  "cuillerees",
  "cuillere a soupe",
  "cuilleres a soupe",
  "cuillere a cafe",
  "cuilleres a cafe",
  "tablespoon",
  "tablespoons",
  "teaspoon",
  "teaspoons",
  "verre",
  "verres",
  "tasse",
  "tasses",
  "pincee",
  "pincees",
  "piece",
  "pieces",
  "packet",
  "packets",
  "tranche",
  "tranches",
  "branche",
  "branches",
  "botte",
  "bottes",
  "sachet",
  "sachets",
  "boite",
  "boites"
]);

const prioritizedDishPatterns: Array<{
  regex: RegExp;
  title?: string;
  templateId: DishTemplateId;
  baseScore: number;
}> = [
  {
    regex: /\b(?:sandwich\s+naan|naan\s+sandwich)\b/i,
    title: "Sandwich Naan",
    templateId: "generic",
    baseScore: 0.78
  },
  {
    regex: /\b(?:truffle|truffe)\s+burger\b|\bburger\s+(?:a\s+la|au|aux|de|du|des)\s+truffe\b/i,
    title: "Burger a la truffe",
    templateId: "burger",
    baseScore: 0.8
  },
  {
    regex: /\bfilet\s*o\s*fish(?:\s*burger)?\b/i,
    title: "Filet O Fish Burger",
    templateId: "burger",
    baseScore: 0.74
  },
  {
    regex: /\bsmash\s*burger\b/i,
    title: "Smash Burger",
    templateId: "smash_burger",
    baseScore: 0.78
  },
  {
    regex: /\bcrispy\s*chicken\s*tacos?\b/i,
    title: "Crispy Chicken Tacos",
    templateId: "crispy_chicken_tacos",
    baseScore: 0.76
  },
  {
    regex: /\bchicken\s*curry\s*pasta\b/i,
    title: "Chicken Curry Pasta",
    templateId: "chicken_curry_pasta",
    baseScore: 0.76
  },
  {
    regex: /\btiramisu\b/i,
    title: "Tiramisu",
    templateId: "tiramisu",
    baseScore: 0.74
  },
  {
    regex: /\b(?:chicken|fish|beef|veggie|vegan|spicy|grilled|pulled)\s*burger\b/i,
    templateId: "burger",
    baseScore: 0.62
  },
  {
    regex: /\b(?:chicken|fish|beef|shrimp|crispy)\s*tacos?\b/i,
    templateId: "tacos",
    baseScore: 0.62
  },
  {
    regex: /\b(?:chicken|spicy|creamy|tomato)\s*pasta\b/i,
    templateId: "pasta",
    baseScore: 0.6
  },
  {
    regex: /\b(?:chicken|vegetable|veggie|thai)\s*curry\b/i,
    templateId: "curry",
    baseScore: 0.6
  }
];

const genericDishPhrasePatterns = [
  /\b(?:sandwich|wrap)\s+(?:naan|pita|bagel|focaccia|ciabatta|brioche)\b/i,
  /\b(?:naan|pita|bagel|focaccia|ciabatta|brioche)\s+(?:sandwich|wrap)\b/i,
  /\b(?:truffle|truffe|smash|crispy|spicy|creamy|chicken|poulet|fish|poisson|beef|boeuf|bœuf|veggie|vegan|mushroom|champignon|thai|bbq|salmon|saumon|garlic|ail|hot)\s+(?:burger|tacos?|pizza|pasta|pates?|pâtes?|salad|salade|wrap|sandwich|curry|ramen|risotto|falafel|shawarma|kebab)\b/i,
  /\b(?:burger|tacos?|pizza|pasta|pates?|pâtes?|salad|salade|wrap|sandwich|curry|ramen|risotto|falafel|shawarma|kebab)\s+(?:a\s+la|au|aux|de|du|des|with)\s+[a-z]+(?:\s+[a-z]+)?\b/i
];

const genericDishPattern = /\b(?:burger|tacos?|pasta|pizza|omelette|quiche|salad|salade|wrap|sandwich|toast|curry|brownies?|cookies?|cake|ramen|risotto|falafel|shawarma|kebab|bowl)\b/i;

const genericDishWords = new Set([
  "burger",
  "naan",
  "taco",
  "tacos",
  "pasta",
  "pizza",
  "omelette",
  "quiche",
  "salad",
  "salade",
  "wrap",
  "sandwich",
  "toast",
  "curry",
  "brownie",
  "cookies",
  "cookie",
  "cake",
  "ramen",
  "risotto",
  "falafel",
  "shawarma",
  "kebab",
  "bowl"
]);

const foodSignalPatterns = [
  /\bburger\b/i,
  /\bnaan\b/i,
  /\btacos?\b/i,
  /\bpasta\b/i,
  /\bpizza\b/i,
  /\btiramisu\b/i,
  /\bcurry\b/i,
  /\bsandwich\b/i,
  /\bwrap\b/i,
  /\b(?:salad|salade)\b/i,
  /\bchicken\b/i,
  /\bbeef\b/i,
  /\bfish\b/i,
  /\b(?:recipe|recette)\b/i,
  /\bingredients?\b/i
];

const likelyDishTitlePatterns = [
  /\bsandwich\s+naan\b/i,
  /\bnaan\s+sandwich\b/i,
  /\bburger\b/i,
  /\btacos?\b/i,
  /\bpizza\b/i,
  /\bpasta\b/i,
  /\bwrap\b/i,
  /\bsandwich\b/i,
  /\btoast\b/i,
  /\bcurry\b/i,
  /\brisotto\b/i,
  /\bramen\b/i,
  /\bfalafel\b/i,
  /\bshawarma\b/i,
  /\bkebab\b/i,
  /\bbowl\b/i
];

const ingredientCatalog: Array<{
  key: IngredientCatalogKey;
  name: string;
  nutritionQuery: string;
  amount?: string;
  unit?: string;
  aliases: string[];
}> = [
  {
    key: "ground_beef",
    name: "boeuf hache",
    nutritionQuery: "ground beef",
    amount: "360",
    unit: "g",
    aliases: ["ground beef", "boeuf hache", "beef patty", "steak hache", "steaks"]
  },
  {
    key: "white_fish",
    name: "cabillaud",
    nutritionQuery: "white fish fillet",
    amount: "320",
    unit: "g",
    aliases: ["white fish", "fish fillet", "cabillaud", "cod", "poisson blanc"]
  },
  {
    key: "chicken_breast",
    name: "blanc de poulet",
    nutritionQuery: "chicken breast",
    amount: "320",
    unit: "g",
    aliases: ["chicken breast", "blanc de poulet", "poulet", "chicken"]
  },
  {
    key: "chicken_thigh",
    name: "cuisses de poulet",
    nutritionQuery: "chicken thigh",
    amount: "450",
    unit: "g",
    aliases: ["chicken thigh", "chicken thighs", "haut de cuisse", "cuisse de poulet"]
  },
  {
    key: "chicken_tenders",
    name: "tenders de poulet",
    nutritionQuery: "chicken tenders",
    amount: "4",
    unit: "piece",
    aliases: ["chicken tenders", "hot tenders", "tenders", "tenders de poulet"]
  },
  {
    key: "hamburger_bun",
    name: "pains burger",
    nutritionQuery: "hamburger bun",
    amount: "2",
    unit: "piece",
    aliases: ["hamburger bun", "burger bun", "pain burger", "pains burger", "bun", "buns"]
  },
  {
    key: "bread",
    name: "pain",
    nutritionQuery: "bread",
    amount: "4",
    unit: "tranches",
    aliases: ["bread", "pain", "toast", "pain de mie", "ciabatta"]
  },
  {
    key: "flatbread",
    name: "flatbread",
    nutritionQuery: "flatbread",
    amount: "2",
    unit: "piece",
    aliases: ["flatbread", "naan", "pita", "galette", "wrap bread"]
  },
  {
    key: "cheddar",
    name: "cheddar",
    nutritionQuery: "cheddar cheese",
    amount: "2",
    unit: "tranches",
    aliases: ["cheddar", "cheddar cheese", "fromage cheddar"]
  },
  {
    key: "onion",
    name: "oignon",
    nutritionQuery: "onion",
    amount: "1",
    unit: "piece",
    aliases: ["onion", "onions", "oignon", "oignons"]
  },
  {
    key: "pickles",
    name: "cornichons",
    nutritionQuery: "pickle",
    amount: "6",
    unit: "pieces",
    aliases: ["pickle", "pickles", "cornichon", "cornichons"]
  },
  {
    key: "burger_sauce",
    name: "sauce burger",
    nutritionQuery: "thousand island dressing",
    amount: "2",
    unit: "c a soupe",
    aliases: ["burger sauce", "sauce burger", "burger dressing", "sauce speciale"]
  },
  {
    key: "oil",
    name: "huile",
    nutritionQuery: "vegetable oil",
    amount: "1",
    unit: "c a soupe",
    aliases: ["oil", "huile", "vegetable oil"]
  },
  {
    key: "olive_oil",
    name: "huile d'olive",
    nutritionQuery: "olive oil",
    amount: "1",
    unit: "c a soupe",
    aliases: ["olive oil", "huile d olive", "huile olive"]
  },
  {
    key: "salt",
    name: "sel",
    nutritionQuery: "salt",
    amount: "1",
    unit: "c a cafe",
    aliases: ["salt", "sel"]
  },
  {
    key: "pepper",
    name: "poivre",
    nutritionQuery: "black pepper",
    amount: "0.5",
    unit: "c a cafe",
    aliases: ["pepper", "poivre", "black pepper"]
  },
  {
    key: "lettuce",
    name: "salade",
    nutritionQuery: "lettuce",
    amount: "60",
    unit: "g",
    aliases: ["lettuce", "salade"]
  },
  {
    key: "tomato",
    name: "tomate",
    nutritionQuery: "tomato",
    amount: "1",
    unit: "piece",
    aliases: ["tomato", "tomatoes", "tomate", "tomates"]
  },
  {
    key: "cucumber",
    name: "concombre",
    nutritionQuery: "cucumber",
    amount: "0.5",
    unit: "piece",
    aliases: ["cucumber", "concombre"]
  },
  {
    key: "flour",
    name: "farine",
    nutritionQuery: "flour",
    amount: "80",
    unit: "g",
    aliases: ["flour", "farine"]
  },
  {
    key: "paprika",
    name: "paprika",
    nutritionQuery: "paprika",
    amount: "1",
    unit: "c a cafe",
    aliases: ["paprika"]
  },
  {
    key: "cumin",
    name: "cumin",
    nutritionQuery: "ground cumin",
    amount: "1",
    unit: "c a cafe",
    aliases: ["cumin"]
  },
  {
    key: "garlic",
    name: "ail",
    nutritionQuery: "garlic",
    amount: "2",
    unit: "gousses",
    aliases: ["garlic", "ail", "garlic clove", "gousse d ail"]
  },
  {
    key: "tortilla",
    name: "tortillas",
    nutritionQuery: "flour tortilla",
    amount: "6",
    unit: "piece",
    aliases: ["tortilla", "tortillas", "taco shell", "taco shells"]
  },
  {
    key: "cabbage",
    name: "chou",
    nutritionQuery: "cabbage",
    amount: "180",
    unit: "g",
    aliases: ["cabbage", "chou", "slaw", "coleslaw"]
  },
  {
    key: "lime",
    name: "citron vert",
    nutritionQuery: "lime",
    amount: "1",
    unit: "piece",
    aliases: ["lime", "citron vert"]
  },
  {
    key: "breadcrumbs",
    name: "chapelure",
    nutritionQuery: "breadcrumbs",
    amount: "150",
    unit: "g",
    aliases: ["chapelure", "breadcrumbs", "corn flakes", "cornflakes", "panure"]
  },
  {
    key: "sour_cream",
    name: "creme epaisse",
    nutritionQuery: "sour cream",
    amount: "100",
    unit: "g",
    aliases: ["sour cream", "creme fraiche", "creme epaisse"]
  },
  {
    key: "mayonnaise",
    name: "mayonnaise",
    nutritionQuery: "mayonnaise",
    amount: "1",
    unit: "c a soupe",
    aliases: ["mayonnaise", "mayo"]
  },
  {
    key: "pasta",
    name: "pates",
    nutritionQuery: "dry pasta",
    amount: "250",
    unit: "g",
    aliases: ["pasta", "pates", "pâtes"]
  },
  {
    key: "curry_powder",
    name: "curry",
    nutritionQuery: "curry powder",
    amount: "2",
    unit: "c a soupe",
    aliases: ["curry powder", "curry", "poudre de curry"]
  },
  {
    key: "cream",
    name: "creme",
    nutritionQuery: "heavy cream",
    amount: "200",
    unit: "ml",
    aliases: ["cream", "creme", "crème", "heavy cream"]
  },
  {
    key: "coconut_milk",
    name: "lait de coco",
    nutritionQuery: "coconut milk",
    amount: "200",
    unit: "ml",
    aliases: ["coconut milk", "lait de coco"]
  },
  {
    key: "parmesan",
    name: "parmesan",
    nutritionQuery: "parmesan cheese",
    amount: "40",
    unit: "g",
    aliases: ["parmesan", "parmigiano"]
  },
  {
    key: "mozzarella",
    name: "mozzarella",
    nutritionQuery: "mozzarella cheese",
    amount: "150",
    unit: "g",
    aliases: ["mozzarella"]
  },
  {
    key: "mascarpone",
    name: "mascarpone",
    nutritionQuery: "mascarpone cheese",
    amount: "250",
    unit: "g",
    aliases: ["mascarpone"]
  },
  {
    key: "egg",
    name: "oeufs",
    nutritionQuery: "egg",
    amount: "3",
    unit: "oeufs",
    aliases: ["egg", "eggs", "oeuf", "oeufs"]
  },
  {
    key: "sugar",
    name: "sucre",
    nutritionQuery: "sugar",
    amount: "80",
    unit: "g",
    aliases: ["sugar", "sucre"]
  },
  {
    key: "coffee",
    name: "cafe fort",
    nutritionQuery: "coffee",
    amount: "240",
    unit: "ml",
    aliases: ["coffee", "espresso", "cafe", "café"]
  },
  {
    key: "ladyfinger",
    name: "biscuits cuillere",
    nutritionQuery: "ladyfinger cookie",
    amount: "200",
    unit: "g",
    aliases: ["ladyfinger", "ladyfingers", "biscuits cuillere", "biscuit cuillere"]
  },
  {
    key: "cocoa_powder",
    name: "cacao",
    nutritionQuery: "cocoa powder",
    amount: "2",
    unit: "c a soupe",
    aliases: ["cocoa powder", "cacao", "cocoa"]
  },
  {
    key: "mushroom",
    name: "champignons",
    nutritionQuery: "mushroom",
    amount: "120",
    unit: "g",
    aliases: ["mushroom", "mushrooms", "champignon", "champignons"]
  },
  {
    key: "truffle_oil",
    name: "huile de truffe",
    nutritionQuery: "truffle oil",
    amount: "1",
    unit: "c a cafe",
    aliases: ["truffle oil", "huile de truffe", "truffle", "truffe"]
  },
  {
    key: "butter",
    name: "beurre",
    nutritionQuery: "butter",
    amount: "15",
    unit: "g",
    aliases: ["butter", "beurre"]
  },
  {
    key: "yogurt",
    name: "yaourt",
    nutritionQuery: "yogurt",
    amount: "100",
    unit: "g",
    aliases: ["yogurt", "yaourt", "greek yogurt", "yaourt grec"]
  },
  {
    key: "pizza_dough",
    name: "pate a pizza",
    nutritionQuery: "pizza dough",
    amount: "1",
    unit: "piece",
    aliases: ["pizza dough", "pate a pizza", "pizza base"]
  },
  {
    key: "tomato_sauce",
    name: "sauce tomate",
    nutritionQuery: "tomato sauce",
    amount: "120",
    unit: "g",
    aliases: ["tomato sauce", "sauce tomate", "pizza sauce"]
  },
  {
    key: "basil",
    name: "basilic",
    nutritionQuery: "basil",
    amount: "6",
    unit: "feuilles",
    aliases: ["basil", "basilic"]
  },
  {
    key: "chocolate",
    name: "chocolat noir",
    nutritionQuery: "dark chocolate",
    amount: "180",
    unit: "g",
    aliases: ["chocolate", "dark chocolate", "chocolat", "pepites de chocolat", "chocolate chips"]
  },
  {
    key: "baking_powder",
    name: "levure chimique",
    nutritionQuery: "baking powder",
    amount: "1",
    unit: "c a cafe",
    aliases: ["baking powder", "levure chimique"]
  },
  {
    key: "chickpeas",
    name: "pois chiches",
    nutritionQuery: "chickpeas",
    amount: "240",
    unit: "g",
    aliases: ["chickpeas", "pois chiches"]
  }
];

const ingredientCatalogByKey = new Map(
  ingredientCatalog.map((entry) => [entry.key, entry] as const)
);

function extractTime(input: string, pattern: RegExp): string {
  return input.match(pattern)?.[1] ?? "";
}

function emptyRecipe(): RecipeImportResult {
  return {
    title: "",
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
    confidence: "low",
    needsWebFallback: true,
    searchQuery: "",
    inferredFromPhoto: false
  };
}

function buildFallbackNotes(input: NormalizerInput): string {
  if (input.mode === "url") {
    return "Recette reconstituée avec le parseur de secours du backend.";
  }

  if (input.mode === "photo") {
    return "Analyse photo limitée sans IA distante.";
  }

  return "Recette reconstituée avec le parseur de secours du backend.";
}
