import { fetchPageSummary, resolveRemoteURL } from "./generalPageService.js";
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
import { platformFromUrl } from "../utils/text.js";

export async function importFromUrl(input: {
  url: string;
  sharedText?: string;
}): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const startedAt = Date.now();
  const resolvedSourceURL = await resolveImportSourceURL(input.url);
  const [pageSummary, socialContent] = await Promise.all([
    fetchPageSummary(resolvedSourceURL).catch(() => null),
    resolveSocialContent(resolvedSourceURL)
  ]);
  const canonicalSourceURL = pageSummary?.canonicalUrl ?? pageSummary?.url ?? resolvedSourceURL;
  const structuredRecipe = structuredRecipeFromBlocks(pageSummary?.structuredDataBlocks ?? []);
  const mediaURL = socialContent?.audioUrl ?? socialContent?.videoUrl;
  const captionWasSparse = hasSparseSocialText(
    input.sharedText,
    socialContent?.caption,
    socialContent?.description,
    socialContent?.subtitlesText,
    pageSummary?.description
  );
  let transcript: string | null = null;
  let importStrategy: "social" | "audio" | "web" = "social";
  let importStrategySourceURL: string | undefined;

  const baseRecipeContext = {
    mode: "url" as const,
    sourceUrl: canonicalSourceURL,
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
    await safeNormalize(baseRecipeContext),
    structuredRecipe
  );

  const linkedFallbackPages = shouldTryLinkedWebFallback(recipe, socialContent?.externalLinks ?? [])
    ? await fetchFallbackPagesFromLinks(socialContent?.externalLinks ?? [])
    : [];

  let usedWebFallback = false;

  if (linkedFallbackPages.length) {
    const linkedFallbackRecipe = await recipeFromFallbackPages(
      linkedFallbackPages,
      input.sharedText,
      canonicalSourceURL
    );

    if (linkedFallbackRecipe && scoreRecipe(linkedFallbackRecipe.recipe) >= scoreRecipe(recipe)) {
      recipe = linkedFallbackRecipe.recipe;
      usedWebFallback = true;
      importStrategy = "web";
      importStrategySourceURL = linkedFallbackRecipe.sourceUrl;
    }
  }

  if (shouldPrioritizeTranscription({
    sharedText: input.sharedText,
    pageSummary,
    socialContent,
    mediaURL
  })) {
    transcript = await transcribeMediaFromUrl(mediaURL).catch(() => null);

    if (transcript) {
      const transcribedRecipe = preferStructuredRecipe(
        await safeNormalize({
          ...baseRecipeContext,
          transcript
        }),
        structuredRecipe
      );

      if (scoreRecipe(transcribedRecipe) >= scoreRecipe(recipe)) {
        recipe = transcribedRecipe;
        importStrategy = "audio";
        importStrategySourceURL = undefined;
      }
    }
  }

  if (!transcript && shouldUseTranscriptionFallback(recipe, socialContent, input.sharedText, mediaURL)) {
    transcript = await transcribeMediaFromUrl(mediaURL).catch(() => null);

    if (transcript) {
      const transcribedRecipe = preferStructuredRecipe(
        await safeNormalize({
          ...baseRecipeContext,
          transcript
        }),
        structuredRecipe
      );

      if (scoreRecipe(transcribedRecipe) >= scoreRecipe(recipe)) {
        recipe = transcribedRecipe;
        importStrategy = "audio";
        importStrategySourceURL = undefined;
      }
    }
  }

  if (shouldFallbackToSearch(recipe)) {
    const query = recipe.searchQuery || recipe.title || socialContent?.caption || pageSummary?.title || input.sharedText || "";
    const fallbackPages = await fetchFallbackPages(query);

    if (fallbackPages.length) {
      const fallbackRecipe = await recipeFromFallbackPages(
        fallbackPages,
        input.sharedText,
        canonicalSourceURL
      );

      if (fallbackRecipe && scoreRecipe(fallbackRecipe.recipe) >= scoreRecipe(recipe)) {
        recipe = fallbackRecipe.recipe;
        importStrategy = "web";
        importStrategySourceURL = fallbackRecipe.sourceUrl;
      }
      usedWebFallback = true;
    }
  }

  const recipeWithImportContext = applyImportContextNotes(
    {
      ...recipe,
      sourceUrl: recipe.sourceUrl || canonicalSourceURL,
      remoteImageUrl: recipe.remoteImageUrl || socialContent?.imageUrls[0] || pageSummary?.imageUrl || ""
    },
    {
      importStrategy,
      captionWasSparse,
      webSourceUrl: importStrategySourceURL
    }
  );

  const finalizedRecipe = await finalizeImportedRecipe(recipeWithImportContext);

  console.info(
    `[importService] URL import completed in ${Date.now() - startedAt}ms` +
    ` (strategy=${importStrategy} transcript=${Boolean(transcript)} webFallback=${usedWebFallback} usda=${finalizedRecipe.usedUsda}) for ${canonicalSourceURL}`
  );

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

