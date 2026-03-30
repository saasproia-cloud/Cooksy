import { env, providerStatus } from "../config/env.js";
import { normalizeRecipeImportFlags, type RecipeImportResult, type RecipeIngredientDraft } from "../types/recipe.js";
import { uniqueStrings } from "../utils/text.js";

const USDA_SEARCH_ENDPOINT = "https://api.nal.usda.gov/fdc/v1/foods/search";

type USDAFoodNutrient = {
  nutrientNumber?: string;
  nutrientName?: string;
  value?: number;
};

type USDAFoodSearchItem = {
  fdcId: number;
  description?: string;
  dataType?: string;
  brandOwner?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  foodNutrients?: USDAFoodNutrient[];
};

type USDAFoodSearchResponse = {
  foods?: USDAFoodSearchItem[];
};

type NutritionTotals = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type IngredientNutritionEstimate = NutritionTotals & {
  source: "usda" | "fallback";
};

type ParsedNutritionValues = {
  calories: number | null;
  protein: number | null;
  carbs: number | null;
  fat: number | null;
};

export type NutritionEnrichmentResult = {
  recipe: RecipeImportResult;
  usedUsda: boolean;
  nutritionCoverage: number;
  matchedIngredients: number;
};

const searchCache = new Map<string, Promise<USDAFoodSearchItem[]>>();

export async function enrichRecipeNutrition(
  recipe: RecipeImportResult,
  options?: {
    apiKey?: string;
    fetchImpl?: typeof fetch;
    enabled?: boolean;
  }
): Promise<NutritionEnrichmentResult> {
  const apiKey = options?.apiKey ?? env.USDA_API_KEY;
  const enabled = options?.enabled ?? providerStatus.usda;
  const fetchImpl = options?.fetchImpl ?? fetch;
  const canUseUsda = Boolean(enabled && apiKey);

  if (recipe.ingredientDrafts.length < 1) {
    return {
      recipe,
      usedUsda: false,
      nutritionCoverage: 0,
      matchedIngredients: 0
    };
  }

  let matchedIngredients = 0;
  let matchedUsdaIngredients = 0;
  const totals: NutritionTotals = {
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0
  };

  const consideredIngredients = recipe.ingredientDrafts.filter((ingredient) => !isMinorIngredient(ingredient));
  const nutritionResults = await Promise.all(
    consideredIngredients.map(async (ingredient) => estimateIngredientNutrition(ingredient, {
      apiKey,
      fetchImpl,
      canUseUsda
    }))
  );

  for (const nutrition of nutritionResults) {
    if (!nutrition) {
      continue;
    }

    matchedIngredients += 1;
    if (nutrition.source === "usda") {
      matchedUsdaIngredients += 1;
    }
    totals.calories += nutrition.calories;
    totals.protein += nutrition.protein;
    totals.carbs += nutrition.carbs;
    totals.fat += nutrition.fat;
  }

  const nutritionCoverage = consideredIngredients.length > 0
    ? matchedIngredients / consideredIngredients.length
    : 0;
  const existingNutrition = parseExistingNutrition(recipe);
  const hasExistingNutrition = Object.values(existingNutrition).some((value) => value !== null);

  if (matchedIngredients === 0 || totals.calories <= 0) {
    return {
      recipe: hasExistingNutrition
        ? {
          ...recipe,
          flags: hasExistingNutrition
            ? normalizeRecipeImportFlags(recipe.flags)
            : {
              ...normalizeRecipeImportFlags(recipe.flags),
              generatedNutrition: true
            }
        }
        : recipe,
      usedUsda: matchedUsdaIngredients > 0,
      nutritionCoverage,
      matchedIngredients
    };
  }

  const perServingDivisor = parseServings(recipe.servingsText) ||
    inferRecipeServings(recipe) ||
    1;
  const perServing = {
    calories: totals.calories / perServingDivisor,
    protein: totals.protein / perServingDivisor,
    carbs: totals.carbs / perServingDivisor,
    fat: totals.fat / perServingDivisor
  };

  const shouldApplyUsda = nutritionCoverage >= 0.35 ||
    !hasExistingNutrition ||
    nutritionLooksSuspicious(existingNutrition, perServing, {
      matchedIngredients,
      consideredIngredients: consideredIngredients.length
    });
  if (!shouldApplyUsda) {
    return {
      recipe,
      usedUsda: matchedUsdaIngredients > 0,
      nutritionCoverage,
      matchedIngredients
    };
  }

  return {
    recipe: {
      ...recipe,
      caloriesText: formatCalories(perServing.calories),
      proteinText: formatMacro(perServing.protein),
      carbsText: formatMacro(perServing.carbs),
      fatText: formatMacro(perServing.fat),
      flags: {
        ...normalizeRecipeImportFlags(recipe.flags),
        generatedNutrition: true
      }
    },
    usedUsda: matchedUsdaIngredients > 0,
    nutritionCoverage,
    matchedIngredients
  };
}

