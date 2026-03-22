import { ApifyClient } from "apify-client";

import { env, providerStatus } from "../config/env.js";
import { fetchPageSummary } from "./generalPageService.js";
import { hostFromUrl, platformFromUrl, safeUrl } from "../utils/text.js";

export type SocialContentSnapshot = {
  platform: "tiktok" | "instagram" | "pinterest";
  source: "apify" | "direct";
  canonicalUrl: string;
  title?: string;
  caption?: string;
  description?: string;
  authorName?: string;
  subtitlesText?: string;
  imageUrls: string[];
  videoUrl?: string;
  audioUrl?: string;
  pageText?: string;
  externalLinks: string[];
};

const apifyClient = providerStatus.apify ? new ApifyClient({ token: env.APIFY_TOKEN }) : null;

export async function resolveSocialContent(url: string): Promise<SocialContentSnapshot | null> {
  const platform = platformFromUrl(url);
  if (platform === "web") {
    return null;
  }

  const apifySnapshot = await withTimeout(
    resolveViaApify(platform, url),
    18_000,
    new Error("Apify social lookup timed out.")
  ).catch((error) => {
    logProviderFailure("apify", platform, url, error);
    return null;
  });
  if (apifySnapshot) {
    return apifySnapshot;
  }

  return resolveViaDirectFetch(platform, url).catch((error) => {
    logProviderFailure("direct", platform, url, error);
    return null;
  });
}

async function resolveViaApify(
  platform: "tiktok" | "instagram" | "pinterest",
  url: string
): Promise<SocialContentSnapshot | null> {
  if (!apifyClient) {
    return null;
  }

  const actorId = {
    tiktok: env.APIFY_TIKTOK_ACTOR_ID,
    instagram: env.APIFY_INSTAGRAM_ACTOR_ID,
    pinterest: env.APIFY_PINTEREST_ACTOR_ID
  }[platform];

  const input = {
    tiktok: { postURLs: [url] },
    instagram: { directUrls: [url], resultsType: "posts", resultsLimit: 1 },
    pinterest: { startUrls: [{ url }] }
  }[platform];

  const run = await apifyClient.actor(actorId).call(input);
  if (!run.defaultDatasetId) {
    return null;
  }

  const { items } = await apifyClient.dataset(run.defaultDatasetId).listItems({ limit: 1 });
  if (!items.length) {
    return null;
  }

  return mapApifyItemToSnapshot(platform, items[0] as Record<string, unknown>, url);
}

function mapApifyItemToSnapshot(
  platform: "tiktok" | "instagram" | "pinterest",
  item: Record<string, unknown>,
  url: string
): SocialContentSnapshot {
  const imageUrls = extractUrls([
    item.thumbnailUrl,
    item.imageUrl,
    item.displayUrl,
    item.coverUrl,
    ...(Array.isArray(item.images) ? item.images : []),
    ...(Array.isArray(item.imageUrls) ? item.imageUrls : [])
  ]);

  const subtitlesText = extractText([
    item.subtitleText,
    item.subtitles,
    item.transcript,
    item.captionText
  ]);
  const externalLinks = extractExternalLinks(platform, item, url);

  return {
    platform,
    source: "apify",
    canonicalUrl: safeUrl(String(item.url ?? item.webVideoUrl ?? item.link ?? url)) ?? url,
    title: extractText([item.title]),
    caption: extractText([item.text, item.caption, item.edge_media_to_caption, item.description]),
    description: extractText([item.description, item.alt]),
    authorName: extractText([
      item.authorName,
      item.ownerUsername,
      item.username,
      item.authorMeta && typeof item.authorMeta === "object"
        ? (item.authorMeta as Record<string, unknown>).name
        : undefined
    ]),
    subtitlesText,
    imageUrls,
    videoUrl: firstValidURL([
      safeUrl(
        extractText([
          item.videoUrl,
          item.downloadUrl,
          item.playUrl,
          item.videoPlayUrl,
          item.contentUrl
        ])
      ),
      extractUrlByKeyHints(item, ["video", "download", "play", "content", "stream"])
    ]),
    audioUrl: firstValidURL([
      safeUrl(
        extractText([
          item.musicUrl,
          item.audioUrl,
          item.musicPlayUrl
        ])
      ),
      extractUrlByKeyHints(item, ["music", "audio", "sound", "track"])
    ]),
    pageText: extractText([item.text, item.caption, item.description, subtitlesText]),
    externalLinks
  };
}

async function resolveViaDirectFetch(
  platform: "tiktok" | "instagram" | "pinterest",
  url: string
): Promise<SocialContentSnapshot | null> {
  const page = await fetchPageSummary(url);

  return {
    platform,
    source: "direct",
    canonicalUrl: page.canonicalUrl ?? url,
    title: page.title,
    caption: page.description,
    description: page.description,
    imageUrls: page.imageUrl ? [page.imageUrl] : [],
    pageText: page.textContent,
    externalLinks: []
  };
}

