import { env, providerStatus } from "../config/env.js";
import type { RecipeImportResult, RecipeIngredientDraft } from "../types/recipe.js";
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

  if (!enabled || !apiKey || recipe.ingredientDrafts.length < 2) {
    return {
      recipe,
      usedUsda: false,
      nutritionCoverage: 0,
      matchedIngredients: 0
    };
  }

  let matchedIngredients = 0;
  const totals: NutritionTotals = {
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0
  };

  const consideredIngredients = recipe.ingredientDrafts.filter((ingredient) => !isMinorIngredient(ingredient));
  const nutritionResults = await Promise.all(
    consideredIngredients.map(async (ingredient) => estimateIngredientNutrition(ingredient, { apiKey, fetchImpl }))
  );

  for (const nutrition of nutritionResults) {
    if (!nutrition) {
      continue;
    }

    matchedIngredients += 1;
    totals.calories += nutrition.calories;
    totals.protein += nutrition.protein;
    totals.carbs += nutrition.carbs;
    totals.fat += nutrition.fat;
  }

  const nutritionCoverage = consideredIngredients.length > 0
    ? matchedIngredients / consideredIngredients.length
    : 0;

  if (matchedIngredients < 2 || totals.calories <= 0) {
    return {
      recipe,
      usedUsda: false,
      nutritionCoverage,
      matchedIngredients
    };
  }

  const hasExistingNutrition = [
    recipe.caloriesText,
    recipe.proteinText,
    recipe.carbsText,
    recipe.fatText
  ].some((value) => value.trim().length > 0);

  const shouldApplyUsda = nutritionCoverage >= 0.5 || !hasExistingNutrition;
  if (!shouldApplyUsda) {
    return {
      recipe,
      usedUsda: false,
      nutritionCoverage,
      matchedIngredients
    };
  }

  const perServingDivisor = parseServings(recipe.servingsText) || 1;
  const perServing = {
    calories: totals.calories / perServingDivisor,
    protein: totals.protein / perServingDivisor,
    carbs: totals.carbs / perServingDivisor,
    fat: totals.fat / perServingDivisor
  };

  return {
    recipe: {
      ...recipe,
      caloriesText: formatCalories(perServing.calories),
      proteinText: formatMacro(perServing.protein),
      carbsText: formatMacro(perServing.carbs),
      fatText: formatMacro(perServing.fat)
    },
    usedUsda: true,
    nutritionCoverage,
    matchedIngredients
  };
}

async function estimateIngredientNutrition(
  ingredient: RecipeIngredientDraft,
  options: {
    apiKey: string;
    fetchImpl: typeof fetch;
  }
): Promise<NutritionTotals | null> {
  const grams = estimateIngredientGrams(ingredient);
  if (!grams || grams <= 0) {
    return null;
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
      calories: (calories * grams) / basisGrams,
      protein: (protein * grams) / basisGrams,
      carbs: (carbs * grams) / basisGrams,
      fat: (fat * grams) / basisGrams
    };
  }

  return null;
}

async function searchFoods(
  query: string,
  options: {
    apiKey: string;
    fetchImpl: typeof fetch;
  }
): Promise<USDAFoodSearchItem[]> {
  const cacheKey = query.toLowerCase();
  const existing = searchCache.get(cacheKey);
  if (existing) {
    return existing;
  }

  const pending = (async () => {
    const url = new URL(USDA_SEARCH_ENDPOINT);
    url.searchParams.set("api_key", options.apiKey);

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
  const quantity = parseQuantity(ingredient.amount);
  const normalizedUnit = normalizeUnit(ingredient.unit);
  const density = ingredientDensity(ingredient);

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

  if (/^\d+(?:\.\d+)?$/.test(normalized)) {
    return Number(normalized);
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
  const normalized = normalizeFoodText(`${ingredient.name} ${ingredient.nutritionQuery}`);

  for (const profile of itemWeightProfiles) {
    if (profile.keywords.some((keyword) => normalized.includes(keyword))) {
      return profile.grams;
    }
  }

  return 100;
}

function ingredientDensity(ingredient: RecipeIngredientDraft): number {
  const normalized = normalizeFoodText(`${ingredient.name} ${ingredient.nutritionQuery}`);

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
  [/\bgruyere\b/g, "gruyere cheese"],
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

const densityProfiles = [
  { keywords: ["olive oil", "vegetable oil", "oil"], gramsPerMl: 0.91 },
  { keywords: ["butter"], gramsPerMl: 0.96 },
  { keywords: ["flour"], gramsPerMl: 0.53 },
  { keywords: ["sugar", "brown sugar"], gramsPerMl: 0.85 },
  { keywords: ["powdered sugar"], gramsPerMl: 0.56 },
  { keywords: ["honey"], gramsPerMl: 1.42 },
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
  { keywords: ["avocado"], grams: 150 },
  { keywords: ["banana"], grams: 118 },
  { keywords: ["apple"], grams: 182 },
  { keywords: ["parsley", "cilantro", "basil"], grams: 15 },
  { keywords: ["slice bread", "bread"], grams: 30 }
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