async function estimateIngredientNutrition(
  ingredient: RecipeIngredientDraft,
  options: {
    apiKey?: string;
    fetchImpl: typeof fetch;
    canUseUsda: boolean;
  }
): Promise<IngredientNutritionEstimate | null> {
  const grams = estimateIngredientGrams(ingredient);
  if (!grams || grams <= 0) {
    return null;
  }

  if (!options.canUseUsda) {
    return fallbackIngredientNutrition(ingredient, grams);
  }

  const queries = buildIngredientQueries(ingredient);
  for (const query of queries) {
    const foods = await searchFoods(query, options);
    const match = chooseBestFoodMatch(query, foods);
    if (!match) {
      continue;
    }

    const basisGrams = nutrientBasisGrams(match, ingredient);
    if (!basisGrams || basisGrams <= 0) {
      continue;
    }

    const calories = nutrientValue(match.foodNutrients, "208");
    const protein = nutrientValue(match.foodNutrients, "203");
    const carbs = nutrientValue(match.foodNutrients, "205");
    const fat = nutrientValue(match.foodNutrients, "204");

    return {
      source: "usda",
      calories: (calories * grams) / basisGrams,
      protein: (protein * grams) / basisGrams,
      carbs: (carbs * grams) / basisGrams,
      fat: (fat * grams) / basisGrams
    };
  }

  return fallbackIngredientNutrition(ingredient, grams);
}

function fallbackIngredientNutrition(
  ingredient: RecipeIngredientDraft,
  grams: number
): IngredientNutritionEstimate | null {
  const normalized = ingredientLookupText(ingredient);
  const profile = fallbackNutritionProfiles.find((entry) =>
    entry.keywords.some((keyword) => normalized.includes(keyword))
  );
  if (!profile) {
    return null;
  }

  return {
    source: "fallback",
    calories: (profile.calories * grams) / 100,
    protein: (profile.protein * grams) / 100,
    carbs: (profile.carbs * grams) / 100,
    fat: (profile.fat * grams) / 100
  };
}

async function searchFoods(
  query: string,
  options: {
    apiKey?: string;
    fetchImpl: typeof fetch;
  }
): Promise<USDAFoodSearchItem[]> {
  const apiKey = options.apiKey;
  if (!apiKey) {
    return [];
  }

  const cacheKey = query.toLowerCase();
  const existing = searchCache.get(cacheKey);
  if (existing) {
    return existing;
  }

  const pending = (async () => {
    const url = new URL(USDA_SEARCH_ENDPOINT);
    url.searchParams.set("api_key", apiKey);

    const response = await options.fetchImpl(url, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        query,
        pageSize: 8,
        dataType: ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]
      }),
      signal: AbortSignal.timeout(15_000)
    });

    if (!response.ok) {
      return [];
    }

    const json = await response.json() as USDAFoodSearchResponse;
    return json.foods ?? [];
  })().catch(() => []);

  searchCache.set(cacheKey, pending);
  return pending;
}

function chooseBestFoodMatch(query: string, foods: USDAFoodSearchItem[]): USDAFoodSearchItem | null {
  const normalizedQuery = normalizeFoodText(query);
  const queryTokens = tokenSet(normalizedQuery);

  const scored = foods
    .map((food) => ({
      food,
      score: foodMatchScore(food, normalizedQuery, queryTokens)
    }))
    .filter((entry) => entry.score > 0)
    .sort((left, right) => right.score - left.score);

  return scored[0]?.food ?? null;
}

function foodMatchScore(
  food: USDAFoodSearchItem,
  normalizedQuery: string,
  queryTokens: Set<string>
): number {
  const description = normalizeFoodText(food.description ?? "");
  if (!description) {
    return 0;
  }

  const descriptionTokens = tokenSet(description);
  let score = dataTypeScore(food.dataType);

  if (description === normalizedQuery) {
    score += 50;
  }

  if (description.includes(normalizedQuery)) {
    score += 24;
  }

  let overlap = 0;
  for (const token of queryTokens) {
    if (descriptionTokens.has(token)) {
      overlap += 1;
    }
  }

  score += overlap * 10;
  if (overlap === queryTokens.size && queryTokens.size > 0) {
    score += 18;
  }

  if (food.brandOwner) {
    score -= 4;
  }

  if (description.includes("raw") || description.includes("fresh")) {
    score += 2;
  }

  return overlap > 0 ? score : 0;
}

function dataTypeScore(dataType?: string): number {
  switch ((dataType ?? "").toLowerCase()) {
    case "foundation":
      return 40;
    case "survey (fndds)":
      return 34;
    case "sr legacy":
      return 32;
    case "branded":
      return 18;
    default:
      return 10;
  }
}

