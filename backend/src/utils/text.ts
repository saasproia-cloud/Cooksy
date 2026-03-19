export function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

export function truncate(value: string, maxLength: number): string {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength - 1).trimEnd()}…`;
}

export function compactTextBlocks(values: Array<string | undefined | null>, maxLength = 4000): string {
  const combined = values
    .map((value) => normalizeWhitespace(value ?? ""))
    .filter(Boolean)
    .join("\n\n");

  return truncate(combined, maxLength);
}

export function uniqueStrings(values: Array<string | undefined | null>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values) {
    const normalized = normalizeWhitespace(value ?? "");
    if (!normalized || seen.has(normalized)) {
      continue;
    }

    seen.add(normalized);
    result.push(normalized);
  }

  return result;
}

export function safeUrl(value?: string | null): string | undefined {
  const trimmed = normalizeWhitespace(value ?? "");
  if (!trimmed) {
    return undefined;
  }

  try {
    return new URL(trimmed).toString();
  } catch {
    return undefined;
  }
}

export function hostFromUrl(input: string): string {
  try {
    return new URL(input).host.toLowerCase();
  } catch {
    return "";
  }
}

export function platformFromUrl(input: string): "tiktok" | "instagram" | "pinterest" | "web" {
  const host = hostFromUrl(input);

  if (host.includes("tiktok")) {
    return "tiktok";
  }

  if (host.includes("instagram")) {
    return "instagram";
  }

  if (host.includes("pinterest") || host.includes("pin.it")) {
    return "pinterest";
  }

  return "web";
}
