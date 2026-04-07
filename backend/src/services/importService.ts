import { fetchPageSummary, resolveRemoteURL } from "./generalPageService.js";
import {
  normalizeRecipeFromContext,
  reviewRecipeCookability,
  transcribeMediaFromUrl
} from "./openAIService.js";
import { fetchFallbackPages } from "./searchFallbackService.js";
import { resolveSocialContent } from "./socialContentService.js";
import { enrichRecipePresentationMetadata } from "./recipeMetadataService.js";
import {
  fallbackRecipeFromContext,
  isOpenAIUnavailable,
  strictRecipeFromContext,
  structuredRecipeFromBlocks
} from "./heuristicRecipeService.js";
import { enrichRecipeNutrition } from "./usdaNutritionService.js";
import {
  containsLikelyFoodTitleTerm,
  hasMeaningfulFoodSignal,
  hasCookabilityGaps,
  hasSuspiciousRecipeTitle,
  importFailureReason,
  importMissingParts,
  isLikelyMajorIngredient,
  isLikelyValidRecipe,
  normalizeRecipeImportFlags,
  normalizeLookup,
  recipeCookabilitySignals,
  sanitizeRecipeImport,
  scoreRecipe,
  shouldFallbackToSearch,
  type ImportDebug,
  type RecipeImportResult
} from "../types/recipe.js";
import { platformFromUrl } from "../utils/text.js";

type ImportExecutionOptions = {
  previewMode?: boolean;
  sharedMode?: boolean;
};

type ImportRuntimeProfile = "preview" | "shared" | "full";
type ImportStrategy = "social" | "web" | "fallback" | "audio" | "text" | "photo";
type ImportedPageSummary = {
  url: string;
  title?: string;
  description?: string;
  textContent?: string;
  structuredDataBlocks: string[];
  imageUrl?: string;
};

export class RecipeImportNotFoodError extends Error {
  readonly error = "not_food";
  readonly reason = "no_food_detected";

  constructor() {
    super("not_food");
    this.name = "RecipeImportNotFoodError";
  }
}

const PREVIEW_TOTAL_LIMIT_MS = 9_000;
const PREVIEW_RESOLVE_TIMEOUT_MS = 2_500;
const PREVIEW_SOCIAL_TIMEOUT_MS = 4_500;
const PREVIEW_WEB_TIMEOUT_MS = 2_000;
const PREVIEW_RESERVE_MS = 700;
const SHARED_TOTAL_LIMIT_MS = 75_000;
const SHARED_RESOLVE_TIMEOUT_MS = 2_500;
const SHARED_SOCIAL_TIMEOUT_MS = 5_000;
const SHARED_SOCIAL_NORMALIZE_TIMEOUT_MS = 12_000;
const SHARED_APIFY_TIMEOUT_MS = 45_000;
const SHARED_AUDIO_FETCH_TIMEOUT_MS = 8_000;
const SHARED_AUDIO_TRANSCRIPTION_TIMEOUT_MS = 12_000;
const SHARED_AUDIO_MAX_DURATION_SECONDS = 75;
const SHARED_WEB_TIMEOUT_MS = 5_000;
const SHARED_RESERVE_MS = 1_200;
const FULL_TOTAL_LIMIT_MS = 120_000;

