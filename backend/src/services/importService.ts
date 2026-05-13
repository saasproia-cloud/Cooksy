import { fetchPageSummary, resolveRemoteURL } from "./generalPageService.js";
import {
  distillTranscriptForRecipe,
  normalizeRecipeFromContext,
  normalizeRecipePreservationMode,
  reviewRecipeCookability,
  transcribeMediaFromUrl
} from "./openAIService.js";
import { analyzeGaps, type GapReport } from "./gapAnalyzer.js";
import {
  buildCleanedPrimarySnapshot,
  makeSnapshot,
  selectBestSnapshot,
  type PipelineSnapshot,
} from "./pipelineSnapshots.js";
import {
  createPipelineTrace,
  summarizeSnapshot,
  type PipelineTrace,
} from "./pipelineTrace.js";
import { transcribeWithGoogleFromUrl } from "./googleSpeechService.js";
import { providerStatus } from "../config/env.js";
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
  compileRecipeFromSources,
  measureRecipeQuality,
  type CompilerResult,
} from "./recipeCompiler.js";
import {
  containsLikelyFoodTitleTerm,
  hasMeaningfulFoodSignal,
  hasCookabilityGaps,
  hasSuspiciousRecipeTitle,
  importFailureReason,
  importMissingParts,
  isLikelyMajorIngredient,
  isLikelyValidRecipe,
  minimumStepCountForRecipeTitle,
  normalizeRecipeImportFlags,
  normalizeLookup,
  recipeCookabilitySignals,
  sanitizeRecipeImport,
  scoreRecipe,
  shouldFallbackToSearch,
  type ImportDebug,
  type RecipeImportResult
} from "../types/recipe.js";
import {
  validateStrictRecipe,
  type StrictIssue,
} from "./strictRecipeValidator.js";
import { platformFromUrl } from "../utils/text.js";

