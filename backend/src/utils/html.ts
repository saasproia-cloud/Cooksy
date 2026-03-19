import * as cheerio from "cheerio";

import { compactTextBlocks, normalizeWhitespace, safeUrl, uniqueStrings } from "./text.js";

export type HtmlPageSummary = {
  url: string;
  title?: string;
  description?: string;
  imageUrl?: string;
  canonicalUrl?: string;
  textContent?: string;
  structuredDataBlocks: string[];
};

function readMetaContent($: cheerio.CheerioAPI, selectors: string[]): string | undefined {
  for (const selector of selectors) {
    const value = $(selector).attr("content") ?? $(selector).attr("href");
    const normalized = normalizeWhitespace(value ?? "");
    if (normalized) {
      return normalized;
    }
  }

  return undefined;
}

export function parseHtmlPage(url: string, html: string): HtmlPageSummary {
  const $ = cheerio.load(html);

  const structuredDataBlocks = uniqueStrings(
    $('script[type="application/ld+json"]')
      .toArray()
      .map((element) => $(element).html())
  );

  $("script, style, noscript, svg").remove();

  const title = normalizeWhitespace(
    $("title").first().text() ||
      readMetaContent($, [
        'meta[property="og:title"]',
        'meta[name="twitter:title"]'
      ]) ||
      ""
  );

  const description = readMetaContent($, [
    'meta[name="description"]',
    'meta[property="og:description"]',
    'meta[name="twitter:description"]'
  ]);

  const imageUrl = safeUrl(readMetaContent($, [
    'meta[property="og:image"]',
    'meta[name="twitter:image"]',
    'link[rel="image_src"]'
  ]));

  const canonicalUrl = safeUrl(
    $('link[rel="canonical"]').attr("href") ??
      readMetaContent($, ['meta[property="og:url"]'])
  );

  const textContent = compactTextBlocks(
    [
      $("main").text(),
      $("article").text(),
      $("body").text()
    ],
    10000
  );

  return {
    url,
    title: title || undefined,
    description,
    imageUrl,
    canonicalUrl,
    textContent: textContent || undefined,
    structuredDataBlocks
  };
}
