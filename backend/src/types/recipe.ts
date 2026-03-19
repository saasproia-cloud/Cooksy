import { z } from "zod";

export const recipeIngredientSchema = z.object({
  amount: z.string().default(""),
  unit: z.string().default(""),
  name: z.string().default("")
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

export type RecipeImportResult = z.infer<typeof recipeImportSchema>;

export type ImportDebug = {
  platform?: string;
  usedApify: boolean;
  usedTranscription: boolean;
  usedWebFallback: boolean;
  sourceKind: "url" | "text" | "photo";
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
  socialAuthor?: string;
  socialSubtitles?: string;
  transcript?: string;
  imageDataUrl?: string;
};

function clean(value?: string | null): string {
  return (value ?? "").trim();
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
  return {
    ...input,
    title: clean(input.title),
    sourceUrl: normalizeUrl(input.sourceUrl),
    remoteImageUrl: normalizeUrl(input.remoteImageUrl),
    ingredientDrafts: input.ingredientDrafts
      .map((ingredient) => ({
        amount: clean(ingredient.amount),
        unit: clean(ingredient.unit),
        name: clean(ingredient.name)
      }))
      .filter((ingredient) => ingredient.name.length > 0),
    stepDrafts: input.stepDrafts
      .map((step) => ({
        detail: clean(step.detail)
      }))
      .filter((step) => step.detail.length > 0),
    notesText: clean(input.notesText),
    prepTimeText: clean(input.prepTimeText),
    cookTimeText: clean(input.cookTimeText),
    servingsText: clean(input.servingsText),
    caloriesText: clean(input.caloriesText),
    proteinText: clean(input.proteinText),
    carbsText: clean(input.carbsText),
    fatText: clean(input.fatText),
    searchQuery: clean(input.searchQuery)
  };
}

export function scoreRecipe(recipe: RecipeImportResult): number {
  return recipe.ingredientDrafts.length * 5 +
    recipe.stepDrafts.length * 6 +
    (recipe.title.length > 0 ? 8 : 0) +
    (recipe.notesText.length > 0 ? 2 : 0) +
    (recipe.remoteImageUrl.length > 0 ? 2 : 0) +
    (recipe.confidence === "high" ? 6 : recipe.confidence === "medium" ? 3 : 0);
}

export function shouldFallbackToSearch(recipe: RecipeImportResult): boolean {
  return recipe.needsWebFallback ||
    recipe.confidence === "low" ||
    recipe.ingredientDrafts.length < 2 ||
    recipe.stepDrafts.length < 2;
}