function nutrientBasisGrams(food: USDAFoodSearchItem, ingredient: RecipeIngredientDraft): number | null {
  if ((food.dataType ?? "").toLowerCase() !== "branded") {
    return 100;
  }

  const servingSize = Number(food.servingSize ?? 0);
  if (!Number.isFinite(servingSize) || servingSize <= 0) {
    return null;
  }

  const normalizedUnit = normalizeUnit(food.servingSizeUnit ?? "");
  if (normalizedUnit === "g") {
    return servingSize;
  }

  if (normalizedUnit === "ml") {
    return servingSize * ingredientDensity(ingredient);
  }

  return null;
}

function nutrientValue(foodNutrients: USDAFoodNutrient[] | undefined, nutrientNumber: string): number {
  const direct = foodNutrients?.find((entry) => entry.nutrientNumber === nutrientNumber)?.value;
  return Number.isFinite(direct) ? Number(direct) : 0;
}

function buildIngredientQueries(ingredient: RecipeIngredientDraft): string[] {
  const baseCandidates = uniqueStrings([
    translateIngredientName(ingredient.nutritionQuery),
    translateIngredientName(ingredient.name),
    ingredient.nutritionQuery,
    ingredient.name,
    translateIngredientName(`${ingredient.name} ${ingredient.nutritionQuery}`)
  ]);

  return uniqueStrings(
    baseCandidates.flatMap((candidate) => {
      const normalized = normalizeIngredientQuery(candidate);
      if (!normalized) {
        return [];
      }

      return [
        normalized,
        singularizeQuery(normalized)
      ];
    })
  ).slice(0, 4);
}

function normalizeIngredientQuery(value: string): string {
  return normalizeFoodText(
    value
      .replace(/\([^)]*\)/g, " ")
      .replace(/\b(?:finement|minced|diced|chopped|sliced|crushed|peeled|fresh|optional)\b/gi, " ")
      .replace(/\b(?:hache|haché|hachee|emine|émincé|emince|coupe|coupé|pelé|pele|frais|fraiche|facultatif)\b/gi, " ")
  );
}

function singularizeQuery(value: string): string {
  return value
    .replace(/\beggs\b/g, "egg")
    .replace(/\bonions\b/g, "onion")
    .replace(/\btomatoes\b/g, "tomato")
    .replace(/\bpotatoes\b/g, "potato")
    .replace(/\bpickles\b/g, "pickle")
    .replace(/\bbuns\b/g, "bun")
    .replace(/\bcloves\b/g, "clove")
    .replace(/\bbreasts\b/g, "breast")
    .replace(/\bcarrots\b/g, "carrot")
    .replace(/\bshallots\b/g, "shallot");
}

function translateIngredientName(value: string): string {
  let translated = normalizeFoodText(value);

  for (const [pattern, replacement] of translationPatterns) {
    translated = translated.replace(pattern, replacement);
  }

  return translated;
}

function estimateIngredientGrams(ingredient: RecipeIngredientDraft): number | null {
  const normalizedUnit = normalizeUnit(ingredient.unit);
  const explicitQuantity = parseQuantity(ingredient.amount);
  const implicitVolumeMl = explicitQuantity === null
    ? inferImplicitVolumeMilliliters(ingredient, normalizedUnit)
    : null;
  const quantity = explicitQuantity ?? inferImplicitQuantity(ingredient, normalizedUnit);
  const density = ingredientDensity(ingredient);

  if (quantity === null && implicitVolumeMl !== null) {
    return implicitVolumeMl * density;
  }

  if (quantity === null) {
    return null;
  }

  switch (normalizedUnit) {
    case "g":
      return quantity;
    case "kg":
      return quantity * 1000;
    case "mg":
      return quantity / 1000;
    case "oz":
      return quantity * 28.3495;
    case "lb":
      return quantity * 453.592;
    case "ml":
      return quantity * density;
    case "cl":
      return quantity * 10 * density;
    case "dl":
      return quantity * 100 * density;
    case "l":
      return quantity * 1000 * density;
    case "tsp":
      return quantity * 5 * density;
    case "tbsp":
      return quantity * 15 * density;
    case "cup":
      return quantity * 240 * density;
    case "glass":
      return quantity * 200 * density;
    case "pinch":
      return quantity * 0.36;
    case "piece":
    case "slice":
    case "clove":
    case "egg":
    case "can":
    case "jar":
    case "packet":
    case "bunch":
    case "":
      return quantity * inferItemWeightGrams(ingredient);
    default:
      return quantity * inferItemWeightGrams(ingredient);
  }
}

