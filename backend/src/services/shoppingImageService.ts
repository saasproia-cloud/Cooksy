import { env, providerStatus } from "../config/env.js";

type ShoppingImageRequest = {
  id: string;
  article: string;
  category?: string;
};

type ShoppingImageResult = {
  id: string;
  imageUrl?: string;
  sourcePageUrl?: string;
};

const imageCache = new Map<string, ShoppingImageResult>();

export async function enrichShoppingImages(items: ShoppingImageRequest[]): Promise<ShoppingImageResult[]> {
  const uniqueItems = items.filter((item, index, array) => {
    return array.findIndex((candidate) => candidate.id === item.id) === index;
  });

  const results = await Promise.all(uniqueItems.map((item) => searchImageForItem(item)));
  return results;
}

async function searchImageForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  const cacheKey = `${item.article.toLowerCase()}::${item.category ?? ""}`;
  const cached = imageCache.get(cacheKey);
  if (cached) {
    return { ...cached, id: item.id };
  }

  const result = await searchRemoteImage(item);

  imageCache.set(cacheKey, result);
  return { ...result, id: item.id };
}

async function searchRemoteImage(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  const serpApiResult = await searchSerpApiForItem(item);
  if (serpApiResult.imageUrl) {
    return serpApiResult;
  }

  const wikimediaResult = await searchWikimediaForItem(item);
  if (wikimediaResult.imageUrl) {
    return wikimediaResult;
  }

  return { id: item.id };
}

async function searchSerpApiForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  if (!providerStatus.serpApi) {
    return { id: item.id };
  }

  try {
    const params = new URLSearchParams({
      engine: "google_images",
      q: buildShoppingQuery(item.article, item.category),
      safe: "active",
      ijn: "0",
      api_key: env.SERPAPI_KEY
    });

    const response = await fetch(`https://serpapi.com/search.json?${params.toString()}`, {
      signal: AbortSignal.timeout(20_000)
    });

    if (!response.ok) {
      return { id: item.id };
    }

    const json = await response.json() as {
      images_results?: Array<{
        original?: string;
        thumbnail?: string;
        link?: string;
      }>;
    };

    const bestImage = json.images_results?.find((entry) => entry.original || entry.thumbnail);
    return {
      id: item.id,
      imageUrl: bestImage?.original ?? bestImage?.thumbnail,
      sourcePageUrl: bestImage?.link
    };
  } catch {
    return { id: item.id };
  }
}

async function searchWikimediaForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  for (const query of buildWikimediaQueries(item.article, item.category)) {
    const result = await searchWikimediaQuery(item.id, query);
    if (result.imageUrl) {
      return result;
    }
  }

  return { id: item.id };
}

async function searchWikimediaQuery(id: string, query: string): Promise<ShoppingImageResult> {
  try {
    const params = new URLSearchParams({
      action: "query",
      generator: "search",
      gsrsearch: query,
      gsrlimit: "3",
      prop: "pageimages",
      piprop: "thumbnail",
      pithumbsize: "360",
      format: "json",
      origin: "*"
    });

    const response = await fetch(`https://en.wikipedia.org/w/api.php?${params.toString()}`, {
      signal: AbortSignal.timeout(10_000)
    });

    if (!response.ok) {
      return { id };
    }

    const json = await response.json() as {
      query?: {
        pages?: Record<string, {
          pageid?: number;
          title?: string;
          thumbnail?: {
            source?: string;
          };
        }>;
      };
    };

    const pages = Object.values(json.query?.pages ?? {})
      .filter((page) => page.thumbnail?.source)
      .filter((page) => !looksLikeWikimediaNoise(page.title))
      .sort((lhs, rhs) => {
        const lhsTitle = (lhs.title ?? "").length;
        const rhsTitle = (rhs.title ?? "").length;
        return lhsTitle - rhsTitle;
      });

    const bestPage = pages[0];
    if (!bestPage?.thumbnail?.source) {
      return { id };
    }

    return {
      id,
      imageUrl: bestPage.thumbnail.source,
      sourcePageUrl: bestPage.pageid
        ? `https://en.wikipedia.org/?curid=${bestPage.pageid}`
        : undefined
    };
  } catch {
    return { id };
  }
}

function buildShoppingQuery(article: string, category?: string): string {
  const suffix = category ? `${category} ingrédient` : "ingrédient";
  return `${article} ${suffix} photo`;
}

function buildWikimediaQueries(article: string, category?: string): string[] {
  const articleQuery = normalizeQueryText(article);
  const categoryQuery = normalizeQueryText(category);
  const queries = [
    articleQuery,
    articleQuery ? `${articleQuery} ingredient` : "",
    articleQuery && categoryQuery && articleQuery !== categoryQuery
      ? `${articleQuery} ${categoryQuery}`
      : "",
    categoryQuery,
    categoryQuery ? `${categoryQuery} food` : ""
  ]
    .map((value) => value.trim())
    .filter(Boolean);

  return [...new Set(queries)];
}

function normalizeQueryText(value?: string): string {
  return (value ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function looksLikeWikimediaNoise(title?: string): boolean {
  const normalized = normalizeQueryText(title);
  if (!normalized) {
    return true;
  }

  return normalized.startsWith("list of ") ||
    normalized.startsWith("category ") ||
    normalized.startsWith("template ") ||
    normalized.startsWith("help ");
}
