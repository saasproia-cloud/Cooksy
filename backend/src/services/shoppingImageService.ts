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

  if (!providerStatus.serpApi) {
    return { id: item.id };
  }

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
  const result = {
    id: item.id,
    imageUrl: bestImage?.original ?? bestImage?.thumbnail,
    sourcePageUrl: bestImage?.link
  };

  imageCache.set(cacheKey, result);
  return result;
}

function buildShoppingQuery(article: string, category?: string): string {
  const suffix = category ? `${category} ingrédient` : "ingrédient";
  return `${article} ${suffix} photo`;
}