function parseQuantity(value: string): number | null {
  const cleaned = value.trim().toLowerCase();
  if (!cleaned) {
    return null;
  }

  const normalized = cleaned
    .replace(",", ".")
    .replace(/½/g, "1/2")
    .replace(/¼/g, "1/4")
    .replace(/¾/g, "3/4")
    .replace(/⅓/g, "1/3")
    .replace(/⅔/g, "2/3")
    .replace(/⅛/g, "1/8")
    .replace(/\s+/g, " ")
    .trim();

  const rangeMatch = normalized.match(/^(\d+(?:\.\d+)?)\s*(?:-|a|à|to)\s*(\d+(?:\.\d+)?)/);
  if (rangeMatch) {
    const start = Number(rangeMatch[1]);
    const end = Number(rangeMatch[2]);
    return Number.isFinite(start) && Number.isFinite(end)
      ? (start + end) / 2
      : null;
  }

  if (/^(a|an|one|un|une)$/.test(normalized)) {
    return 1;
  }

  if (/^(two|deux)$/.test(normalized)) {
    return 2;
  }

  if (/^(three|trois)$/.test(normalized)) {
    return 3;
  }

  if (/^(four|quatre)$/.test(normalized)) {
    return 4;
  }

  if (/^(five|cinq)$/.test(normalized)) {
    return 5;
  }

  if (/^(half|demi|moitie|moitie d|moitie de)$/.test(normalized)) {
    return 0.5;
  }

  if (/^\d+(?:\.\d+)?$/.test(normalized)) {
    return Number(normalized);
  }

  const multiplierMatch = normalized.match(/^x\s*(\d+(?:\.\d+)?)$|^(\d+(?:\.\d+)?)\s*x$/);
  if (multiplierMatch) {
    const parsed = Number(multiplierMatch[1] ?? multiplierMatch[2]);
    return Number.isFinite(parsed) ? parsed : null;
  }

  if (/^\d+\/\d+$/.test(normalized)) {
    return fractionToNumber(normalized);
  }

  const parts = normalized.split(" ").filter(Boolean);
  if (parts.length === 2 && /^\d+(?:\.\d+)?$/.test(parts[0]) && /^\d+\/\d+$/.test(parts[1])) {
    return Number(parts[0]) + fractionToNumber(parts[1]);
  }

  return null;
}

function fractionToNumber(value: string): number {
  const [numerator, denominator] = value.split("/").map(Number);
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) {
    return 0;
  }

  return numerator / denominator;
}

function inferItemWeightGrams(ingredient: RecipeIngredientDraft): number {
  const normalized = ingredientLookupText(ingredient);

  for (const profile of itemWeightProfiles) {
    if (profile.keywords.some((keyword) => normalized.includes(keyword))) {
      return profile.grams;
    }
  }

  return 100;
}

function inferImplicitQuantity(
  ingredient: RecipeIngredientDraft,
  normalizedUnit: string
): number | null {
  if (["piece", "slice", "clove", "egg", "can", "jar", "packet", "bunch"].includes(normalizedUnit)) {
    return 1;
  }

  if (normalizedUnit) {
    return null;
  }

  const normalized = ingredientLookupText(ingredient);
  return implicitPieceKeywords.some((keyword) => normalized.includes(keyword)) ? 1 : null;
}

function inferImplicitVolumeMilliliters(
  ingredient: RecipeIngredientDraft,
  normalizedUnit: string
): number | null {
  if (normalizedUnit) {
    return null;
  }

  const normalized = ingredientLookupText(ingredient);
  for (const profile of implicitVolumeProfiles) {
    if (profile.keywords.some((keyword) => normalized.includes(keyword))) {
      return profile.ml;
    }
  }

  return null;
}

function ingredientDensity(ingredient: RecipeIngredientDraft): number {
  const normalized = ingredientLookupText(ingredient);

  for (const profile of densityProfiles) {
    if (profile.keywords.some((keyword) => normalized.includes(keyword))) {
      return profile.gramsPerMl;
    }
  }

  return 1;
}

function normalizeUnit(value: string): string {
  const normalized = normalizeFoodText(value);

  if (["g", "gr", "gram", "gramme", "grammes"].includes(normalized)) {
    return "g";
  }
  if (["kg", "kilogram", "kilogramme", "kilogrammes"].includes(normalized)) {
    return "kg";
  }
  if (["mg"].includes(normalized)) {
    return "mg";
  }
  if (["ml"].includes(normalized)) {
    return "ml";
  }
  if (["cl"].includes(normalized)) {
    return "cl";
  }
  if (["dl"].includes(normalized)) {
    return "dl";
  }
  if (["l", "litre", "liter"].includes(normalized)) {
    return "l";
  }
  if (["c a cafe", "cuillere a cafe", "cuillere cafe", "teaspoon", "tsp", "cac"].includes(normalized)) {
    return "tsp";
  }
  if (["c a soupe", "cuillere a soupe", "tablespoon", "tbsp", "cas"].includes(normalized)) {
    return "tbsp";
  }
  if (["cup", "cups", "tasse", "tasses"].includes(normalized)) {
    return "cup";
  }
  if (["verre", "verres", "glass"].includes(normalized)) {
    return "glass";
  }
  if (["pincee", "pinch"].includes(normalized)) {
    return "pinch";
  }
  if (["piece", "pieces", "piece(s)", "unit", "unite"].includes(normalized)) {
    return "piece";
  }
  if (["tranche", "tranches", "slice", "slices"].includes(normalized)) {
    return "slice";
  }
  if (["gousse", "gousses", "clove", "cloves"].includes(normalized)) {
    return "clove";
  }
  if (["oeuf", "oeufs", "egg", "eggs"].includes(normalized)) {
    return "egg";
  }
  if (["boite", "can", "canned"].includes(normalized)) {
    return "can";
  }
  if (["bocal", "jar"].includes(normalized)) {
    return "jar";
  }
  if (["sachet", "packet", "pack"].includes(normalized)) {
    return "packet";
  }
  if (["botte", "bunch"].includes(normalized)) {
    return "bunch";
  }
  if (["oz", "ounce", "ounces"].includes(normalized)) {
    return "oz";
  }
  if (["lb", "lbs", "pound", "pounds"].includes(normalized)) {
    return "lb";
  }

  return normalized;
}

