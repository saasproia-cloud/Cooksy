import { ApifyClient } from "apify-client";

import { env, providerStatus } from "../config/env.js";
import { fetchPageSummary } from "./generalPageService.js";
import { platformFromUrl, safeUrl } from "../utils/text.js";

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
};

const apifyClient = providerStatus.apify ? new ApifyClient({ token: env.APIFY_TOKEN }) : null;

export async function resolveSocialContent(url: string): Promise<SocialContentSnapshot | null> {
  const platform = platformFromUrl(url);
  if (platform === "web") {
    return null;
  }

  const apifySnapshot = await resolveViaApify(platform, url).catch(() => null);
  if (apifySnapshot) {
    return apifySnapshot;
  }

  return resolveViaDirectFetch(platform, url).catch(() => null);
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
    videoUrl: safeUrl(
      extractText([
        item.videoUrl,
        item.downloadUrl,
        item.playUrl,
        item.videoPlayUrl,
        item.contentUrl
      ])
    ),
    audioUrl: safeUrl(
      extractText([
        item.musicUrl,
        item.audioUrl,
        item.musicPlayUrl
      ])
    ),
    pageText: extractText([item.text, item.caption, item.description, subtitlesText])
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
    pageText: page.textContent
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
