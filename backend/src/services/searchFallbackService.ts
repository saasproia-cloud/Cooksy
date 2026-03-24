import * as cheerio from "cheerio";

import { env, providerStatus } from "../config/env.js";
import { fetchPageSummary } from "./generalPageService.js";

export type SearchResultPage = {
  url: string;
  title?: string;
  snippet?: string;
};

export async function searchRecipePages(
  query: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<SearchResultPage[]> {
  if (!query.trim()) {
    return [];
  }

  if (providerStatus.serpApi) {
    const serpResults = await searchRecipePagesViaSerpApi(query, options);
    if (serpResults.length) {
      return serpResults;
    }
  }

  return searchRecipePagesViaDuckDuckGo(query, options);
}

async function searchRecipePagesViaSerpApi(
  query: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<SearchResultPage[]> {
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
    signal: AbortSignal.timeout(options?.timeoutMs ?? 20_000)
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

  return dedupeSearchResults(
    (json.organic_results ?? [])
    .map((result) => ({
      url: result.link ?? "",
      title: result.title,
      snippet: result.snippet
    }))
  );
}

async function searchRecipePagesViaDuckDuckGo(
  query: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<SearchResultPage[]> {
  const params = new URLSearchParams({
    q: `${query} recette`
  });
  const response = await fetch(`https://html.duckduckgo.com/html/?${params.toString()}`, {
    headers: {
      "user-agent": "CooksyBot/1.0 (+https://cooksy.app)",
      "accept-language": "fr-FR,fr;q=0.9,en;q=0.8"
    },
    signal: AbortSignal.timeout(options?.timeoutMs ?? 12_000)
  });

  if (!response.ok) {
    return [];
  }

  const html = await response.text();
  const $ = cheerio.load(html);
  const results: SearchResultPage[] = [];

  $(".result").each((_, element) => {
    if (results.length >= 5) {
      return false;
    }

    const anchor = $(element).find("a.result__a").first();
    const rawHref = anchor.attr("href") ?? "";
    const url = decodeDuckDuckGoTarget(rawHref);
    const title = anchor.text().trim();
    const snippet = $(element).find(".result__snippet").first().text().trim();

    if (url) {
      results.push({ url, title, snippet });
    }

    return undefined;
  });

  return dedupeSearchResults(results);
}

function decodeDuckDuckGoTarget(rawHref: string): string {
  if (!rawHref) {
    return "";
  }

  try {
    const url = new URL(rawHref, "https://html.duckduckgo.com");
    if (url.hostname.includes("duckduckgo.com") && url.pathname.startsWith("/l/")) {
      return url.searchParams.get("uddg") ?? "";
    }

    return url.toString();
  } catch {
    return rawHref;
  }
}

function dedupeSearchResults(results: SearchResultPage[]): SearchResultPage[] {
  const seen = new Set<string>();

  return results.filter((result) => {
    if (!result.url) {
      return false;
    }

    let parsedURL: URL;
    try {
      parsedURL = new URL(result.url);
    } catch {
      return false;
    }

    const host = parsedURL.host.toLowerCase();
    if (
      host.includes("tiktok") ||
      host.includes("instagram") ||
      host.includes("pinterest") ||
      host.includes("pin.it") ||
      host.includes("facebook")
    ) {
      return false;
    }

    const dedupeKey = parsedURL.toString();
    if (seen.has(dedupeKey)) {
      return false;
    }

    seen.add(dedupeKey);
    return true;
  });
}

export async function fetchFallbackPages(
  query: string,
  options?: {
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
  const results = await searchRecipePages(query, options);
  const pages = await Promise.all(
    results.slice(0, 3).map(async (result) => {
      try {
        return await fetchPageSummary(result.url, {
          timeoutMs: options?.timeoutMs
        });
      } catch {
        return null;
      }
    })
  );

  return pages.filter((page): page is NonNullable<typeof page> => Boolean(page));
}