function ingredientLookupText(ingredient: RecipeIngredientDraft): string {
  return normalizeFoodText(
    `${ingredient.name} ${ingredient.nutritionQuery} ${translateIngredientName(ingredient.name)} ${translateIngredientName(ingredient.nutritionQuery)}`
  );
}

function parseServings(value: string): number | null {
  const match = value.match(/(\d+(?:[.,]\d+)?)/);
  if (!match) {
    return null;
  }

  const parsed = Number(match[1].replace(",", "."));
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
}

function inferRecipeServings(recipe: RecipeImportResult): number | null {
  const normalizedTitle = normalizeFoodText(recipe.title);
  const sandwichLikeTitle = /\b(burger|sandwich|wrap|taco|toast|hot dog)\b/.test(normalizedTitle);
  if (!sandwichLikeTitle) {
    return null;
  }

  const servingAnchorCount = recipe.ingredientDrafts.reduce<number | null>((bestCount, ingredient) => {
    const normalizedIngredient = normalizeFoodText(
      `${ingredient.name} ${ingredient.nutritionQuery} ${translateIngredientName(ingredient.name)} ${translateIngredientName(ingredient.nutritionQuery)}`
    );
    const isServingAnchor = /\b(hamburger bun|bun|bread|slice bread|wrap|tortilla|taco shell|hot dog bun)\b/.test(normalizedIngredient);
    if (!isServingAnchor) {
      return bestCount;
    }

    const quantity = parseQuantity(ingredient.amount) ?? inferImplicitQuantity(ingredient, normalizeUnit(ingredient.unit));
    if (!quantity || quantity < 1 || quantity > 8) {
      return bestCount;
    }

    const rounded = Math.round(quantity);
    if (bestCount === null) {
      return rounded;
    }

    return Math.max(bestCount, rounded);
  }, null);

  return servingAnchorCount;
}

function formatCalories(value: number): string {
  return `${Math.max(0, Math.round(value))} kcal`;
}

function formatMacro(value: number): string {
  const rounded = Math.max(0, Math.round(value * 10) / 10);
  return `${new Intl.NumberFormat("fr-FR", {
    maximumFractionDigits: 1,
    minimumFractionDigits: 0
  }).format(rounded)} g`;
}

function parseExistingNutrition(recipe: RecipeImportResult): ParsedNutritionValues {
  return {
    calories: parseNutritionNumber(recipe.caloriesText),
    protein: parseNutritionNumber(recipe.proteinText),
    carbs: parseNutritionNumber(recipe.carbsText),
    fat: parseNutritionNumber(recipe.fatText)
  };
}

function parseNutritionNumber(value: string): number | null {
  const match = value.replace(",", ".").match(/(\d+(?:\.\d+)?)/);
  if (!match) {
    return null;
  }

  const parsed = Number(match[1]);
  return Number.isFinite(parsed) ? parsed : null;
}

function nutritionLooksSuspicious(
  existingNutrition: ParsedNutritionValues,
  usdaPerServing: NutritionTotals,
  context: {
    matchedIngredients: number;
    consideredIngredients: number;
  }
): boolean {
  if (context.matchedIngredients < 2 || usdaPerServing.calories <= 0) {
    return false;
  }

  const coverage = context.consideredIngredients > 0
    ? context.matchedIngredients / context.consideredIngredients
    : 0;
  if (coverage >= 0.35) {
    return true;
  }

  if (caloriesConflictWithMacros(existingNutrition) || impossibleMacroDensity(existingNutrition)) {
    return true;
  }

  if (numericMismatch(existingNutrition.protein, usdaPerServing.protein, 12)) {
    return true;
  }

  if (numericMismatch(existingNutrition.calories, usdaPerServing.calories, 180)) {
    return true;
  }

  if (numericMismatch(existingNutrition.fat, usdaPerServing.fat, 8)) {
    return true;
  }

  return numericMismatch(existingNutrition.carbs, usdaPerServing.carbs, 20);
}

function caloriesConflictWithMacros(values: ParsedNutritionValues): boolean {
  if (values.calories === null || values.calories < 80) {
    return false;
  }

  const macroCalories = impliedMacroCalories(values);
  if (macroCalories === null || macroCalories < 60) {
    return false;
  }

  const delta = Math.abs(values.calories - macroCalories);
  const tolerance = Math.max(45, values.calories * 0.22, macroCalories * 0.22);
  return delta > tolerance;
}

