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
  importFailureReason,
  importMissingParts,
  isLikelyValidRecipe,
  sanitizeRecipeImport,
  scoreRecipe,
  shouldFallbackToSearch,
  type ImportDebug,
  type RecipeImportResult
} from "../types/recipe.js";
import { platformFromUrl } from "../utils/text.js";

type ImportExecutionOptions = {
  previewMode?: boolean;
};

type ImportStrategy = "social" | "web" | "fallback" | "audio" | "text" | "photo";
type ImportedPageSummary = {
  url: string;
  title?: string;
  description?: string;
  textContent?: string;
  structuredDataBlocks: string[];
  imageUrl?: string;
};

const PREVIEW_TOTAL_LIMIT_MS = 9_000;
const PREVIEW_RESOLVE_TIMEOUT_MS = 2_500;
const PREVIEW_SOCIAL_TIMEOUT_MS = 4_500;
const PREVIEW_WEB_TIMEOUT_MS = 2_000;
const PREVIEW_RESERVE_MS = 700;

export async function importFromUrl(input: {
  url: string;
  sharedText?: string;
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const previewMode = options?.previewMode ?? false;
  const startedAt = Date.now();
  const resolvedSourceURL = await resolveImportSourceURL(
    input.url,
    previewMode ? PREVIEW_RESOLVE_TIMEOUT_MS : undefined
  );

  if (previewMode) {
    return importPreviewFromUrl(input, {
      startedAt,
      resolvedSourceURL
    });
  }

  const sourcePlatform = platformFromUrl(resolvedSourceURL);
  const initialSocialContentOptions = sourcePlatform === "tiktok"
    ? {
        preferDirectFetch: true,
        skipApify: true
      }
    : {};
  const [pageSummary, socialContent] = await Promise.all([
    fetchPageSummary(resolvedSourceURL).catch(() => null),
    resolveSocialContent(resolvedSourceURL, {
      ...initialSocialContentOptions
    })
  ]);
  const canonicalSourceURL = pageSummary?.canonicalUrl ?? pageSummary?.url ?? resolvedSourceURL;
  let resolvedSocialContent = socialContent;
  let mediaURL = resolvedSocialContent?.audioUrl ?? resolvedSocialContent?.videoUrl;
  let captionWasSparse = hasSparseSocialText(
    input.sharedText,
    resolvedSocialContent?.caption,
    resolvedSocialContent?.description,
    resolvedSocialContent?.subtitlesText,
    pageSummary?.description
  );
  let transcript: string | null = null;
  let importStrategy: ImportStrategy = sourcePlatform === "web" ? "web" : "social";
  let importStrategySourceURL: string | undefined;
  let fallbackPages: ImportedPageSummary[] = [];
  let usedWebFallback = false;
  let normalizedFromSocialText = false;
  let normalizedAfterTranscript = false;
  let normalizedFromWebFallback = false;

  const buildContext = () => buildUrlNormalizationContext({
    canonicalSourceURL,
    sharedText: input.sharedText,
    pageSummary,
    socialContent: resolvedSocialContent,
    transcript,
    fallbackPages
  });

  let recipe = recipeFromContext(buildContext());

  if (shouldAttemptSocialNormalization({
    recipe,
    sourcePlatform,
    context: buildContext()
  })) {
    console.info(`[importService] Trying social text normalization for ${canonicalSourceURL}`);
    const socialContext = buildContext();
    const socialNormalizedRecipe = preferStructuredRecipe(
      await safeNormalize(socialContext, false),
      structuredRecipeFromBlocks(socialContext.pageStructuredData ?? [])
    );

    normalizedFromSocialText = true;
    if (scoreRecipe(socialNormalizedRecipe) >= scoreRecipe(recipe)) {
      recipe = socialNormalizedRecipe;
    }
  }

  if (
    shouldFetchFullSocialSnapshot({
      recipe,
      sourcePlatform,
      socialContent: resolvedSocialContent,
      mediaURL
    })
  ) {
    const enrichedSocialContent = await resolveSocialContent(resolvedSourceURL, {
      preferDirectFetch: sourcePlatform === "tiktok"
    }).catch(() => null);

    if (enrichedSocialContent) {
      resolvedSocialContent = enrichedSocialContent;
      mediaURL = resolvedSocialContent.audioUrl ?? resolvedSocialContent.videoUrl;
      captionWasSparse = hasSparseSocialText(
        input.sharedText,
        resolvedSocialContent.caption,
        resolvedSocialContent.description,
        resolvedSocialContent.subtitlesText,
        pageSummary?.description
      );
    }
  }

  if (!shouldTrustFastSocialRecipe(recipe, sourcePlatform) &&
    shouldUseTranscriptionFallback(recipe, resolvedSocialContent, input.sharedText, mediaURL)
  ) {
    console.info(`[importService] Trying audio fallback for ${canonicalSourceURL}`);
    transcript = await transcribeMediaFromUrl(mediaURL, transcriptionOptions(false)).catch(() => null);

    if (transcript) {
      const audioContext = buildContext();
      let audioRecipe = recipeFromContext(audioContext);
      if (shouldAttemptTranscriptNormalization(audioRecipe, audioContext)) {
        audioRecipe = preferStructuredRecipe(
          await safeNormalize(audioContext, false),
          structuredRecipeFromBlocks(audioContext.pageStructuredData ?? [])
        );
        normalizedAfterTranscript = true;
      }
      if (scoreRecipe(audioRecipe) >= scoreRecipe(recipe)) {
        recipe = audioRecipe;
        importStrategy = "audio";
        importStrategySourceURL = undefined;
      }
    }
  }

  if (
    resolvedSocialContent?.externalLinks.length &&
    shouldTryLinkedWebFallback(recipe, resolvedSocialContent.externalLinks)
  ) {
    const linkedPages = await fetchFallbackPagesFromLinks(resolvedSocialContent.externalLinks);
    if (linkedPages.length) {
      fallbackPages = mergeFallbackPages(fallbackPages, linkedPages);
      const linkedFallbackRecipe = await recipeFromFallbackPages(
        linkedPages,
        input.sharedText,
        canonicalSourceURL,
        false
      );

      if (linkedFallbackRecipe && scoreRecipe(linkedFallbackRecipe.recipe) >= scoreRecipe(recipe)) {
        recipe = linkedFallbackRecipe.recipe;
        usedWebFallback = true;
        importStrategy = "web";
        importStrategySourceURL = linkedFallbackRecipe.sourceUrl ?? linkedPages[0]?.url;
        normalizedFromWebFallback = true;
      }
    }
  }

  if (shouldFallbackToSearch(recipe)) {
    const query = bestSearchQuery({
      recipe,
      pageSummary,
      socialContent: resolvedSocialContent,
      sharedText: input.sharedText
    });
    const searchPages = await fetchFallbackPages(query);

    if (searchPages.length) {
      fallbackPages = mergeFallbackPages(fallbackPages, searchPages);
      const searchFallbackRecipe = await recipeFromFallbackPages(
        searchPages,
        input.sharedText,
        canonicalSourceURL,
        false
      );

      if (searchFallbackRecipe && scoreRecipe(searchFallbackRecipe.recipe) >= scoreRecipe(recipe)) {
        recipe = searchFallbackRecipe.recipe;
        importStrategy = "fallback";
        importStrategySourceURL = searchFallbackRecipe.sourceUrl ?? searchPages[0]?.url;
        normalizedFromWebFallback = true;
      }
      usedWebFallback = true;
    }
  }

  const normalizedWithLatestContext = fallbackPages.length > 0
    ? normalizedFromWebFallback
    : Boolean(transcript)
      ? normalizedAfterTranscript
      : normalizedFromSocialText;

  if (
    !shouldTrustFastSocialRecipe(recipe, sourcePlatform) &&
    !normalizedWithLatestContext &&
    shouldAttemptFinalNormalization({
      recipe,
      sourcePlatform,
      context: buildContext(),
      transcript,
      fallbackPages
    })
  ) {
    const normalizedContext = buildContext();
    const normalizedRecipe = preferStructuredRecipe(
      await safeNormalize(normalizedContext, false),
      structuredRecipeFromBlocks(normalizedContext.pageStructuredData ?? [])
    );

    if (scoreRecipe(normalizedRecipe) >= scoreRecipe(recipe)) {
      recipe = normalizedRecipe;
    }
  } else if (!shouldTrustFastSocialRecipe(recipe, sourcePlatform)) {
    console.info(
      `[importService] Skipping final normalization for thin context on ${canonicalSourceURL}`
    );
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

  const finalizedRecipe = await finalizeImportedRecipe(recipeWithImportContext, {
    skipNutrition: false
  });
  const durationMs = Date.now() - startedAt;
  const debug = buildImportDebug(finalizedRecipe.recipe, {
    platform: resolvedSocialContent?.platform,
    sourceKind: "url",
    strategy: importStrategy,
    durationMs,
    usedApify: resolvedSocialContent?.source === "apify",
    usedTranscription: Boolean(transcript),
    usedWebFallback,
    usedUsda: finalizedRecipe.usedUsda,
    nutritionCoverage: finalizedRecipe.nutritionCoverage,
    matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
    preferWeakMetadataReason: sourcePlatform !== "web" && captionWasSparse
  });

  logImportDebug(finalizedRecipe.recipe, debug);
  console.info(
    `[importService] URL import completed in ${durationMs}ms` +
    ` (preview=${previewMode} strategy=${importStrategy} transcript=${Boolean(transcript)} webFallback=${usedWebFallback} usda=${finalizedRecipe.usedUsda}) for ${canonicalSourceURL}`
  );

  return {
    recipe: finalizedRecipe.recipe,
    debug
  };
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

function shouldFetchFullSocialSnapshot(input: {
  recipe: RecipeImportResult;
  sourcePlatform: ReturnType<typeof platformFromUrl>;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  mediaURL?: string;
}): boolean {
  if (input.sourcePlatform !== "tiktok") {
    return false;
  }

  if (!input.socialContent) {
    return true;
  }

  if (input.socialContent.source === "apify") {
    return false;
  }

  if (input.mediaURL || input.socialContent.externalLinks.length > 0) {
    return false;
  }

  return input.recipe.stepDrafts.length < 2 || input.recipe.needsWebFallback;
}

function shouldAttemptSocialNormalization(input: {
  recipe: RecipeImportResult;
  sourcePlatform: ReturnType<typeof platformFromUrl>;
  context: ReturnType<typeof buildUrlNormalizationContext>;
}): boolean {
  if (input.sourcePlatform === "web" || shouldTrustFastSocialRecipe(input.recipe, input.sourcePlatform)) {
    return false;
  }

  const combinedText = [
    input.context.sharedText,
    input.context.socialCaption,
    input.context.socialDescription,
    input.context.socialPageText,
    input.context.socialSubtitles
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n")
    .trim();

  if (combinedText.length < 100) {
    return false;
  }

  return input.recipe.ingredientDrafts.length >= 2 ||
    input.recipe.stepDrafts.length >= 1 ||
    /\b(?:ingrédients?|ingredients?|burger|tacos?|poulet|pasta|pates?|gateau|gâteau|tarte|pizza)\b/i.test(combinedText);
}

function shouldAttemptTranscriptNormalization(
  recipe: RecipeImportResult,
  context: ReturnType<typeof buildUrlNormalizationContext>
): boolean {
  const transcript = context.transcript?.trim() ?? "";
  if (transcript.length < 60) {
    return false;
  }

  return recipe.stepDrafts.length < 2 ||
    recipe.ingredientDrafts.length < 3 ||
    !isLikelyValidRecipe(recipe);
}

function shouldTryLinkedWebFallback(
  recipe: RecipeImportResult,
  externalLinks: string[]
): boolean {
  return externalLinks.length > 0 && shouldFallbackToSearch(recipe);
}

function isStrongPreviewRecipe(recipe: RecipeImportResult): boolean {
  return recipe.ingredientDrafts.length >= 3 &&
    recipe.stepDrafts.length >= 2 &&
    recipe.confidence !== "low";
}

function shouldTrustFastSocialRecipe(
  recipe: RecipeImportResult,
  sourcePlatform: ReturnType<typeof platformFromUrl>
): boolean {
  if (sourcePlatform === "web") {
    return false;
  }

  return recipe.ingredientDrafts.length >= 3 &&
    recipe.stepDrafts.length >= 2 &&
    recipe.title.trim().length > 2 &&
    !recipe.needsWebFallback &&
    recipe.confidence !== "low";
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
    importStrategy: ImportStrategy;
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

async function importPreviewFromUrl(
  input: {
    url: string;
    sharedText?: string;
  },
  state: {
    startedAt: number;
    resolvedSourceURL: string;
  }
): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const previewDeadline = state.startedAt + PREVIEW_TOTAL_LIMIT_MS;
  const sourcePlatform = platformFromUrl(state.resolvedSourceURL);
  const previewFromSharedText = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: state.resolvedSourceURL,
    sharedText: input.sharedText
  });

  if (sourcePlatform === "web") {
    const pageTimeoutMs = boundedPreviewTimeout(previewDeadline, 3_000);
    const pageSummary = pageTimeoutMs
      ? await fetchPageSummary(state.resolvedSourceURL, { timeoutMs: pageTimeoutMs }).catch(() => null)
      : null;
    const structuredRecipe = structuredRecipeFromBlocks(pageSummary?.structuredDataBlocks ?? []);
    const previewRecipe = preferStructuredRecipe(
      fallbackRecipeFromContext({
        mode: "url",
        sourceUrl: pageSummary?.canonicalUrl ?? pageSummary?.url ?? state.resolvedSourceURL,
        remoteImageUrl: pageSummary?.imageUrl,
        sharedText: input.sharedText,
        pageTitle: pageSummary?.title,
        pageDescription: pageSummary?.description,
        pageTextContent: pageSummary?.textContent,
        pageStructuredData: pageSummary?.structuredDataBlocks
      }),
      structuredRecipe
    );

    return finalizePreviewResult(
      previewRecipe,
      {
        startedAt: state.startedAt,
        sourceKind: "url",
        platform: sourcePlatform,
        strategy: "web",
        usedApify: false,
        usedTranscription: false,
        usedWebFallback: false,
        preferWeakMetadataReason: false
      }
    );
  }

  let recipe = previewFromSharedText;
  let importStrategy: ImportStrategy = previewFromSharedText.title || previewFromSharedText.ingredientDrafts.length || previewFromSharedText.stepDrafts.length
    ? "fallback"
    : "social";
  let usedWebFallback = false;
  let socialContent = null as Awaited<ReturnType<typeof resolveSocialContent>> | null;

  if (!isLikelyValidRecipe(recipe) && hasPreviewBudget(previewDeadline)) {
    const socialTimeoutMs = boundedPreviewTimeout(previewDeadline, PREVIEW_SOCIAL_TIMEOUT_MS);
    if (socialTimeoutMs) {
      socialContent = await resolveSocialContent(state.resolvedSourceURL, {
        timeoutMs: socialTimeoutMs,
        allowDirectFetch: true,
        skipApify: true,
        preferDirectFetch: true
      }).catch(() => null);
    }

    if (socialContent) {
      const socialRecipeContext = socialContent.source === "direct" && sourcePlatform === "tiktok"
        ? {
            mode: "url" as const,
            sourceUrl: socialContent.canonicalUrl || state.resolvedSourceURL,
            remoteImageUrl: socialContent.imageUrls[0],
            sharedText: input.sharedText,
            socialTitle: socialContent.title,
            socialPageText: socialContent.pageText,
            socialAuthor: socialContent.authorName
          }
        : {
            mode: "url" as const,
            sourceUrl: socialContent.canonicalUrl || state.resolvedSourceURL,
            remoteImageUrl: socialContent.imageUrls[0],
            sharedText: input.sharedText,
            socialTitle: socialContent.title,
            socialCaption: socialContent.caption,
            socialDescription: socialContent.description,
            socialPageText: socialContent.pageText,
            socialAuthor: socialContent.authorName,
            socialSubtitles: socialContent.subtitlesText
          };
      const socialRecipe = fallbackRecipeFromContext(socialRecipeContext);

      if (scoreRecipe(socialRecipe) >= scoreRecipe(recipe)) {
        recipe = socialRecipe;
        importStrategy = "social";
      }
    }
  }

  if (
    socialContent?.externalLinks.length &&
    shouldTryLinkedWebFallback(recipe, socialContent.externalLinks) &&
    hasPreviewBudget(previewDeadline, PREVIEW_RESERVE_MS)
  ) {
    const linkedPages = await fetchFallbackPagesFromLinks(socialContent.externalLinks, {
      limit: 1,
      timeoutMs: boundedPreviewTimeout(previewDeadline, PREVIEW_WEB_TIMEOUT_MS, PREVIEW_RESERVE_MS)
    });

    if (linkedPages.length) {
      const linkedFallbackRecipe = await recipeFromFallbackPages(
        linkedPages,
        input.sharedText,
        socialContent?.canonicalUrl || state.resolvedSourceURL,
        true
      );

      if (linkedFallbackRecipe && scoreRecipe(linkedFallbackRecipe.recipe) >= scoreRecipe(recipe)) {
        recipe = linkedFallbackRecipe.recipe;
        importStrategy = "web";
        usedWebFallback = true;
      }
    }
  }

  const captionWasSparse = hasSparseSocialText(
    input.sharedText,
    socialContent?.caption,
    socialContent?.description,
    socialContent?.subtitlesText
  );
  const previewRecipe = applyImportContextNotes(
    {
      ...recipe,
      sourceUrl: recipe.sourceUrl || socialContent?.canonicalUrl || state.resolvedSourceURL,
      remoteImageUrl: recipe.remoteImageUrl || socialContent?.imageUrls[0] || ""
    },
    {
      importStrategy,
      captionWasSparse,
      webSourceUrl: socialContent?.externalLinks[0]
    }
  );

  return finalizePreviewResult(
    previewRecipe,
    {
      startedAt: state.startedAt,
      sourceKind: "url",
      platform: socialContent?.platform,
      strategy: importStrategy,
      usedApify: socialContent?.source === "apify",
      usedTranscription: false,
      usedWebFallback,
      preferWeakMetadataReason: captionWasSparse && !socialContent?.externalLinks.length
    }
  );
}

async function finalizePreviewResult(
  recipe: RecipeImportResult,
  context: {
    startedAt: number;
    sourceKind: "url" | "text" | "photo";
    platform?: string;
    strategy: ImportStrategy;
    usedApify: boolean;
    usedTranscription: boolean;
    usedWebFallback: boolean;
    preferWeakMetadataReason: boolean;
  }
): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const finalizedRecipe = await finalizeImportedRecipe(recipe, {
    skipNutrition: true
  });
  const durationMs = Date.now() - context.startedAt;
  const debug = buildImportDebug(finalizedRecipe.recipe, {
    platform: context.platform,
    sourceKind: context.sourceKind,
    strategy: context.strategy,
    durationMs,
    usedApify: context.usedApify,
    usedTranscription: context.usedTranscription,
    usedWebFallback: context.usedWebFallback,
    usedUsda: false,
    nutritionCoverage: 0,
    matchedNutritionIngredients: 0,
    preferWeakMetadataReason: context.preferWeakMetadataReason,
    timedOut: durationMs > PREVIEW_TOTAL_LIMIT_MS
  });

  logImportDebug(finalizedRecipe.recipe, debug);
  console.info(
    `[importService] URL import completed in ${durationMs}ms` +
    ` (preview=true strategy=${context.strategy} transcript=${context.usedTranscription} webFallback=${context.usedWebFallback} usda=false) for ${finalizedRecipe.recipe.sourceUrl || "(unknown)"}`
  );

  return {
    recipe: finalizedRecipe.recipe,
    debug
  };
}

async function fetchFallbackPagesFromLinks(
  urls: string[],
  options?: {
    limit?: number;
    timeoutMs?: number;
  }
): Promise<Array<{
  url: string;
  title?: string;
  description?: string;
  textContent?: string;
  structuredDataBlocks: string[];
  imageUrl?: string;
}>> {
  const pages = await Promise.all(
    urls.slice(0, options?.limit ?? 3).map(async (url) => {
      try {
        return await fetchPageSummary(url, {
          timeoutMs: options?.timeoutMs
        });
      } catch {
        return null;
      }
    })
  );

  return pages.filter((page): page is NonNullable<typeof page> => Boolean(page));
}

function buildUrlNormalizationContext(input: {
  canonicalSourceURL: string;
  sharedText?: string;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  transcript?: string | null;
  fallbackPages?: ImportedPageSummary[];
}) {
  const fallbackPages = input.fallbackPages ?? [];
  const combinedPages = [
    ...fallbackPages,
    ...(input.pageSummary ? [input.pageSummary] : [])
  ];

  return {
    mode: "url" as const,
    sourceUrl: input.canonicalSourceURL,
    remoteImageUrl: input.socialContent?.imageUrls[0] ??
      fallbackPages.map((page) => page.imageUrl).find(Boolean) ??
      input.pageSummary?.imageUrl,
    sharedText: input.sharedText,
    pageTitle: preferredPageValue(fallbackPages, "title") ?? input.pageSummary?.title,
    pageDescription: preferredPageValue(fallbackPages, "description") ?? input.pageSummary?.description,
    pageTextContent: combinedPages
      .map((page) => page.textContent?.trim())
      .filter((value): value is string => Boolean(value))
      .join("\n\n"),
    pageStructuredData: combinedPages.flatMap((page) => page.structuredDataBlocks ?? []),
    socialTitle: input.socialContent?.title,
    socialCaption: input.socialContent?.caption,
    socialDescription: input.socialContent?.description,
    socialPageText: input.socialContent?.pageText,
    socialAuthor: input.socialContent?.authorName,
    socialSubtitles: input.socialContent?.subtitlesText,
    transcript: input.transcript ?? undefined
  };
}

function recipeFromContext(
  context: ReturnType<typeof buildUrlNormalizationContext>
): RecipeImportResult {
  return preferStructuredRecipe(
    fallbackRecipeFromContext(context),
    structuredRecipeFromBlocks(context.pageStructuredData ?? [])
  );
}

function preferredPageValue(
  pages: ImportedPageSummary[],
  key: "title" | "description"
): string | undefined {
  return pages
    .map((page) => page[key]?.trim())
    .find((value): value is string => Boolean(value));
}

function mergeFallbackPages(
  currentPages: ImportedPageSummary[],
  newPages: ImportedPageSummary[]
): ImportedPageSummary[] {
  const mergedPages = [...currentPages];
  const seen = new Set(currentPages.map((page) => page.url));

  for (const page of newPages) {
    if (seen.has(page.url)) {
      continue;
    }

    seen.add(page.url);
    mergedPages.push(page);
  }

  return mergedPages;
}

async function recipeFromFallbackPages(
  pages: ImportedPageSummary[],
  sharedText: string | undefined,
  sourceUrl: string,
  previewMode = false
): Promise<{ recipe: RecipeImportResult; sourceUrl?: string } | null> {
  if (!pages.length) {
    return null;
  }

  const baseContext = {
    mode: "url",
    sourceUrl,
    remoteImageUrl: pages.map((page) => page.imageUrl).find(Boolean),
    sharedText,
    pageTitle: pages.map((page) => page.title).find(Boolean),
    pageDescription: pages.map((page) => page.description).find(Boolean),
    pageTextContent: pages.map((page) => page.textContent).filter(Boolean).join("\n\n"),
    pageStructuredData: pages.flatMap((page) => page.structuredDataBlocks)
  } as const;
  const fallbackStructuredRecipe = structuredRecipeFromBlocks(
    pages.flatMap((page) => page.structuredDataBlocks)
  );
  let normalizedFallbackRecipe = preferStructuredRecipe(
    fallbackRecipeFromContext(baseContext),
    fallbackStructuredRecipe
  );

  if (!previewMode) {
    const fallbackRecipe = await safeNormalize(baseContext, previewMode);
    normalizedFallbackRecipe = preferStructuredRecipe(fallbackRecipe, fallbackStructuredRecipe);
  }

  return {
    recipe: normalizedFallbackRecipe,
    sourceUrl: pages[0]?.url
  };
}

function bestSearchQuery(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
}): string {
  const candidates = [
    input.recipe.searchQuery,
    nonGenericSearchCandidate(input.socialContent?.caption),
    nonGenericSearchCandidate(input.sharedText),
    nonGenericSearchCandidate(input.socialContent?.description),
    nonGenericSearchCandidate(input.pageSummary?.description),
    nonGenericSearchCandidate(input.pageSummary?.title),
    nonGenericSearchCandidate(input.recipe.title)
  ];

  return candidates.find((value): value is string => Boolean(value)) ?? "";
}

