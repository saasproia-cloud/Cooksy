// =====================================================================
// sourceSanitizer — per-source cleaning and isolation layer.
//
// Each raw source (caption, description, subtitles, web text, transcript)
// is processed independently into a SanitizedSourceEnvelope. Sources
// are NEVER concatenated at this stage — downstream consumers decide
// whether/how to combine them, with explicit provenance.
//
// Phase 2 contamination defenses:
//   - socialCaption and socialDescription are kept SEPARATE (the
//     previous pipeline concatenated them, which leaked creator bios,
//     music credits, branding, and promos into the caption string).
//   - Web page body text is stripped of nav/cookie/sidebar/footer
//     boilerplate before parsing.
//   - Social noise (hashtags, CTAs, emoji runs) is stripped via the
//     existing stripSocialNoise helper.
// =====================================================================

import type { NormalizerInput } from "../types/recipe.js";
import {
  foodSignalScore,
  passesDualGate,
} from "./foodTermGate.js";
import { stripSocialNoise } from "./ingredientNormalization.js";

export type SourceKind =
  | "caption"
  | "social_description"
  | "social_subtitles"
  | "structured_data"
  | "transcript_digest"
  | "audio_raw"
  | "web";

export interface SanitizedSourceEnvelope {
  kind: SourceKind;
  rawText: string;
  cleanedText: string;
  foodSignalScore: number;
  /** Lines that pass the dual gate (plausible ingredient candidates). */
  recipeLines: string[];
  /** Lines stripped by cleaning (kept for debug visibility). */
  noiseLines: string[];
  /** Explicit section headers detected in the cleaned text. */
  sectionHints: string[];
  metadata: {
    source: string;
    charCount: number;
    lineCount: number;
  };
}

// ---------------------------------------------------------------------
// Web boilerplate blocklist — conservative. We only drop a line when
// we are highly confident it is page chrome, not recipe content.
// ---------------------------------------------------------------------

