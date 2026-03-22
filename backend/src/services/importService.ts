import { fetchPageSummary } from "./generalPageService.js";
import { normalizeRecipeFromContext, transcribeMediaFromUrl } from "./openAIService.js";
import { fetchFallbackPages } from "./searchFallbackService.js";
import { resolveSocialContent } from "./socialContentService.js";
import {
  fallbackRecipeFromContext,
  isOpenAIUnavailable,
  structuredRecipeFromBlocks
} from "./heuristicRecipeService.js";
import { enrichRecipeNutrition } from "./usdaNutritionService.js";
import {
  sanitizeRecipeImport,
  scoreRecipe,
  shouldFallbackToSearch,
  type ImportDebug,
  type RecipeImportResult
} from "../types/recipe.js";

export async function importFromUrl(input: {
  url: string;
  sharedText?: string;
}): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const socialContent = await resolveSocialContent(input.url);
  const pageSummary = await fetchPageSummary(input.url).catch(() => null);
  const transcript = await transcribeMediaFromUrl(socialContent?.audioUrl ?? socialContent?.videoUrl).catch(() => null);
  const structuredRecipe = structuredRecipeFromBlocks(pageSummary?.structuredDataBlocks ?? []);

  const recipeContext = {
    mode: "url" as const,
    sourceUrl: input.url,
    remoteImageUrl: socialContent?.imageUrls[0] ?? pageSummary?.imageUrl,
    sharedText: input.sharedText,
    pageTitle: pageSummary?.title,
    pageDescription: pageSummary?.description,
    pageTextContent: pageSummary?.textContent,
    pageStructuredData: pageSummary?.structuredDataBlocks,
    socialTitle: socialContent?.title,
    socialCaption: socialContent?.caption,
    socialDescription: socialContent?.description,
    socialPageText: socialContent?.pageText,
    socialAuthor: socialContent?.authorName,
    socialSubtitles: socialContent?.subtitlesText,
    transcript: transcript ?? undefined
  };

  let recipe = preferStructuredRecipe(
    await safeNormalize(recipeContext),
    structuredRecipe
  );

  let usedWebFallback = false;

  if (shouldFallbackToSearch(recipe)) {
    const query = recipe.searchQuery || recipe.title || socialContent?.caption || pageSummary?.title || input.sharedText || "";
    const fallbackPages = await fetchFallbackPages(query);

    if (fallbackPages.length) {
      const fallbackRecipe = await safeNormalize({
        mode: "url",
        sourceUrl: input.url,
        remoteImageUrl: fallbackPages.map((page) => page.imageUrl).find(Boolean),
        sharedText: input.sharedText,
        pageTitle: fallbackPages.map((page) => page.title).find(Boolean),
        pageDescription: fallbackPages.map((page) => page.description).find(Boolean),
        pageTextContent: fallbackPages.map((page) => page.textContent).filter(Boolean).join("\n\n"),
        pageStructuredData: fallbackPages.flatMap((page) => page.structuredDataBlocks)
      });
      const fallbackStructuredRecipe = structuredRecipeFromBlocks(
        fallbackPages.flatMap((page) => page.structuredDataBlocks)
      );
      const normalizedFallbackRecipe = preferStructuredRecipe(fallbackRecipe, fallbackStructuredRecipe);

      if (scoreRecipe(normalizedFallbackRecipe) >= scoreRecipe(recipe)) {
        recipe = normalizedFallbackRecipe;
      }
      usedWebFallback = true;
    }
  }

  const finalizedRecipe = await finalizeImportedRecipe({
    ...recipe,
    sourceUrl: recipe.sourceUrl || input.url,
    remoteImageUrl: recipe.remoteImageUrl || socialContent?.imageUrls[0] || pageSummary?.imageUrl || ""
  });

  return {
    recipe: finalizedRecipe.recipe,
    debug: {
      platform: socialContent?.platform,
      usedApify: socialContent?.source === "apify",
      usedTranscription: Boolean(transcript),
      usedWebFallback,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      sourceKind: "url"
    }
  };
}

export async function importFromText(input: {
  text: string;
  imageDataUrl?: string;
}): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const recipe = await safeNormalize({
    mode: "text",
    sharedText: input.text,
    imageDataUrl: input.imageDataUrl
  });
  const finalizedRecipe = await finalizeImportedRecipe(recipe);

  return {
    recipe: finalizedRecipe.recipe,
    debug: {
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: false,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      sourceKind: "text"
    }
  };
}

export async function importFromPhoto(input: {
  imageDataUrl: string;
}): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const recipe = await safeNormalize({
    mode: "photo",
    imageDataUrl: input.imageDataUrl
  });
  const finalizedRecipe = await finalizeImportedRecipe(recipe);

  return {
    recipe: finalizedRecipe.recipe,
    debug: {
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: false,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      sourceKind: "photo"
    }
  };
}

async function safeNormalize(
  input: Parameters<typeof normalizeRecipeFromContext>[0]
): Promise<RecipeImportResult> {
  try {
    return await normalizeRecipeFromContext(input);
  } catch (error) {
    if (isOpenAIUnavailable(error)) {
      return fallbackRecipeFromContext(input);
    }

    throw error;
  }
}

async function finalizeImportedRecipe(recipe: RecipeImportResult) {
  const sanitizedRecipe = sanitizeRecipeImport(recipe);
  const nutritionResult = await enrichRecipeNutrition(sanitizedRecipe);

  return {
    ...nutritionResult,
    recipe: sanitizeRecipeImport(nutritionResult.recipe)
  };
}

function preferStructuredRecipe(
  recipe: RecipeImportResult,
  structuredRecipe: RecipeImportResult | null
): RecipeImportResult {
  if (!structuredRecipe) {
    return recipe;
  }

  const structuredIsStrong = structuredRecipe.confidence === "high" &&
    structuredRecipe.ingredientDrafts.length >= 3 &&
    structuredRecipe.stepDrafts.length >= 2;

  if (!structuredIsStrong && scoreRecipe(structuredRecipe) < scoreRecipe(recipe)) {
    return recipe;
  }

  return sanitizeRecipeImport({
    ...recipe,
    ...structuredRecipe,
    title: structuredRecipe.title || recipe.title,
    sourceUrl: recipe.sourceUrl || structuredRecipe.sourceUrl,
    remoteImageUrl: recipe.remoteImageUrl || structuredRecipe.remoteImageUrl,
    ingredientDrafts: structuredRecipe.ingredientDrafts.length >= recipe.ingredientDrafts.length
      ? structuredRecipe.ingredientDrafts
      : recipe.ingredientDrafts,
    stepDrafts: structuredRecipe.stepDrafts.length >= recipe.stepDrafts.length
      ? structuredRecipe.stepDrafts
      : recipe.stepDrafts,
    notesText: recipe.notesText || structuredRecipe.notesText,
    prepTimeText: structuredRecipe.prepTimeText || recipe.prepTimeText,
    cookTimeText: structuredRecipe.cookTimeText || recipe.cookTimeText,
    servingsText: structuredRecipe.servingsText || recipe.servingsText,
    caloriesText: structuredRecipe.caloriesText || recipe.caloriesText,
    proteinText: structuredRecipe.proteinText || recipe.proteinText,
    carbsText: structuredRecipe.carbsText || recipe.carbsText,
    fatText: structuredRecipe.fatText || recipe.fatText,
    confidence: structuredRecipe.confidence,
    needsWebFallback: structuredRecipe.needsWebFallback && recipe.needsWebFallback,
    searchQuery: recipe.searchQuery || structuredRecipe.searchQuery
  });
}