export async function importFromUrl(input: {
  url: string;
  sharedText?: string;
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const profile = runtimeProfile(options);
  const previewMode = profile === "preview";
  const sharedMode = profile === "shared";
  const startedAt = Date.now();
  const executionDeadline = deadlineForProfile(profile, startedAt);
  const sharedTextRecipe = recipeFromContext(
    buildUrlNormalizationContext({
      canonicalSourceURL: input.url,
      sharedText: input.sharedText,
      pageSummary: null,
      socialContent: null
    })
  );

  if (shouldTrustSharedTextRecipe(sharedTextRecipe, input.sharedText)) {
    const sharedTextContext = buildUrlNormalizationContext({
      canonicalSourceURL: input.url,
      sharedText: input.sharedText,
      pageSummary: null,
      socialContent: null
    });
    const sharedTextBaseRecipe = {
      ...sharedTextRecipe,
      sourceUrl: sharedTextRecipe.sourceUrl || input.url
    };
    const reviewedSharedTextRecipe = await maybeReviewRecipeCookability(
      sharedTextBaseRecipe,
      sharedTextContext,
      profile,
      executionDeadline,
      "shared-text"
    );
    const strictSharedTextRecipe = requireStrictRecipe(reviewedSharedTextRecipe, sharedTextContext);
    const finalizedRecipe = await finalizeImportedRecipe(strictSharedTextRecipe, {
      skipNutrition: false
    });
    const durationMs = Date.now() - startedAt;
    const debug = buildImportDebug(finalizedRecipe.recipe, {
      sourceKind: "url",
      strategy: "text",
      durationMs,
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: false,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      preferWeakMetadataReason: false
    });

    logImportDebug(finalizedRecipe.recipe, debug);
    console.info(
      `[importService] URL import completed in ${durationMs}ms` +
      ` (preview=${previewMode} strategy=text transcript=false webFallback=false usda=${finalizedRecipe.usedUsda}) for ${input.url}`
    );

    return {
      recipe: finalizedRecipe.recipe,
      debug
    };
  }

  const resolvedSourceURL = await resolveImportSourceURL(
    input.url,
    input.sharedText,
    previewMode
      ? PREVIEW_RESOLVE_TIMEOUT_MS
      : boundedExecutionTimeout(executionDeadline, SHARED_RESOLVE_TIMEOUT_MS)
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
  const socialTimeoutMs = sourcePlatform === "web"
    ? undefined
    : boundedExecutionTimeout(
      executionDeadline,
      sharedMode ? SHARED_SOCIAL_TIMEOUT_MS : undefined
    );
  const [pageSummary, socialContent] = await Promise.all([
    sourcePlatform === "web"
      ? fetchPageSummary(
        resolvedSourceURL,
        sharedMode
          ? { timeoutMs: boundedExecutionTimeout(executionDeadline, SHARED_WEB_TIMEOUT_MS, SHARED_RESERVE_MS) }
          : undefined
      ).catch(() => null)
      : Promise.resolve(null),
    sourcePlatform === "web"
      ? Promise.resolve(null)
      : resolveSocialContent(resolvedSourceURL, {
        ...initialSocialContentOptions,
        timeoutMs: socialTimeoutMs
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
  }) && hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)) {
    console.info(`[importService] Trying social text normalization for ${canonicalSourceURL}`);
    const socialContext = buildContext();
    const socialNormalizedRecipe = preferStructuredRecipe(
      await safeNormalize(socialContext, {
        timeoutMs: normalizationTimeoutForProfile(profile, executionDeadline)
      }),
      structuredRecipeFromBlocks(socialContext.pageStructuredData ?? [])
    );

    normalizedFromSocialText = true;
    if (shouldPreferRecipeCandidate(recipe, socialNormalizedRecipe)) {
      recipe = socialNormalizedRecipe;
    }
  }

  if (
    shouldFetchFullSocialSnapshot({
      recipe,
      sourcePlatform,
      sourceURL: resolvedSourceURL,
      socialContent: resolvedSocialContent,
      mediaURL,
      sharedText: input.sharedText
    }) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    const enrichedSocialContent = await resolveSocialContent(resolvedSourceURL, {
      preferDirectFetch: sourcePlatform === "tiktok",
      timeoutMs: boundedExecutionTimeout(
        executionDeadline,
        sharedMode ? SHARED_APIFY_TIMEOUT_MS : 18_000,
        sharedMode ? SHARED_RESERVE_MS : 0
      )
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

  if (shouldUseTranscriptionFallback(recipe, resolvedSocialContent, input.sharedText, mediaURL) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    console.info(`[importService] Attempting audio transcription for ${canonicalSourceURL}`);
    const audioOptions = transcriptionOptions(profile, executionDeadline);
    if (audioOptions != null) {
      transcript = await transcribeMediaFromUrl(mediaURL, audioOptions).catch(() => null);
    }

    if (isUsableTranscript(transcript)) {
      transcript = truncateTranscript(transcript);
      console.info(
        `[importService] Usable transcript obtained (${transcript.length} chars) for ${canonicalSourceURL}`
      );
      const audioContext = buildContext();
      let audioRecipe = recipeFromContext(audioContext);
      if (shouldAttemptTranscriptNormalization(audioRecipe, audioContext)) {
        audioRecipe = preferStructuredRecipe(
          await safeNormalize(audioContext, {
            timeoutMs: normalizationTimeoutForProfile(profile, executionDeadline, 10_000)
          }),
          structuredRecipeFromBlocks(audioContext.pageStructuredData ?? [])
        );
        normalizedAfterTranscript = true;
      }
      if (shouldPreferRecipeCandidate(recipe, audioRecipe)) {
        recipe = audioRecipe;
        importStrategy = "audio";
        importStrategySourceURL = undefined;
      } else {
        // Transcript enriches the final normalization/review pass even when
        // the audio-only recipe didn't outscore the caption-based one.
        normalizedAfterTranscript = false;
      }
    } else {
      const rawTranscript = transcript as string | null;
      if (rawTranscript) {
        console.info(
          `[importService] Transcript discarded (low quality, ${rawTranscript.length} chars) for ${canonicalSourceURL}`
        );
      }
      transcript = null;
    }
  }

  recipe = attemptDishRescue(recipe, buildContext());

  if (
    resolvedSocialContent?.externalLinks.length &&
    shouldTryLinkedWebFallback(recipe, resolvedSocialContent.externalLinks) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    const linkedPages = await fetchFallbackPagesFromLinks(
      resolvedSocialContent.externalLinks,
      sharedMode
        ? {
          timeoutMs: boundedExecutionTimeout(executionDeadline, SHARED_WEB_TIMEOUT_MS, SHARED_RESERVE_MS)
        }
        : undefined
    );
    if (linkedPages.length) {
      fallbackPages = mergeFallbackPages(fallbackPages, linkedPages);
      const linkedFallbackRecipe = await recipeFromFallbackPages(
        linkedPages,
        input.sharedText,
        canonicalSourceURL,
        {
          previewMode: false,
          normalizationTimeoutMs: normalizationTimeoutForProfile(profile, executionDeadline, 8_000)
        }
      );

      if (linkedFallbackRecipe && shouldPreferRecipeCandidate(recipe, linkedFallbackRecipe.recipe)) {
        recipe = linkedFallbackRecipe.recipe;
        usedWebFallback = true;
        importStrategy = "web";
        importStrategySourceURL = linkedFallbackRecipe.sourceUrl ?? linkedPages[0]?.url;
        normalizedFromWebFallback = true;
      }
    }
  }

  if (
    shouldAttemptSearchEnrichment({
      recipe,
      sourcePlatform,
      captionWasSparse,
      hasTranscript: Boolean(transcript),
      transcript: transcript ?? undefined
    }) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    const queries = searchQueryCandidates({
      recipe,
      pageSummary,
      socialContent: resolvedSocialContent,
      sharedText: input.sharedText,
      transcript
    }).slice(0, 4);

    if (queries.length) {
      console.info(`[importService] Trying search fallback queries for ${canonicalSourceURL}: ${queries.join(" | ")}`);
    }

    for (const query of queries) {
      let searchPages: Awaited<ReturnType<typeof fetchFallbackPages>>;
      try {
        searchPages = await fetchFallbackPages(
          query,
          sharedMode
            ? { timeoutMs: boundedExecutionTimeout(executionDeadline, SHARED_WEB_TIMEOUT_MS, SHARED_RESERVE_MS) }
            : undefined
        );
      } catch {
        continue;
      }

      if (!searchPages.length) {
        continue;
      }

      fallbackPages = mergeFallbackPages(fallbackPages, searchPages);
      if (fallbackPages.length >= 4) {
        break;
      }
    }

    if (fallbackPages.length) {
      const searchFallbackRecipe = await recipeFromFallbackPages(
        fallbackPages,
        input.sharedText,
        canonicalSourceURL,
        {
          previewMode: false,
          normalizationTimeoutMs: normalizationTimeoutForProfile(profile, executionDeadline, 8_000)
        }
      );

      if (searchFallbackRecipe && shouldPreferRecipeCandidate(recipe, searchFallbackRecipe.recipe)) {
        recipe = searchFallbackRecipe.recipe;
        importStrategy = "fallback";
        importStrategySourceURL = searchFallbackRecipe.sourceUrl ?? fallbackPages[0]?.url;
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
    }) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    const normalizedContext = buildContext();
    const normalizedRecipe = preferStructuredRecipe(
      await safeNormalize(normalizedContext, {
        timeoutMs: normalizationTimeoutForProfile(profile, executionDeadline, 10_000)
      }),
      structuredRecipeFromBlocks(normalizedContext.pageStructuredData ?? [])
    );

    if (shouldPreferRecipeCandidate(recipe, normalizedRecipe)) {
      recipe = normalizedRecipe;
    }
  } else if (!shouldTrustFastSocialRecipe(recipe, sourcePlatform)) {
    console.info(
      `[importService] Skipping final normalization for thin context on ${canonicalSourceURL}`
    );
  }

  recipe = attemptDishRescue(recipe, buildContext());

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

  const reviewedRecipe = await maybeReviewRecipeCookability(
    recipeWithImportContext,
    buildContext(),
    profile,
    executionDeadline,
    importStrategy
  );
  const strictRecipe = requireStrictRecipe(reviewedRecipe, buildContext());
  const validatedRecipe = await enforceRecipeValidation(
    strictRecipe,
    buildContext(),
    executionDeadline
  );
  const finalizedRecipe = await finalizeImportedRecipe(validatedRecipe, {
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
    preferWeakMetadataReason: sourcePlatform !== "web" && captionWasSparse,
    transcript: transcript ?? undefined
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
  _recipe: RecipeImportResult,
  _socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null,
  _sharedText: string | undefined,
  mediaURL?: string
): boolean {
  // Always attempt transcription when a media URL is available.
  // Quality is validated after transcription via isUsableTranscript();
  // empty or low-quality transcripts are discarded before they reach
  // the LLM context.
  return Boolean(mediaURL);
}

const TRANSCRIPT_MAX_LENGTH = 4000;

/**
 * Validates that a transcript contains enough meaningful spoken content
 * to be useful context for recipe generation. Discards transcripts that
 * are empty, too short, music-only, or contain no real word content.
 */
function isUsableTranscript(transcript: string | null): transcript is string {
  if (!transcript) {
    return false;
  }

  const trimmed = transcript.trim();

  // Too short to contain any useful information at all
  if (trimmed.length < 15) {
    return false;
  }

  // Strip Whisper artifacts like [Music], (applause), etc.
  const cleanedOfBrackets = trimmed
    .replace(/\[.*?\]/g, "")
    .replace(/\(.*?\)/g, "")
    .trim();

  // After stripping brackets, nothing useful remains
  if (!cleanedOfBrackets || cleanedOfBrackets.length < 10) {
    return false;
  }

  // Count actual word tokens (not just noise characters)
  const wordCount = cleanedOfBrackets
    .split(/\s+/)
    .filter((w) => w.length >= 2)
    .length;

  // Accept short transcripts (3+ words) that contain food-related terms
  if (wordCount >= 3 && containsLikelyFoodTitleTerm(normalizeLookup(cleanedOfBrackets))) {
    return true;
  }

  // General threshold: need enough spoken content to be useful
  if (wordCount < 4) {
    return false;
  }

  return true;
}

/**
 * Truncates transcript to a safe length before sending to LLM to prevent
 * excessive cost and latency. Preserves complete sentences where possible.
 */
function truncateTranscript(transcript: string): string {
  if (transcript.length <= TRANSCRIPT_MAX_LENGTH) {
    return transcript;
  }

  // Cut at the last sentence boundary within the limit
  const truncated = transcript.slice(0, TRANSCRIPT_MAX_LENGTH);
  const lastSentenceEnd = Math.max(
    truncated.lastIndexOf(". "),
    truncated.lastIndexOf("! "),
    truncated.lastIndexOf("? ")
  );

  if (lastSentenceEnd > TRANSCRIPT_MAX_LENGTH * 0.6) {
    return truncated.slice(0, lastSentenceEnd + 1).trim();
  }

  return truncated.trim();
}

type RecipeIssueReport = {
  hasIssues: boolean;
  unusedIngredients: string[];
  logicalOrderIssue: boolean;
  summary: string;
  issueCount: number;
};

/**
 * Detects recipe quality issues: unused ingredients, ingredients missing
 * from steps, and illogical cooking sequences (cook-before-prep).
 *
 * Ingredient matching handles plural forms and slight variations using
 * stem-based comparison (e.g. chicken/chickens, tomato/tomatoes).
 */
function detectRecipeIssues(recipe: RecipeImportResult): RecipeIssueReport {
  const stepText = recipe.stepDrafts
    .map((s) => s.detail)
    .join(" ");
  const normalizedStepText = normalizeForIngredientMatching(stepText);

  // 1. Find unused major ingredients (not mentioned in any step)
  const unusedIngredients: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    if (!isLikelyMajorIngredient(ingredient.name)) {
      continue;
    }

    const tokens = ingredientLookupTokens(ingredient.name);
    const isUsed = tokens.some((token) =>
      normalizedStepText.includes(token) ||
      normalizedStepText.includes(stemToken(token))
    );

    if (!isUsed) {
      unusedIngredients.push(ingredient.name);
    }
  }

  // 2. Check for cook-before-prep logical sequence issues
  const stepDetails = recipe.stepDrafts.map((s) => s.detail);
  const hasCookBeforePrep = stepDetails.length >= 3 &&
    stepDetails.slice(0, 1).some((s) =>
      /\b(?:cuire|cuisson|frire|griller|rôtir|bake|fry|grill|roast|sear|saisir)\b/i.test(s)
    ) &&
    stepDetails.slice(2).some((s) =>
      /\b(?:couper|émincer|peler|laver|préparer|éplucher|cut|chop|peel|wash|prepare|dice|mince)\b/i.test(s)
    );

  const cookability = recipeCookabilitySignals(recipe);
  const hasUncoveredIngredients = cookability.uncoveredMajorIngredientCount >= 2;

  const hasIssues = unusedIngredients.length > 0 ||
    hasUncoveredIngredients ||
    hasCookBeforePrep;

  const parts: string[] = [];
  if (unusedIngredients.length) {
    parts.push(`${unusedIngredients.length} unused ingredients`);
  }
  if (hasUncoveredIngredients) {
    parts.push(`${cookability.uncoveredMajorIngredientCount} uncovered in steps`);
  }
  if (hasCookBeforePrep) {
    parts.push("cook-before-prep detected");
  }

  return {
    hasIssues,
    unusedIngredients,
    logicalOrderIssue: hasCookBeforePrep,
    summary: parts.join(", ") || "none",
    issueCount: unusedIngredients.length +
      (hasUncoveredIngredients ? cookability.uncoveredMajorIngredientCount : 0) +
      (hasCookBeforePrep ? 1 : 0)
  };
}

/**
 * Normalizes text for ingredient matching by stripping accents, lowering
 * case, and removing punctuation.
 */
function normalizeForIngredientMatching(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Builds lookup tokens for an ingredient name, handling plural forms
 * and slight variations (chicken→chickens, tomato→tomatoes).
 * Returns both the singular stem and the original token for matching.
 */
function ingredientLookupTokens(name: string): string[] {
  const normalized = normalizeForIngredientMatching(name);
  const rawTokens = normalized
    .split(/[\s,/-]+/)
    .filter((t) => t.length >= 3);

  const result = new Set<string>();
  for (const token of rawTokens) {
    result.add(token);
    result.add(stemToken(token));

    // Also add common plural forms so we match in both directions
    if (!token.endsWith("s")) {
      result.add(`${token}s`);
    }
    if (!token.endsWith("es")) {
      result.add(`${token}es`);
    }
  }

  return Array.from(result).filter((t) => t.length >= 3);
}

/**
 * Simple stemming: strips common French and English plural suffixes
 * to enable matching across singular/plural forms.
 */
function stemToken(token: string): string {
  // French/English plural patterns in order of specificity
  if (token.endsWith("ies") && token.length > 4) {
    return token.slice(0, -3) + "y";
  }
  if (token.endsWith("aux") && token.length > 4) {
    return token.slice(0, -3) + "al";
  }
  if (token.endsWith("eaux") && token.length > 5) {
    return token.slice(0, -4) + "eau";
  }
  if (token.endsWith("es") && token.length > 4) {
    return token.slice(0, -2);
  }
  if (token.endsWith("s") && token.length > 3) {
    return token.slice(0, -1);
  }

  return token;
}

/**
 * Mandatory validation gate. Ensures three invariants before a recipe
 * is returned:
 *   1. Every major ingredient is referenced in at least one step
 *   2. No step references ingredients missing from the ingredient list
 *   3. Steps follow a logical cooking sequence (prep → cook → assemble)
 *
 * If validation fails:
 *   - First attempt: auto-correct via reviewRecipeCookability()
 *   - Second attempt: regenerate via normalizeRecipeFromContext()
 *   - Final fallback: structural fix via ensureCookableRecipeStructure()
 *
 * This function MUST be called before finalizeImportedRecipe().
 */
async function enforceRecipeValidation(
  recipe: RecipeImportResult,
  context: Parameters<typeof normalizeRecipeFromContext>[0],
  deadline: number | undefined
): Promise<RecipeImportResult> {
  const issues = detectRecipeIssues(recipe);

  if (!issues.hasIssues) {
    return recipe;
  }

  console.info(
    `[importService] Validation failed (${issues.summary}), auto-correcting via cookability review`
  );

  // --- Attempt 1: Auto-correct via LLM cookability review ---
  const reviewTimeoutMs = boundedExecutionTimeout(deadline, 12_000, 1_000);
  if (reviewTimeoutMs) {
    const corrected = await safeReviewCookability(
      { draft: recipe, context },
      { timeoutMs: reviewTimeoutMs }
    );
    const correctedIssues = detectRecipeIssues(corrected);
    if (!correctedIssues.hasIssues) {
      return corrected;
    }

    // Check if correction at least improved things
    if (correctedIssues.issueCount < issues.issueCount) {
      return corrected;
    }
  }

  // --- Attempt 2: Full regeneration via normalizeRecipeFromContext ---
  console.info(
    `[importService] Cookability review insufficient, regenerating recipe via normalization`
  );
  const normalizeTimeoutMs = boundedExecutionTimeout(deadline, 12_000, 1_000);
  if (normalizeTimeoutMs) {
    const regenerated = await safeNormalize(context, {
      timeoutMs: normalizeTimeoutMs
    });
    const regeneratedFixed = ensureCookableRecipeStructure(regenerated);
    const regeneratedIssues = detectRecipeIssues(regeneratedFixed);

    if (!regeneratedIssues.hasIssues || regeneratedIssues.issueCount < issues.issueCount) {
      return regeneratedFixed;
    }
  }

  // --- Attempt 3: Last-resort structural fix ---
  console.info(
    `[importService] Regeneration insufficient, applying structural fix as last resort`
  );
  return ensureCookableRecipeStructure(recipe);
}

function shouldFetchFullSocialSnapshot(input: {
  recipe: RecipeImportResult;
  sourcePlatform: ReturnType<typeof platformFromUrl>;
  sourceURL: string;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  mediaURL?: string;
  sharedText?: string;
}): boolean {
  if (input.sourcePlatform !== "tiktok") {
    return false;
  }

  if (isTikTokShortURL(input.sourceURL)) {
    return false;
  }

  if (!input.socialContent) {
    return true;
  }

  if (input.socialContent.source === "apify") {
    return false;
  }

  if (hasSparseSocialText(
    input.sharedText,
    input.socialContent.caption,
    input.socialContent.description,
    input.socialContent.subtitlesText,
    input.socialContent.pageText
  )) {
    return true;
  }

  if (input.socialContent.externalLinks.length > 0 && input.recipe.stepDrafts.length >= 2) {
    return false;
  }

  return input.recipe.stepDrafts.length < 2 ||
    input.recipe.ingredientDrafts.length < 3 ||
    input.recipe.needsWebFallback;
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
    return Boolean(input.context.remoteImageUrl) &&
      (
        input.recipe.needsWebFallback ||
        input.recipe.ingredientDrafts.length < 3 ||
        input.recipe.stepDrafts.length < 2 ||
        hasSuspiciousRecipeTitle(input.recipe.title)
      );
  }

  return input.recipe.ingredientDrafts.length >= 2 ||
    input.recipe.stepDrafts.length >= 1 ||
    Boolean(input.context.remoteImageUrl) ||
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

  // If text is short but contains a food term, it's still meaningful
  if (combined.length < 50 && combined.length >= 10) {
    return !containsLikelyFoodTitleTerm(normalizeLookup(combined));
  }

  return combined.length < 50;
}

function attemptDishRescue(
  recipe: RecipeImportResult,
  context: Parameters<typeof fallbackRecipeFromContext>[0]
): RecipeImportResult {
  if (!shouldAttemptDishRescue(recipe)) {
    return recipe;
  }

  const cueText = [recipe.searchQuery, recipe.title]
    .map((value) => value.trim())
    .filter(Boolean)
    .join("\n");
  const rescueContext = {
    ...context,
    sharedText: [cueText, context.sharedText]
      .filter((value): value is string => Boolean(value?.trim()))
      .join("\n"),
    pageTitle: context.pageTitle || recipe.title || recipe.searchQuery,
    socialTitle: context.socialTitle || recipe.title || recipe.searchQuery
  };
  const rescuedRecipe = fallbackRecipeFromContext(rescueContext);

  return shouldPreferRecipeCandidate(recipe, rescuedRecipe)
    ? rescuedRecipe
    : recipe;
}

function shouldAttemptDishRescue(recipe: RecipeImportResult): boolean {
  const titleCue = recipe.title.trim() || recipe.searchQuery.trim();
  if (!titleCue) {
    return false;
  }

  return recipe.ingredientDrafts.length < 5 ||
    recipe.stepDrafts.length < 4 ||
    recipe.confidence === "low" ||
    recipe.needsWebFallback ||
    importMissingParts(recipe).length > 0;
}

function shouldAttemptSearchEnrichment(input: {
  recipe: RecipeImportResult;
  sourcePlatform: ReturnType<typeof platformFromUrl>;
  captionWasSparse: boolean;
  hasTranscript?: boolean;
  transcript?: string;
}): boolean {
  if (!hasMeaningfulFoodSignal(input.recipe, { transcript: input.transcript })) {
    // When we have a transcript the video likely contains food content that
    // the heuristic recipe extraction couldn't capture.  Allow search
    // enrichment so we can still find the recipe online.
    if (!input.hasTranscript) {
      return false;
    }
  }

  if (shouldFallbackToSearch(input.recipe)) {
    return true;
  }

  if (input.sourcePlatform === "web" || (!input.captionWasSparse && !input.hasTranscript)) {
    return false;
  }

  const flags = normalizeRecipeImportFlags(input.recipe.flags);
  return input.recipe.ingredientDrafts.length < 7 ||
    input.recipe.stepDrafts.length < 5 ||
    !flags.usedExplicitIngredients ||
    flags.usedInferredIngredients ||
    flags.generatedSteps;
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
      },
      {
        mode: "url",
        sourceUrl: pageSummary?.canonicalUrl ?? pageSummary?.url ?? state.resolvedSourceURL,
        remoteImageUrl: pageSummary?.imageUrl,
        sharedText: input.sharedText,
        pageTitle: pageSummary?.title,
        pageDescription: pageSummary?.description,
        pageTextContent: pageSummary?.textContent,
        pageStructuredData: pageSummary?.structuredDataBlocks
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

      if (shouldPreferRecipeCandidate(recipe, socialRecipe)) {
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
        {
          previewMode: true
        }
      );

      if (linkedFallbackRecipe && shouldPreferRecipeCandidate(recipe, linkedFallbackRecipe.recipe)) {
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
    },
    {
      mode: "url",
      sourceUrl: socialContent?.canonicalUrl || state.resolvedSourceURL,
      remoteImageUrl: socialContent?.imageUrls[0] || "",
      sharedText: input.sharedText,
      socialTitle: socialContent?.title,
      socialCaption: socialContent?.caption,
      socialDescription: socialContent?.description,
      socialPageText: socialContent?.pageText,
      socialAuthor: socialContent?.authorName,
      socialSubtitles: socialContent?.subtitlesText
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
  },
  recipeContext: Parameters<typeof strictRecipeFromContext>[0]
): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const strictRecipe = requireStrictRecipe(recipe, recipeContext);
  const finalizedRecipe = await finalizeImportedRecipe(strictRecipe, {
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
    pageTextContent: combinedPageContextText(combinedPages),
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
  return sanitizeRecipeImport({
    ...preferStructuredRecipe(
      fallbackRecipeFromContext(context),
      structuredRecipeFromBlocks(context.pageStructuredData ?? [])
    ),
    creatorHandle: context.socialAuthor
  });
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
  options?: {
    previewMode?: boolean;
    normalizationTimeoutMs?: number;
  }
): Promise<{ recipe: RecipeImportResult; sourceUrl?: string } | null> {
  if (!pages.length) {
    return null;
  }

  const baseContext = buildFallbackPageContext(pages, sharedText, sourceUrl);
  const fallbackStructuredRecipe = structuredRecipeFromBlocks(
    pages.flatMap((page) => page.structuredDataBlocks)
  );
  let bestRecipe = preferStructuredRecipe(
    fallbackRecipeFromContext(baseContext),
    fallbackStructuredRecipe
  );
  let bestSourceUrl = pages[0]?.url;

  for (const page of pages) {
    const pageContext = buildFallbackPageContext([page], sharedText, page.url);
    const pageStructuredRecipe = structuredRecipeFromBlocks(page.structuredDataBlocks);
    const pageRecipe = preferStructuredRecipe(
      fallbackRecipeFromContext(pageContext),
      pageStructuredRecipe
    );

    if (shouldPreferRecipeCandidate(bestRecipe, pageRecipe)) {
      bestRecipe = pageRecipe;
      bestSourceUrl = page.url;
    }
  }

  if (!options?.previewMode) {
    if (options && options.normalizationTimeoutMs == null) {
      return {
        recipe: bestRecipe,
        sourceUrl: bestSourceUrl
      };
    }

    const fallbackRecipe = await safeNormalize(baseContext, {
      timeoutMs: options?.normalizationTimeoutMs
    });
    const normalizedFallbackRecipe = preferStructuredRecipe(fallbackRecipe, fallbackStructuredRecipe);
    if (shouldPreferRecipeCandidate(bestRecipe, normalizedFallbackRecipe)) {
      bestRecipe = normalizedFallbackRecipe;
      bestSourceUrl = pages[0]?.url;
    }
  }

  return {
    recipe: bestRecipe,
    sourceUrl: bestSourceUrl
  };
}

async function maybeEnrichRecipeFromSearch(
  recipe: RecipeImportResult,
  input: {
    sourcePlatform: ReturnType<typeof platformFromUrl>;
    pageSummary: ImportedPageSummary | null;
    socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
    sharedText?: string;
    transcript?: string | null;
  },
  profile: ImportRuntimeProfile,
  deadline?: number
): Promise<RecipeImportResult> {
  if (!shouldAttemptSearchEnrichment({
    recipe,
    sourcePlatform: input.sourcePlatform,
    captionWasSparse: true
  })) {
    return recipe;
  }

  const timeoutMs = profile === "preview"
    ? boundedPreviewTimeout(deadline ?? Date.now() + PREVIEW_TOTAL_LIMIT_MS, PREVIEW_WEB_TIMEOUT_MS)
    : boundedExecutionTimeout(deadline, SHARED_WEB_TIMEOUT_MS, profile === "shared" ? SHARED_RESERVE_MS : 0);
  if (!timeoutMs) {
    return recipe;
  }

  const queries = searchQueryCandidates({
    recipe,
    pageSummary: input.pageSummary,
    socialContent: input.socialContent,
    sharedText: input.sharedText,
    transcript: input.transcript ?? null
  }).slice(0, 3);
  if (!queries.length) {
    return recipe;
  }

  const pages: ImportedPageSummary[] = [];
  for (const query of queries) {
    const results = await fetchFallbackPages(query, { timeoutMs });
    for (const page of results) {
      if (!pages.some((existing) => existing.url === page.url)) {
        pages.push(page);
      }
      if (pages.length >= 4) {
        break;
      }
    }
    if (pages.length >= 4) {
      break;
    }
  }

  if (!pages.length) {
    return recipe;
  }

  const sourceUrl = recipe.sourceUrl || input.pageSummary?.url || input.socialContent?.canonicalUrl || "";
  const fallbackRecipe = await recipeFromFallbackPages(
    pages,
    input.sharedText,
    sourceUrl,
    {
      previewMode: profile === "preview",
      normalizationTimeoutMs: profile === "preview"
        ? undefined
        : normalizationTimeoutForProfile(profile, deadline, 8_000)
    }
  );

  if (!fallbackRecipe) {
    return recipe;
  }

  return shouldPreferRecipeCandidate(recipe, fallbackRecipe.recipe)
    ? fallbackRecipe.recipe
    : recipe;
}

export function bestSearchQuery(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
  transcript?: string | null;
}): string {
  return searchQueryCandidates(input)[0] ?? "";
}

function searchQueryCandidates(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
  transcript?: string | null;
}): string[] {
  const candidates = [
    decorateRecipeSearchQuery(input.recipe.searchQuery),
    decorateRecipeSearchQuery(keywordRichRecipeQuery(input)),
    inferredDishSearchTitle(input),
    ...searchTextCandidates(input)
      .map(nonGenericSearchCandidate)
      .map((value) => value ? decorateRecipeSearchQuery(extractDishPhraseFromText(value) ?? value) : undefined)
  ];

  const result: string[] = [];
  const seen = new Set<string>();
  for (const candidate of candidates) {
    const normalized = candidate?.trim();
    if (!normalized || seen.has(normalized)) {
      continue;
    }

    seen.add(normalized);
    result.push(normalized);
  }

  return result;
}

function searchTextCandidates(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
  transcript?: string | null;
}): string[] {
  return [
    input.transcript ?? undefined,
    input.socialContent?.subtitlesText,
    input.socialContent?.pageText,
    input.socialContent?.caption,
    input.socialContent?.description,
    input.sharedText,
    input.pageSummary?.description,
    input.pageSummary?.textContent,
    input.pageSummary?.title,
    input.socialContent?.title,
    input.recipe.title,
    input.recipe.ingredientDrafts.map((ingredient) => ingredient.name).join(" "),
    input.recipe.stepDrafts.map((step) => step.detail).join(" ")
  ]
    .filter((value): value is string => Boolean(value?.trim()));
}

function nonGenericSearchCandidate(value?: string): string | undefined {
  const trimmed = compactRecipeSearchCandidate(value);
  if (!trimmed) {
    return undefined;
  }

  if (hasSuspiciousRecipeTitle(trimmed)) {
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
    !line.toLowerCase().includes("http") &&
    !hasSuspiciousRecipeTitle(line)
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

function compactRecipeSearchCandidate(value?: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) {
    return undefined;
  }

  let candidate = trimmed
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/\s*---+\s*(?:instructions?|étapes?|etapes|préparation|preparation)\b.*$/iu, "")
    .replace(/\b(?:ingredients?|ingrédients?|instructions?|étapes?|etapes|dough|mixture|coating|serve with)\b.*$/iu, "")
    .replace(/\s{2,}/g, " ")
    .trim();

  const quantityMatch = candidate.match(/\b\d+(?:[.,]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs|tbsp|tsp|tablespoons?|teaspoons?|cups?|cup)\b/i);
  if (quantityMatch && typeof quantityMatch.index === "number" && quantityMatch.index >= 8) {
    candidate = candidate.slice(0, quantityMatch.index).trim();
  }

  candidate = candidate
    .split(/\n+/)[0]
    ?.split(/[.!?]/)[0]
    ?.trim() ?? candidate;

  return candidate || undefined;
}

function inferredDishSearchTitle(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
  transcript?: string | null;
}): string | undefined {
  const directTitle = [
    input.recipe.title,
    input.socialContent?.title,
    input.pageSummary?.title
  ]
    .map(dishTitleSearchCandidate)
    .find((value): value is string => Boolean(value));

  if (directTitle) {
    return decorateRecipeSearchQuery(directTitle);
  }

  const textDishTitle = searchTextCandidates(input)
    .map(extractDishPhraseFromText)
    .find((value): value is string => Boolean(value));

  if (textDishTitle) {
    return decorateRecipeSearchQuery(textDishTitle);
  }

  const inferredRecipe = fallbackRecipeFromContext({
    mode: "url",
    sourceUrl: input.recipe.sourceUrl || input.pageSummary?.url || input.socialContent?.canonicalUrl || "",
    sharedText: input.sharedText,
    pageTitle: input.pageSummary?.title,
    pageDescription: input.pageSummary?.description,
    pageTextContent: combinedPageContextText(input.pageSummary ? [input.pageSummary] : []),
    socialTitle: input.socialContent?.title,
    socialCaption: input.socialContent?.caption,
    socialDescription: input.socialContent?.description,
    socialPageText: input.socialContent?.pageText,
    socialAuthor: input.socialContent?.authorName,
    socialSubtitles: input.socialContent?.subtitlesText,
    transcript: input.transcript ?? undefined
  });
  const inferredTitle = dishTitleSearchCandidate(inferredRecipe.title) ??
    keywordRichRecipeQuery({
      ...input,
      recipe: inferredRecipe
    });

  return decorateRecipeSearchQuery(inferredTitle);
}

function dishTitleSearchCandidate(value?: string): string | undefined {
  const compact = compactRecipeSearchCandidate(value);
  if (!compact) {
    return undefined;
  }

  const candidate = compact
    .split(/\n+/)[0]
    ?.split(/[.!?]/)[0]
    ?.trim() ?? compact;
  const normalized = candidate.toLowerCase();

  if (hasSuspiciousRecipeTitle(candidate)) {
    return undefined;
  }

  if (
    candidate.length < 4 ||
    candidate.length > 90 ||
    normalized.includes("http") ||
    normalized.includes("tiktok") ||
    normalized.includes("instagram") ||
    normalized.includes("original sound")
  ) {
    return undefined;
  }

  return extractDishPhraseFromText(candidate) ?? candidate;
}

function decorateRecipeSearchQuery(value?: string): string | undefined {
  const compact = compactRecipeSearchCandidate(value);
  if (!compact) {
    return undefined;
  }

  if (/\b(?:recette|recipe)\b/i.test(compact)) {
    return compact.slice(0, 140).trim();
  }

  return `${compact.slice(0, 116).trim()} recette`;
}

function keywordRichRecipeQuery(input: {
  recipe: RecipeImportResult;
  pageSummary: ImportedPageSummary | null;
  socialContent: Awaited<ReturnType<typeof resolveSocialContent>> | null;
  sharedText?: string;
  transcript?: string | null;
}): string | undefined {
  const texts = searchTextCandidates(input);
  const dishPhrase = texts
    .map(extractDishPhraseFromText)
    .find((value): value is string => Boolean(value));
  const foodTerms = collectFoodSearchTerms(texts.join("\n"));
  const head = dishPhrase ??
    foodTerms.find((term) => dishHeadSearchTerms.has(term));

  if (!head) {
    return undefined;
  }

  const normalizedHead = normalizeSearchText(head);
  const supportTerms = foodTerms
    .filter((term) => !normalizedHead.includes(normalizeSearchText(term)))
    .filter((term) => term !== head)
    .slice(0, 2);

  return trimSearchPhrase([head, ...supportTerms].join(" "));
}

function extractDishPhraseFromText(value?: string): string | undefined {
  const normalized = normalizeSearchText(value);
  if (!normalized) {
    return undefined;
  }

  for (const pattern of dishPhrasePatterns) {
    const match = normalized.match(pattern);
    if (match?.[0]) {
      return trimSearchPhrase(match[0]);
    }
  }

  return undefined;
}

function collectFoodSearchTerms(value: string): string[] {
  const normalized = normalizeSearchText(value);
  if (!normalized) {
    return [];
  }

  const matches: string[] = [];
  for (const term of prioritizedFoodSearchTerms) {
    const pattern = new RegExp(`(?:^|\\s)${escapeSearchRegex(term)}(?:$|\\s)`, "i");
    if (pattern.test(normalized)) {
      matches.push(term);
    }
  }

  return matches;
}

function normalizeSearchText(value?: string): string {
  return (value ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .replace(/@[\p{L}\p{N}._-]+/gu, " ")
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function trimSearchPhrase(value: string): string {
  return value
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120)
    .trim();
}

function escapeSearchRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const prioritizedFoodSearchTerms = [
  "filet o fish",
  "fish burger",
  "smash burger",
  "chicken burger",
  "hot tenders",
  "sweet relish",
  "coleslaw",
  "cornichon",
  "pickle",
  "cheddar",
  "cabillaud",
  "poisson",
  "fish",
  "chicken",
  "poulet",
  "burger",
  "tacos",
  "taco",
  "pizza",
  "pasta",
  "pates",
  "pâtes",
  "crepe",
  "crepes",
  "pancake",
  "pancakes",
  "sandwich",
  "wrap",
  "salade",
  "salad",
  "omelette",
  "quiche",
  "gratin",
  "risotto",
  "ramen",
  "curry",
  "bowl",
  "falafel",
  "shawarma",
  "kebab",
  "brownie",
  "cookie",
  "cookies",
  "gateau",
  "gâteau",
  "cake"
];

const dishHeadSearchTerms = new Set([
  "filet o fish",
  "fish burger",
  "smash burger",
  "chicken burger",
  "burger",
  "tacos",
  "taco",
  "pizza",
  "pasta",
  "pates",
  "pâtes",
  "crepe",
  "crepes",
  "pancake",
  "pancakes",
  "sandwich",
  "wrap",
  "salade",
  "salad",
  "omelette",
  "quiche",
  "gratin",
  "risotto",
  "ramen",
  "curry",
  "bowl",
  "falafel",
  "shawarma",
  "kebab",
  "brownie",
  "cookie",
  "cookies",
  "gateau",
  "gâteau",
  "cake",
  "bruschetta",
  "focaccia",
  "tartare",
  "carpaccio",
  "gnocchi",
  "hummus",
  "couscous",
  "poke",
  "bibimbap",
  "gyoza"
]);

const dishPhrasePatterns = [
  /\bfilet o fish(?:\s+burger)?\b/i,
  /\bfish burger\b/i,
  /\bsmash burger\b/i,
  /\bchicken burger\b/i,
  /\b(?:crepes?|pancakes?)\b/i,
  /\b(?:hot tenders?|crispy chicken|poulet croustillant)\s+burger\b/i,
  /\b(?:smash|double|crispy|spicy|veggie|vegan|chicken|fish|filet o fish|hot tenders?|pulled|bbq|bacon|cheese|cheesy|poulet|boeuf|bœuf|beef|poisson|cabillaud|saumon|salmon|halloumi|falafel|shawarma|kebab|sweet|sucre|banana|banane|vanilla|vanille|chocolate|chocolat)\s+(?:burger|sandwich|wrap|crepes?|pancakes?|bruschetta|focaccia|tartare|carpaccio|crostini|gnocchi|hummus|couscous|poke|bibimbap|gyoza)\b/i,
  /\b(?:burger|tacos?|pizza|pasta|pates?|pâtes?|crepes?|pancakes?|sandwich|wrap|salade|salad|omelette|quiche|gratin|risotto|ramen|curry|bowl|falafel|shawarma|kebab|brownie|cookies?|gateau|gâteau|cake|bruschetta|focaccia|tartare|carpaccio|crostini|poke|bibimbap|gnocchi|hummus|couscous|gyoza)\b/i
];

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

  if (input.context.remoteImageUrl?.trim()) {
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

function buildFallbackPageContext(
  pages: ImportedPageSummary[],
  sharedText: string | undefined,
  sourceUrl: string
) {
  return {
    mode: "url" as const,
    sourceUrl,
    remoteImageUrl: pages.map((page) => page.imageUrl).find(Boolean),
    sharedText,
    pageTitle: preferredPageValue(pages, "title"),
    pageDescription: preferredPageValue(pages, "description"),
    pageTextContent: combinedPageContextText(pages),
    pageStructuredData: pages.flatMap((page) => page.structuredDataBlocks)
  };
}

function combinedPageContextText(pages: ImportedPageSummary[]): string {
  return pages
    .map((page, index) => {
      const title = page.title?.trim();
      const host = hostLabelForImportNotice(page.url);
      const snippet = compactPageTextSnippet(page.textContent);
      const parts = [
        pages.length > 1
          ? `Source web ${index + 1}: ${title || host || page.url}`
          : title || host ? `Source web: ${title || host}` : "",
        page.description?.trim() ? `Résumé: ${page.description.trim()}` : "",
        snippet
      ]
        .filter((value): value is string => Boolean(value));

      return parts.join("\n").trim();
    })
    .filter(Boolean)
    .join("\n\n---\n\n");
}

function compactPageTextSnippet(text?: string): string | undefined {
  const trimmed = text?.trim();
  if (!trimmed) {
    return undefined;
  }

  const normalized = trimmed
    .replace(/\s+/g, " ")
    .trim();

  return normalized.length > 360
    ? `${normalized.slice(0, 360).trim()}...`
    : normalized;
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
    transcript?: string;
  }
): ImportDebug {
  const missing = importMissingParts(recipe);
  const isLikelyValid = isLikelyValidRecipe(recipe, { transcript: context.transcript });
  const failureReason = isLikelyValid
    ? undefined
    : importFailureReason(recipe, {
      preferWeakMetadata: context.preferWeakMetadataReason,
      timedOut: context.timedOut,
      transcript: context.transcript
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

async function resolveImportSourceURL(
  url: string,
  sharedText?: string,
  timeoutMs?: number
): Promise<string> {
  if (platformFromUrl(url) === "web") {
    const sharedTikTokVideoURL = extractTikTokVideoURLFromText(sharedText);
    return sharedTikTokVideoURL ?? url;
  }

  const sharedTikTokVideoURL = extractTikTokVideoURLFromText(sharedText);
  if (sharedTikTokVideoURL) {
    if (sharedTikTokVideoURL !== url) {
      console.info(`[importService] Using TikTok video URL from shared text ${url} -> ${sharedTikTokVideoURL}`);
    }
    return sharedTikTokVideoURL;
  }

  try {
    const resolvedURL = await resolveRemoteURL(url, { timeoutMs });
    const normalizedResolvedURL = normalizeResolvedImportURL(url, resolvedURL);
    if (normalizedResolvedURL !== resolvedURL) {
      console.warn(
        `[importService] Ignoring invalid social redirect target ${resolvedURL} and keeping ${normalizedResolvedURL}`
      );
    } else if (resolvedURL !== url) {
      console.info(`[importService] Resolved social import URL ${url} -> ${resolvedURL}`);
    }
    return normalizedResolvedURL;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.warn(`[importService] Failed to resolve social import URL ${url}: ${message}`);
    return url;
  }
}

function normalizeResolvedImportURL(originalURL: string, resolvedURL: string): string {
  if (!isBrokenTikTokRedirectURL(resolvedURL)) {
    return resolvedURL;
  }

  return originalURL;
}

function isBrokenTikTokRedirectURL(url: string): boolean {
  try {
    const parsed = new URL(url);
    const host = parsed.host.toLowerCase();
    const pathname = parsed.pathname.toLowerCase();
    const redirectTarget = parsed.searchParams.get("redirect_url") ?? "";

    if (!host.endsWith("tiktok.com")) {
      return false;
    }

    if (/\/@[^/]+\/video\/\d+/i.test(`${host}${pathname}`)) {
      return false;
    }

    if (redirectTarget.startsWith("sslocal://")) {
      return true;
    }

    return pathname === "/" || pathname === "/explore";
  } catch {
    return false;
  }
}

function isTikTokShortURL(url: string): boolean {
  try {
    const parsed = new URL(url);
    const host = parsed.host.toLowerCase();
    return host === "vm.tiktok.com" || host === "vt.tiktok.com" || host.endsWith(".vm.tiktok.com");
  } catch {
    return false;
  }
}

function extractTikTokVideoURLFromText(text?: string): string | undefined {
  if (!text?.trim()) {
    return undefined;
  }

  const match = text.match(/https?:\/\/(?:www\.)?tiktok\.com\/@[^/\s]+\/video\/\d+[^\s]*/i);
  return match?.[0];
}

function shouldTrustSharedTextRecipe(recipe: RecipeImportResult, sharedText?: string): boolean {
  if (!sharedText?.trim()) {
    return false;
  }

  return isLikelyValidRecipe(recipe) &&
    recipe.title.trim().length > 2 &&
    recipe.ingredientDrafts.length >= 3 &&
    recipe.stepDrafts.length >= 2;
}

export async function importFromText(input: {
  text: string;
  imageDataUrl?: string;
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug }> {
  const previewMode = options?.previewMode ?? false;
  const profile: ImportRuntimeProfile = previewMode ? "preview" : "full";
  const startedAt = Date.now();
  const executionDeadline = deadlineForProfile(profile, startedAt);
  const baseContext = {
    mode: "text",
    sharedText: input.text,
    imageDataUrl: input.imageDataUrl
  } as const;
  const recipe = await safeNormalize(baseContext, {
    timeoutMs: previewMode ? 8_000 : 60_000
  });
  const reviewedRecipe = await maybeReviewRecipeCookability(
    recipe,
    baseContext,
    profile,
    executionDeadline,
    "text"
  );
  const rescuedRecipe = attemptDishRescue(reviewedRecipe, baseContext);
  const strictBaseRecipe = requireStrictRecipe(rescuedRecipe, baseContext);
  const searchEnrichedRecipe = await maybeEnrichRecipeFromSearch(
    strictBaseRecipe,
    {
      sourcePlatform: "web",
      pageSummary: null,
      socialContent: null,
      sharedText: input.text,
      transcript: null
    },
    profile,
    executionDeadline
  );
  const strictRecipe = requireStrictRecipe(searchEnrichedRecipe, baseContext);
  const usedWebFallback = searchEnrichedRecipe !== strictBaseRecipe;
  const validatedRecipe = await enforceRecipeValidation(
    strictRecipe,
    baseContext,
    executionDeadline
  );
  const finalizedRecipe = await finalizeImportedRecipe(validatedRecipe, {
    skipNutrition: previewMode
  });

  const debug = buildImportDebug(finalizedRecipe.recipe, {
    sourceKind: "text",
    strategy: "text",
    durationMs: Date.now() - startedAt,
    usedApify: false,
    usedTranscription: false,
    usedWebFallback,
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
  const profile: ImportRuntimeProfile = previewMode ? "preview" : "full";
  const startedAt = Date.now();
  const executionDeadline = deadlineForProfile(profile, startedAt);
  const baseContext = {
    mode: "photo",
    imageDataUrl: input.imageDataUrl
  } as const;
  const recipe = await safeNormalize(baseContext, {
    timeoutMs: previewMode ? 8_000 : 60_000
  });
  const reviewedRecipe = await maybeReviewRecipeCookability(
    recipe,
    baseContext,
    profile,
    executionDeadline,
    "photo"
  );
  const rescuedRecipe = attemptDishRescue(reviewedRecipe, baseContext);
  const strictBaseRecipe = requireStrictRecipe(rescuedRecipe, baseContext);
  const searchEnrichedRecipe = await maybeEnrichRecipeFromSearch(
    strictBaseRecipe,
    {
      sourcePlatform: "web",
      pageSummary: null,
      socialContent: null,
      sharedText: strictBaseRecipe.title || strictBaseRecipe.searchQuery,
      transcript: null
    },
    profile,
    executionDeadline
  );
  const strictRecipe = requireStrictRecipe(searchEnrichedRecipe, baseContext);
  const usedWebFallback = searchEnrichedRecipe !== strictBaseRecipe;
  const validatedRecipe = await enforceRecipeValidation(
    strictRecipe,
    baseContext,
    executionDeadline
  );
  const finalizedRecipe = await finalizeImportedRecipe(validatedRecipe, {
    skipNutrition: previewMode
  });

  const debug = buildImportDebug(finalizedRecipe.recipe, {
    sourceKind: "photo",
    strategy: "photo",
    durationMs: Date.now() - startedAt,
    usedApify: false,
    usedTranscription: false,
    usedWebFallback,
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

async function maybeReviewRecipeCookability(
  recipe: RecipeImportResult,
  context: Parameters<typeof normalizeRecipeFromContext>[0],
  profile: ImportRuntimeProfile,
  deadline: number | undefined,
  stage: ImportStrategy | "shared-text"
): Promise<RecipeImportResult> {
  if (!shouldAttemptCookabilityReview(recipe, context, profile)) {
    return recipe;
  }

  const timeoutMs = cookabilityReviewTimeout(profile, deadline);
  if (!timeoutMs) {
    return recipe;
  }

  console.info(
    `[importService] Reviewing cookability for ${context.sourceUrl || context.mode} at stage=${stage}`
  );
  const reviewedRecipe = await safeReviewCookability(
    {
      draft: recipe,
      context
    },
    {
      timeoutMs
    }
  );

  if (shouldPreferRecipeCandidate(recipe, reviewedRecipe)) {
    return reviewedRecipe;
  }

  return recipe;
}

async function safeNormalize(
  input: Parameters<typeof normalizeRecipeFromContext>[0],
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  try {
    return await normalizeRecipeFromContext(input, {
      timeoutMs: options?.timeoutMs ?? 60_000
    });
  } catch (error) {
    if (isOpenAIUnavailable(error) || isTimeoutLikeError(error)) {
      return fallbackRecipeFromContext(input);
    }

    throw error;
  }
}

async function safeReviewCookability(
  input: Parameters<typeof reviewRecipeCookability>[0],
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  try {
    return await reviewRecipeCookability(input, {
      timeoutMs: options?.timeoutMs ?? 12_000
    });
  } catch (error) {
    if (isOpenAIUnavailable(error) || isTimeoutLikeError(error)) {
      return input.draft;
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
  const sanitizedRecipe = ensureCookableRecipeStructure(recipe);
  if (options?.skipNutrition) {
    const metadataRecipe = await enrichRecipePresentationMetadata(sanitizedRecipe);
    return {
      recipe: metadataRecipe,
      usedUsda: false,
      nutritionCoverage: 0,
      matchedIngredients: 0
    };
  }
  const nutritionResult = await enrichRecipeNutrition(sanitizedRecipe);
  const postNutritionRecipe = ensureCookableRecipeStructure(nutritionResult.recipe);

  // Final quality gate: never return a recipe with fewer than 4 ingredients or 4 steps
  const finalRecipe = (postNutritionRecipe.ingredientDrafts.length < 4 || postNutritionRecipe.stepDrafts.length < 4)
    ? ensureCookableRecipeStructure(postNutritionRecipe)
    : postNutritionRecipe;

  const metadataRecipe = await enrichRecipePresentationMetadata(finalRecipe);

  return {
    ...nutritionResult,
    recipe: metadataRecipe
  };
}

export function ensureCookableRecipeStructure(recipe: RecipeImportResult): RecipeImportResult {
  const sanitizedRecipe = sanitizeRecipeImport(recipe);
  const title = stableGeneratedRecipeTitle(sanitizedRecipe);
  const requiredStepCount = minimumGeneratedStepCount(title, sanitizedRecipe.ingredientDrafts);
  const explicitSteps = dedupeGeneratedStepDrafts(sanitizedRecipe.stepDrafts);
  const needsCookabilityUpgrade = hasCookabilityGaps({
    ingredientDrafts: sanitizedRecipe.ingredientDrafts,
    stepDrafts: explicitSteps
  });

  if (
    !sanitizedRecipe.ingredientDrafts.length ||
    (explicitSteps.length >= requiredStepCount && !needsCookabilityUpgrade)
  ) {
    return sanitizeRecipeImport({
      ...sanitizedRecipe,
      title
    });
  }

  const generatedSteps = generateCookableStepDrafts(title, sanitizedRecipe.ingredientDrafts);
  const mergedSteps = dedupeGeneratedStepDrafts([
    ...generatedSteps,
    ...explicitSteps
  ]);
  const preferredSteps = mergedSteps.length >= requiredStepCount
    ? mergedSteps
    : generatedSteps;
  const nextSteps = preferredSteps.slice(
    0,
    Math.max(requiredStepCount, Math.min(preferredSteps.length, 12))
  );
  const flags = normalizeRecipeImportFlags(sanitizedRecipe.flags);

  return sanitizeRecipeImport({
    ...sanitizedRecipe,
    title,
    stepDrafts: nextSteps,
    flags: {
      ...flags,
      generatedSteps: flags.generatedSteps || nextSteps.length > explicitSteps.length
    }
  });
}

export function resolveAcceptedRecipeCandidate(
  recipe: RecipeImportResult,
  context: Parameters<typeof strictRecipeFromContext>[0]
) {
  const sanitizedRecipe = sanitizeRecipeImport(recipe);
  const strictRecipe = strictRecipeFromContext(context, sanitizedRecipe);

  if (strictRecipe && shouldPreferRecipeCandidate(strictRecipe, sanitizedRecipe)) {
    return sanitizedRecipe;
  }

  if (strictRecipe) {
    return strictRecipe;
  }

  if (isLikelyValidRecipe(sanitizedRecipe, { transcript: context.transcript })) {
    return sanitizedRecipe;
  }

  return null;
}

function requireStrictRecipe(
  recipe: RecipeImportResult,
  context: Parameters<typeof strictRecipeFromContext>[0]
): RecipeImportResult {
  const acceptedRecipe = resolveAcceptedRecipeCandidate(recipe, context);
  if (!acceptedRecipe) {
    throw new RecipeImportNotFoodError();
  }

  return acceptedRecipe;
}

function transcriptionOptions(
  profile: ImportRuntimeProfile,
  deadline?: number
) {
  if (profile === "full") {
    return undefined;
  }

  if (profile === "shared") {
    const mediaFetchTimeoutMs = boundedExecutionTimeout(
      deadline,
      SHARED_AUDIO_FETCH_TIMEOUT_MS,
      SHARED_RESERVE_MS
    );
    const transcriptionTimeoutMs = boundedExecutionTimeout(
      deadline,
      SHARED_AUDIO_TRANSCRIPTION_TIMEOUT_MS,
      SHARED_RESERVE_MS
    );

    if (!mediaFetchTimeoutMs || !transcriptionTimeoutMs) {
      return null;
    }

    return {
      mediaFetchTimeoutMs,
      transcriptionTimeoutMs,
      maxDurationSeconds: SHARED_AUDIO_MAX_DURATION_SECONDS,
      maxFileBytes: 14 * 1024 * 1024
    };
  }

  return {
    mediaFetchTimeoutMs: 10_000,
    transcriptionTimeoutMs: 15_000,
    maxDurationSeconds: 75,
    maxFileBytes: 12 * 1024 * 1024
  };
}

function shouldAttemptCookabilityReview(
  recipe: RecipeImportResult,
  context: Parameters<typeof normalizeRecipeFromContext>[0],
  profile: ImportRuntimeProfile
): boolean {
  if (profile === "preview") {
    return false;
  }

  const hasRecipeSignal = Boolean(recipe.title.trim()) ||
    recipe.ingredientDrafts.length > 0 ||
    recipe.stepDrafts.length > 0;

  if (!hasRecipeSignal && !hasCookabilityContext(context)) {
    return false;
  }

  return true;
}

function hasCookabilityContext(
  context: Parameters<typeof normalizeRecipeFromContext>[0]
): boolean {
  const textBudget = [
    context.sharedText,
    context.pageTitle,
    context.pageDescription,
    context.pageTextContent,
    context.socialTitle,
    context.socialCaption,
    context.socialDescription,
    context.socialPageText,
    context.socialSubtitles,
    context.transcript
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n")
    .trim()
    .length;

  const structuredBudget = (context.pageStructuredData ?? [])
    .join("\n")
    .trim()
    .length;

  return textBudget >= 140 ||
    structuredBudget >= 140 ||
    Boolean(context.transcript?.trim()) ||
    Boolean((context.imageDataUrl || context.remoteImageUrl) && (textBudget >= 40 || structuredBudget >= 40)) ||
    Boolean(context.imageDataUrl || context.remoteImageUrl);
}

function cookabilityReviewTimeout(
  profile: ImportRuntimeProfile,
  deadline?: number
): number | undefined {
  if (profile === "preview") {
    return undefined;
  }

  if (profile === "shared") {
    return boundedExecutionTimeout(deadline, 10_000, SHARED_RESERVE_MS);
  }

  return 12_000;
}

function shouldPreferRecipeCandidate(
  currentRecipe: RecipeImportResult,
  reviewedRecipe: RecipeImportResult
): boolean {
  const currentCookability = recipeCookabilitySignals(currentRecipe);
  const reviewedCookability = recipeCookabilitySignals(reviewedRecipe);
  const currentMissingCount = importMissingParts(currentRecipe).length;
  const reviewedMissingCount = importMissingParts(reviewedRecipe).length;

  if (reviewedMissingCount < currentMissingCount) {
    return true;
  }

  if (reviewedMissingCount > currentMissingCount) {
    return false;
  }

  if (isLikelyValidRecipe(reviewedRecipe) && !isLikelyValidRecipe(currentRecipe)) {
    return true;
  }

  if (reviewedCookability.uncoveredMajorIngredientCount < currentCookability.uncoveredMajorIngredientCount) {
    return true;
  }

  if (reviewedCookability.majorIngredientCoverage > currentCookability.majorIngredientCoverage + 0.15) {
    return true;
  }

  if (
    reviewedRecipe.ingredientDrafts.length > currentRecipe.ingredientDrafts.length &&
    reviewedRecipe.stepDrafts.length >= currentRecipe.stepDrafts.length
  ) {
    return true;
  }

  if (
    reviewedRecipe.stepDrafts.length > currentRecipe.stepDrafts.length &&
    reviewedRecipe.ingredientDrafts.length >= currentRecipe.ingredientDrafts.length
  ) {
    return true;
  }

  return scoreRecipe(reviewedRecipe) >= scoreRecipe(currentRecipe);
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

function runtimeProfile(options?: ImportExecutionOptions): ImportRuntimeProfile {
  if (options?.previewMode) {
    return "preview";
  }

  if (options?.sharedMode) {
    return "shared";
  }

  return "full";
}

function deadlineForProfile(
  profile: ImportRuntimeProfile,
  startedAt: number
): number | undefined {
  if (profile === "preview") {
    return startedAt + PREVIEW_TOTAL_LIMIT_MS;
  }

  if (profile === "shared") {
    return startedAt + SHARED_TOTAL_LIMIT_MS;
  }

  return startedAt + FULL_TOTAL_LIMIT_MS;
}

function hasExecutionBudget(deadline?: number, reserveMs = 0): boolean {
  if (!deadline) {
    return true;
  }

  return deadline - Date.now() - reserveMs > 0;
}

function boundedExecutionTimeout(
  deadline: number | undefined,
  desiredMs: number | undefined,
  reserveMs = 0
): number | undefined {
  if (!desiredMs) {
    return undefined;
  }

  if (!deadline) {
    return desiredMs;
  }

  const remainingMs = deadline - Date.now() - reserveMs;
  if (remainingMs <= 0) {
    return undefined;
  }

  return Math.max(500, Math.min(desiredMs, remainingMs));
}

function normalizationTimeoutForProfile(
  profile: ImportRuntimeProfile,
  deadline?: number,
  desiredMs?: number
): number | undefined {
  if (profile === "preview") {
    return Math.min(desiredMs ?? 8_000, 8_000);
  }

  if (profile === "shared") {
    return boundedExecutionTimeout(
      deadline,
      Math.min(desiredMs ?? SHARED_SOCIAL_NORMALIZE_TIMEOUT_MS, SHARED_SOCIAL_NORMALIZE_TIMEOUT_MS),
      SHARED_RESERVE_MS
    );
  }

  return desiredMs ?? 60_000;
}

function stableGeneratedRecipeTitle(recipe: RecipeImportResult): string {
  const title = recipe.title.trim() || recipe.searchQuery.trim();
  return title || "Recette importée";
}

function minimumGeneratedStepCount(
  title: string,
  ingredients: RecipeImportResult["ingredientDrafts"]
): number {
  const normalizedTitle = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  const ingredientSignals = generatedIngredientSignals(ingredients);

  if (/\b(?:omelette|toast|croque|quesadilla|tartine)\b/.test(normalizedTitle)) {
    return 3;
  }

  if (/\b(?:crepes?|crêpes?|pancakes?)\b/.test(normalizedTitle)) {
    return 6;
  }

  if (/\b(?:burger|sandwich|naan|wrap|taco)\b/.test(normalizedTitle)) {
    if (ingredientSignals.hasBreadDoughBase && ingredientSignals.hasProtein) {
      return 8;
    }

    if (ingredientSignals.hasProtein || ingredientSignals.hasAssemblyFillings) {
      return 7;
    }
  }

  if (/\b(?:cake|gateau|gâteau|brownie|cookie|dessert|tiramisu)\b/.test(normalizedTitle)) {
    return 6;
  }

  return 6;
}

function dedupeGeneratedStepDrafts(stepDrafts: Array<{ detail: string }>): Array<{ detail: string }> {
  const seen = new Set<string>();
  const result: Array<{ detail: string }> = [];

  for (const stepDraft of stepDrafts) {
    const detail = stepDraft.detail.trim();
    if (!detail) {
      continue;
    }

    const key = detail
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
    result.push({ detail });
  }

  return result;
}

function generateCookableStepDrafts(
  title: string,
  ingredients: RecipeImportResult["ingredientDrafts"]
): Array<{ detail: string }> {
  const normalizedTitle = title
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  const ingredientSignals = generatedIngredientSignals(ingredients);
  const protein = preferredGeneratedIngredient(ingredients, [/\bpoulet\b/i, /\bboeuf\b/i, /\bburger\b/i, /\bviande\b/i, /\bpoisson\b/i], "garniture principale");
  const bread = preferredGeneratedIngredient(ingredients, [/\bpain\b/i, /\bbun\b/i, /\bnaan\b/i, /\bwrap\b/i, /\btortilla\b/i, /\bflatbread\b/i], "support");
  const greens = preferredGeneratedIngredient(ingredients, [/\bsalade\b/i, /\blaitue\b/i, /\bcabbage\b/i, /\bchou\b/i], "garniture");
  const sauce = preferredGeneratedIngredient(ingredients, [/\bsauce\b/i, /\bcreme\b/i, /\bcrème\b/i, /\byaourt\b/i], "sauce");
  const aromatic = preferredGeneratedIngredient(ingredients, [/\boignon\b/i, /\bail\b/i, /\btomate\b/i, /\bchampignon\b/i], "aromates");
  const flour = preferredGeneratedIngredient(ingredients, [/\bfarine\b/i, /\bflour\b/i], "farine");
  const milk = preferredGeneratedIngredient(ingredients, [/\blait\b/i, /\bmilk\b/i], "lait");
  const eggs = preferredGeneratedIngredient(ingredients, [/\boeufs?\b/i, /\bœufs?\b/i, /\beggs?\b/i], "oeufs");
  const butter = preferredGeneratedIngredient(ingredients, [/\bbeurre\b/i, /\bbutter\b/i], "beurre");
  const sugar = preferredGeneratedIngredient(ingredients, [/\bsucre\b/i, /\bsugar\b/i, /\bvanille\b/i, /\bvanilla\b/i], "sucre");
  const yeast = preferredGeneratedIngredient(ingredients, [/\blevure\b/i, /\byeast\b/i], "levure");
  const water = preferredGeneratedIngredient(ingredients, [/\beau\b/i, /\bwater\b/i], "eau tiède");
  const yogurt = preferredGeneratedIngredient(ingredients, [/\byaourt\b/i, /\byogurt\b/i, /\bfromage blanc\b/i], "yaourt");
  const cheese = preferredGeneratedIngredient(ingredients, [/\bfromage\b/i, /\bcheddar\b/i, /\bmozzarella\b/i, /\bparmesan\b/i], "fromage");

  if (/\b(?:crepes?|crêpes?|pancakes?)\b/.test(normalizedTitle)) {
    return [
      { detail: `Versez le ${flour} et le ${sugar} dans un saladier, puis formez un puits au centre.` },
      { detail: `Incorporez les ${eggs}, puis fouettez en versant progressivement le ${milk} pour obtenir une pâte bien lisse.` },
      { detail: `Ajoutez le ${butter} fondu, mélangez une dernière fois et laissez reposer la pâte quelques minutes.` },
      { detail: "Chauffez une poêle légèrement beurrée, versez une louche de pâte et répartissez-la en une couche fine." },
      { detail: "Faites cuire la crêpe jusqu'à ce que les bords se décollent, retournez-la, puis répétez avec le reste de la pâte avant de servir." }
    ];
  }

  if (/\b(?:burger|sandwich|naan|toast)\b/.test(normalizedTitle) && ingredientSignals.hasBreadDoughBase && ingredientSignals.hasProtein) {
    return [
      { detail: `Diluez la ${yeast} dans la ${water} avec un peu de ${sugar}, puis laissez mousser quelques minutes.` },
      { detail: `Mélangez le ${flour} avec l'assaisonnement, ajoutez le ${yogurt} et la levure diluée, puis pétrissez jusqu'à obtenir une pâte souple.` },
      { detail: `Incorporez le ${butter}, couvrez la pâte et laissez-la reposer jusqu'à ce qu'elle gonfle légèrement.` },
      { detail: "Divisez la pâte en portions, étalez-les en disques puis faites cuire les naans dans une poêle bien chaude jusqu'à ce qu'ils soient dorés par endroits." },
      { detail: `Préparez la garniture en éminçant le ${aromatic}, en lavant la ${greens} et en assaisonnant le ${protein}.` },
      { detail: `Faites cuire le ${protein} jusqu'à ce qu'il soit bien doré et cuit à cœur, puis ajoutez éventuellement le ${cheese} pour le faire fondre légèrement.` },
      { detail: `Garnissez chaque ${bread} ou naan avec la ${sauce}, la ${greens}, le ${protein} et les autres garnitures, puis servez aussitôt.` }
    ];
  }

  if (/\b(?:burger|sandwich|naan|toast)\b/.test(normalizedTitle)) {
    return [
      { detail: `Préparez les garnitures en éminçant le ${aromatic} et en assaisonnant le ${protein}.` },
      { detail: `Faites cuire le ${protein} dans une poêle chaude jusqu'à ce qu'il soit bien doré et cuit à cœur.` },
      { detail: `Préparez les accompagnements en lavant la ${greens}, en ajoutant la ${sauce} et en gardant le ${bread} prêt à être garni.` },
      { detail: `Réchauffez ou toastez le ${bread} pour lui redonner du moelleux et un peu de croustillant.` },
      { detail: `Montez le ${title.toLocaleLowerCase()} avec le ${bread}, le ${protein}, les garnitures et la sauce, puis servez aussitôt.` }
    ];
  }

  if (/\bwrap\b/.test(normalizedTitle)) {
    return [
      { detail: `Assaisonnez le ${protein} puis faites-le cuire jusqu'à ce qu'il soit bien doré.` },
      { detail: `Préparez la garniture en éminçant le ${aromatic} et en gardant la ${greens} et la ${sauce} à portée de main.` },
      { detail: `Réchauffez le ${bread} quelques secondes pour l'assouplir sans le dessécher.` },
      { detail: `Disposez la ${greens}, le ${protein}, le ${aromatic} et la ${sauce} au centre du ${bread}.` },
      { detail: `Rabattez les côtés, roulez le ${title.toLocaleLowerCase()} bien serré et servez immédiatement.` }
    ];
  }

  if (/\b(?:pasta|pates?|pâtes?|curry|risotto)\b/.test(normalizedTitle)) {
    return [
      { detail: `Préparez tous les ingrédients en coupant le ${aromatic} et en assaisonnant le ${protein}.` },
      { detail: `Faites revenir le ${aromatic} avec un peu de matière grasse, puis ajoutez le ${protein} et faites-le cuire.` },
      { detail: "Ajoutez l'élément principal de la recette, mélangez bien et laissez mijoter jusqu'à obtenir une texture liée." },
      { detail: `Rectifiez l'assaisonnement, dressez le ${title.toLocaleLowerCase()} bien chaud et servez sans attendre.` }
    ];
  }

  if (/\b(?:salade|salad|bowl)\b/.test(normalizedTitle)) {
    return [
      { detail: `Lavez et préparez les légumes, puis détaillez le ${aromatic} si nécessaire.` },
      { detail: `Faites cuire le ${protein} jusqu'à obtenir une belle coloration, puis laissez-le tiédir légèrement.` },
      { detail: `Assemblez les ingrédients dans un saladier avec la ${greens} et la ${sauce}.` },
      { detail: `Mélangez délicatement, rectifiez l'assaisonnement et servez le ${title.toLocaleLowerCase()}.` }
    ];
  }

  if (/\b(?:cake|gateau|gâteau|brownie|cookie|dessert|tiramisu)\b/.test(normalizedTitle)) {
    return [
      { detail: "Préparez tous les ingrédients et préchauffez le four ou le matériel nécessaire selon la recette." },
      { detail: "Mélangez les ingrédients secs dans un premier récipient et les ingrédients humides dans un second." },
      { detail: "Réunissez les deux préparations sans trop travailler la pâte afin de conserver une texture homogène." },
      { detail: `Versez la préparation dans le moule ou le plat adapté, puis faites cuire jusqu'à ce que le ${title.toLocaleLowerCase()} soit pris.` },
      { detail: "Laissez tiédir quelques minutes avant de démouler, découper ou dresser, puis servez." }
    ];
  }

  return [
    { detail: `Préparez les ingrédients du ${title.toLocaleLowerCase()} en détaillant le ${aromatic} et en assaisonnant la garniture principale.` },
    { detail: "Faites cuire les éléments principaux dans une poêle chaude jusqu'à obtenir une cuisson régulière et une bonne coloration." },
    { detail: "Ajoutez les garnitures et mélangez jusqu'à obtenir une préparation bien liée et équilibrée." },
    { detail: `Rectifiez l'assaisonnement, dressez le ${title.toLocaleLowerCase()} et servez immédiatement.` }
  ];
}

function preferredGeneratedIngredient(
  ingredients: RecipeImportResult["ingredientDrafts"],
  patterns: RegExp[],
  fallback: string
): string {
  const match = ingredients.find((ingredient) =>
    patterns.some((pattern) => pattern.test(ingredient.name))
  );

  return match?.name || fallback;
}

function generatedIngredientSignals(
  ingredients: RecipeImportResult["ingredientDrafts"]
): {
  hasBreadDoughBase: boolean;
  hasProtein: boolean;
  hasAssemblyFillings: boolean;
} {
  const hasFlour = ingredients.some((ingredient) => /\bfarine\b|\bflour\b/i.test(ingredient.name));
  const hasLeavening = ingredients.some((ingredient) => /\blevure\b|\byeast\b|\bbaking powder\b|\blevure chimique\b/i.test(ingredient.name));
  const hasDairyOrWater = ingredients.some((ingredient) => /\byaourt\b|\byogurt\b|\blait\b|\bmilk\b|\beau\b|\bwater\b/i.test(ingredient.name));
  const hasProtein = ingredients.some((ingredient) => /\bpoulet\b|\bchicken\b|\bboeuf\b|\bburger\b|\bviande\b|\bpoisson\b|\bfish\b|\bsaumon\b|\btofu\b/i.test(ingredient.name));
  const hasAssemblyFillings = ingredients.some((ingredient) => /\bsalade\b|\blettuce\b|\boignon\b|\bonion\b|\bfromage\b|\bcheddar\b|\bsauce\b|\btomate\b/i.test(ingredient.name));

  return {
    hasBreadDoughBase: hasFlour && hasLeavening && hasDairyOrWater,
    hasProtein,
    hasAssemblyFillings
  };
}