function impossibleMacroDensity(values: ParsedNutritionValues): boolean {
  if (values.calories === null || values.calories <= 0) {
    return false;
  }

  const calorieBudget = values.calories * 1.15 + 30;
  if (values.protein !== null && values.protein >= 12 && values.protein * 4 > calorieBudget) {
    return true;
  }

  if (values.carbs !== null && values.carbs >= 16 && values.carbs * 4 > calorieBudget) {
    return true;
  }

  return values.fat !== null &&
    values.fat >= 8 &&
    values.fat * 9 > calorieBudget;
}

function impliedMacroCalories(
  values: Pick<ParsedNutritionValues, "protein" | "carbs" | "fat">
): number | null {
  if (values.protein === null || values.carbs === null || values.fat === null) {
    return null;
  }

  return Math.max(values.protein, 0) * 4 +
    Math.max(values.carbs, 0) * 4 +
    Math.max(values.fat, 0) * 9;
}

function numericMismatch(
  existingValue: number | null,
  usdaValue: number,
  minimumMeaningfulValue: number
): boolean {
  if (usdaValue < minimumMeaningfulValue) {
    return false;
  }

  if (existingValue === null) {
    return true;
  }

  if (existingValue <= 0 && usdaValue > minimumMeaningfulValue) {
    return true;
  }

  const lowerBound = usdaValue * 0.6;
  const upperBound = usdaValue * 1.8;
  return existingValue < lowerBound || existingValue > upperBound;
}

function isMinorIngredient(ingredient: RecipeIngredientDraft): boolean {
  const normalized = normalizeFoodText(
    `${ingredient.name} ${ingredient.nutritionQuery} ${translateIngredientName(ingredient.name)} ${translateIngredientName(ingredient.nutritionQuery)}`
  );
  return minorIngredientKeywords.some((keyword) => normalized.includes(keyword));
}

function normalizeFoodText(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s/]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokenSet(value: string): Set<string> {
  return new Set(
    value
      .split(" ")
      .filter((token) => token.length > 1 && !stopWords.has(token))
  );
}

const stopWords = new Set([
  "de",
  "des",
  "du",
  "d",
  "the",
  "a",
  "an",
  "and",
  "with"
]);

const translationPatterns: Array<[RegExp, string]> = [
  [/\bhuile d olive\b/g, "olive oil"],
  [/\bhuile vegetale\b/g, "vegetable oil"],
  [/\bhuile\b/g, "oil"],
  [/\bbeurre\b/g, "butter"],
  [/\bfarine\b/g, "flour"],
  [/\bsucre glace\b/g, "powdered sugar"],
  [/\bcassonade\b/g, "brown sugar"],
  [/\bsucre\b/g, "sugar"],
  [/\bsel\b/g, "salt"],
  [/\bpoivre noir\b/g, "black pepper"],
  [/\bpoivre\b/g, "pepper"],
  [/\boeufs?\b/g, "egg"],
  [/\bblanc de poulet\b/g, "chicken breast"],
  [/\bpoulet\b/g, "chicken"],
  [/\bboeuf hache\b/g, "ground beef"],
  [/\bboeuf\b/g, "beef"],
  [/\bporc\b/g, "pork"],
  [/\bsaumon\b/g, "salmon"],
  [/\bthon\b/g, "tuna"],
  [/\boignons?\b/g, "onion"],
  [/\bechalotes?\b/g, "shallot"],
  [/\bgousses? d ail\b/g, "garlic clove"],
  [/\bail\b/g, "garlic"],
  [/\btomates?\b/g, "tomato"],
  [/\bcarottes?\b/g, "carrot"],
  [/\bpommes? de terre\b/g, "potato"],
  [/\bcourgettes?\b/g, "zucchini"],
  [/\baubergines?\b/g, "eggplant"],
  [/\bpoivrons?\b/g, "bell pepper"],
  [/\bchampignons?\b/g, "mushroom"],
  [/\bepinards?\b/g, "spinach"],
  [/\blait\b/g, "milk"],
  [/\bcreme fraiche\b/g, "cream"],
  [/\bcreme\b/g, "cream"],
  [/\byaourt\b/g, "yogurt"],
  [/\bfromage parmesan\b/g, "parmesan cheese"],
  [/\bparmesan\b/g, "parmesan cheese"],
  [/\bmozzarella\b/g, "mozzarella cheese"],
  [/\bcheddar\b/g, "cheddar cheese"],
  [/\bemmental\b/g, "emmental cheese"],
  [/\bgruyere\b/g, "gruyere cheese"],
  [/\bfromage\b/g, "cheese"],
  [/\bcornichons?\b/g, "pickle"],
  [/\bmayonnaise\b/g, "mayonnaise"],
  [/\bketchup\b/g, "ketchup"],
  [/\bmoutarde\b/g, "mustard"],
  [/\bsweet relish\b/g, "pickle relish"],
  [/\brelish\b/g, "pickle relish"],
  [/\bcoleslaw\b/g, "coleslaw"],
  [/\bpain burger\b/g, "hamburger bun"],
  [/\bbuns?\b/g, "hamburger bun"],
  [/\bhot tenders?\b/g, "chicken tenders"],
  [/\btenders?\b/g, "chicken tenders"],
  [/\bsteaks? de poulet\b/g, "chicken patty"],
  [/\bsteaks? hach(?:e|ee|es|és)?\b/g, "beef patty"],
  [/\bpain\b/g, "bread"],
  [/\briz\b/g, "rice"],
  [/\bpates?\b/g, "pasta"],
  [/\bavoine\b/g, "oats"],
  [/\bflocons d avoine\b/g, "oats"],
  [/\bmiel\b/g, "honey"],
  [/\bcitron\b/g, "lemon"],
  [/\bcoriandre\b/g, "cilantro"],
  [/\bpersil\b/g, "parsley"],
  [/\bbasilic\b/g, "basil"]
];