function shouldPrioritizeTranscription(input: {
  sharedText?: string;
  pageSummary: Awaited<ReturnType<typeof fetchPageSummary>> | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  mediaURL?: string;
}): boolean {
  if (!input.mediaURL) {
    return false;
  }

  return hasSparseSocialText(
    input.sharedText,
    input.socialContent?.caption,
    input.socialContent?.description,
    input.socialContent?.subtitlesText,
    input.pageSummary?.description
  );
}

function shouldUseTranscriptionFallback(
  recipe: RecipeImportResult,
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null,
  sharedText: string | undefined,
  mediaURL?: string
): boolean {
  if (!mediaURL) {
    return false;
  }

  const alreadyStrongRecipe = recipe.ingredientDrafts.length >= 3 &&
    recipe.stepDrafts.length >= 2 &&
    recipe.confidence !== "low" &&
    !recipe.needsWebFallback;

  if (alreadyStrongRecipe) {
    return false;
  }

  return hasSparseSocialText(
    sharedText,
    socialContent?.caption,
    socialContent?.description,
    socialContent?.subtitlesText
  ) || recipe.needsWebFallback;
}

function shouldTryLinkedWebFallback(
  recipe: RecipeImportResult,
  externalLinks: string[]
): boolean {
  return externalLinks.length > 0 && shouldFallbackToSearch(recipe);
}

function hasSparseSocialText(...values: Array<string | undefined>): boolean {
  const combined = values
    .map((value) => value?.trim() ?? "")
    .filter(Boolean)
    .join("\n")
    .replace(/https?:\/\/\S+/g, "")
    .replace(/#[\p{L}\p{N}_]+/gu, "")
    .replace(/@[\p{L}\p{N}._]+/gu, "")
    .replace(/\s+/g, " ")
    .trim();

  return combined.length < 90;
}

function applyImportContextNotes(
  recipe: RecipeImportResult,
  input: {
    importStrategy: "social" | "audio" | "web";
    captionWasSparse: boolean;
    webSourceUrl?: string;
  }
): RecipeImportResult {
  if (!input.captionWasSparse || input.importStrategy === "social") {
    return recipe;
  }

  const importNotice = input.importStrategy === "audio"
    ? "Import info: recette reconstruite depuis l'audio du post."
    : webImportNotice(input.webSourceUrl);
  const existingNotes = recipe.notesText.trim();

  return {
    ...recipe,
    notesText: existingNotes
      ? `${importNotice}\n${existingNotes}`
      : importNotice
  };
}

function webImportNotice(sourceUrl?: string): string {
  const host = hostLabelForImportNotice(sourceUrl);
  if (host) {
    return `Import info: recette reconstruite depuis le site web ${host}.`;
  }

  return "Import info: recette reconstruite depuis une page recette du web.";
}

function hostLabelForImportNotice(sourceUrl?: string): string | undefined {
  if (!sourceUrl) {
    return undefined;
  }

  try {
    return new URL(sourceUrl).host.replace(/^www\./i, "");
  } catch {
    return undefined;
  }
}

async function fetchFallbackPagesFromLinks(urls: string[]): Promise<Array<{
  url: string;
  title?: string;
  description?: string;
  textContent?: string;
  structuredDataBlocks: string[];
  imageUrl?: string;
}>> {
  const pages = await Promise.all(
    urls.slice(0, 3).map(async (url) => {
      try {
        return await fetchPageSummary(url);
      } catch {
        return null;
      }
    })
  );

  return pages.filter((page): page is NonNullable<typeof page> => Boolean(page));
}

async function recipeFromFallbackPages(
  pages: Array<{
    url: string;
    title?: string;
    description?: string;
    textContent?: string;
    structuredDataBlocks: string[];
    imageUrl?: string;
  }>,
  sharedText: string | undefined,
  sourceUrl: string
): Promise<{ recipe: RecipeImportResult; sourceUrl?: string } | null> {
  if (!pages.length) {
    return null;
  }

  const fallbackRecipe = await safeNormalize({
    mode: "url",
    sourceUrl,
    remoteImageUrl: pages.map((page) => page.imageUrl).find(Boolean),
    sharedText,
    pageTitle: pages.map((page) => page.title).find(Boolean),
    pageDescription: pages.map((page) => page.description).find(Boolean),
    pageTextContent: pages.map((page) => page.textContent).filter(Boolean).join("\n\n"),
    pageStructuredData: pages.flatMap((page) => page.structuredDataBlocks)
  });
  const fallbackStructuredRecipe = structuredRecipeFromBlocks(
    pages.flatMap((page) => page.structuredDataBlocks)
  );
  const normalizedFallbackRecipe = preferStructuredRecipe(fallbackRecipe, fallbackStructuredRecipe);

  return {
    recipe: normalizedFallbackRecipe,
    sourceUrl: pages[0]?.url
  };
}

async function resolveImportSourceURL(url: string): Promise<string> {
  if (platformFromUrl(url) === "web") {
    return url;
  }

  try {
    const resolvedURL = await resolveRemoteURL(url);
    if (resolvedURL !== url) {
      console.info(`[importService] Resolved social import URL ${url} -> ${resolvedURL}`);
    }
    return resolvedURL;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[importService] Failed to resolve social import URL ${url}: ${message}`);
    return url;
  }
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