type ImportExecutionOptions = {
  previewMode?: boolean;
  sharedMode?: boolean;
  debug?: boolean;
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
  readonly reason: string;

  constructor(reason: string = "no_food_detected") {
    super("not_food");
    this.name = "RecipeImportNotFoodError";
    this.reason = reason;
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
const SHARED_SOCIAL_NORMALIZE_TIMEOUT_MS = 25_000;
const SHARED_TRANSCRIPT_DISTILL_TIMEOUT_MS = 8_000;
const SHARED_APIFY_TIMEOUT_MS = 45_000;
const SHARED_AUDIO_FETCH_TIMEOUT_MS = 12_000;
const SHARED_AUDIO_TRANSCRIPTION_TIMEOUT_MS = 20_000;
const SHARED_AUDIO_MAX_DURATION_SECONDS = 300;
const SHARED_WEB_TIMEOUT_MS = 5_000;
const SHARED_RESERVE_MS = 1_200;
const FULL_TOTAL_LIMIT_MS = 120_000;

// Phase 4: opt-in pipeline v2 enables preservation-mode dispatch + baseline
// snapshot + non-degradation selector. Legacy path (quality-ratio guard)
// remains the default until fixture validation completes.
const PIPELINE_V2 = process.env.PIPELINE_V2 === "true";
const PRESERVATION_TIMEOUT_MS = 18_000;

export async function importFromUrl(input: {
  url: string;
  sharedText?: string;
}, options?: ImportExecutionOptions): Promise<{ recipe: RecipeImportResult; debug: ImportDebug; pipelineTrace?: PipelineTrace }> {
  const profile = runtimeProfile(options);
  const previewMode = profile === "preview";
  const sharedMode = profile === "shared";
  const startedAt = Date.now();
  const executionDeadline = deadlineForProfile(profile, startedAt);
  const traceEnabled = options?.debug === true;
  const pipelineTrace: PipelineTrace | undefined = traceEnabled
    ? createPipelineTrace(input.url)
    : undefined;
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

  // =====================================================================
  // COMPILER-FIRST GATE: Try deterministic compilation BEFORE any LLM call.
  // If the caption contains a structured recipe, use it directly.
  // LLM is only called as a LAST RESORT when the compiler output is incomplete.
  // =====================================================================
  const compilerInput = buildUrlNormalizationContext({
    canonicalSourceURL: resolvedSourceURL,
    sharedText: input.sharedText,
    pageSummary: null,
    socialContent: null
  });
  const compilerResult = compileRecipeFromSources(compilerInput);

  // Compiler-first short-circuit: skip the LLM only when the compiler
  // has VERY high confidence — at least 6 ingredients, 3 steps, and
  // either an explicit section count >= 2 or a clearly named dish. This
  // keeps the LLM as the default oracle: the compiler bypass exists only
  // for the rare case where the caption is a fully-formatted blog-style
  // recipe that the LLM cannot meaningfully improve.
  const compilerIngredientCount = compilerResult.recipe?.ingredientDrafts?.length ?? 0;
  const compilerStepCount = compilerResult.recipe?.stepDrafts?.length ?? 0;
  const compilerSectionCount = new Set(
    (compilerResult.recipe?.ingredientDrafts ?? [])
      .map((i) => i.group?.trim() || "")
      .filter(Boolean)
  ).size;
  const compilerHasHighConfidence =
    compilerIngredientCount >= 6 &&
    compilerStepCount >= 3 &&
    (compilerSectionCount >= 2 || Boolean(compilerResult.recipe?.title?.trim()));

  if (compilerResult.compilerUsed && !compilerResult.llmNeeded && compilerHasHighConfidence) {
    console.info(
      `[importService] Compiler produced high-confidence recipe (ingredients=${compilerIngredientCount}, steps=${compilerStepCount}, sections=${compilerSectionCount}) — skipping LLM for ${resolvedSourceURL}`
    );

    const compilerRecipe = {
      ...compilerResult.recipe,
      sourceUrl: compilerResult.recipe.sourceUrl || resolvedSourceURL,
      remoteImageUrl: compilerResult.recipe.remoteImageUrl || ""
    };

    // Still finalize (nutrition, metadata) but skip the LLM reconstruction
    const finalizedRecipe = await finalizeImportedRecipe(compilerRecipe, {
      skipNutrition: false
    });

    // Non-degradation guard: measure quality before/after finalization
    const preQuality = measureRecipeQuality(compilerRecipe);
    const postQuality = measureRecipeQuality(finalizedRecipe.recipe);
    const bestRecipe = postQuality >= preQuality * 0.85
      ? finalizedRecipe.recipe
      : compilerRecipe;

    const durationMs = Date.now() - startedAt;
    const debug = buildImportDebug(bestRecipe, {
      sourceKind: "url",
      strategy: "social",
      durationMs,
      usedApify: false,
      usedTranscription: false,
      usedWebFallback: compilerResult.usedEnrichment,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      preferWeakMetadataReason: false
    });
    logImportDebug(bestRecipe, debug);
    console.info(
      `[importService] URL import completed via compiler in ${durationMs}ms for ${resolvedSourceURL}`
    );

    return { recipe: bestRecipe, debug };
  }

  // Compiler output is incomplete — fall through to the existing LLM pipeline
  if (compilerResult.compilerUsed) {
    console.info(
      `[importService] Compiler output incomplete (primary=${compilerResult.primarySource}, ingredients=${compilerResult.recipe.ingredientDrafts.length}, steps=${compilerResult.recipe.stepDrafts.length}) — falling through to LLM pipeline for ${resolvedSourceURL}`
    );
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
  let transcriptDigest: string | null = null;
  let parsedDigest: ParsedTranscriptDigest | null = null;
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
    transcriptDigest,
    fallbackPages,
    audioIsPrimarySource: captionWasSparse && Boolean(transcript)
  });

  // Re-run compiler with full social context now available
  const enrichedCompilerResult = compileRecipeFromSources(buildContext());
  if (enrichedCompilerResult.compilerUsed && !enrichedCompilerResult.llmNeeded) {
    console.info(
      `[importService] Compiler (with social) produced complete recipe (primary=${enrichedCompilerResult.primarySource}, ingredients=${enrichedCompilerResult.recipe.ingredientDrafts.length}, steps=${enrichedCompilerResult.recipe.stepDrafts.length}) — skipping LLM for ${canonicalSourceURL}`
    );

    const compilerRecipe = {
      ...enrichedCompilerResult.recipe,
      sourceUrl: enrichedCompilerResult.recipe.sourceUrl || canonicalSourceURL,
      remoteImageUrl: enrichedCompilerResult.recipe.remoteImageUrl || socialContent?.imageUrls[0] || pageSummary?.imageUrl || ""
    };

    const finalizedRecipe = await finalizeImportedRecipe(compilerRecipe, {
      skipNutrition: false
    });

    const preQuality = measureRecipeQuality(compilerRecipe);
    const postQuality = measureRecipeQuality(finalizedRecipe.recipe);
    const bestRecipe = postQuality >= preQuality * 0.85
      ? finalizedRecipe.recipe
      : compilerRecipe;

    const durationMs = Date.now() - startedAt;
    const debug = buildImportDebug(bestRecipe, {
      platform: resolvedSocialContent?.platform,
      sourceKind: "url",
      strategy: importStrategy,
      durationMs,
      usedApify: resolvedSocialContent?.source === "apify",
      usedTranscription: false,
      usedWebFallback: enrichedCompilerResult.usedEnrichment,
      usedUsda: finalizedRecipe.usedUsda,
      nutritionCoverage: finalizedRecipe.nutritionCoverage,
      matchedNutritionIngredients: finalizedRecipe.matchedIngredients,
      preferWeakMetadataReason: false
    });
    logImportDebug(bestRecipe, debug);
    console.info(
      `[importService] URL import completed via compiler (with social) in ${durationMs}ms for ${canonicalSourceURL}`
    );

    return { recipe: bestRecipe, debug };
  }

  // =====================================================================
  // Phase 4: cleaned_primary baseline + gap-aware preservation-mode attempt.
  // =====================================================================
  const pipelineSnapshots: PipelineSnapshot[] = [];
  let cleanedPrimaryBaseline: PipelineSnapshot | null = null;
  if (PIPELINE_V2) {
    const baselineSource =
      enrichedCompilerResult.compilerUsed && enrichedCompilerResult.recipe.ingredientDrafts.length > 0
        ? enrichedCompilerResult.recipe
        : compilerResult.recipe;
    cleanedPrimaryBaseline = buildCleanedPrimarySnapshot({
      ...baselineSource,
      sourceUrl: baselineSource.sourceUrl || canonicalSourceURL,
      remoteImageUrl:
        baselineSource.remoteImageUrl || socialContent?.imageUrls[0] || pageSummary?.imageUrl || ""
    });
    pipelineSnapshots.push(cleanedPrimaryBaseline);
    if (enrichedCompilerResult.compilerUsed) {
      pipelineSnapshots.push(makeSnapshot("compiler_enriched", enrichedCompilerResult.recipe));
    }

    if (pipelineTrace) {
      pipelineTrace.primarySource = enrichedCompilerResult.primarySource
        ?? compilerResult.primarySource
        ?? undefined;
      pipelineTrace.compilerIngredientCount = enrichedCompilerResult.recipe.ingredientDrafts.length;
      pipelineTrace.compilerStepCount = enrichedCompilerResult.recipe.stepDrafts.length;
      pipelineTrace.compilerSectionCount = cleanedPrimaryBaseline.sectionCount;
      pipelineTrace.compilerQuality = cleanedPrimaryBaseline.quality;
    }

    const gapReport = analyzeGaps(enrichedCompilerResult.recipe);
    if (pipelineTrace) {
      pipelineTrace.gaps = gapReport.gaps;
      pipelineTrace.recommendedMode = gapReport.recommendedMode;
      pipelineTrace.llmMode = gapReport.recommendedMode;
    }
    console.info(
      `[importService] Phase 4 gap analysis: mode=${gapReport.recommendedMode} gaps=[${gapReport.gaps.join(",")}] ingredients=${gapReport.ingredientCount} steps=${gapReport.stepCount} sections=${gapReport.sectionCount} for ${canonicalSourceURL}`
    );

    if (
      gapReport.recommendedMode === "preservation" &&
      hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
    ) {
      try {
        const preservationContext = buildContext();
        const preservationTimeout = boundedExecutionTimeout(
          executionDeadline,
          PRESERVATION_TIMEOUT_MS,
          sharedMode ? SHARED_RESERVE_MS : 0
        );
        if (preservationTimeout && preservationTimeout > 3_000) {
          const preservationStart = Date.now();
          const preservedRecipe = await normalizeRecipePreservationMode(
            preservationContext,
            enrichedCompilerResult.recipe,
            {
              timeoutMs: preservationTimeout,
              fillNutrition: gapReport.needsNutrition,
              fillSteps: gapReport.needsSteps,
            }
          );
          pipelineSnapshots.push(makeSnapshot("llm_preservation", preservedRecipe));
          if (pipelineTrace) {
            pipelineTrace.llmDurationMs = Date.now() - preservationStart;
          }
          console.info(
            `[importService] Phase 4 preservation mode produced ingredients=${preservedRecipe.ingredientDrafts.length} steps=${preservedRecipe.stepDrafts.length} for ${canonicalSourceURL}`
          );
        }
      } catch (error) {
        console.warn(
          `[importService] Phase 4 preservation mode failed — falling through to full pipeline: ${(error as Error).message}`
        );
      }
    }
  }

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
      transcript = await transcribeAudioWithFallback(mediaURL, audioOptions).catch(() => null);
    }

    if (isUsableTranscript(transcript, { captionIsSparse: captionWasSparse })) {
      transcript = truncateTranscript(transcript);
      console.info(
        `[importService] Usable transcript obtained (${transcript.length} chars) for ${canonicalSourceURL}`
      );

      const distillTimeoutMs = boundedExecutionTimeout(
        executionDeadline,
        SHARED_TRANSCRIPT_DISTILL_TIMEOUT_MS,
        sharedMode ? SHARED_RESERVE_MS : 0
      );
      if (distillTimeoutMs && distillTimeoutMs > 2_000) {
        try {
          transcriptDigest = await distillTranscriptForRecipe(transcript, {
            timeoutMs: distillTimeoutMs,
            sourceUrl: canonicalSourceURL,
            socialTitle: resolvedSocialContent?.title
          });
          if (transcriptDigest) {
            console.info(
              `[importService] Transcript digest produced (${transcriptDigest.length} chars) for ${canonicalSourceURL}`
            );
            parsedDigest = parseTranscriptDigest(transcriptDigest);
            if (parsedDigest) {
              console.info(
                `[importService] Digest parsed: specificity=${parsedDigest.specificity} dish="${parsedDigest.dish ?? ""}" explicitIngredients=${parsedDigest.explicitIngredients.length} actions=${parsedDigest.actionsSequence.length} gestures=${parsedDigest.signatureGestures.length} noise=${parsedDigest.noiseDetected.length}`
              );
            }
          }
        } catch {
          transcriptDigest = null;
          parsedDigest = null;
        }
      }

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
        // Low-quality transcripts are no longer jetés silencieusement: we keep
        // the raw text as a weak secondary signal for the final normalization
        // and web-fallback passes (LLM decides if it is exploitable) but skip
        // the audio-as-primary reconstruction path.
        transcript = truncateTranscript(rawTranscript);
        console.info(
          `[importService] Transcript kept as weak signal (${rawTranscript.length} chars, below usability threshold) for ${canonicalSourceURL}: "${rawTranscript.slice(0, 120)}"`
        );
      }
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

  // Skip web search when the audio-derived recipe is already valid — the audio
  // content is more faithful to the actual video than a generic web recipe.
  // BUT: never skip when the title is generic (e.g. "Sandwich") or when the
  // recipe drifted away from the digest — those are exactly the cases where
  // the web fallback can rescue a precise title/ingredients.
  const preAudioDrift = recipeDriftedFromDigest(recipe, parsedDigest);
  if (parsedDigest && preAudioDrift.drifted) {
    console.info(
      `[importService] Recipe drifted from digest (pre-web): reasons=[${preAudioDrift.reason.join(", ")}] missingIngredients=${preAudioDrift.missingIngredients.length} missingGestures=${preAudioDrift.missingGestures.length} noiseLeaks=${preAudioDrift.noiseLeaks.length} for ${canonicalSourceURL}`
    );
  }
  if (isGenericDishTitle(recipe.title)) {
    console.info(
      `[importService] Generic title detected (pre-web): "${recipe.title}" — forcing web fallback for ${canonicalSourceURL}`
    );
  }
  const skipWebForAudio = importStrategy === "audio" &&
    isLikelyValidRecipe(recipe, { transcript: transcript ?? undefined }) &&
    !isGenericDishTitle(recipe.title) &&
    !preAudioDrift.drifted;

  if (
    !skipWebForAudio &&
    shouldAttemptSearchEnrichment({
      recipe,
      sourcePlatform,
      captionWasSparse,
      hasTranscript: Boolean(transcript),
      transcript: transcript ?? undefined,
      parsedDigest
    }) &&
    hasExecutionBudget(executionDeadline, sharedMode ? SHARED_RESERVE_MS : 0)
  ) {
    const queries = searchQueryCandidates({
      recipe,
      pageSummary,
      socialContent: resolvedSocialContent,
      sharedText: input.sharedText,
      transcript,
      parsedDigest
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

  if (parsedDigest) {
    const postRescueDrift = recipeDriftedFromDigest(recipe, parsedDigest);
    if (postRescueDrift.drifted) {
      const enrichment = enrichRecipeFromDigest(recipe, parsedDigest, postRescueDrift);
      recipe = enrichment.recipe;
      const titleSuffix = enrichment.titleChanged
        ? `, title="${enrichment.titleChanged.from}"→"${enrichment.titleChanged.to}"`
        : "";
      console.info(
        `[importService] Recipe enriched from digest: +${enrichment.addedIngredients} ingredients, +${enrichment.addedSteps} steps${titleSuffix} for ${canonicalSourceURL}`
      );
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

  // NON-DEGRADATION GUARD (plan §10): compare against the cleaned_primary
  // baseline when PIPELINE_V2 is enabled; otherwise use the legacy
  // quality-ratio guard that only compares to the compiler partial output.
  let bestValidatedRecipe = validatedRecipe;
  if (PIPELINE_V2 && cleanedPrimaryBaseline) {
    pipelineSnapshots.push(makeSnapshot("validated", validatedRecipe));
    const chosen = selectBestSnapshot(pipelineSnapshots);
    if (pipelineTrace) {
      pipelineTrace.snapshots = pipelineSnapshots.map(summarizeSnapshot);
      pipelineTrace.snapshotUsed = chosen.stage;
      pipelineTrace.nonDegradationTriggered = chosen.isBaseline;
    }
    console.info(
      `[importService] Phase 4 snapshot selection: stage=${chosen.stage} isBaseline=${chosen.isBaseline} foodCoverage=${chosen.foodSignalCoverage.toFixed(2)} specificity=${chosen.specificityScore.toFixed(2)} sections=${chosen.sectionCount} ingredients=${chosen.ingredientCount} for ${canonicalSourceURL}`
    );
    bestValidatedRecipe = chosen.recipe;
  } else if (compilerResult.compilerUsed && compilerResult.recipe.ingredientDrafts.length >= 2) {
    const compilerQuality = measureRecipeQuality(compilerResult.recipe);
    const llmQuality = measureRecipeQuality(validatedRecipe);
    if (llmQuality < compilerQuality * 0.85) {
      console.warn(
        `[importService] Non-degradation guard: LLM output (q=${llmQuality.toFixed(2)}) worse than ` +
        `compiler partial (q=${compilerQuality.toFixed(2)}) — using compiler output for ${canonicalSourceURL}`
      );
      bestValidatedRecipe = compilerResult.recipe;
    }
  }

  // Graceful "not enough info" fallback: when caption is sparse, no
  // transcript was usable, and the recipe ended up basically empty, fail
  // explicitly instead of returning a half-fabricated recipe. The iOS
  // client renders a clean error screen for this code.
  if (
    captionWasSparse &&
    !transcript &&
    !usedWebFallback &&
    bestValidatedRecipe.ingredientDrafts.filter((i) => i.name?.trim()).length < 2
  ) {
    console.warn(
      `[importService] No usable caption, transcript or web fallback for ${canonicalSourceURL}; raising not_enough_info.`
    );
    throw new RecipeImportNotFoodError("not_enough_info");
  }

  // Final QA gate: after every retry, reject results that are too thin
  // to be cookable. We'd rather show the user a clean error screen than
  // ship a recipe with 2 vague ingredients and 1 generic step. The
  // thresholds here are intentionally lenient — they only fire when the
  // result is genuinely unusable, not when it's just a simple recipe.
  const qaIssues = assessFinalRecipeQuality(bestValidatedRecipe);
  if (qaIssues.length > 0) {
    console.warn(
      `[importService] QA gate rejected recipe for ${canonicalSourceURL}: ${qaIssues.join("; ")}`
    );
    throw new RecipeImportNotFoodError("not_enough_info");
  }

  const finalizedRecipe = await finalizeImportedRecipe(bestValidatedRecipe, {
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

  if (pipelineTrace) {
    pipelineTrace.totalDurationMs = durationMs;
  }
  return {
    recipe: finalizedRecipe.recipe,
    debug,
    ...(pipelineTrace ? { pipelineTrace } : {})
  };
}

/**
 * Final quality assessment of a recipe before we ship it to the iOS
 * client. Returns an empty array if the recipe is shippable, or a list
 * of human-readable issues if not. Lenient thresholds — we only block
 * results that are genuinely unusable.
 */
function assessFinalRecipeQuality(recipe: RecipeImportResult): string[] {
  const issues: string[] = [];
  const usableIngredients = recipe.ingredientDrafts.filter((i) => {
    const name = i.name?.trim() ?? "";
    return name.length >= 2 && /[a-zA-ZÀ-ÿ]/.test(name);
  });
  const usableSteps = recipe.stepDrafts.filter((s) => {
    const detail = s.detail?.trim() ?? "";
    return detail.length >= 12;
  });

  const title = recipe.title?.trim() ?? "";
  if (!title || title.length < 3) {
    issues.push("title missing or too short");
  }

  if (usableIngredients.length < 3) {
    issues.push(`only ${usableIngredients.length} usable ingredients (need ≥3)`);
  }

  if (usableSteps.length < 3) {
    issues.push(`only ${usableSteps.length} usable steps (need ≥3)`);
  }

  // Title must look like an actual dish, not a category placeholder or
  // a CTA. Bare single-word category titles are flagged.
  if (title) {
    const titleKey = title.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
    const bareCategoryTitles = new Set([
      "recette",
      "recette importée",
      "plat",
      "dish",
      "food",
      "video",
      "tiktok",
      "instagram"
    ]);
    if (bareCategoryTitles.has(titleKey)) {
      issues.push(`title is a bare category placeholder ("${title}")`);
    }
  }

  return issues;
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
function isUsableTranscript(
  transcript: string | null,
  options?: { captionIsSparse?: boolean }
): transcript is string {
  if (!transcript) {
    return false;
  }

  const trimmed = transcript.trim();
  const captionIsSparse = options?.captionIsSparse === true;

  // Too short to contain any useful information at all. When the
  // caption is empty/sparse the audio is our only source — accept much
  // shorter voiceovers (TikToks frequently have ≤ 20 chars of actual
  // spoken content).
  const minLength = captionIsSparse ? 8 : 12;
  if (trimmed.length < minLength) {
    return false;
  }

  // Strip Whisper artifacts like [Music], (applause), etc.
  const cleanedOfBrackets = trimmed
    .replace(/\[.*?\]/g, "")
    .replace(/\(.*?\)/g, "")
    .trim();

  // After stripping brackets, nothing useful remains
  const minCleanedLength = captionIsSparse ? 6 : 8;
  if (!cleanedOfBrackets || cleanedOfBrackets.length < minCleanedLength) {
    return false;
  }

  // Count actual word tokens (not just noise characters)
  const wordCount = cleanedOfBrackets
    .split(/\s+/)
    .filter((w) => w.length >= 2)
    .length;

  // Accept very short transcripts (2+ words) when they contain a food term —
  // a single dish name + one ingredient is enough to seed the digest.
  if (wordCount >= 2 && containsLikelyFoodTitleTerm(normalizeLookup(cleanedOfBrackets))) {
    return true;
  }

  // General threshold: need enough spoken content to be useful. When
  // the caption is empty/sparse, accept 2 word tokens — the LLM gets
  // an explicit directive to extract conservatively.
  const minWordCount = captionIsSparse ? 2 : 3;
  if (wordCount < minWordCount) {
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
  missingPhases: string[];
  groupingGap: boolean;
  expectedGroupLabels: string[];
  summary: string;
  issueCount: number;
};

/**
 * Detects entire cooking phases that are implied by the ingredient list but
 * absent from the steps. Covers the common Cooksy failure mode where the
 * audio transcript is cut short and the LLM only reconstructs the tail end
 * of the recipe (e.g. ships a sandwich recipe with no dough prep, no
 * breading, no frying, no sauce).
 *
 * Uses simple keyword heuristics on the normalized ingredient list + step
 * text — no ML. Each phase is inferred from a distinctive ingredient signal
 * and verified against cooking verbs/nouns in the step text.
 */
function detectMissingPhases(recipe: RecipeImportResult): string[] {
  const ingredientText = normalizeForIngredientMatching(
    recipe.ingredientDrafts.map((ingredient) => ingredient.name).join(" ")
  );
  const stepText = normalizeForIngredientMatching(
    recipe.stepDrafts.map((step) => step.detail).join(" ")
  );

  const has = (haystack: string, needles: string[]): boolean =>
    needles.some((needle) => haystack.includes(needle));

  const missing: string[] = [];

  // Dough-prep phase: if ingredients include flour + yeast/baking or egg,
  // expect steps covering mixing + resting/kneading.
  const hasFlour = has(ingredientText, ["farine", "flour"]);
  const hasYeast = has(ingredientText, ["levure", "yeast"]);
  if (hasFlour && hasYeast) {
    const hasDoughStep = has(stepText, [
      "petrir", "petri", "pate", "reposer", "repos", "lever", "leve",
      "knead", "dough", "rest", "rise"
    ]);
    if (!hasDoughStep) {
      missing.push("dough-prep");
    }
  }

  // Breading phase: raw protein + breadcrumbs implies a coat step.
  const hasProtein = has(ingredientText, [
    "poulet", "chicken", "boeuf", "beef", "porc", "pork", "poisson", "fish",
    "crevette", "shrimp"
  ]);
  const hasBreadcrumbs = has(ingredientText, ["chapelure", "panko", "breadcrumb", "bread crumb"]);
  if (hasProtein && hasBreadcrumbs) {
    const hasCoatStep = has(stepText, [
      "chapelur", "paner", "pane", "enrober", "enrobe", "tremper", "trempe",
      "coat", "bread", "dredge", "dip"
    ]);
    if (!hasCoatStep) {
      missing.push("breading");
    }
  }

  // Frying phase: oil + breadcrumbs or raw protein + mention of friture
  // context suggests frying should appear.
  if (hasProtein && hasBreadcrumbs) {
    const hasFryStep = has(stepText, [
      "frire", "friture", "frit", "friterie", "huile chaude", "huile bien chaude",
      "fry", "deep fry", "pan fry", "saisir"
    ]);
    if (!hasFryStep) {
      missing.push("frying");
    }
  }

  // Sauce phase: signature "hot sauce + honey + butter" or similar sauce
  // ingredient combos imply a sauce-making step.
  const sauceBases = ["sriracha", "tabasco", "gochujang", "harissa", "buffalo"];
  const hasHotSauce = has(ingredientText, sauceBases);
  const hasSweetener = has(ingredientText, ["miel", "honey", "sirop"]);
  const hasButter = has(ingredientText, ["beurre", "butter"]);
  if ((hasHotSauce && hasSweetener) || (hasHotSauce && hasButter)) {
    const hasSauceStep = has(stepText, [
      "sauce", "melange", "mélange", "mix", "chauffer", "tiedir", "tiédir",
      "fondre", "emulsion", "émulsion", "whisk", "combine"
    ]);
    if (!hasSauceStep) {
      missing.push("sauce-prep");
    }
  }

  return missing;
}

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
  const missingPhases = detectMissingPhases(recipe);
  const { groupingGap, expectedGroupLabels } = detectGroupingGap(recipe);

  const hasIssues = unusedIngredients.length > 0 ||
    hasUncoveredIngredients ||
    hasCookBeforePrep ||
    missingPhases.length > 0 ||
    groupingGap;

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
  if (missingPhases.length) {
    parts.push(`missing phases: ${missingPhases.join("+")}`);
  }
  if (groupingGap) {
    parts.push(`grouping gap (expected: ${expectedGroupLabels.join("/")})`);
  }

  return {
    hasIssues,
    unusedIngredients,
    logicalOrderIssue: hasCookBeforePrep,
    missingPhases,
    groupingGap,
    expectedGroupLabels,
    summary: parts.join(", ") || "none",
    issueCount: unusedIngredients.length +
      (hasUncoveredIngredients ? cookability.uncoveredMajorIngredientCount : 0) +
      (hasCookBeforePrep ? 1 : 0) +
      missingPhases.length * 2 +
      (groupingGap ? 2 : 0)
  };
}

/**
 * Detects the common failure mode where the recipe actually has multiple
 * sub-preparations (marinade + sauce + salad + assembly) but the LLM shipped
 * a flat ingredient list with no `group` labels. Uses three signals:
 *   1. Step `section` labels — if the model bothered to tag step sections,
 *      ingredients should share those labels via `group`.
 *   2. Keyword regex on step text — verbs and nouns that give away a
 *      distinct sub-preparation phase ("marinade", "sauce", "dressage"…).
 *   3. Ingredient count — only triggers once the recipe is complex enough
 *      to benefit from grouping (≥6 ingredients, ≥4 steps).
 *
 * When triggered, returns the expected group labels so the review pass can
 * be steered explicitly.
 */
function detectGroupingGap(recipe: RecipeImportResult): {
  groupingGap: boolean;
  expectedGroupLabels: string[];
} {
  if (recipe.ingredientDrafts.length < 6 || recipe.stepDrafts.length < 4) {
    return { groupingGap: false, expectedGroupLabels: [] };
  }

  const ingredientsWithGroup = recipe.ingredientDrafts.filter(
    (ingredient) => (ingredient.group ?? "").trim().length > 0
  ).length;
  if (ingredientsWithGroup >= recipe.ingredientDrafts.length * 0.5) {
    return { groupingGap: false, expectedGroupLabels: [] };
  }

  const stepSections = new Set<string>();
  for (const step of recipe.stepDrafts) {
    const label = (step.section ?? "").trim();
    if (label) {
      stepSections.add(label);
    }
  }

  const SUB_PREP_LABELS: Array<{ label: string; pattern: RegExp }> = [
    { label: "Marinade", pattern: /\bmarinad(?:e|er)\b|\bfaire\s+mariner\b/i },
    { label: "Sauce", pattern: /\bpour\s+la\s+sauce\b|\bsauce\s*(?::|\n)|\bpréparer\s+la\s+sauce\b|\bmélanger.*sauce\b/i },
    { label: "Pâte", pattern: /\bp[âa]te\s*(?::|\n)|\bp[eé]trir\b|\bpour\s+la\s+p[âa]te\b/i },
    { label: "Garniture", pattern: /\bgarniture\s*(?::|\n)|\bpour\s+la\s+garniture\b/i },
    { label: "Salade", pattern: /\bsalade\s*(?::|\n)|\bpour\s+la\s+salade\b/i },
    { label: "Montage", pattern: /\bmontage\s*(?::|\n)|\bmonter\s+le\b|\bassembler\b|\bdressage\b/i },
    { label: "Cuisson", pattern: /\bcuisson\s*(?::|\n)|\bfaire\s+cuire\b/i }
  ];

  const stepsJoined = recipe.stepDrafts.map((s) => s.detail).join(" \n ");
  const keywordLabels = new Set<string>();
  for (const { label, pattern } of SUB_PREP_LABELS) {
    if (pattern.test(stepsJoined)) {
      keywordLabels.add(label);
    }
  }

  const expected = new Set<string>([...stepSections, ...keywordLabels]);

  if (expected.size < 2) {
    return { groupingGap: false, expectedGroupLabels: [] };
  }

  return {
    groupingGap: true,
    expectedGroupLabels: Array.from(expected)
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

  let currentRecipe = recipe;
  let correctedSuccessfully = !issues.hasIssues;

  if (issues.hasIssues) {
    console.info(
      `[importService] Validation failed (${issues.summary}), auto-correcting via cookability review`
    );

    // --- Attempt 1: Auto-correct via LLM cookability review ---
    const reviewTimeoutMs = boundedExecutionTimeout(deadline, 12_000, 1_000);
    if (reviewTimeoutMs) {
      const reviewHint = issues.groupingGap && issues.expectedGroupLabels.length > 0
        ? `GROUPEMENT OBLIGATOIRE — Les étapes révèlent ces sous-préparations : ${issues.expectedGroupLabels.join(", ")}. Tu DOIS répartir CHAQUE ingredientDraft dans le champ \`group\` avec exactement un de ces labels, et marquer la première étape de chaque sous-préparation via \`section\` en réutilisant le même label.`
        : undefined;
      const corrected = await safeReviewCookability(
        { draft: recipe, context, reviewHint },
        { timeoutMs: reviewTimeoutMs }
      );
      const correctedIssues = detectRecipeIssues(corrected);
      if (!correctedIssues.hasIssues) {
        currentRecipe = corrected;
        correctedSuccessfully = true;
      } else if (correctedIssues.issueCount < issues.issueCount) {
        currentRecipe = corrected;
      }
    }

    // --- Attempt 2: Full regeneration via normalizeRecipeFromContext ---
    if (!correctedSuccessfully) {
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

        if (!regeneratedIssues.hasIssues) {
          currentRecipe = regeneratedFixed;
          correctedSuccessfully = true;
        } else if (regeneratedIssues.issueCount < issues.issueCount) {
          currentRecipe = regeneratedFixed;
        }
      }
    }

    // --- Attempt 3: Last-resort structural fix ---
    if (!correctedSuccessfully) {
      console.info(
        `[importService] Regeneration insufficient, applying structural fix as last resort`
      );
      currentRecipe = ensureCookableRecipeStructure(currentRecipe);
    }
  }

  // --- Final strict-validator pass: annotate needsReview when hard
  // issues remain after all repair attempts. Never throws; never blocks
  // the import — the iOS client surfaces this as a non-blocking warning
  // badge. This is the rare fallback path, not the common outcome.
  return annotateStrictValidationFlags(currentRecipe);
}

function annotateStrictValidationFlags(
  recipe: RecipeImportResult
): RecipeImportResult {
  const report = validateStrictRecipe(recipe, {
    minimumSteps: minimumStepCountForRecipeTitle(recipe.title),
  });

  if (report.ok) {
    // Clear any stale needsReview from upstream; everything checks out.
    if (recipe.flags?.needsReview) {
      return {
        ...recipe,
        flags: {
          ...normalizeRecipeImportFlags(recipe.flags),
          needsReview: false,
        },
      };
    }
    return recipe;
  }

  const hardCodes = report.hardIssues.map((issue: StrictIssue) => issue.code).join(", ");
  console.info(
    `[importService] Strict validator flagged needsReview after repair: hardIssues=[${hardCodes}]`
  );

  return {
    ...recipe,
    flags: {
      ...normalizeRecipeImportFlags(recipe.flags),
      needsReview: true,
    },
  };
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
  if (!transcript) {
    return false;
  }

  // When the caption is empty/sparse and audio is the only source, do
  // not gate on transcript length — we want every audio-only video to
  // get a real LLM normalization pass instead of falling through to
  // the heuristic recipe builder. Otherwise keep the original 60-char
  // safety margin that filters out music-only or one-word transcripts.
  if (!context.audioIsPrimarySource && transcript.length < 60) {
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

  if (isGenericDishTitle(recipe.title)) {
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

  if (isGenericDishTitle(recipe.title)) {
    return true;
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
  parsedDigest?: ParsedTranscriptDigest | null;
}): boolean {
  // Generic title or drifted recipe ⇒ always try the web to recover precision.
  if (isGenericDishTitle(input.recipe.title)) {
    return true;
  }
  if (input.parsedDigest && recipeDriftedFromDigest(input.recipe, input.parsedDigest).drifted) {
    return true;
  }

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
  transcriptDigest?: string | null;
  fallbackPages?: ImportedPageSummary[];
  audioIsPrimarySource?: boolean;
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
    transcript: input.transcript ?? undefined,
    transcriptDigest: input.transcriptDigest ?? undefined,
    audioIsPrimarySource: input.audioIsPrimarySource === true
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
  parsedDigest?: ParsedTranscriptDigest | null;
}): string[] {
  // Digest-backed priority queries: use DISH + signature gestures + explicit
  // ingredients when available. This produces "philly cheesesteak provolone
  // hoagie" instead of just "burger".
  const digestQueries: (string | undefined)[] = [];
  if (input.parsedDigest) {
    const digest = input.parsedDigest;
    if (digest.dish && digest.dish.toUpperCase() !== "INCONNU" && !isGenericDishTitle(digest.dish)) {
      digestQueries.push(decorateRecipeSearchQuery(digest.dish));
    }
    // head + 2 distinctive ingredients
    if (isGenericDishTitle(input.recipe.title) || digest.specificity !== "high") {
      const head = (digest.dish && digest.dish.toUpperCase() !== "INCONNU")
        ? digest.dish
        : input.recipe.title || "";
      const distinctiveIngredients = digest.explicitIngredients
        .map((value) => value.replace(/\d+[\d,.\s/]*/, "").replace(/\(.*?\)/g, "").trim())
        .filter((value) => value.length >= 3)
        .slice(0, 3);
      if (head || distinctiveIngredients.length > 0) {
        const combined = [head, ...distinctiveIngredients].filter(Boolean).join(" ").trim();
        if (combined) {
          digestQueries.push(decorateRecipeSearchQuery(combined));
        }
      }
    }
  }

  // When the recipe title is generic (single word like "Pizza") and a transcript
  // is available, try to extract a more specific dish phrase from the transcript
  // to produce better search queries (e.g., "pizza tartiflette recette").
  const transcriptDishQuery = input.transcript
    ? decorateRecipeSearchQuery(extractDishPhraseFromText(input.transcript) ?? "")
    : undefined;

  const candidates = [
    ...digestQueries,
    decorateRecipeSearchQuery(input.recipe.searchQuery),
    decorateRecipeSearchQuery(keywordRichRecipeQuery(input)),
    transcriptDishQuery,
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
  parsedDigest?: ParsedTranscriptDigest | null;
}): string | undefined {
  const texts = searchTextCandidates(input);
  const dishPhrase = texts
    .map(extractDishPhraseFromText)
    .find((value): value is string => Boolean(value));
  const foodTerms = collectFoodSearchTerms(texts.join("\n"));
  const head = dishPhrase ??
    foodTerms.find((term) => dishHeadSearchTerms.has(term));

  if (!head) {
    // Last resort: if we have a parsed digest with explicit ingredients, use
    // them directly to compose a query.
    if (input.parsedDigest && input.parsedDigest.explicitIngredients.length > 0) {
      const distinctive = input.parsedDigest.explicitIngredients
        .map((value) => value.replace(/\d+[\d,.\s/]*/, "").replace(/\(.*?\)/g, "").trim())
        .filter((value) => value.length >= 3)
        .slice(0, 3);
      if (distinctive.length > 0) {
        return trimSearchPhrase(distinctive.join(" "));
      }
    }
    return undefined;
  }

  const normalizedHead = normalizeSearchText(head);
  const supportTerms = foodTerms
    .filter((term) => !normalizedHead.includes(normalizeSearchText(term)))
    .filter((term) => term !== head)
    .slice(0, 2);

  // If the head is a generic category word and we have a parsed digest, add
  // the 2 most distinctive ingredients to make the query precise.
  const headIsGeneric = genericDishHeadWords.has(normalizedHead) || dishHeadSearchTerms.has(normalizedHead);
  let digestSupport: string[] = [];
  if (headIsGeneric && input.parsedDigest && input.parsedDigest.explicitIngredients.length > 0) {
    digestSupport = input.parsedDigest.explicitIngredients
      .map((value) => value.replace(/\d+[\d,.\s/]*/, "").replace(/\(.*?\)/g, "").trim())
      .filter((value) => {
        const norm = normalizeSearchText(value);
        return value.length >= 3 && !normalizedHead.includes(norm) && !supportTerms.some((term) => normalizeSearchText(term) === norm);
      })
      .slice(0, 2);
  }

  return trimSearchPhrase([head, ...supportTerms, ...digestSupport].join(" "));
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

// === Fidélité vidéo : digest structuré + détection de dérive ===

type DigestSpecificity = "high" | "medium" | "low";

type ParsedTranscriptDigest = {
  dish?: string;
  specificity: DigestSpecificity;
  explicitIngredients: string[];
  impliedIngredients: string[];
  actionsSequence: string[];
  signatureGestures: string[];
  noiseDetected: string[];
};

// Mots de catégorie qui, seuls, désignent un titre trop générique.
const genericDishHeadWords = new Set([
  "sandwich",
  "burger",
  "pizza",
  "pasta",
  "pates",
  "pates",
  "salade",
  "salad",
  "tacos",
  "taco",
  "wrap",
  "bowl",
  "curry",
  "ramen",
  "gratin",
  "quiche",
  "omelette",
  "soupe",
  "soup",
  "cake",
  "gateau",
  "brownie",
  "cookies",
  "cookie",
  "tarte",
  "crepes",
  "crepe",
  "pancakes",
  "pancake",
  "smoothie",
  "bagel"
]);

// Mots mono-token qui sont DÉJÀ des noms de plats spécifiques (autorisés seuls).
const specificStandaloneDishes = new Set([
  "carbonara",
  "bolognese",
  "bolognaise",
  "risotto",
  "ratatouille",
  "cassoulet",
  "tartiflette",
  "raclette",
  "bibimbap",
  "gyoza",
  "ramen",
  "pho",
  "shakshuka",
  "tiramisu",
  "lasagne",
  "lasagnes",
  "moussaka",
  "paella",
  "couscous",
  "tajine",
  "tagine",
  "falafel",
  "shawarma",
  "kebab",
  "bruschetta",
  "focaccia",
  "tartare",
  "carpaccio",
  "gnocchi",
  "hummus",
  "halloumi",
  "burrata",
  "calzone",
  "panzerotti",
  "panini",
  "croissant",
  "macaron",
  "millefeuille",
  "clafoutis",
  "fondant",
  "crumble"
]);

const titleStopWords = new Set([
  "recette",
  "recipe",
  "facile",
  "rapide",
  "simple",
  "express",
  "maison",
  "delicieux",
  "delicieuse",
  "best",
  "meilleur",
  "meilleure",
  "le",
  "la",
  "les",
  "un",
  "une",
  "des",
  "de",
  "du",
  "au",
  "aux",
  "pour",
  "avec",
  "sans",
  "et",
  "the",
  "a",
  "an"
]);

/**
 * Extrait les sections du digest structuré renvoyé par distillTranscriptForRecipe.
 * Tolère les variantes de casse et l'absence de certaines sections.
 */
export function parseTranscriptDigest(digest?: string | null): ParsedTranscriptDigest | null {
  if (!digest || !digest.trim()) {
    return null;
  }

  const lines = digest.split(/\r?\n/);
  const sections: Record<string, string[]> = {};
  let current: string | null = null;
  let dish: string | undefined;
  let specificity: DigestSpecificity = "low";

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    const headerMatch = line.match(/^([A-Z_]+)\s*:\s*(.*)$/);
    if (headerMatch) {
      const header = headerMatch[1];
      const inline = headerMatch[2]?.trim() ?? "";

      if (header === "DISH") {
        dish = inline || undefined;
        current = null;
        continue;
      }
      if (header === "SPECIFICITY") {
        const value = inline.toLowerCase();
        if (value === "high" || value === "medium" || value === "low") {
          specificity = value;
        }
        current = null;
        continue;
      }
      if (
        header === "INGREDIENTS_EXPLICIT" ||
        header === "INGREDIENTS_IMPLIED" ||
        header === "ACTIONS_SEQUENCE" ||
        header === "SIGNATURE_GESTURES" ||
        header === "NOISE_DETECTED"
      ) {
        current = header;
        sections[current] = sections[current] ?? [];
        if (inline) {
          sections[current].push(inline);
        }
        continue;
      }

      // Header inconnu : on arrête d'accumuler.
      current = null;
      continue;
    }

    if (current) {
      // Strip bullets et numérotations.
      const cleaned = line
        .replace(/^[-*•]\s*/, "")
        .replace(/^\d+[.)]\s*/, "")
        .trim();
      if (cleaned && !/^aucun\b/i.test(cleaned)) {
        sections[current].push(cleaned);
      }
    }
  }

  return {
    dish: dish || undefined,
    specificity,
    explicitIngredients: sections["INGREDIENTS_EXPLICIT"] ?? [],
    impliedIngredients: sections["INGREDIENTS_IMPLIED"] ?? [],
    actionsSequence: sections["ACTIONS_SEQUENCE"] ?? [],
    signatureGestures: sections["SIGNATURE_GESTURES"] ?? [],
    noiseDetected: sections["NOISE_DETECTED"] ?? []
  };
}

/**
 * Indique si le titre courant est trop générique (un mot de catégorie seul).
 */
export function isGenericDishTitle(title?: string): boolean {
  if (!title || typeof title !== "string") {
    return true;
  }
  const trimmed = title.trim();
  if (trimmed.length < 3) {
    return true;
  }
  const lowered = trimmed.toLowerCase();
  if (lowered === "recette importée" || lowered === "recette") {
    return true;
  }

  const tokens = normalizeSearchText(trimmed)
    .split(/\s+/)
    .filter((token) => token && !titleStopWords.has(token));

  if (tokens.length === 0) {
    return true;
  }
  if (tokens.length === 1) {
    const token = tokens[0];
    if (specificStandaloneDishes.has(token)) {
      return false;
    }
    if (genericDishHeadWords.has(token) || dishHeadSearchTerms.has(token)) {
      return true;
    }
    return false;
  }

  // Plusieurs tokens significatifs ⇒ probablement un titre composé valide.
  return false;
}

function normalizeIngredientLabel(label: string): string {
  return normalizeSearchText(label)
    .replace(/^\d+[\d,\.\s\/]*/, "")
    .replace(/\b(g|gr|kg|ml|cl|l|tasse|cuillere|cuilleres|cuillère|cuillères|cs|cc|c\s*a\s*s|c\s*a\s*c|pincee|pincée|pincees|pincées|sachet|tranche|tranches|portion|portions|piece|pieces|pièce|pièces)\b/g, " ")
    .replace(/\(.*?\)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function ingredientNoiseTokens(name: string): string[] {
  return normalizeIngredientLabel(name)
    .split(/\s+/)
    .filter((token) => token.length >= 3 && !titleStopWords.has(token));
}

function recipeContainsIngredient(recipe: RecipeImportResult, digestIngredient: string): boolean {
  const tokens = ingredientNoiseTokens(digestIngredient);
  if (tokens.length === 0) {
    return true;
  }

  const haystack = recipe.ingredientDrafts
    .map((ingredient) => normalizeIngredientLabel(ingredient.name))
    .join(" | ");
  if (!haystack) {
    return false;
  }

  // Considère "présent" si au moins un token distinctif (≥4 chars) ou
  // 60% des tokens sont retrouvés dans la liste d'ingrédients.
  const distinctive = tokens.filter((token) => token.length >= 4);
  if (distinctive.length > 0) {
    if (distinctive.some((token) => haystack.includes(token))) {
      return true;
    }
  }

  const matches = tokens.filter((token) => haystack.includes(token)).length;
  return matches / tokens.length >= 0.6;
}

function recipeContainsGesture(recipe: RecipeImportResult, gesture: string): boolean {
  const tokens = ingredientNoiseTokens(gesture);
  if (tokens.length === 0) {
    return true;
  }

  const haystack = recipe.stepDrafts
    .map((step) => normalizeSearchText(step.detail))
    .join(" | ");
  if (!haystack) {
    return false;
  }

  const distinctive = tokens.filter((token) => token.length >= 5);
  if (distinctive.length > 0 && distinctive.some((token) => haystack.includes(token))) {
    return true;
  }

  const matches = tokens.filter((token) => haystack.includes(token)).length;
  return matches / tokens.length >= 0.5;
}

export type RecipeDriftReport = {
  drifted: boolean;
  missingIngredients: string[];
  missingGestures: string[];
  noiseLeaks: string[];
  reason: string[];
};

/**
 * Détecte si la recette générée s'est éloignée du digest (titre générique,
 * ingrédients explicites manquants, gestes signature manquants, bruit qui a fui).
 */
export function recipeDriftedFromDigest(
  recipe: RecipeImportResult,
  digest: ParsedTranscriptDigest | null
): RecipeDriftReport {
  const report: RecipeDriftReport = {
    drifted: false,
    missingIngredients: [],
    missingGestures: [],
    noiseLeaks: [],
    reason: []
  };

  if (!digest) {
    return report;
  }

  for (const ingredient of digest.explicitIngredients) {
    if (!recipeContainsIngredient(recipe, ingredient)) {
      report.missingIngredients.push(ingredient);
    }
  }

  for (const gesture of digest.signatureGestures) {
    if (!recipeContainsGesture(recipe, gesture)) {
      report.missingGestures.push(gesture);
    }
  }

  const recipeText = [
    recipe.title,
    ...recipe.ingredientDrafts.map((i) => i.name),
    ...recipe.stepDrafts.map((s) => s.detail),
    recipe.notesText ?? ""
  ]
    .map(normalizeSearchText)
    .join(" | ");

  for (const noise of digest.noiseDetected) {
    const normalized = normalizeSearchText(noise);
    if (!normalized) {
      continue;
    }
    const distinctiveTokens = normalized
      .split(/\s+/)
      .filter((token) => token.length >= 5 && !titleStopWords.has(token));
    if (distinctiveTokens.length === 0) {
      continue;
    }
    if (distinctiveTokens.every((token) => recipeText.includes(token))) {
      report.noiseLeaks.push(noise);
    }
  }

  const totalExplicit = digest.explicitIngredients.length;
  const missingRatio = totalExplicit > 0 ? report.missingIngredients.length / totalExplicit : 0;

  if (totalExplicit > 0 && missingRatio >= 0.3) {
    report.drifted = true;
    report.reason.push(`missing-ingredients-ratio=${missingRatio.toFixed(2)}`);
  }
  if (report.missingGestures.length > 0) {
    report.drifted = true;
    report.reason.push(`missing-gestures=${report.missingGestures.length}`);
  }
  if (report.noiseLeaks.length > 0) {
    report.drifted = true;
    report.reason.push(`noise-leaks=${report.noiseLeaks.length}`);
  }
  if (digest.specificity === "high" && isGenericDishTitle(recipe.title)) {
    report.drifted = true;
    report.reason.push("generic-title-vs-high-specificity");
  }

  return report;
}

const noisePhrases = [
  "abonne toi",
  "abonnez vous",
  "abonne-toi",
  "follow",
  "like la video",
  "like la vidéo",
  "lien en bio",
  "code promo",
  "swipe up",
  "n oublie pas",
  "fais le toi meme",
  "fais-le toi-même",
  "salut tout le monde",
  "bienvenue",
  "merci d avoir regarde",
  "merci d'avoir regardé"
];

function stripNoiseFromText(value: string): string {
  if (!value) {
    return value;
  }
  let cleaned = value;
  const lowered = normalizeSearchText(value);
  for (const phrase of noisePhrases) {
    if (lowered.includes(phrase)) {
      // Suppression best-effort en gardant la ponctuation.
      const regex = new RegExp(phrase.replace(/\s+/g, "\\s+").replace(/[-]/g, "[-\\s]?"), "gi");
      cleaned = cleaned.replace(regex, " ").replace(/\s{2,}/g, " ").trim();
    }
  }
  return cleaned;
}

function pickEnglishNutritionQuery(name: string): string {
  // Best-effort : on tente une traduction très simple via une mini-table,
  // sinon on renvoie le nom français qui sera traité par USDA en "best match".
  const table: Record<string, string> = {
    "provolone": "provolone cheese",
    "mozzarella": "mozzarella cheese",
    "burrata": "burrata cheese",
    "ricotta": "ricotta cheese",
    "cheddar": "cheddar cheese",
    "panko": "panko breadcrumbs",
    "gochujang": "gochujang paste",
    "ribeye": "ribeye steak",
    "entrecote": "ribeye steak",
    "baguette": "french baguette",
    "hoagie": "hoagie roll",
    "kiri": "cream cheese",
    "boursin": "boursin cheese"
  };
  const key = normalizeSearchText(name).split(/\s+/)[0];
  return table[key] ?? name;
}

/**
 * Garde-fou final : si la recette dérive du digest, ajoute les ingrédients
 * et étapes manquants depuis le digest, purge le bruit, recompose le titre
 * si générique. Préserve les ingrédients/étapes existants.
 */
export function enrichRecipeFromDigest(
  recipe: RecipeImportResult,
  digest: ParsedTranscriptDigest | null,
  drift?: RecipeDriftReport
): { recipe: RecipeImportResult; addedIngredients: number; addedSteps: number; titleChanged?: { from: string; to: string } } {
  if (!digest) {
    return { recipe, addedIngredients: 0, addedSteps: 0 };
  }

  const report = drift ?? recipeDriftedFromDigest(recipe, digest);
  let next: RecipeImportResult = { ...recipe };
  let addedIngredients = 0;
  let addedSteps = 0;
  let titleChanged: { from: string; to: string } | undefined;

  // 1) Titre : si générique, recompose à partir de DISH ou des ingrédients distinctifs.
  if (isGenericDishTitle(next.title)) {
    let newTitle: string | undefined;
    if (digest.dish && !isGenericDishTitle(digest.dish) && digest.dish.toUpperCase() !== "INCONNU") {
      newTitle = digest.dish.trim();
    } else if (digest.explicitIngredients.length > 0) {
      const head = next.title?.trim() || "Recette";
      const distinctive = digest.explicitIngredients
        .map((ingredient) => ingredient.replace(/\d+[\d,\.\s\/]*/, "").trim())
        .filter((ingredient) => ingredient.length > 0)
        .slice(0, 2);
      if (distinctive.length > 0) {
        newTitle = `${head} ${distinctive.join(" ")}`.replace(/\s+/g, " ").trim();
      }
    }

    if (newTitle && newTitle !== next.title) {
      titleChanged = { from: next.title, to: newTitle };
      next = { ...next, title: newTitle };
    }
  }

  // 2) Ingrédients manquants : ajoute les explicites absents.
  if (report.missingIngredients.length > 0) {
    const newIngredients = [...next.ingredientDrafts];
    for (const missing of report.missingIngredients) {
      const cleanName = missing
        .replace(/\(.*?\)/g, "")
        .replace(/^\d+[\d,\.\s\/]*/, "")
        .trim();
      if (!cleanName) {
        continue;
      }
      // Filtre anti-bruit : doit ressembler à un mot alimentaire.
      const tokens = ingredientNoiseTokens(cleanName);
      if (tokens.length === 0) {
        continue;
      }
      newIngredients.push({
        amount: "",
        unit: "",
        name: cleanName,
        nutritionQuery: pickEnglishNutritionQuery(cleanName)
      });
      addedIngredients += 1;
    }
    if (addedIngredients > 0) {
      next = { ...next, ingredientDrafts: newIngredients };
    }
  }

  // 3) Étapes manquantes : insère les signature gestures avant le dernier dressage.
  if (report.missingGestures.length > 0) {
    const newSteps = [...next.stepDrafts];
    const insertPosition = Math.max(newSteps.length - 1, 0);
    for (const gesture of report.missingGestures) {
      newSteps.splice(insertPosition, 0, {
        section: "",
        detail: gesture.charAt(0).toUpperCase() + gesture.slice(1)
      });
      addedSteps += 1;
    }
    next = { ...next, stepDrafts: newSteps };
  }

  // 4) Purge bruit dans titre, ingrédients, étapes, notes.
  if (digest.noiseDetected.length > 0 || noisePhrases.length > 0) {
    next = {
      ...next,
      title: stripNoiseFromText(next.title),
      notesText: stripNoiseFromText(next.notesText ?? ""),
      ingredientDrafts: next.ingredientDrafts.map((ingredient) => ({
        ...ingredient,
        name: stripNoiseFromText(ingredient.name)
      })),
      stepDrafts: next.stepDrafts.map((step) => ({
        ...step,
        detail: stripNoiseFromText(step.detail)
      }))
    };
  }

  // 5) Si encore générique malgré tout, demande un fallback web.
  if (isGenericDishTitle(next.title)) {
    next = {
      ...next,
      needsWebFallback: true,
      confidence: "low"
    };
  }

  return { recipe: next, addedIngredients, addedSteps, titleChanged };
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
    failureReason,
    needsReview: recipe.flags?.needsReview === true
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

  const rawGeneratedSteps = generateCookableStepDrafts(title, sanitizedRecipe.ingredientDrafts);
  // When the recipe already has a real ingredient list (>= 4 items), the
  // generated step templates must not reference any ingredient-shaped noun
  // that is not actually in that list — otherwise we hallucinate cross-
  // template content (e.g. poulet in a crêpe batter).
  const generatedSteps =
    sanitizedRecipe.ingredientDrafts.length >= 4
      ? filterGeneratedStepsAgainstIngredients(rawGeneratedSteps, sanitizedRecipe.ingredientDrafts)
      : rawGeneratedSteps;
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

type TranscriptionOptions = {
  mediaFetchTimeoutMs: number;
  transcriptionTimeoutMs: number;
  maxDurationSeconds: number;
  maxFileBytes: number;
};

// Route transcription through Google Cloud Speech when credentials are
// available, falling back to OpenAI Whisper when Google fails or is not
// configured. Google's speechContexts biasing gives us much better
// recognition of cooking-specific vocabulary (provolone, panko, gochujang,
// cuillère à soupe) which directly translates into more precise ingredient
// names and quantities in the final recipe.
// Process-wide circuit breaker: when Google Speech-to-Text returns a
// fatal config error (API not enabled, missing scope, billing not set
// up…), we stop trying for the rest of the process lifetime. Avoids
// spamming the logs and burning a second per request on a doomed call.
let googleSpeechDisabledReason: string | null = null;

function isFatalGoogleSpeechError(error: unknown): string | null {
  const message = error instanceof Error ? error.message : String(error);
  if (!message) return null;
  if (/PERMISSION_DENIED/i.test(message)) return "permission_denied";
  if (/has not been used in project|api has not been enabled/i.test(message)) return "api_disabled";
  if (/Could not load the default credentials|invalid_grant|invalid_client/i.test(message)) return "bad_credentials";
  if (/billing/i.test(message)) return "billing_required";
  return null;
}

async function transcribeAudioWithFallback(
  mediaUrl: string | undefined,
  options: TranscriptionOptions
): Promise<string | null> {
  if (!mediaUrl) {
    return null;
  }

  if (providerStatus.googleSpeech && !googleSpeechDisabledReason) {
    try {
      const googleTranscript = await transcribeWithGoogleFromUrl(mediaUrl, {
        mediaFetchTimeoutMs: options.mediaFetchTimeoutMs,
        maxDurationSeconds: options.maxDurationSeconds,
        maxFileBytes: options.maxFileBytes
      });
      if (googleTranscript && googleTranscript.trim().length > 0) {
        console.info(`[transcription] provider=google length=${googleTranscript.length}`);
        return googleTranscript;
      }
      console.info("[transcription] provider=google result=empty, falling back to openAI");
    } catch (error) {
      const fatal = isFatalGoogleSpeechError(error);
      if (fatal) {
        googleSpeechDisabledReason = fatal;
        console.warn(
          `[transcription] Google Speech-to-Text fatally disabled (${fatal}); using OpenAI Whisper exclusively for the rest of this process.`
        );
      } else {
        console.warn(
          `[transcription] provider=google error=${(error as Error).message ?? String(error)}, falling back to openAI`
        );
      }
    }
  }

  const whisperTranscript = await transcribeMediaFromUrl(mediaUrl, options).catch(() => null);
  if (whisperTranscript) {
    console.info(`[transcription] provider=openAI length=${whisperTranscript.length}`);
  }
  return whisperTranscript;
}

function transcriptionOptions(
  profile: ImportRuntimeProfile,
  deadline?: number
): TranscriptionOptions | null | undefined {
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
    mediaFetchTimeoutMs: 12_000,
    transcriptionTimeoutMs: 30_000,
    maxDurationSeconds: 300,
    maxFileBytes: 14 * 1024 * 1024
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

const GENERATED_STEP_INGREDIENT_TOKENS: ReadonlyArray<{ token: string; keys: ReadonlyArray<string> }> = [
  { token: "poulet", keys: ["poulet", "chicken"] },
  { token: "boeuf", keys: ["boeuf", "bœuf", "beef", "steak hach", "ground beef"] },
  { token: "porc", keys: ["porc", "pork", "lard", "bacon"] },
  { token: "poisson", keys: ["poisson", "saumon", "cabillaud", "thon", "fish"] },
  { token: "crevettes", keys: ["crevette", "shrimp"] },
  { token: "pates", keys: ["pate", "pâtes", "pasta", "spaghetti", "penne", "tagliatelle", "linguine", "fusilli", "rigatoni", "ravioli", "gnocchi", "macaroni"] },
  { token: "riz", keys: ["riz", "rice"] },
  { token: "farine", keys: ["farine", "flour"] },
  { token: "sucre", keys: ["sucre", "sugar"] },
  { token: "oeufs", keys: ["oeuf", "œuf", "egg"] },
  { token: "lait", keys: ["lait", "milk"] },
  { token: "beurre", keys: ["beurre", "butter"] },
  { token: "creme", keys: ["creme", "crème", "cream"] },
  { token: "fromage", keys: ["fromage", "cheese", "cheddar", "mozzarella", "parmesan", "provolone", "feta", "gruyere"] },
  { token: "yaourt", keys: ["yaourt", "yogurt", "fromage blanc"] },
  { token: "ail", keys: ["ail", "garlic"] },
  { token: "oignon", keys: ["oignon", "onion", "echalote", "échalote"] },
  { token: "tomate", keys: ["tomate", "tomato"] },
  { token: "pain", keys: ["pain", "bread", "bun", "naan", "tortilla", "flatbread", "wrap"] },
  { token: "levure", keys: ["levure", "yeast"] },
  { token: "vanille", keys: ["vanille", "vanilla"] },
  { token: "chocolat", keys: ["chocolat", "chocolate", "cacao", "cocoa"] },
  { token: "mascarpone", keys: ["mascarpone"] },
  { token: "cafe", keys: ["cafe", "café", "coffee", "espresso"] },
  { token: "boudoirs", keys: ["boudoir", "ladyfinger"] }
];

function foldStepText(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/œ/g, "oe")
    .replace(/æ/g, "ae");
}

function filterGeneratedStepsAgainstIngredients(
  steps: Array<{ detail: string }>,
  ingredients: RecipeImportResult["ingredientDrafts"]
): Array<{ detail: string }> {
  const ingredientBlob = foldStepText(
    ingredients.map((ingredient) => ingredient.name ?? "").join(" | ")
  );
  return steps.filter((step) => {
    const stepBody = foldStepText(step.detail ?? "");
    for (const entry of GENERATED_STEP_INGREDIENT_TOKENS) {
      const token = entry.token;
      const tokenRegex = new RegExp(`\\b${token}s?\\b`);
      if (!tokenRegex.test(stepBody)) {
        continue;
      }
      const hasMatch = entry.keys.some((key) => ingredientBlob.includes(foldStepText(key)));
      if (!hasMatch) {
        return false;
      }
    }
    return true;
  });
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
