import { z } from "zod";

import { enrichRecipeNutrition } from "./usdaNutritionService.js";
import { sanitizeRecipeImport, type RecipeImportResult, type RecipeIngredientDraft } from "../types/recipe.js";
import { normalizeWhitespace } from "../utils/text.js";

const URL_IMPORT_FAILURE_MESSAGE = "Impossible de générer la recette";
const RECIPE_IMAGE_FALLBACK_URL = "https://placehold.co/1200x900/png?text=Cooksy+Recipe";

const apiIngredientSchema = z.object({
  name: z.string(),
  quantity: z.string(),
  unit: z.string()
});

const apiStepSchema = z.object({
  stepNumber: z.number().int().positive(),
  description: z.string()
});

const apiNutritionSchema = z.object({
  calories: z.number().finite().min(0),
  protein: z.number().finite().min(0),
  carbs: z.number().finite().min(0),
  fat: z.number().finite().min(0)
});

const apiSuccessSchema = z.object({
  success: z.literal(true),
  data: z.object({
    title: z.string(),
    ingredients: z.array(apiIngredientSchema).min(1),
    steps: z.array(apiStepSchema).min(1),
    nutrition: apiNutritionSchema,
    image: z.string().url(),
    sourceUrl: z.string().url()
  })
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
}): Promise<URLImportSuccessResponse | URLImportFailureResponse> {
  const normalizedSourceUrl = normalizeUrl(input.sourceUrl);
  if (!normalizedSourceUrl) {
    return buildURLImportFailureResponse();
  }

  try {
    const recipeWithNutrition = await ensureRecipeNutrition(input.recipe);
    const title = stableTitle(recipeWithNutrition.title);
    const ingredients = normalizeIngredients(recipeWithNutrition.ingredientDrafts);
    const steps = ensureCompleteSteps(recipeWithNutrition, title, ingredients);
    const nutrition = resolveNutrition(recipeWithNutrition);

    if (!title || !ingredients.length || !steps.length) {
      return buildURLImportFailureResponse();
    }

    const response = apiSuccessSchema.parse({
      success: true,
      data: {
        title,
        ingredients,
        steps,
        nutrition,
        image: stableImageUrl(recipeWithNutrition.remoteImageUrl),
        sourceUrl: normalizedSourceUrl
      }
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
  ingredients: RecipeIngredientDraft[]
): URLImportSuccessResponse["data"]["ingredients"] {
  return ingredients
    .map((ingredient) => ({
      name: cleanIngredientText(ingredient.name),
      quantity: cleanIngredientText(ingredient.amount),
      unit: normalizeUnitLabel(ingredient.unit)
    }))
    .filter((ingredient) => ingredient.name.length > 0);
}

function normalizeSteps(
  recipe: RecipeImportResult
): URLImportSuccessResponse["data"]["steps"] {
  return recipe.stepDrafts
    .map((step) => cleanStepDescription(step.detail))
    .filter((description) => isUsableCookingInstruction(description))
    .filter(Boolean)
    .map((description, index) => ({
      stepNumber: index + 1,
      description
    }));
}

function ensureCompleteSteps(
  recipe: RecipeImportResult,
  title: string,
  ingredients: URLImportSuccessResponse["data"]["ingredients"]
): URLImportSuccessResponse["data"]["steps"] {
  const explicitSteps = normalizeSteps(recipe);
  if (explicitSteps.length >= 4) {
    return explicitSteps;
  }

  const rebuiltSteps = dedupeStepDescriptions([
    ...explicitSteps.map((step) => step.description),
    ...generatedStepsForRecipe(title, ingredients)
  ])
    .filter((description) => isUsableCookingInstruction(description))
    .slice(0, 6)
    .map((description, index) => ({
      stepNumber: index + 1,
      description
    }));

  if (rebuiltSteps.length >= 4) {
    return rebuiltSteps;
  }

  return generatedStepsForRecipe(title, ingredients).map((description, index) => ({
    stepNumber: index + 1,
    description
  }));
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

  if (/\b(?:read more|view post|link in bio)\b/.test(normalized)) {
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
    .replace(/\bc(?:uill?e?re)?\.?\s*a\s*soupe\b/gi, "c. à soupe")
    .replace(/\bc(?:uill?e?re)?\.?\s*a\s*cafe\b/gi, "c. à café")
    .replace(/\bcas\b/gi, "c. à soupe")
    .replace(/\bcac\b/gi, "c. à café")
    .replace(/\bgrammes?\b/gi, "g")
    .replace(/\bgr\b/gi, "g")
    .replace(/\bmillilit(?:er|re)s?\b/gi, "ml")
    .replace(/\blitres?\b/gi, "l")
    .replace(/\bpieces?\b/gi, "")
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
  const protein = preferredIngredient(ingredients, [/\bpoulet\b/i, /\bboeuf\b/i, /\bburger\b/i, /\bviande\b/i, /\bpoisson\b/i], "garniture principale");
  const bread = preferredIngredient(ingredients, [/\bpain\b/i, /\bbun\b/i, /\bnaan\b/i, /\bwrap\b/i, /\btortilla\b/i], "support");
  const greens = preferredIngredient(ingredients, [/\bsalade\b/i, /\blaitue\b/i, /\bcabbage\b/i, /\bchou\b/i], "garniture");
  const sauce = preferredIngredient(ingredients, [/\bsauce\b/i, /\bcreme\b/i, /\bcrème\b/i, /\byaourt\b/i], "sauce");
  const aromatic = preferredIngredient(ingredients, [/\boignon\b/i, /\bail\b/i, /\btomate\b/i, /\bchampignon\b/i], "aromates");

  if (/\b(?:burger|sandwich|naan|toast)\b/.test(normalizedTitle)) {
    return [
      `Préparez les garnitures en éminçant le ${aromatic} et en assaisonnant le ${protein}.`,
      `Faites cuire le ${protein} dans une poêle chaude jusqu'à ce qu'il soit bien doré et cuit à cœur.`,
      `Toastez le ${bread} puis préparez la garniture avec la ${greens} et la ${sauce}.`,
      `Montez le ${title.toLocaleLowerCase()} avec le ${bread}, le ${protein}, les garnitures et la sauce, puis servez aussitôt.`
    ];
  }

  if (/\bwrap\b/.test(normalizedTitle)) {
    return [
      `Assaisonnez le ${protein} puis faites-le cuire jusqu'à ce qu'il soit bien doré.`,
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
      "Mélangez les ingrédients secs, puis incorporez progressivement les ingrédients humides jusqu'à obtenir une pâte homogène.",
      `Versez la préparation dans le moule ou le plat adapté, puis faites cuire jusqu'à ce que le ${title.toLocaleLowerCase()} soit pris.`,
      "Laissez tiédir quelques minutes avant de découper ou de dresser, puis servez."
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

const instructionVerbPattern = /\b(?:preparez|assaisonnez|faites|faites cuire|chauffez|cuisez|ajoutez|melangez|mélangez|versez|disposez|repartissez|répartissez|montez|assemblez|rabattez|roulez|etalez|étalez|rechauffez|réchauffez|toastez|fouettez|incorporez|laissez|servez|garnissez|saisissez|rectifiez|poursuivez|dressez|enfournez|coupez|emincez|émincez|detaillez|détaillez)\b/;