function extractText(values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }

    if (Array.isArray(value)) {
      const nested = value
        .map((entry) => extractText([entry]))
        .filter((entry): entry is string => Boolean(entry))
        .join("\n");
      if (nested.trim()) {
        return nested.trim();
      }
    }

    if (value && typeof value === "object") {
      const objectValue = value as Record<string, unknown>;
      const nested = extractText(Object.values(objectValue));
      if (nested) {
        return nested;
      }
    }
  }

  return undefined;
}

function extractUrls(values: unknown[]): string[] {
  const urls: string[] = [];

  for (const value of values) {
    if (typeof value === "string") {
      const normalized = safeUrl(value);
      if (normalized) {
        urls.push(normalized);
      }
      continue;
    }

    if (value && typeof value === "object") {
      const objectValue = value as Record<string, unknown>;
      const nested = extractUrls(Object.values(objectValue));
      urls.push(...nested);
    }
  }

  return Array.from(new Set(urls));
}

function firstValidURL(values: Array<string | undefined>): string | undefined {
  return values.find((value): value is string => Boolean(value));
}

function extractExternalLinks(
  platform: "tiktok" | "instagram" | "pinterest",
  item: Record<string, unknown>,
  sourceUrl: string
): string[] {
  const hintedUrls = extractUrls(Object.values(item));
  const embeddedTextUrls = collectEmbeddedTextUrls(Object.values(item));
  const sourceHost = hostFromUrl(sourceUrl);

  return Array.from(new Set([...hintedUrls, ...embeddedTextUrls]))
    .filter((candidate) => candidate !== sourceUrl)
    .filter((candidate) => platformFromUrl(candidate) === "web")
    .filter((candidate) => hostFromUrl(candidate) !== sourceHost)
    .filter((candidate) => !isLikelyMediaAsset(candidate))
    .slice(0, 5);
}

function collectEmbeddedTextUrls(values: unknown[]): string[] {
  const matches: string[] = [];

  for (const value of values) {
    if (typeof value === "string") {
      const embeddedMatches = value.match(/https?:\/\/[^\s<>"')]+/g) ?? [];
      for (const embeddedMatch of embeddedMatches) {
        const normalized = safeUrl(embeddedMatch);
        if (normalized) {
          matches.push(normalized);
        }
      }
      continue;
    }

    if (Array.isArray(value)) {
      matches.push(...collectEmbeddedTextUrls(value));
      continue;
    }

    if (value && typeof value === "object") {
      matches.push(...collectEmbeddedTextUrls(Object.values(value as Record<string, unknown>)));
    }
  }

  return matches;
}

function isLikelyMediaAsset(url: string): boolean {
  const lowercaseUrl = url.toLowerCase();
  return [
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".gif",
    ".mp4",
    ".mov",
    ".mp3",
    ".m4a",
    ".aac",
    ".wav",
    ".m3u8"
  ].some((suffix) => lowercaseUrl.includes(suffix));
}

function extractUrlByKeyHints(
  value: unknown,
  keyHints: string[]
): string | undefined {
  const matches: string[] = [];
  collectHintedUrls(value, keyHints.map((hint) => hint.toLowerCase()), matches);
  return matches[0];
}

function collectHintedUrls(
  value: unknown,
  keyHints: string[],
  matches: string[],
  currentKey = ""
) {
  if (matches.length > 0) {
    return;
  }

  if (typeof value === "string") {
    if (!currentKey || !keyHints.some((hint) => currentKey.includes(hint))) {
      return;
    }

    const normalized = safeUrl(value);
    if (normalized) {
      matches.push(normalized);
    }
    return;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      collectHintedUrls(entry, keyHints, matches, currentKey);
      if (matches.length > 0) {
        return;
      }
    }
    return;
  }

  if (!value || typeof value !== "object") {
    return;
  }

  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    collectHintedUrls(entry, keyHints, matches, key.toLowerCase());
    if (matches.length > 0) {
      return;
    }
  }
}

function logProviderFailure(
  provider: "apify" | "direct",
  platform: "tiktok" | "instagram" | "pinterest",
  url: string,
  error: unknown
) {
  const message = error instanceof Error ? error.message : String(error);
  console.warn(`[socialContentService] ${provider} failed for ${platform} ${url}: ${message}`);
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  timeoutError: Error
): Promise<T> {
  let timeoutHandle: NodeJS.Timeout | undefined;

  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutHandle = setTimeout(() => reject(timeoutError), timeoutMs);
      })
    ]);
  } finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
  }
}
