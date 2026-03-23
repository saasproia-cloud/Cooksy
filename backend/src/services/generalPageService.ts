import { env } from "../config/env.js";
import { parseHtmlPage, type HtmlPageSummary } from "../utils/html.js";

const DEFAULT_HEADERS = {
  "user-agent": "CooksyBot/1.0 (+https://cooksy.app)",
  "accept-language": "fr-FR,fr;q=0.9,en;q=0.8"
};

export type HtmlPageDocument = {
  url: string;
  html: string;
  summary: HtmlPageSummary;
};

export async function fetchPageSummary(
  url: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<HtmlPageSummary> {
  const document = await fetchPageDocument(url, options);
  return document.summary;
}

export async function fetchPageDocument(
  url: string,
  options?: {
    timeoutMs?: number;
  }
): Promise<HtmlPageDocument> {
  const response = await fetch(url, {
    headers: DEFAULT_HEADERS,
    redirect: "follow",
    signal: AbortSignal.timeout(options?.timeoutMs ?? 15_000)
  });

  if (!response.ok) {
    throw new Error(`Unable to fetch page ${url} (${response.status})`);
  }

  const html = await response.text();
  const resolvedUrl = response.url || url;

  return {
    url: resolvedUrl,
    html,
    summary: parseHtmlPage(resolvedUrl, html)
  };
}

export async function resolveRemoteURL(
  url: string,
  options?: {
    fetchImpl?: typeof fetch;
    timeoutMs?: number;
  }
): Promise<string> {
  const fetchImpl = options?.fetchImpl ?? fetch;
  const response = await fetchImpl(url, {
    method: "GET",
    headers: DEFAULT_HEADERS,
    redirect: "follow",
    signal: AbortSignal.timeout(options?.timeoutMs ?? 12_000)
  });

  const resolvedURL = response.url || url;
  try {
    void response.body?.cancel();
  } catch {
    // Ignored: the redirect target is all we need here.
  }

  return resolvedURL;
}

export async function fetchRemoteBuffer(
  url: string,
  maxBytes: number,
  options?: {
    timeoutMs?: number;
  }
): Promise<Buffer> {
  const response = await fetch(url, {
    headers: DEFAULT_HEADERS,
    redirect: "follow",
    signal: AbortSignal.timeout(options?.timeoutMs ?? 25_000)
  });

  if (!response.ok) {
    throw new Error(`Unable to download remote file ${url} (${response.status})`);
  }

  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > maxBytes) {
    throw new Error(`Remote file is too large (${contentLength} bytes)`);
  }

  const arrayBuffer = await response.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);

  if (buffer.byteLength > maxBytes) {
    throw new Error(`Remote file exceeds the allowed limit (${buffer.byteLength} bytes)`);
  }

  return buffer;
}

export function baseUrlForRemoteImage(candidate?: string): string | undefined {
  if (!candidate) {
    return undefined;
  }

  try {
    return new URL(candidate, env.BACKEND_BASE_URL).toString();
  } catch {
    return undefined;
  }
}
