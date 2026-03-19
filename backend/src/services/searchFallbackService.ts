import { env, providerStatus } from "../config/env.js";
import { fetchPageSummary } from "./generalPageService.js";

export type SearchResultPage = {
  url: string;
  title?: string;
  snippet?: string;
};

export async function searchRecipePages(query: string): Promise<SearchResultPage[]> {
  if (!providerStatus.serpApi || !query.trim()) {
    return [];
  }

  const params = new URLSearchParams({
    engine: "google",
    q: `${query} recette`,
    hl: "fr",
    gl: "fr",
    num: "5",
    api_key: env.SERPAPI_KEY
  });

  const response = await fetch(`https://serpapi.com/search.json?${params.toString()}`, {
    signal: AbortSignal.timeout(20_000)
  });

  if (!response.ok) {
    return [];
  }

  const json = await response.json() as {
    organic_results?: Array<{
      link?: string;
      title?: string;
      snippet?: string;
    }>;
  };

  return (json.organic_results ?? [])
    .map((result) => ({
      url: result.link ?? "",
      title: result.title,
      snippet: result.snippet
    }))
    .filter((result) => {
      if (!result.url) {
        return false;
      }

      try {
        const host = new URL(result.url).host.toLowerCase();
        return !host.includes("tiktok") && !host.includes("instagram");
      } catch {
        return false;
      }
    });
}

export async function fetchFallbackPages(query: string): Promise<Array<{
  url: string;
  title?: string;
  description?: string;
  textContent?: string;
  structuredDataBlocks: string[];
  imageUrl?: string;
}>> {
  const results = await searchRecipePages(query);
  const pages = await Promise.all(
    results.slice(0, 3).map(async (result) => {
      try {
        return await fetchPageSummary(result.url);
      } catch {
        return null;
      }
    })
  );

  return pages.filter((page): page is NonNullable<typeof page> => Boolean(page));
}