function nonGenericSearchCandidate(value?: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) {
    return undefined;
  }

  const normalized = trimmed
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();

  if (
    normalized === "tiktok - make your day" ||
    normalized === "make your day" ||
    normalized === "tiktok"
  ) {
    return undefined;
  }

  const lines = trimmed
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);
  const narrativeLine = lines.find((line) =>
    !line.startsWith("#") &&
    !/^(?:[-•*]|\d+[.)-])/.test(line) &&
    line.length >= 6 &&
    !line.toLowerCase().includes("http")
  );

  if (narrativeLine) {
    return narrativeLine.slice(0, 120).trim();
  }

  const ingredientWords = lines
    .slice(0, 6)
    .map((line) => line
      .replace(/^(?:[-•*]|\d+[.)-])\s*/g, "")
      .replace(/\b\d+(?:[.,/]\d+)?\s*(?:g|kg|ml|cl|l|cas|cac|cuill[eè]re?s?|tablespoons?|teaspoons?|cups?)\b/gi, "")
      .replace(/[^\p{L}\p{N}\s-]/gu, " ")
      .replace(/\s+/g, " ")
      .trim()
    )
    .filter(Boolean);

  if (ingredientWords.length) {
    return ingredientWords.join(" ").slice(0, 120).trim();
  }

  return trimmed.slice(0, 120).trim();
}

