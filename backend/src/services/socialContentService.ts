import { ApifyClient } from "apify-client";

import { env, providerStatus } from "../config/env.js";
import { fetchPageDocument } from "./generalPageService.js";
import { hostFromUrl, normalizeWhitespace, platformFromUrl, safeUrl } from "../utils/text.js";

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

export async function resolveSocialContent(
  url: string,
  options?: {
    timeoutMs?: number;
    allowDirectFetch?: boolean;
    skipApify?: boolean;
    preferDirectFetch?: boolean;
  }
): Promise<SocialContentSnapshot | null> {
  const platform = platformFromUrl(url);
  if (platform === "web") {
    return null;
  }

  const shouldDirectFetch = options?.allowDirectFetch !== false;
  const shouldSkipApify = options?.skipApify === true;
  const shouldPreferDirectFetch = shouldSkipApify || options?.preferDirectFetch === true || platform === "tiktok";
  let directSnapshot: SocialContentSnapshot | null = null;

  if (shouldDirectFetch && shouldPreferDirectFetch) {
    directSnapshot = await resolveViaDirectFetch(platform, url, {
      timeoutMs: directFetchTimeout(options?.timeoutMs)
    }).catch((error) => {
      logProviderFailure("direct", platform, url, error);
      return null;
    });

    if (directSnapshot && (shouldSkipApify || isUsefulSocialSnapshot(directSnapshot))) {
      return directSnapshot;
    }
  }

  if (shouldSkipApify) {
    return directSnapshot;
  }

  const apifySnapshot = await withTimeout(
    resolveViaApify(platform, url),
    options?.timeoutMs ?? 18_000,
    new Error("Apify social lookup timed out.")
  ).catch((error) => {
    logProviderFailure("apify", platform, url, error);
    return null;
  });
  if (apifySnapshot) {
    return apifySnapshot;
  }

  if (!shouldDirectFetch) {
    return null;
  }

  if (directSnapshot) {
    return directSnapshot;
  }

  return resolveViaDirectFetch(platform, url, {
    timeoutMs: directFetchTimeout(options?.timeoutMs)
  }).catch((error) => {
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
  url: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<SocialContentSnapshot | null> {
  const page = await fetchPageDocument(url, {
    timeoutMs: options?.timeoutMs
  });

  if (platform === "tiktok") {
    const tiktokSnapshot = await parseTikTokDirectSnapshot(page.html, page.url, options?.timeoutMs);
    if (tiktokSnapshot) {
      return {
        platform,
        source: "direct",
        canonicalUrl: tiktokSnapshot.canonicalUrl ?? page.summary.canonicalUrl ?? page.url,
        title: tiktokSnapshot.title ?? page.summary.title,
        caption: tiktokSnapshot.caption ?? page.summary.description,
        description: tiktokSnapshot.description ?? page.summary.description,
        authorName: tiktokSnapshot.authorName,
        subtitlesText: tiktokSnapshot.subtitlesText,
        imageUrls: tiktokSnapshot.imageUrls.length ? tiktokSnapshot.imageUrls : (page.summary.imageUrl ? [page.summary.imageUrl] : []),
        videoUrl: tiktokSnapshot.videoUrl,
        audioUrl: tiktokSnapshot.audioUrl,
        pageText: tiktokSnapshot.pageText ?? page.summary.textContent,
        externalLinks: tiktokSnapshot.externalLinks
      };
    }
  }

  return {
    platform,
    source: "direct",
    canonicalUrl: page.summary.canonicalUrl ?? page.url,
    title: page.summary.title,
    caption: page.summary.description,
    description: page.summary.description,
    imageUrls: page.summary.imageUrl ? [page.summary.imageUrl] : [],
    pageText: page.summary.textContent,
    externalLinks: []
  };
}

function directFetchTimeout(timeoutMs?: number): number | undefined {
  if (!timeoutMs) {
    return 4_000;
  }

  return Math.max(1_000, Math.min(timeoutMs, 4_000));
}

function isUsefulSocialSnapshot(snapshot: SocialContentSnapshot): boolean {
  const textLength = [
    snapshot.caption,
    snapshot.description,
    snapshot.subtitlesText,
    snapshot.pageText
  ]
    .map((value) => value?.length ?? 0)
    .reduce((sum, value) => sum + value, 0);

  return textLength >= 120 || snapshot.imageUrls.length > 0;
}

async function parseTikTokDirectSnapshot(
  html: string,
  fallbackUrl: string,
  timeoutMs?: number
): Promise<{
  canonicalUrl?: string;
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
} | null> {
  const payload = extractJsonScriptById(html, "__UNIVERSAL_DATA_FOR_REHYDRATION__");
  const defaultScope = recordValue(recordValue(payload)?.__DEFAULT_SCOPE__);
  const videoDetail = recordValue(defaultScope?.["webapp.video-detail"]);
  const itemInfo = recordValue(videoDetail?.itemInfo);
  const item = recordValue(itemInfo?.itemStruct);
  const shareMeta = recordValue(videoDetail?.shareMeta);

  if (!item && !shareMeta) {
    return null;
  }

  const contentLines = extractTikTokContentLines(item);
  const ingredientLines = extractTikTokIngredientLines(contentLines);
  const subtitleUrls = extractTikTokSubtitleUrls(item);
  const subtitleTimeoutMs = subtitleUrls.length
    ? Math.max(800, Math.min(2_500, Math.floor((timeoutMs ?? 4_000) * 0.5)))
    : undefined;
  const subtitlesText = subtitleTimeoutMs
    ? await fetchSubtitleText(subtitleUrls, subtitleTimeoutMs).catch(() => undefined)
    : undefined;
  const instructionLines = subtitlesText ? extractInstructionLinesFromVtt(subtitlesText) : [];
  const pageText = buildTikTokStructuredPageText({
    ingredientLines,
    instructionLines
  });

  return {
    canonicalUrl: safeUrl(
      stringValue(item?.shareUrl) ??
      stringValue(videoDetail?.canonicalUrl) ??
      stringValue(shareMeta?.canonicalUrl) ??
      fallbackUrl
    ) ?? fallbackUrl,
    title: normalizeTikTokTitle(
      stringValue(readTikTokStickerTitle(item)) ??
      undefined
    ),
    caption: normalizeWhitespace(
      stringValue(item?.desc) ??
      stringValue(shareMeta?.desc) ??
      contentLines.join(" ")
    ),
    description: normalizeWhitespace(
      stringValue(shareMeta?.desc) ??
      stringValue(item?.desc) ??
      contentLines.join(" ")
    ),
    authorName: normalizeWhitespace(
      stringValue(recordValue(item?.author)?.uniqueId) ??
      stringValue(recordValue(item?.author)?.nickname) ??
      ""
    ) || undefined,
    subtitlesText,
    imageUrls: extractUrls([
      recordValue(item?.video)?.cover,
      recordValue(item?.video)?.originCover,
      recordValue(item?.video)?.dynamicCover,
      recordValue(item?.video)?.coverUrl,
      recordValue(item?.video)?.originCoverUrl
    ]),
    videoUrl: firstValidURL([
      extractPrimaryTiktokVideoUrl(item),
      extractUrlByKeyHints(item, ["video", "play", "download"])
    ]),
    audioUrl: firstValidURL([
      safeUrl(stringValue(recordValue(item?.music)?.playUrl)),
      extractUrlByKeyHints(item, ["music", "audio", "sound", "track"])
    ]),
    pageText: pageText || undefined,
    externalLinks: extractExternalLinks("tiktok", item ?? {}, fallbackUrl)
  };
}

function extractJsonScriptById(html: string, scriptId: string): unknown {
  const escapedId = scriptId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `<script[^>]+id="${escapedId}"[^>]*>([\\s\\S]*?)<\\/script>`,
    "i"
  );
  const match = html.match(pattern);
  if (!match?.[1]) {
    return undefined;
  }

  try {
    return JSON.parse(match[1]);
  } catch {
    return undefined;
  }
}

function recordValue(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  return value as Record<string, unknown>;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim()
    ? value.trim()
    : undefined;
}

function readTikTokStickerTitle(item?: Record<string, unknown>): string | undefined {
  const stickers = Array.isArray(item?.stickersOnItem) ? item?.stickersOnItem : [];

  for (const sticker of stickers) {
    const stickerRecord = recordValue(sticker);
    const stickerText = Array.isArray(stickerRecord?.stickerText)
      ? (stickerRecord?.stickerText as unknown[])
        .map(stringValue)
        .filter((value): value is string => Boolean(value))
        .join(" ")
      : stringValue(stickerRecord?.stickerText);

    const normalized = normalizeTikTokTitle(stickerText);
    if (normalized) {
      return normalized;
    }
  }

  return undefined;
}

function normalizeTikTokTitle(value?: string): string | undefined {
  const normalized = normalizeWhitespace((value ?? "").replace(/\n+/g, " "));
  if (!normalized) {
    return undefined;
  }

  const cleaned = normalized
    .replace(/\s+sur\s+tiktok$/i, "")
    .replace(/\s+on\s+tiktok$/i, "")
    .trim();

  return cleaned || undefined;
}

function extractTikTokContentLines(item?: Record<string, unknown>): string[] {
  const contents = Array.isArray(item?.contents) ? item?.contents : [];

  return contents
    .map((entry) => stringValue(recordValue(entry)?.desc))
    .filter((line): line is string => Boolean(line))
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

function extractTikTokIngredientLines(lines: string[]): string[] {
  if (!lines.length) {
    return [];
  }

  const ingredientHeaderIndex = lines.findIndex((line) =>
    /tu auras besoin|ingredients?|ingrédients?/i.test(line)
  );

  if (ingredientHeaderIndex === -1) {
    return lines
      .filter((line) => /^[-•*]/u.test(line))
      .map(cleanTikTokIngredientLine);
  }

  const result: string[] = [];
  for (const line of lines.slice(ingredientHeaderIndex + 1)) {
    if (/^[-•*]/u.test(line)) {
      result.push(cleanTikTokIngredientLine(line));
      continue;
    }

    if (result.length > 0) {
      break;
    }
  }

  return result;
}

function cleanTikTokIngredientLine(line: string): string {
  return normalizeWhitespace(
    line
      .replace(/^[-•*]\s*/u, "")
      .replace(/\p{Extended_Pictographic}/gu, " ")
  );
}

function extractTikTokSubtitleUrls(item?: Record<string, unknown>): string[] {
  const video = recordValue(item?.video);
  const claInfo = recordValue(video?.claInfo);
  const captionInfos = Array.isArray(claInfo?.captionInfos) ? claInfo?.captionInfos : [];
  const subtitleInfos = Array.isArray(video?.subtitleInfos) ? video?.subtitleInfos : [];
  const sources = [...captionInfos, ...subtitleInfos];
  const urls: string[] = [];

  for (const source of sources) {
    const sourceRecord = recordValue(source);
    const directUrl = safeUrl(stringValue(sourceRecord?.url));
    if (directUrl) {
      urls.push(directUrl);
    }

    const urlList = Array.isArray(sourceRecord?.urlList) ? sourceRecord?.urlList : [];
    urls.push(...extractUrls(urlList));
  }

  return Array.from(new Set(urls))
    .filter((candidate) => !candidate.includes("www.tiktok.com/aweme/v1/play/"))
    .slice(0, 3);
}

async function fetchSubtitleText(urls: string[], timeoutMs: number): Promise<string | undefined> {
  for (const url of urls) {
    const response = await fetch(url, {
      headers: {
        "user-agent": "Mozilla/5.0",
        "accept-language": "fr-FR,fr;q=0.9,en;q=0.8"
      },
      redirect: "follow",
      signal: AbortSignal.timeout(timeoutMs)
    }).catch(() => null);

    if (!response?.ok) {
      continue;
    }

    const contentType = response.headers.get("content-type") ?? "";
    const text = await response.text();
    if (!text.trim()) {
      continue;
    }

    if (contentType.includes("text") || text.includes("WEBVTT")) {
      return text;
    }
  }

  return undefined;
}

function extractInstructionLinesFromVtt(raw: string): string[] {
  const cueLines = raw
    .replace(/^WEBVTT\s*/i, "")
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !/^\d+$/.test(line))
    .filter((line) => !line.includes("-->"));

  const sentences: string[] = [];
  let buffer = "";

  for (const line of cueLines) {
    buffer = buffer ? `${buffer} ${line}` : line;
    if (/[.!?]$/.test(line)) {
      sentences.push(normalizeWhitespace(buffer));
      buffer = "";
    }
  }

  if (buffer) {
    sentences.push(normalizeWhitespace(buffer));
  }

  const dropPatterns = [
    /^les p[ée]n[ée]s /i,
    /^je te montre/i,
    /^tu vas voir/i,
    /^tu vas te r[ée]galer/i,
    /^bon app/i
  ];
  const cookingPatterns = /(ajout|assaison|mettre|mets|faire|fondre|revenir|cuire|verse|verser|laisse|laisser|m[eé]lang|servir|couper|rajout|arrose|d[ée]glace|incorpor|hache|saisir)/i;

  return Array.from(new Set(
    sentences
      .map(rewriteTikTokInstructionSentence)
      .filter((line): line is string => Boolean(line))
      .filter((line) => !dropPatterns.some((pattern) => pattern.test(line)))
      .filter((line) => cookingPatterns.test(line))
  )).slice(0, 12);
}

function rewriteTikTokInstructionSentence(sentence: string): string | undefined {
  let value = normalizeWhitespace(sentence);
  if (!value) {
    return undefined;
  }

  const replacements: Array<[RegExp, string]> = [
    [/^pour commencer,?\s*/i, ""],
    [/^et une fois que c['’]est fait,?\s*/i, ""],
    [/^une fois que c['’]est fait,?\s*/i, ""],
    [/^tu vas assaisonner\b/i, "Assaisonner"],
    [/^tu mets\b/i, "Mettre"],
    [/^tu met\b/i, "Mettre"],
    [/^tu fais fondre\b/i, "Faire fondre"],
    [/^tu fais revenir\b/i, "Faire revenir"],
    [/^tu les arroses\b/i, "Arroser le poulet"],
    [/^tu ajoutes\b/i, "Ajouter"],
    [/^tu ajoute\b/i, "Ajouter"],
    [/^t['’]ajoutes\b/i, "Ajouter"],
    [/^t['’]ajoute\b/i, "Ajouter"],
    [/^tu verses\b/i, "Verser"],
    [/^tu verse\b/i, "Verser"],
    [/^tu laisses\b/i, "Laisser"],
    [/^tu laisse\b/i, "Laisser"],
    [/^tu m[eé]langes\b/i, "Mélanger"],
    [/^tu m[eé]lange\b/i, "Mélanger"],
    [/^tu coupes\b/i, "Couper"],
    [/^tu coupe\b/i, "Couper"],
    [/^tu incorpores\b/i, "Incorporer"],
    [/^tu incorpore\b/i, "Incorporer"],
    [/^tu fais cuire\b/i, "Faire cuire"],
    [/^tu rajoutes\b/i, "Ajouter"],
    [/^tu rajoute\b/i, "Ajouter"],
    [/^tu vas rajouter\b/i, "Ajouter"],
    [/^tu d[ée]glaces\b/i, "Déglacer"],
    [/^tu d[ée]glace\b/i, "Déglacer"]
  ];

  for (const [pattern, replacement] of replacements) {
    value = value.replace(pattern, `${replacement} `);
  }

  value = normalizeWhitespace(value.replace(/^dans 1 /i, "Dans une "));

  if (!value) {
    return undefined;
  }

  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}

function buildTikTokStructuredPageText(input: {
  ingredientLines: string[];
  instructionLines: string[];
}): string {
  const sections: string[] = [];

  if (input.ingredientLines.length) {
    sections.push("Ingrédients:");
    sections.push(...input.ingredientLines.map((line) => `- ${line}`));
  }

  if (input.instructionLines.length) {
    if (sections.length) {
      sections.push("");
    }
    sections.push("Instructions:");
    sections.push(...input.instructionLines);
  }

  return sections.join("\n");
}

function extractPrimaryTiktokVideoUrl(item?: Record<string, unknown>): string | undefined {
  const video = recordValue(item?.video);
  const playAddr = recordValue(video?.PlayAddrStruct) ?? recordValue(video?.playAddr) ?? recordValue(item?.playAddr);
  const urlList = Array.isArray(playAddr?.UrlList) ? playAddr?.UrlList : Array.isArray(playAddr?.urlList) ? playAddr?.urlList : [];

  return firstValidURL(extractUrls(urlList));
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