const fallbackNutritionProfiles: Array<NutritionTotals & { keywords: string[] }> = [
  { keywords: ["olive oil", "truffle oil", "vegetable oil", "oil"], calories: 884, protein: 0, carbs: 0, fat: 100 },
  { keywords: ["butter"], calories: 717, protein: 0.9, carbs: 0.1, fat: 81 },
  { keywords: ["flour"], calories: 364, protein: 10, carbs: 76, fat: 1 },
  { keywords: ["sugar"], calories: 387, protein: 0, carbs: 100, fat: 0 },
  { keywords: ["dark chocolate", "chocolate"], calories: 540, protein: 4.9, carbs: 61, fat: 31 },
  { keywords: ["cocoa powder"], calories: 228, protein: 20, carbs: 58, fat: 14 },
  { keywords: ["egg"], calories: 143, protein: 12.6, carbs: 0.7, fat: 9.5 },
  { keywords: ["ground beef", "beef patty"], calories: 250, protein: 26, carbs: 0, fat: 17 },
  { keywords: ["chicken thigh"], calories: 209, protein: 26, carbs: 0, fat: 10.9 },
  { keywords: ["chicken breast", "chicken patty"], calories: 165, protein: 31, carbs: 0, fat: 3.6 },
  { keywords: ["chicken tenders"], calories: 220, protein: 14, carbs: 16, fat: 10 },
  { keywords: ["white fish", "fish fillet", "cod"], calories: 96, protein: 20, carbs: 0, fat: 2 },
  { keywords: ["hamburger bun", "pizza dough", "flatbread", "flour tortilla", "bread"], calories: 275, protein: 9, carbs: 52, fat: 4.5 },
  { keywords: ["dry pasta", "pasta"], calories: 371, protein: 13, carbs: 75, fat: 1.5 },
  { keywords: ["rice"], calories: 365, protein: 7, carbs: 80, fat: 0.7 },
  { keywords: ["cheddar cheese"], calories: 404, protein: 25, carbs: 1.3, fat: 33 },
  { keywords: ["mozzarella cheese"], calories: 280, protein: 28, carbs: 3, fat: 17 },
  { keywords: ["parmesan cheese"], calories: 431, protein: 38, carbs: 4, fat: 29 },
  { keywords: ["mascarpone cheese"], calories: 429, protein: 4, carbs: 4, fat: 44 },
  { keywords: ["mayonnaise"], calories: 680, protein: 1, carbs: 1, fat: 75 },
  { keywords: ["thousand island dressing", "burger sauce"], calories: 430, protein: 1, carbs: 18, fat: 39 },
  { keywords: ["sour cream"], calories: 193, protein: 2.4, carbs: 4.6, fat: 19 },
  { keywords: ["yogurt"], calories: 61, protein: 3.5, carbs: 4.7, fat: 3.3 },
  { keywords: ["pickle relish", "coleslaw"], calories: 140, protein: 1.2, carbs: 13, fat: 9 },
  { keywords: ["pickle"], calories: 18, protein: 0.5, carbs: 4, fat: 0.2 },
  { keywords: ["lettuce"], calories: 15, protein: 1.4, carbs: 2.9, fat: 0.2 },
  { keywords: ["cabbage"], calories: 25, protein: 1.3, carbs: 6, fat: 0.1 },
  { keywords: ["tomato sauce"], calories: 29, protein: 1.4, carbs: 5.6, fat: 0.2 },
  { keywords: ["tomato"], calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2 },
  { keywords: ["cucumber"], calories: 15, protein: 0.7, carbs: 3.6, fat: 0.1 },
  { keywords: ["onion"], calories: 40, protein: 1.1, carbs: 9.3, fat: 0.1 },
  { keywords: ["garlic"], calories: 149, protein: 6.4, carbs: 33, fat: 0.5 },
  { keywords: ["mushroom"], calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3 },
  { keywords: ["basil", "parsley", "cilantro"], calories: 30, protein: 3, carbs: 4, fat: 0.8 },
  { keywords: ["lime", "lemon"], calories: 29, protein: 1.1, carbs: 9.3, fat: 0.3 },
  { keywords: ["breadcrumbs"], calories: 395, protein: 13, carbs: 72, fat: 5 },
  { keywords: ["curry powder"], calories: 325, protein: 14, carbs: 58, fat: 14 },
  { keywords: ["paprika", "ground cumin", "black pepper", "salt", "baking powder"], calories: 0, protein: 0, carbs: 0, fat: 0 },
  { keywords: ["heavy cream", "cream"], calories: 340, protein: 2, carbs: 3, fat: 36 },
  { keywords: ["coconut milk"], calories: 197, protein: 2, carbs: 3, fat: 21 },
  { keywords: ["coffee"], calories: 1, protein: 0.1, carbs: 0, fat: 0 },
  { keywords: ["ladyfinger cookie"], calories: 390, protein: 10, carbs: 72, fat: 5 },
  { keywords: ["chickpeas"], calories: 164, protein: 8.9, carbs: 27.4, fat: 2.6 }
];

