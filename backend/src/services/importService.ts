import { fetchPageSummary } from "./generalPageService.js";
import { normalizeRecipeFromContext, transcribeMediaFromUrl } from "./openAIService.js";
import { fetchFallbackPages } from "./searchFallbackService.js";
import { resolveSocialContent } from "./socialContentService.js";
import { fallbackRecipeFromContext, isOpenAIUnavailable } from "./heuristicRecipeService.js";
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
    socialAuthor: socialContent?.authorName,
    socialSubtitles: socialContent?.subtitlesText,
    transcript: transcript ?? undefined
  };

  let recipe = await safeNormalize(recipeContext);

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

      if (scoreRecipe(fallbackRecipe) >= scoreRecipe(recipe)) {
        recipe = fallbackRecipe;
      }
      usedWebFallback = true;
    }
  }

  recipe = sanitizeRecipeImport({
    ...recipe,
    sourceUrl: recipe.sourceUrl || input.url,
    remoteImageUrl: recipe.remoteImageUrl || socialContent?.imageUrls[0] || pageSummary?.imageUrl || ""
  });

  return {
    recipe,
    debug: {
      platform: socialContent?.platform,
      usedApify: socialContent?.source === "apify",
      usedTranscription: Boolean(transcript),
      usedWebFallback,
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

  return {
    recipe,
    debug: {
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: false,
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

  return {
    recipe,
    debug: {
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: false,
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
