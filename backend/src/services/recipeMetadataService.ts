import { fetchPageSummary } from "./generalPageService.js";
import { searchRecipePages } from "./searchFallbackService.js";
import { sanitizeRecipeImport, type RecipeImportResult } from "../types/recipe.js";
import { normalizeWhitespace } from "../utils/text.js";

type RatingCandidate = {
  rating: number;
  ratingCount?: number;
  recipeName?: string;
};

export async function enrichRecipePresentationMetadata(
  recipe: RecipeImportResult,
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  const enrichedRating = await estimateExternalRating(recipe, options?.timeoutMs).catch(() => null);

  return sanitizeRecipeImport({
    ...recipe,
    externalRating: enrichedRating?.rating ?? recipe.externalRating,
    externalRatingCount: enrichedRating?.ratingCount ?? recipe.externalRatingCount
  });
}

async function estimateExternalRating(
  recipe: RecipeImportResult,
  timeoutMs = 8_000
): Promise<RatingCandidate | null> {
  const title = normalizeWhitespace(recipe.title);
  if (!title) {
    return null;
  }

  const results = await searchRecipePages(recipe.searchQuery || title, {
    timeoutMs: Math.min(timeoutMs, 4_500)
  });
  if (!results.length) {
    return null;
  }

  const pages = await Promise.all(
    results.slice(0, 3).map(async (result) => {
      try {
        return await fetchPageSummary(result.url, {
          timeoutMs: Math.min(timeoutMs, 3_000)
        });
      } catch {
        return null;
      }
    })
  );

  const candidates = pages
    .flatMap((page) => page ? extractRatingCandidates(page.structuredDataBlocks) : [])
    .map((candidate) => ({
      candidate,
      relevance: recipeNameRelevance(title, candidate.recipeName)
    }))
    .filter(({ candidate, relevance }) => {
      if (candidate.rating < 0 || candidate.rating > 5) {
        return false;
      }
      return relevance >= 0.25 || !candidate.recipeName;
    });

  if (!candidates.length) {
    return null;
  }

  candidates.sort((left, right) => {
    if (right.relevance !== left.relevance) {
      return right.relevance - left.relevance;
    }

    return (right.candidate.ratingCount ?? 0) - (left.candidate.ratingCount ?? 0);
  });

  return candidates[0]?.candidate ?? null;
}

function extractRatingCandidates(structuredDataBlocks: string[]): RatingCandidate[] {
  const candidates: RatingCandidate[] = [];

  for (const block of structuredDataBlocks) {
    try {
      const parsed = JSON.parse(block) as unknown;
      collectRatingCandidates(parsed, candidates);
    } catch {
      continue;
    }
  }

  return candidates;
}

function collectRatingCandidates(node: unknown, candidates: RatingCandidate[], inheritedName?: string): void {
  if (!node) {
    return;
  }

  if (Array.isArray(node)) {
    for (const item of node) {
      collectRatingCandidates(item, candidates, inheritedName);
    }
    return;
  }

  if (typeof node !== "object") {
    return;
  }

  const record = node as Record<string, unknown>;
  const nextInheritedName = stringValue(record.name) ?? inheritedName;
  const aggregateRating = record.aggregateRating;

  if (aggregateRating && typeof aggregateRating === "object") {
    const candidate = ratingCandidateFromRecord(aggregateRating as Record<string, unknown>, nextInheritedName);
    if (candidate) {
      candidates.push(candidate);
    }
  }

  const directCandidate = ratingCandidateFromRecord(record, nextInheritedName);
  if (directCandidate) {
    candidates.push(directCandidate);
  }

  if (Array.isArray(record["@graph"])) {
    collectRatingCandidates(record["@graph"], candidates, nextInheritedName);
  }

  for (const value of Object.values(record)) {
    if (value && typeof value === "object" && value !== aggregateRating) {
      collectRatingCandidates(value, candidates, nextInheritedName);
    }
  }
}

function ratingCandidateFromRecord(record: Record<string, unknown>, recipeName?: string): RatingCandidate | null {
  const ratingValue = numericValue(record.ratingValue);
  if (ratingValue == null || ratingValue <= 0 || ratingValue > 5) {
    return null;
  }

  const ratingCount = numericValue(record.ratingCount) ?? numericValue(record.reviewCount);

  return {
    rating: Math.round(ratingValue * 10) / 10,
    ratingCount: ratingCount != null && ratingCount > 0 ? Math.round(ratingCount) : undefined,
    recipeName
  };
}

function numericValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.replace(",", ".").replace(/[^0-9.]/g, "");
    const parsed = Number(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = normalizeWhitespace(value);
  return normalized || undefined;
}

function recipeNameRelevance(title: string, candidateName?: string): number {
  if (!candidateName) {
    return 0.4;
  }

  const titleTokens = normalizedTokens(title);
  const candidateTokens = normalizedTokens(candidateName);

  if (!titleTokens.length || !candidateTokens.length) {
    return 0;
  }

  const overlap = titleTokens.filter((token) => candidateTokens.includes(token));
  return overlap.length / Math.max(titleTokens.length, candidateTokens.length);
}

function normalizedTokens(value: string): string[] {
  return normalizeWhitespace(value)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length > 2 && !["recipe", "recette", "easy", "simple"].includes(token));
}