const densityProfiles = [
  { keywords: ["olive oil", "vegetable oil", "oil"], gramsPerMl: 0.91 },
  { keywords: ["butter"], gramsPerMl: 0.96 },
  { keywords: ["flour"], gramsPerMl: 0.53 },
  { keywords: ["sugar", "brown sugar"], gramsPerMl: 0.85 },
  { keywords: ["powdered sugar"], gramsPerMl: 0.56 },
  { keywords: ["honey"], gramsPerMl: 1.42 },
  { keywords: ["mayonnaise"], gramsPerMl: 0.95 },
  { keywords: ["ketchup", "mustard"], gramsPerMl: 1.15 },
  { keywords: ["oats"], gramsPerMl: 0.34 },
  { keywords: ["rice"], gramsPerMl: 0.85 },
  { keywords: ["milk", "cream", "yogurt"], gramsPerMl: 1.03 }
];

const itemWeightProfiles = [
  { keywords: ["egg"], grams: 50 },
  { keywords: ["garlic clove", "garlic"], grams: 5 },
  { keywords: ["shallot"], grams: 35 },
  { keywords: ["onion"], grams: 150 },
  { keywords: ["tomato"], grams: 120 },
  { keywords: ["carrot"], grams: 70 },
  { keywords: ["potato"], grams: 170 },
  { keywords: ["zucchini"], grams: 180 },
  { keywords: ["bell pepper"], grams: 120 },
  { keywords: ["mushroom"], grams: 18 },
  { keywords: ["lemon"], grams: 85 },
  { keywords: ["lime"], grams: 67 },
  { keywords: ["chicken breast"], grams: 174 },
  { keywords: ["chicken thigh"], grams: 120 },
  { keywords: ["chicken tenders"], grams: 45 },
  { keywords: ["chicken patty"], grams: 100 },
  { keywords: ["beef patty"], grams: 110 },
  { keywords: ["avocado"], grams: 150 },
  { keywords: ["banana"], grams: 118 },
  { keywords: ["apple"], grams: 182 },
  { keywords: ["pickle"], grams: 8 },
  { keywords: ["pickle relish"], grams: 15 },
  { keywords: ["coleslaw"], grams: 35 },
  { keywords: ["emmental cheese", "cheddar cheese", "mozzarella cheese", "gruyere cheese"], grams: 20 },
  { keywords: ["hamburger bun", "bun"], grams: 75 },
  { keywords: ["parsley", "cilantro", "basil"], grams: 15 },
  { keywords: ["slice bread", "bread"], grams: 30 }
];

const implicitPieceKeywords = [
  "egg",
  "garlic clove",
  "garlic",
  "shallot",
  "onion",
  "tomato",
  "carrot",
  "potato",
  "zucchini",
  "bell pepper",
  "mushroom",
  "lemon",
  "lime",
  "chicken breast",
  "chicken thigh",
  "chicken tenders",
  "chicken patty",
  "beef patty",
  "avocado",
  "banana",
  "apple",
  "pickle",
  "hamburger bun",
  "bun"
];

const implicitVolumeProfiles = [
  { keywords: ["mayonnaise"], ml: 15 },
  { keywords: ["ketchup"], ml: 15 },
  { keywords: ["mustard"], ml: 10 },
  { keywords: ["pickle relish", "relish"], ml: 15 },
  { keywords: ["coleslaw"], ml: 30 },
  { keywords: ["sauce"], ml: 15 }
];

const minorIngredientKeywords = [
  "salt",
  "pepper",
  "water",
  "ice",
  "garnish",
  "parsley",
  "cilantro",
  "basil",
  "mint",
  "thyme",
  "oregano",
  "paprika",
  "cinnamon"
];
