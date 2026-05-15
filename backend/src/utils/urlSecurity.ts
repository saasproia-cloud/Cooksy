import dns from "node:dns/promises";
import type { LookupAddress } from "node:dns";
import net from "node:net";

/**
 * SSRF protection for outbound URL fetches.
 *
 * Cooksy accepts user-pasted URLs (TikTok / Instagram / Pinterest, but
 * also arbitrary cooking blogs via `platform === "web"`), so we cannot
 * whitelist a fixed set of hosts. Instead, we:
 *
 *   1. Reject anything that is not http(s).
 *   2. Reject obvious internal hostnames (localhost, .local, .internal…).
 *   3. DNS-resolve the host and reject any address in a private,
 *      loopback, link-local, multicast, broadcast or unspecified range.
 *
 * Every outbound fetch initiated from user input (page scrape, image
 * download, subtitle fetch, redirect resolution) MUST funnel through
 * {@link assertSafeFetchUrl} before being passed to `fetch()`.
 */

export class UnsafeUrlError extends Error {
  constructor(public readonly reason: string, message: string) {
    super(message);
    this.name = "UnsafeUrlError";
  }
}

const BLOCKED_HOST_PATTERNS: RegExp[] = [
  /^localhost$/i,
  /\.local$/i,
  /\.internal$/i,
  /^metadata\.google\.internal$/i,
  /^instance-data$/i
];

/**
 * Validate a URL string and return its parsed form. Throws
 * {@link UnsafeUrlError} on any structural problem.
 *
 * This is the cheap, synchronous portion — it cannot detect a hostname
 * that resolves to a private IP. Use {@link assertSafeFetchUrl} for the
 * full check (it calls this internally and then performs DNS).
 */
export function parseSafeUrl(rawUrl: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new UnsafeUrlError("invalid_url", "URL is not parseable.");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new UnsafeUrlError(
      "invalid_scheme",
      `Only http(s) URLs are allowed (got ${parsed.protocol}).`
    );
  }

  if (!parsed.hostname) {
    throw new UnsafeUrlError("missing_host", "URL has no hostname.");
  }

  // Strip the surrounding brackets that Node leaves on IPv6 literals.
  const host = parsed.hostname.replace(/^\[/, "").replace(/]$/, "");

  if (BLOCKED_HOST_PATTERNS.some((pattern) => pattern.test(host))) {
    throw new UnsafeUrlError(
      "blocked_host",
      `Hostname ${host} is not allowed.`
    );
  }

  // If the host is already a literal IP we can shortcut to the range
  // check without doing a DNS lookup.
  if (net.isIP(host) !== 0 && isBlockedIp(host)) {
    throw new UnsafeUrlError("blocked_ip", `IP ${host} is in a reserved range.`);
  }

  return parsed;
}

/**
 * Full SSRF check. Resolves the URL's host and rejects if any returned
 * address sits in a reserved range. Use before passing user-influenced
 * URLs to `fetch()`.
 */
export async function assertSafeFetchUrl(rawUrl: string): Promise<URL> {
  const parsed = parseSafeUrl(rawUrl);
  const host = parsed.hostname.replace(/^\[/, "").replace(/]$/, "");

  // Literal IP: parseSafeUrl already validated it. Done.
  if (net.isIP(host) !== 0) {
    return parsed;
  }

  let addresses: LookupAddress[];
  try {
    addresses = await dns.lookup(host, { all: true, verbatim: true });
  } catch {
    throw new UnsafeUrlError(
      "dns_failed",
      `Unable to resolve ${host}.`
    );
  }

  if (!addresses.length) {
    throw new UnsafeUrlError("dns_empty", `No addresses for ${host}.`);
  }

  for (const { address } of addresses) {
    if (isBlockedIp(address)) {
      throw new UnsafeUrlError(
        "blocked_ip",
        `${host} resolves to a reserved IP (${address}).`
      );
    }
  }

  return parsed;
}

/**
 * Lightweight check for inbound user URLs — used in the Zod schema for
 * `/api/import/url` to fail fast before any pipeline work happens.
 * Performs the synchronous portion only. The async fetch-time check in
 * {@link assertSafeFetchUrl} remains the authoritative guard.
 */
export function isSyntacticallySafeImportUrl(rawUrl: string): boolean {
  try {
    parseSafeUrl(rawUrl);
    return true;
  } catch {
    return false;
  }
}

function isBlockedIp(ip: string): boolean {
  const version = net.isIP(ip);
  if (version === 4) {
    return isBlockedIpv4(ip);
  }
  if (version === 6) {
    return isBlockedIpv6(ip);
  }
  return false;
}

function isBlockedIpv4(ip: string): boolean {
  const octets = ip.split(".").map(Number);
  if (octets.length !== 4 || octets.some((value) => Number.isNaN(value))) {
    return true;
  }
  const [a, b] = octets;

  // 0.0.0.0/8 — "this network"
  if (a === 0) return true;
  // 10.0.0.0/8 — private
  if (a === 10) return true;
  // 127.0.0.0/8 — loopback
  if (a === 127) return true;
  // 169.254.0.0/16 — link-local / cloud metadata (AWS, GCP, Azure)
  if (a === 169 && b === 254) return true;
  // 172.16.0.0/12 — private
  if (a === 172 && b >= 16 && b <= 31) return true;
  // 192.0.0.0/24 — IETF assignments
  if (a === 192 && b === 0) return true;
  // 192.168.0.0/16 — private
  if (a === 192 && b === 168) return true;
  // 198.18.0.0/15 — benchmarking
  if (a === 198 && (b === 18 || b === 19)) return true;
  // 224.0.0.0/4 — multicast
  if (a >= 224 && a <= 239) return true;
  // 240.0.0.0/4 — reserved / 255.255.255.255 broadcast
  if (a >= 240) return true;

  return false;
}

function isBlockedIpv6(ip: string): boolean {
  const normalized = ip.toLowerCase();

  if (normalized === "::" || normalized === "::1") return true;
  // IPv4-mapped (::ffff:a.b.c.d) — re-check via v4 logic.
  if (normalized.startsWith("::ffff:")) {
    const tail = normalized.slice(7);
    return isBlockedIpv4(tail);
  }
  // fc00::/7 — unique local
  if (/^f[cd][0-9a-f]{2}:/.test(normalized)) return true;
  // fe80::/10 — link-local
  if (/^fe[89ab][0-9a-f]:/.test(normalized)) return true;
  // ff00::/8 — multicast
  if (normalized.startsWith("ff")) return true;

  return false;
}