function shouldAttemptFinalNormalization(input: {
  recipe: RecipeImportResult;
  sourcePlatform: ReturnType<typeof platformFromUrl>;
  context: ReturnType<typeof buildUrlNormalizationContext>;
  transcript: string | null;
  fallbackPages: ImportedPageSummary[];
}): boolean {
  if (shouldTrustFastSocialRecipe(input.recipe, input.sourcePlatform)) {
    return false;
  }

  if (input.transcript) {
    return true;
  }

  if (input.fallbackPages.length) {
    return true;
  }

  const combinedText = [
    input.context.sharedText,
    input.context.socialCaption,
    input.context.socialDescription,
    input.context.socialSubtitles,
    input.context.socialPageText,
    input.context.pageDescription,
    input.context.pageTextContent
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n")
    .trim();

  if (combinedText.length < 160) {
    return false;
  }

  if (looksMostlyIngredientText(combinedText) && input.recipe.stepDrafts.length == 0) {
    return false;
  }

  return true;
}

function looksMostlyIngredientText(text: string): boolean {
  const lines = text
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (lines.length < 3) {
    return false;
  }

  const ingredientLikeLines = lines.filter((line) =>
    /^[-•*]?\s*\d+(?:[.,/]\d+)?\s*(?:g|kg|ml|cl|l|cas|cac|cuill[eè]re?s?|tablespoons?|teaspoons?|cups?)?/i.test(line) ||
    /^[-•*]\s*/.test(line) ||
    line.split(/\s+/).length <= 6
  );

  return ingredientLikeLines.length / lines.length >= 0.7;
}

function buildImportDebug(
  recipe: RecipeImportResult,
  context: {
    platform?: string;
    sourceKind: "url" | "text" | "photo";
    strategy: ImportStrategy;
    durationMs: number;
    usedApify: boolean;
    usedTranscription: boolean;
    usedWebFallback: boolean;
    usedUsda?: boolean;
    nutritionCoverage?: number;
    matchedNutritionIngredients?: number;
    preferWeakMetadataReason: boolean;
    timedOut?: boolean;
  }
): ImportDebug {
  const missing = importMissingParts(recipe);
  const isLikelyValid = isLikelyValidRecipe(recipe);
  const failureReason = isLikelyValid
    ? undefined
    : importFailureReason(recipe, {
      preferWeakMetadata: context.preferWeakMetadataReason,
      timedOut: context.timedOut
    });

  return {
    platform: context.platform,
    usedApify: context.usedApify,
    usedTranscription: context.usedTranscription,
    usedWebFallback: context.usedWebFallback,
    usedUsda: context.usedUsda,
    nutritionCoverage: context.nutritionCoverage,
    matchedNutritionIngredients: context.matchedNutritionIngredients,
    sourceKind: context.sourceKind,
    ingredientsCount: recipe.ingredientDrafts.length,
    stepsCount: recipe.stepDrafts.length,
    strategy: context.strategy,
    durationMs: context.durationMs,
    isLikelyValid,
    missing,
    failureReason
  };
}

function logImportDebug(recipe: RecipeImportResult, debug: ImportDebug) {
  const missing = debug.missing.length ? debug.missing.join(",") : "none";
  const failureReason = debug.failureReason ?? "none";
  console.info(
    [
      "[IMPORT DEBUG]",
      `title=${recipe.title || "(empty)"}`,
      `ingredients=${debug.ingredientsCount}`,
      `steps=${debug.stepsCount}`,
      `hasTranscript=${debug.usedTranscription}`,
      `strategy=${debug.strategy}`,
      `duration=${debug.durationMs}ms`,
      `validCandidate=${debug.isLikelyValid}`,
      `missing=${missing}`,
      `failureReason=${failureReason}`
    ].join("\n")
  );
}

function hasPreviewBudget(deadline: number, reserveMs = 0): boolean {
  return boundedPreviewTimeout(deadline, Number.MAX_SAFE_INTEGER, reserveMs) != null;
}

function boundedPreviewTimeout(
  deadline: number,
  desiredMs: number,
  reserveMs = 0
): number | undefined {
  const remainingMs = deadline - Date.now() - reserveMs;
  if (remainingMs <= 0) {
    return undefined;
  }

  return Math.max(250, Math.min(desiredMs, remainingMs));
}

async function resolveImportSourceURL(url: string, timeoutMs?: number): Promise<string> {
  if (platformFromUrl(url) === "web") {
    return url;
  }

  try {
    const resolvedURL = await resolveRemoteURL(url, { timeoutMs });
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
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const previewMode = options?.previewMode ?? false;
  const startedAt = Date.now();
  const recipe = await safeNormalize({
    mode: "text",
    sharedText: input.text,
    imageDataUrl: input.imageDataUrl
  }, previewMode);
  const finalizedRecipe = await finalizeImportedRecipe(recipe, {
    skipNutrition: previewMode
  });

  const debug = buildImportDebug(finalizedRecipe.recipe, {
    sourceKind: "text",
    strategy: "text",
    durationMs: Date.now() - startedAt,
    usedApify: false,
    usedTranscription: false,
    usedWebFallback: false,
    usedUsda: finalizedRecipe.usedUsda,
    nutritionCoverage: finalizedRecipe.nutritionCoverage,
    matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
    preferWeakMetadataReason: false
  });
  logImportDebug(finalizedRecipe.recipe, debug);

  return {
    recipe: finalizedRecipe.recipe,
    debug
  };
}

export async function importFromPhoto(input: {
  imageDataUrl: string;
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const previewMode = options?.previewMode ?? false;
  const startedAt = Date.now();
  const recipe = await safeNormalize({
    mode: "photo",
    imageDataUrl: input.imageDataUrl
  }, previewMode);
  const finalizedRecipe = await finalizeImportedRecipe(recipe, {
    skipNutrition: previewMode
  });

  const debug = buildImportDebug(finalizedRecipe.recipe, {
    sourceKind: "photo",
    strategy: "photo",
    durationMs: Date.now() - startedAt,
    usedApify: false,
    usedTranscription: false,
    usedWebFallback: false,
    usedUsda: finalizedRecipe.usedUsda,
    nutritionCoverage: finalizedRecipe.nutritionCoverage,
    matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
    preferWeakMetadataReason: false
  });
  logImportDebug(finalizedRecipe.recipe, debug);

  return {
    recipe: finalizedRecipe.recipe,
    debug
  };
}

async function safeNormalize(
  input: Parameters<typeof normalizeRecipeFromContext>[0],
  previewMode = false
): Promise<RecipeImportResult> {
  try {
    return await normalizeRecipeFromContext(input, {
      timeoutMs: previewMode ? 8_000 : 60_000
    });
  } catch (error) {
    if (isOpenAIUnavailable(error) || isTimeoutLikeError(error)) {
      return fallbackRecipeFromContext(input);
    }

    throw error;
  }
}

async function finalizeImportedRecipe(
  recipe: RecipeImportResult,
  options?: {
    skipNutrition?: boolean;
  }
) {
  const sanitizedRecipe = sanitizeRecipeImport(recipe);
  if (options?.skipNutrition) {
    return {
      recipe: sanitizedRecipe,
      usedUsda: false,
      nutritionCoverage: 0,
      matchedIngredients: 0
    };
  }
  const nutritionResult = await enrichRecipeNutrition(sanitizedRecipe);

  return {
    ...nutritionResult,
    recipe: sanitizeRecipeImport(nutritionResult.recipe)
  };
}

function transcriptionOptions(previewMode: boolean) {
  if (!previewMode) {
    return undefined;
  }

  return {
    mediaFetchTimeoutMs: 10_000,
    transcriptionTimeoutMs: 15_000,
    maxDurationSeconds: 75,
    maxFileBytes: 12 * 1024 * 1024
  };
}

function isTimeoutLikeError(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return message.includes("timeout") ||
    message.includes("timed out") ||
    message.includes("aborted") ||
    message.includes("aborterror");
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