const WEB_BOILERPLATE_LINE_RE: RegExp[] = [
  // Cookie / privacy banners
  /\bthis\s+site\s+uses\s+cookies\b/i,
  /\bwe\s+use\s+cookies\b/i,
  /\bprivacy\s+policy\b/i,
  /\bcookie\s+settings?\b/i,
  /\baccept\s+all\s+cookies\b/i,
  /\bgdpr\b/i,
  /\bce\s+site\s+utilise\s+des?\s+cookies\b/i,
  /\bparam[éè]trer\s+les\s+cookies\b/i,
  // Footer
  /\ball\s+rights?\s+reserved\b/i,
  /\bcopyright\s*[\u00a9]?\s*\d{4}/i,
  /[\u00a9]\s*\d{4}/,
  /\btous\s+droits?\s+r[eé]serv[eé]s\b/i,
  // Social share strips
  /\bshare\s+on\s+(?:facebook|twitter|pinterest|whatsapp)\b/i,
  /\bpartager\s+sur\s+(?:facebook|twitter|pinterest|whatsapp)\b/i,
  /\btweet\s+this\b/i,
  /\bfollow\s+us\s+on\b/i,
  /\bsuivez[-\s]nous\b/i,
  // Advertising
  /\badvertisement\b/i,
  /\bsponsor(?:ed|isé)?\b/i,
  /\bpublicit[eé]\b/i,
  // Newsletter
  /\bsubscribe\s+to\s+our\s+newsletter\b/i,
  /\bsign\s+up\s+for\s+(?:our)?\s*newsletter\b/i,
  /\bjoin\s+our\s+mailing\s+list\b/i,
  /\binscrivez[-\s]vous\s+(?:à|a)\s+(?:notre|la)\s+newsletter\b/i,
  // Nav / menu-ish
  /^\s*(?:home|accueil|menu|about|contact|recipes|recettes|blog|shop|boutique|login|register|se\s+connecter|s['’]inscrire)\s*$/i,
  // Pagination / related content prompts
  /\b(?:next|previous|page\s+\d+\s+of\s+\d+)\b/i,
  /\byou\s+may\s+also\s+(?:like|enjoy)\b/i,
  /\bvous\s+aimerez\s+aussi\b/i,
  /\brelated\s+(?:articles?|recipes?|posts?)\b/i,
  /\barticles?\s+similaires?\b/i,
];

// Minimum useful line length — anything shorter is rarely recipe content.
const MIN_WEB_LINE_LENGTH = 12;
// Very long lines (navigation menus mashed together) → strip.
const MAX_WEB_LINE_LENGTH = 400;

function isWebBoilerplate(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return true;
  if (trimmed.length < MIN_WEB_LINE_LENGTH) {
    // Very short lines are suspicious in web body text. Keep only if
    // they contain a quantity prefix (indicating an ingredient line).
    if (!/^\s*(?:[-•*\d]|\d+[.)])/.test(trimmed)) return true;
  }
  if (trimmed.length > MAX_WEB_LINE_LENGTH) return true;
  for (const re of WEB_BOILERPLATE_LINE_RE) {
    if (re.test(trimmed)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------
// Section-header detection — conservative pattern list for the hints
// field. The recipe compiler has its own richer detection; this is a
// lightweight pass so the envelope can surface structural signals for
// downstream merge decisions.
// ---------------------------------------------------------------------

const SECTION_HEADER_RE: RegExp[] = [
  /^(?:pour\s+(?:la|le|les)\s+[a-zà-ÿ\s-]{2,30}\s*:)/i,
  /^(?:for\s+the\s+[a-z\s-]{2,30}\s*:)/i,
  /^(?:marinade|sauce|salade|garniture|accompagnement|montage|assemblage|dressage|pâte|p[aâ]te|base|cr[eè]me|glaçage|topping|farce|filling|dough|batter)\s*:?\s*$/i,
  /^(?:ingr[eé]dients?|ingredients?|[eé]tapes?|steps?|instructions?|pr[eé]paration|preparation|method)\s*:?\s*$/i,
];

function detectSectionHints(lines: string[]): string[] {
  const hints: string[] = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.length > 80) continue;
    for (const re of SECTION_HEADER_RE) {
      if (re.test(trimmed)) {
        hints.push(trimmed.replace(/\s+/g, " "));
        break;
      }
    }
  }
  return hints;
}

// ---------------------------------------------------------------------
// Shared line-level classifier — partition cleaned lines into recipe
// candidates (dual-gate) and everything else.
// ---------------------------------------------------------------------

function classifyLines(cleanedText: string): {
  recipeLines: string[];
  noiseLines: string[];
} {
  const recipeLines: string[] = [];
  const noiseLines: string[] = [];

  for (const rawLine of cleanedText.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    if (passesDualGate(line)) {
      recipeLines.push(line);
    } else {
      noiseLines.push(line);
    }
  }

  return { recipeLines, noiseLines };
}

function buildEnvelope(
  kind: SourceKind,
  rawText: string,
  cleanedText: string,
  source: string
): SanitizedSourceEnvelope {
  const { recipeLines, noiseLines } = classifyLines(cleanedText);
  const lines = cleanedText.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  return {
    kind,
    rawText,
    cleanedText,
    foodSignalScore: foodSignalScore(cleanedText),
    recipeLines,
    noiseLines,
    sectionHints: detectSectionHints(lines),
    metadata: {
      source,
      charCount: cleanedText.length,
      lineCount: lines.length,
    },
  };
}

// ---------------------------------------------------------------------
// Per-source sanitizers.
// ---------------------------------------------------------------------

export function sanitizeCaption(
  socialCaption?: string | null,
  sharedText?: string | null
): SanitizedSourceEnvelope | null {
  const parts: string[] = [];
  if (socialCaption?.trim()) parts.push(socialCaption.trim());
  if (sharedText?.trim() && sharedText.trim() !== socialCaption?.trim()) {
    parts.push(sharedText.trim());
  }
  if (parts.length === 0) return null;

  const raw = parts.join("\n\n");
  const cleaned = stripSocialNoise(raw);
  return buildEnvelope("caption", raw, cleaned, "socialCaption+sharedText");
}

export function sanitizeSocialDescription(
  socialDescription?: string | null
): SanitizedSourceEnvelope | null {
  if (!socialDescription?.trim()) return null;
  const raw = socialDescription.trim();
  const cleaned = stripSocialNoise(raw);
  return buildEnvelope(
    "social_description",
    raw,
    cleaned,
    "socialDescription"
  );
}

export function sanitizeSocialSubtitles(
  socialSubtitles?: string | null
): SanitizedSourceEnvelope | null {
  if (!socialSubtitles?.trim()) return null;
  const raw = socialSubtitles.trim();
  const cleaned = stripSocialNoise(raw);
  return buildEnvelope("social_subtitles", raw, cleaned, "socialSubtitles");
}

export function sanitizeTranscriptDigest(
  digest?: string | null
): SanitizedSourceEnvelope | null {
  if (!digest?.trim()) return null;
  const raw = digest.trim();
  const cleaned = stripSocialNoise(raw);
  return buildEnvelope(
    "transcript_digest",
    raw,
    cleaned,
    "transcriptDigest"
  );
}

export function sanitizeTranscript(
  transcript?: string | null
): SanitizedSourceEnvelope | null {
  if (!transcript?.trim()) return null;
  const raw = transcript.trim();
  const cleaned = stripSocialNoise(raw);
  return buildEnvelope("audio_raw", raw, cleaned, "transcript");
}

export function sanitizeStructuredData(
  structuredData?: readonly string[] | null
): SanitizedSourceEnvelope | null {
  if (!structuredData || structuredData.length === 0) return null;
  const joined = structuredData.filter((v) => v && v.trim()).join("\n");
  if (!joined.trim()) return null;
  return buildEnvelope(
    "structured_data",
    joined,
    joined, // structured data is already clean JSON-LD / microdata
    "pageStructuredData"
  );
}

export function sanitizeWebText(
  pageTitle?: string | null,
  pageDescription?: string | null,
  pageTextContent?: string | null
): SanitizedSourceEnvelope | null {
  const parts: string[] = [];
  if (pageTitle?.trim()) parts.push(pageTitle.trim());
  if (pageDescription?.trim()) parts.push(pageDescription.trim());
  if (pageTextContent?.trim()) parts.push(pageTextContent.trim());
  if (parts.length === 0) return null;

  const raw = parts.join("\n\n");
  const cleaned = cleanWebText(raw);
  return buildEnvelope(
    "web",
    raw,
    cleaned,
    "pageTitle+pageDescription+pageTextContent"
  );
}

export function cleanWebText(raw: string): string {
  if (!raw) return "";
  const lines = raw.split(/\r?\n/);
  const kept: string[] = [];
  for (const line of lines) {
    if (isWebBoilerplate(line)) continue;
    kept.push(line);
  }
  return stripSocialNoise(kept.join("\n")).trim();
}

// ---------------------------------------------------------------------
// Top-level factory: build every envelope from a NormalizerInput.
// Consumers choose which envelopes to elect as primary/secondary.
// ---------------------------------------------------------------------

export function buildSourceEnvelopes(
  input: NormalizerInput
): SanitizedSourceEnvelope[] {
  const envelopes: SanitizedSourceEnvelope[] = [];

  const caption = sanitizeCaption(input.socialCaption, input.sharedText);
  if (caption) envelopes.push(caption);

  const description = sanitizeSocialDescription(input.socialDescription);
  if (description) envelopes.push(description);

  const subtitles = sanitizeSocialSubtitles(input.socialSubtitles);
  if (subtitles) envelopes.push(subtitles);

  const structured = sanitizeStructuredData(input.pageStructuredData);
  if (structured) envelopes.push(structured);

  const digest = sanitizeTranscriptDigest(input.transcriptDigest);
  if (digest) envelopes.push(digest);

  if (!input.transcriptDigest) {
    const audio = sanitizeTranscript(input.transcript);
    if (audio) envelopes.push(audio);
  }

  const web = sanitizeWebText(
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent
  );
  if (web) envelopes.push(web);

  return envelopes;
}
