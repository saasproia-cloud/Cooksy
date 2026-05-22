/**
 * recipeCompiler.ts — Deterministic, structure-preserving recipe compiler.
 *
 * 4-stage pipeline:
 *   1. Classify & elect primary source (caption-first HARD RULE)
 *   2. Parse structure (sections, ingredients, steps)
 *   3. Conservative enrichment (only HIGH-confidence gaps)
 *   4. Validate & guard (never degrade)
 *
 * Hard constraints:
 *   - Caption priority = HARD RULE, not a score
 *   - Source arbitration is deterministic: Caption > Structured > Audio > Web
 *   - Section parsing uses structural detection, not just keywords
 *   - Merge is conservative: only enrich when confidence is HIGH
 *   - Non-degradation invariant: if final is worse → fallback to cleaned primary
 *   - Ingredient normalization: if unsure → KEEP ORIGINAL
 *   - LLM = LAST RESORT (never called from this module)
 */

import {
  sanitizeRecipeImport,
  type RecipeImportResult,
  type RecipeIngredientDraft,
  type NormalizerInput,
} from "../types/recipe.js";
import { normalizeWhitespace } from "../utils/text.js";

// Line-preserving whitespace normalizer. `normalizeWhitespace` collapses
// `\n` into a single space, which destroys the bullet/section structure
// the parser depends on. Use this when the caller is about to split by
// newline (parseStructuredRecipe, section parser).
function normalizeLineWhitespace(value: string): string {
  return value
    .replace(/\r\n?/g, "\n")
    .replace(/[\t\f\v ]+/g, " ")
    .replace(/[\t\f\v ]*\n[\t\f\v ]*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
import {
  normalizeFrenchUnit,
  cleanIngredientNameField,
  normalizeFrenchIngredientName,
} from "./ingredientNormalization.js";
import { passesDualGate, containsFoodSignal } from "./foodTermGate.js";
import { cleanWebText } from "./sourceSanitizer.js";

// =====================================================================
// Types
// =====================================================================

export interface RecipeSection {
  name: string; // "Marinade", "Sauce", "" for unsectioned
  ingredients: RecipeIngredientDraft[];
  steps: Array<{ detail: string; section: string }>;
}

export interface ParsedRecipe {
  title: string;
  sections: RecipeSection[];
  rawIngredientCount: number;
  rawStepCount: number;
  hasExplicitSections: boolean;
}

export type SourceKind =
  | "caption"
  | "structured_data"
  | "transcript_digest"
  | "audio_raw"
  | "web";

export interface ClassifiedSource {
  kind: SourceKind;
  isPrimary: boolean;
  text: string;
  parsed: ParsedRecipe | null;
}

export interface CompilerResult {
  recipe: RecipeImportResult;
  primarySource: SourceKind;
  usedEnrichment: boolean;
  compilerUsed: boolean;
  llmNeeded: boolean; // true if compiler output is incomplete
}

// =====================================================================
// Stage 1: Classify & Elect Primary Source
// =====================================================================

/**
 * Deterministic source election. Caption is PRIMARY if it contains a
 * structured recipe. This is a HARD RULE.
 *
 * Priority order (when caption is not structured):
 *   Structured Data > Caption (still primary text) > Transcript Digest > Audio > Web
 */
export function classifySources(input: NormalizerInput): ClassifiedSource[] {
  const sources: ClassifiedSource[] = [];

  // Caption = socialCaption + sharedText + socialDescription
  const captionText = collectCaptionText(input);
  if (captionText) {
    const parsed = parseStructuredRecipe(captionText);
    sources.push({
      kind: "caption",
      isPrimary: false, // elected below
      text: captionText,
      parsed,
    });
  }

  // Structured data from web pages (JSON-LD/microdata)
  const structuredText = (input.pageStructuredData ?? []).join("\n");
  if (structuredText.trim()) {
    const structuredRecipeText = extractRecipeFromStructuredData(
      input.pageStructuredData ?? []
    );
    sources.push({
      kind: "structured_data",
      isPrimary: false,
      text: structuredRecipeText || structuredText,
      parsed: structuredRecipeText
        ? parseStructuredRecipe(structuredRecipeText)
        : null,
    });
  }

  // Transcript digest (pre-distilled audio)
  if (input.transcriptDigest?.trim()) {
    const digestParsed = parseStructuredRecipe(input.transcriptDigest);
    sources.push({
      kind: "transcript_digest",
      isPrimary: false,
      text: input.transcriptDigest,
      parsed: digestParsed,
    });
  }

  // Raw audio transcript
  if (input.transcript?.trim() && !input.transcriptDigest?.trim()) {
    const audioParsed = parseStructuredRecipe(input.transcript);
    sources.push({
      kind: "audio_raw",
      isPrimary: false,
      text: input.transcript,
      parsed: audioParsed,
    });
  }

  // Web page text
  const webText = collectWebText(input);
  if (webText) {
    const webParsed = parseStructuredRecipe(webText);
    sources.push({
      kind: "web",
      isPrimary: false,
      text: webText,
      parsed: webParsed,
    });
  }

  // --- HARD RULE: Elect primary ---
  electPrimary(sources);

  return sources;
}

function electPrimary(sources: ClassifiedSource[]): void {
  // HARD RULE (non-negotiable): If the caption fires either dual
  // condition of captionTriggersHardPrimary, it IS primary — no score
  // comparison, no override. See plan §3 "CAPTION HARD RULE".
  const caption = sources.find((s) => s.kind === "caption");
  if (caption?.parsed && captionTriggersHardPrimary(caption.parsed)) {
    caption.isPrimary = true;
    return;
  }

  // Deterministic fallback priority: structured_data > caption > transcript_digest > audio_raw > web
  const priority: SourceKind[] = [
    "structured_data",
    "caption",
    "transcript_digest",
    "audio_raw",
    "web",
  ];
  for (const kind of priority) {
    const source = sources.find((s) => s.kind === kind);
    if (source && hasMinimalRecipeSignal(source)) {
      source.isPrimary = true;
      return;
    }
  }

  // If nothing qualifies, mark caption (or first source) as primary anyway
  if (caption) {
    caption.isPrimary = true;
  } else if (sources.length > 0) {
    sources[0].isPrimary = true;
  }
}

/**
 * Caption HARD RULE trigger (plan §3, §5 Fix S1). The caption becomes
 * PRIMARY unconditionally when EITHER:
 *
 *   (a) it contains a plausible ingredient list (≥ 3 ingredient lines),
 *       OR
 *   (b) it contains ≥ 2 explicit recipe section headers each with at
 *       least one ingredient underneath.
 *
 * Either condition alone is sufficient. This fires with or without
 * numbered steps — a caption that lists 10 ingredients in sections but
 * has zero numbered steps must still be elected as primary rather than
 * delegated to the LLM for full reconstruction.
 */
export function captionTriggersHardPrimary(parsed: ParsedRecipe): boolean {
  // Condition (a): plausible ingredient list.
  if (parsed.rawIngredientCount >= 3) return true;

  // Condition (b): explicit sections (named, non-empty) with content.
  const explicitSectionsWithContent = parsed.sections.filter(
    (s) => s.name.trim().length > 0 && s.ingredients.length >= 1
  ).length;
  if (explicitSectionsWithContent >= 2) return true;

  return false;
}

/**
 * @deprecated Retained for API stability in existing call sites. New
 * code must use {@link captionTriggersHardPrimary} which implements the
 * non-negotiable hard-rule contract.
 */
export function isCaptionStructuredRecipe(parsed: ParsedRecipe): boolean {
  return captionTriggersHardPrimary(parsed);
}

function hasMinimalRecipeSignal(source: ClassifiedSource): boolean {
  if (!source.parsed) {
    // Structured data often doesn't go through our parser
    return source.kind === "structured_data" && source.text.length > 100;
  }
  return source.parsed.rawIngredientCount >= 2 || source.parsed.rawStepCount >= 2;
}

// =====================================================================
// Stage 2: Parse Structure (Section-Aware)
// =====================================================================

/**
 * Section-aware recipe parser. Uses THREE detection strategies:
 *   1. Explicit headers ("Pour la marinade:", "Sauce:", "## Garniture")
 *   2. Structural patterns (lines starting with "- " after a header-like line)
 *   3. Grouping heuristics (consecutive ingredient-like lines form sections)
 */
export function parseStructuredRecipe(text: string): ParsedRecipe {
  const cleaned = normalizeLineWhitespace(stripCaptionMarkdown(text || ""));
  if (!cleaned) {
    return emptyParsedRecipe();
  }

  const rawLines = cleaned.split(/\n/).map((l) => l.trim()).filter(Boolean);
  if (!rawLines.length) {
    return emptyParsedRecipe();
  }

  // Expand digest-style one-liners: "Ingredients: a, b, c" becomes a
  // list header plus one bullet per item. Same for "Steps:".
  const lines = expandDigestOneLiners(rawLines);

  const title = extractTitle(lines);
  // Drop the exact title line before section parsing so the headline
  // (e.g. "Homemade cheesy beef panini pockets") doesn't leak into the
  // unnamed section as a phantom ingredient. Only the FIRST occurrence
  // is removed — a later identical line is genuinely content.
  const titleNormalized = title.trim().toLowerCase();
  let titleLineRemoved = false;
  const linesForSections = titleNormalized
    ? lines.filter((line) => {
        if (titleLineRemoved) return true;
        if (line.trim().toLowerCase() === titleNormalized) {
          titleLineRemoved = true;
          return false;
        }
        return true;
      })
    : lines;
  const sections = parseSections(linesForSections);
  const hasExplicitSections = sections.some((s) => s.name !== "");

  let totalIngredients = 0;
  let totalSteps = 0;
  for (const section of sections) {
    totalIngredients += section.ingredients.length;
    totalSteps += section.steps.length;
  }

  return {
    title,
    sections,
    rawIngredientCount: totalIngredients,
    rawStepCount: totalSteps,
    hasExplicitSections,
  };
}

function emptyParsedRecipe(): ParsedRecipe {
  return {
    title: "",
    sections: [],
    rawIngredientCount: 0,
    rawStepCount: 0,
    hasExplicitSections: false,
  };
}

// Normalize Markdown emphasis syntax that some captions use to mark sections
// (e.g. `**La sauce:**`, `__Pour le poulet :__`, `_Marinade_`). The section
// header regexes operate on plain text, so we strip the wrappers up front.
function stripCaptionMarkdown(text: string): string {
  return text
    .replace(/\*\*([^*\n]+?)\*\*/g, "$1")
    .replace(/__([^_\n]+?)__/g, "$1")
    .replace(/(?<![_*\w])_([^_\n]+?)_(?![_*\w])/g, "$1")
    .replace(/(?<![_*\w])\*([^*\n]+?)\*(?![_*\w])/g, "$1");
}

// --- Section Header Detection ---

// Explicit section header patterns (FR + EN)
const SECTION_HEADER_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  // French explicit headers
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?marinade\s*[:：]?\s*$/i, label: "Marinade" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?sauce\s*[:：]?\s*$/i, label: "Sauce" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?(?:pâte|pate)\s*[:：]?\s*$/i, label: "Pâte" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?garniture\s*[:：]?\s*$/i, label: "Garniture" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?salade\s*[:：]?\s*$/i, label: "Salade" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?montage\s*[:：]?\s*$/i, label: "Montage" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?cuisson\s*[:：]?\s*$/i, label: "Cuisson" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?dressage\s*[:：]?\s*$/i, label: "Dressage" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?accompagnement\s*[:：]?\s*$/i, label: "Accompagnement" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?assemblage\s*[:：]?\s*$/i, label: "Assemblage" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?finition\s*[:：]?\s*$/i, label: "Finition" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?crème\s*[:：]?\s*$/i, label: "Crème" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?vinaigrette\s*[:：]?\s*$/i, label: "Vinaigrette" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?farce\s*[:：]?\s*$/i, label: "Farce" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?sirop\s*[:：]?\s*$/i, label: "Sirop" },
  { pattern: /^(?:pour\s+)?(?:la\s+|le\s+|les\s+|l['']\s*)?gla[cç]age\s*[:：]?\s*$/i, label: "Glaçage" },

  // English explicit headers
  { pattern: /^(?:for\s+the\s+)?marinade\s*[:：]?\s*$/i, label: "Marinade" },
  { pattern: /^(?:for\s+the\s+)?sauce\s*[:：]?\s*$/i, label: "Sauce" },
  { pattern: /^(?:for\s+the\s+)?dough\s*[:：]?\s*$/i, label: "Pâte" },
  { pattern: /^(?:for\s+the\s+)?filling\s*[:：]?\s*$/i, label: "Garniture" },
  { pattern: /^(?:for\s+the\s+)?salad\s*[:：]?\s*$/i, label: "Salade" },
  { pattern: /^(?:for\s+the\s+)?assembly\s*[:：]?\s*$/i, label: "Montage" },
  { pattern: /^(?:for\s+the\s+)?dressing\s*[:：]?\s*$/i, label: "Vinaigrette" },
  { pattern: /^(?:for\s+the\s+)?topping\s*[:：]?\s*$/i, label: "Garniture" },
  { pattern: /^(?:for\s+the\s+)?glaze\s*[:：]?\s*$/i, label: "Glaçage" },

  // Inline headers — "Marinade :" or "SAUCE:" at start of a line with content after
  { pattern: /^(?:marinade|sauce|pâte|pate|garniture|salade|montage|cuisson|dressage|assemblage|accompagnement|vinaigrette|farce|crème|sirop|gla[cç]age|dough|filling|salad|assembly|dressing|topping|glaze)\s*[:：]\s*.+/i, label: "_inline_" },
];

// Structural header: a short line — possibly prefixed by a bullet
// (`•·*▪◦‣⁃-`) — followed by ingredient-like or list-like lines. We
// require the colon ONLY when there is no bullet prefix; bullet-marked
// headers like `• sauce raclette` or `•oignons caramélisés` are common
// in TikTok captions and should still be treated as section starts.
const BULLET_PREFIX_RE = /^[\s\u00A0]*(?:[•·▪◦‣⁃*]+|[\p{Extended_Pictographic}\uFE0F]+)[\s\u00A0]*/u;

function isStructuralSectionHeader(line: string, nextLines: string[]): string | null {
  const bulletStripped = line.replace(BULLET_PREFIX_RE, "").trim();
  const hadBulletPrefix = bulletStripped !== line.trim();

  // Trim trailing parenthetical content so creators' inline notes like
  // `MARINADE (au moins 1h au frais)` still match the header pattern.
  const parenStripped = bulletStripped.replace(/\s*\([^)]*\)\s*$/, "").trim();

  // Pattern: short label, optional trailing colon. Colon required only
  // when there is no bullet/emoji prefix (otherwise we'd flag any plain
  // sentence as a section).
  const colonOptional = hadBulletPrefix;
  const headerPattern = colonOptional
    ? /^([A-Za-zÀ-ÿ\s'']{2,60})\s*[:：]?\s*$/
    : /^([A-Za-zÀ-ÿ\s'']{2,60})\s*[:：]\s*$/;
  const headerMatch = parenStripped.match(headerPattern);
  if (!headerMatch) return null;

  const label = headerMatch[1].trim();
  if (!label) return null;
  // Cap section labels at 5 words to avoid catching sentences.
  const wordCount = label.split(/\s+/).filter(Boolean).length;
  if (wordCount === 0 || wordCount > 5) return null;

  // Must be followed by at least 1 ingredient-like or list-like line
  const nextRelevant = nextLines.slice(0, 3);
  const hasListFollowing = nextRelevant.some(
    (l) => looksLikeIngredientLine(l) || /^[-•·*▪◦‣⁃]\s?/.test(l) || /^\d+[.)]\s/.test(l)
  );
  if (!hasListFollowing) return null;

  // Capitalize properly
  return label.charAt(0).toUpperCase() + label.slice(1).toLowerCase();
}

function matchSectionHeader(line: string, nextLines: string[]): string | null {
  // 1. Check explicit patterns
  for (const { pattern, label } of SECTION_HEADER_PATTERNS) {
    if (pattern.test(line)) {
      if (label === "_inline_") {
        // Extract the label from the inline header
        const inlineMatch = line.match(/^([A-Za-zÀ-ÿ]+)\s*[:：]/i);
        return inlineMatch
          ? inlineMatch[1].charAt(0).toUpperCase() + inlineMatch[1].slice(1).toLowerCase()
          : null;
      }
      return label;
    }
  }

  // 2. Check structural pattern (short line ending with ":" followed by list content)
  return isStructuralSectionHeader(line, nextLines);
}

// --- Ingredient Detection ---

const INGREDIENT_LINE_PATTERNS: RegExp[] = [
  // "- 200g farine", "• 3 oeufs", "* sel", "·sel", "▪3 oignons"
  // Accept any common bullet glyph with OR without a following space.
  /^[-•·*▪◦‣⁃]\s*/u,
  // "200g farine", "3 oeufs", "1/2 c.à.s huile"
  /^\d+(?:[.,/]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|c\.\s*à\s*(?:s|c)|cas|cac|cuillère|pincée|sachet|tranche|gousse|tasse)\b/i,
  // Starting with a number followed by a word
  /^\d+(?:[.,/]\d+)?\s+[A-Za-zÀ-ÿ]/,
  // Starting with a vulgar fraction
  /^[¼½¾⅓⅔⅛]\s+/,
];

function looksLikeIngredientLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed || trimmed.length > 120) return false;

  // Must have alphabetical content
  if (!/[A-Za-zÀ-ÿ]/.test(trimmed)) return false;

  // Dual-gate: must pass BOTH structural-shape AND food-signal gates.
  // This replaces the previous permissive short-line fallback that
  // allowed contamination like "PC", "Photo editor", "AI videos for Mac"
  // through as "ingredients". See foodTermGate.ts.
  return passesDualGate(trimmed);
}

// --- Step Detection ---

const COOKING_VERB_PATTERN = /\b(?:cuire|cuisson|chauffer|mélanger|couper|ajouter|verser|laisser|servir|assaisonner|préchauffer|faire|préparer|incorporer|pétrir|étaler|malaxer|saisir|griller|caraméliser|retourner|garnir|napper|finir|enrober|diluer|disposer|réchauffer|rouler|rabattre|mariner|fouetter|battre|émincer|hacher|rincer|égoutter|monter|dresser|décorer|éplucher|laver|beurrer|huiler|salir|saler|poivrer|réduire|déglacer|flamber|rôtir|frire|sauter|mijoter|bouillir|dorer|tailler|tamiser|infuser|aplatir|rassembler|partager|tartiner|parsemer|pré-chauffer|cook|mix|heat|add|pour|serve|bake|fry|grill|roast|sauté|sear|whisk|stir|fold|knead|chop|dice|mince|slice|marinate|season|simmer|boil|blanch|broil|braise|deglaze|reduce|melt|beat|cream|blend|stuff|brush|drizzle|toss|layer|spread|wrap|roll|assemble|plate|garnish|sprinkle|drain|rinse|peel|chill|refrigerate|cool|top|cover)\b/i;

function containsCookingVerb(text: string): boolean {
  return COOKING_VERB_PATTERN.test(text);
}

function looksLikeStepLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed || trimmed.length < 15) return false;

  // Numbered steps: "1. Mélanger...", "1) Cuire..."
  if (/^\d+[.)]\s+/.test(trimmed) && containsCookingVerb(trimmed)) return true;

  // Contains cooking verbs and is long enough to be an instruction
  if (containsCookingVerb(trimmed) && trimmed.split(/\s+/).length >= 4) return true;

  return false;
}

// --- Main Section Parser ---

function parseSections(lines: string[]): RecipeSection[] {
  const sections: RecipeSection[] = [];
  let currentSection: RecipeSection = { name: "", ingredients: [], steps: [] };
  let mode: "ingredients" | "steps" | "unknown" = "unknown";

  // Detect if we have an explicit "Ingrédients" / "Étapes" header
  const hasIngredientsHeader = lines.some((l) =>
    /^(?:ingrédients?|ingredients?)\s*[:：]?\s*$/i.test(l.trim())
  );
  const hasStepsHeader = lines.some((l) =>
    /^(?:étapes?|steps?|instructions?|préparation|preparation|method)\s*[:：]?\s*$/i.test(l.trim())
  );

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    const remainingLines = lines.slice(i + 1);

    // Check for section header
    const sectionLabel = matchSectionHeader(line, remainingLines);
    if (sectionLabel) {
      // Push current section if it has content
      if (currentSection.ingredients.length > 0 || currentSection.steps.length > 0) {
        sections.push(currentSection);
      }
      currentSection = { name: sectionLabel, ingredients: [], steps: [] };
      mode = "ingredients"; // After a section header, expect ingredients first

      // Handle inline header: "Sauce: crème, moutarde, citron".
      // Only triggers when the line genuinely has content after a colon —
      // we used to misfire on bullet-prefixed labels like `•oignons
      // caramélisés` whose label looked like inline content because the
      // strip regex didn't match.
      const colonIndex = line.search(/[:：]/);
      if (colonIndex >= 0) {
        const inlineContent = line.slice(colonIndex + 1).trim();
        if (inlineContent) {
          const parts = inlineContent.split(/[,;]/).map((p) => p.trim()).filter(Boolean);
          for (const part of parts) {
            currentSection.ingredients.push(
              parseIngredientFromLine(part, sectionLabel)
            );
          }
        }
      }
      continue;
    }

    // Check for main section headers (Ingrédients, Étapes)
    if (/^(?:ingrédients?|ingredients?)\s*[:：]?\s*$/i.test(line)) {
      mode = "ingredients";
      continue;
    }
    if (/^(?:étapes?|steps?|instructions?|préparation|preparation|method)\s*[:：]?\s*$/i.test(line)) {
      mode = "steps";
      continue;
    }

    // Classify the line
    let isIngredient = looksLikeIngredientLine(line);
    let isStep = looksLikeStepLine(line);

    // Disambiguate numbered imperatives: "1. Mariner le poulet" has a
    // bullet shape AND a cooking verb — the dual-gate shape check accepts
    // the `\d+[.)]` prefix, but the line is unambiguously a step. Force
    // step classification when a numbered line carries a cooking verb.
    if (isIngredient && isStep && /^\d+[.)]\s+/.test(line) && containsCookingVerb(line)) {
      isIngredient = false;
    }

    if (mode === "unknown") {
      // Auto-detect mode from content
      if (isIngredient && !isStep) {
        mode = "ingredients";
      } else if (isStep && !isIngredient) {
        mode = "steps";
      }
    }

    // Transition: if we're in ingredients mode and hit a step line, switch
    if (mode === "ingredients" && isStep && !isIngredient) {
      mode = "steps";
    }
    // Transition: if we're in steps mode and hit an ingredient line, start new section
    if (mode === "steps" && isIngredient && !isStep && !hasIngredientsHeader && !hasStepsHeader) {
      // This might be a new implicit section
      if (currentSection.steps.length > 0) {
        sections.push(currentSection);
        currentSection = { name: "", ingredients: [], steps: [] };
        mode = "ingredients";
      }
    }

    // Comma-separated ingredient list: a single line like
    // "Salt, black pepper, smoked paprika, garlic powder, oregano" —
    // common under a "Seasonings:" header. Split into individual
    // ingredients instead of dropping the whole line.
    if (mode === "ingredients" && !isStep) {
      const commaParts = splitCommaSeparatedIngredients(line);
      if (commaParts.length >= 3) {
        for (const part of commaParts) {
          currentSection.ingredients.push(
            parseIngredientFromLine(part, currentSection.name)
          );
        }
        continue;
      }
    }

    if (mode === "ingredients" && isIngredient) {
      currentSection.ingredients.push(
        parseIngredientFromLine(line, currentSection.name)
      );
    } else if (mode === "steps" || isStep) {
      const cleanedStep = cleanStepLine(line);
      if (cleanedStep) {
        currentSection.steps.push({
          detail: cleanedStep,
          section: currentSection.steps.length === 0 ? currentSection.name : "",
        });
      }
      mode = "steps";
    } else if (isIngredient) {
      currentSection.ingredients.push(
        parseIngredientFromLine(line, currentSection.name)
      );
      mode = "ingredients";
    }
  }

  // Push final section
  if (currentSection.ingredients.length > 0 || currentSection.steps.length > 0) {
    sections.push(currentSection);
  }

  return sections;
}

// --- Line Parsers ---

/**
 * Splits a single line that is actually a comma-separated list of
 * ingredients ("Salt, black pepper, smoked paprika, garlic powder,
 * oregano, cayenne, thyme & all-purpose seasoning"). Returns the parts
 * ONLY when the line genuinely looks like such a list: ≥ 2 separators,
 * every part short (≤ 4 words), and a majority of parts pass the food
 * gate. Returns [] otherwise so the caller falls back to normal
 * single-ingredient handling.
 */
function splitCommaSeparatedIngredients(line: string): string[] {
  const trimmed = line.trim();
  if (!trimmed || trimmed.length > 240) return [];
  // Bail on lines that look like prose / steps (cooking verbs, etc.).
  if (containsCookingVerb(trimmed)) return [];
  // Must have at least two separators.
  const separatorCount = (trimmed.match(/[,&]|\set\s/gi) ?? []).length;
  if (separatorCount < 2) return [];

  const parts = trimmed
    .split(/\s*(?:,|&|\set\s)\s*/i)
    .map((p) => p.trim())
    .filter(Boolean);
  if (parts.length < 3) return [];

  let foodParts = 0;
  for (const part of parts) {
    const wordCount = part.split(/\s+/).filter(Boolean).length;
    if (wordCount === 0 || wordCount > 4) return [];
    if (/\d/.test(part)) return []; // numbered lists handled elsewhere
    if (passesDualGate(part) || containsFoodSignal(part)) {
      foodParts += 1;
    }
  }
  // Require a clear majority of parts to read as food.
  return foodParts >= Math.ceil(parts.length * 0.6) ? parts : [];
}

function parseIngredientFromLine(line: string, group: string): RecipeIngredientDraft {
  let cleaned = line
    // Accept any common bullet glyph with OR without a following space:
    // `- 200g farine`, `•3 oeufs`, `·sel`, `▪ 1/2 c.s huile`, etc.
    .replace(/^[-•·*▪◦‣⁃]\s*/u, "")
    .replace(/^\d+[.)]\s+/, "")
    // Collapse a leading quantity RANGE to its first value so the rest
    // doesn't leak into the name. `1/2-1 cup Milk` → `1/2 cup Milk`,
    // `2-3 chicken breasts` → `2 chicken breasts`, `150-200g` → `150g`.
    .replace(/^(\d+(?:[.,/]\d+)?)\s*[-–—]\s*\d+(?:[.,/]\d+)?(\s*)/u, "$1$2")
    .trim();

  // Extract amount and unit from prefix
  let amount = "";
  let unit = "";

  // Pattern: "200g", "200 g", "3", "1/2". The unit (when present) must
  // be followed by a word boundary so we don't eat the first letter of
  // the ingredient name — e.g. "3 grande escalopes" must NOT parse as
  // `3 g` + `rande escalopes`. The unit group is optional so plain
  // counts like "3 oignons" still match. We try the long forms first
  // (`c. à soupe`, `c. à café`) so they win over the short forms
  // (`c. à s`, `c. à c`) when the caption uses the full word.
  const amountUnitMatch = cleaned.match(
    /^(\d+(?:[.,/]\d+)?|[¼½¾⅓⅔⅛])\s*(?:(c\.\s*à\s*(?:soupe|café)|cuillères?\s*à\s*(?:soupe|café)|c\.\s*à\s*[sc]|kg|mg|ml|cl|dl|cas|cac|pincée|sachet|tranche|gousse|tasse|tbsp|tsp|cup|g|l|oz|lb)(?=\s|$|[.,)])\s*(?:de\s+|d['']\s*)?)?/i
  );
  if (amountUnitMatch) {
    amount = amountUnitMatch[1] || "";
    unit = amountUnitMatch[2] || "";
    cleaned = cleaned.slice(amountUnitMatch[0].length).trim();
  }

  // Normalize unit
  unit = normalizeFrenchUnit(unit);

  // Clean the name through the ASR cleanup
  const asrCleaned = cleanIngredientNameField(cleaned, unit || undefined, amount || undefined);
  if (asrCleaned.dropped) {
    return { amount: "", unit: "", name: "", nutritionQuery: "", group };
  }

  if (!amount && asrCleaned.extractedAmount) {
    amount = asrCleaned.extractedAmount;
  }
  if (!unit && asrCleaned.extractedUnit) {
    unit = normalizeFrenchUnit(asrCleaned.extractedUnit);
  }

  const finalName = asrCleaned.name || cleaned;

  // Normalize the ingredient name — but KEEP ORIGINAL if unsure
  const normalized = normalizeFrenchIngredientName(finalName);
  const displayName = normalized.displayName || finalName;

  return {
    amount,
    unit,
    name: displayName,
    nutritionQuery: displayName,
    group,
  };
}

function cleanStepLine(line: string): string {
  return line
    .replace(/^\d+[.)]\s+/, "")
    .replace(/^[-•*]\s+/, "")
    .replace(/^(?:étape|step)\s*\d+\s*[:.)]\s*/i, "")
    .replace(/\b\d{2}:\d{2}(?::\d{2})?(?:[.,]\d{3})?\b/g, " ")
    .replace(/-->/g, " ")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/#[\p{L}\p{N}_]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// A leading quantity marks a line as a genuine ingredient, never a title.
const LEADING_QUANTITY_RE = /^\s*[-•·*▪◦‣⁃]?\s*(?:\d+(?:[.,/]\d+)?|[¼½¾⅓⅔⅛])/u;

function extractTitle(lines: string[]): string {
  let isFirstContentLine = true;
  // First non-empty line that doesn't look like an ingredient, step, or section header
  for (const line of lines.slice(0, 5)) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    const isFirst = isFirstContentLine;
    isFirstContentLine = false;

    // The very first content line of a caption is the headline/title in
    // the vast majority of recipe posts — even when it contains a food
    // word ("Homemade cheesy BEEF panini pockets"). Only reject it as a
    // title when it carries a leading quantity (then it's a real
    // ingredient) or is itself a section header.
    const looksLikeStructuredIngredient = LEADING_QUANTITY_RE.test(trimmed);
    const isSectionHeader = Boolean(matchSectionHeader(trimmed, lines.slice(1)));
    const isListHeader = /^(?:ingrédients?|ingredients?|étapes?|steps?|instructions?)\s*[:：]?\s*$/i.test(trimmed);

    if (!isFirst || looksLikeStructuredIngredient || isSectionHeader || isListHeader) {
      if (looksLikeIngredientLine(trimmed)) continue;
      if (looksLikeStepLine(trimmed)) continue;
      if (isListHeader) continue;
      if (isSectionHeader) continue;
    }

    // Likely a title
    const cleaned = trimmed
      .replace(/^(?:recette|recipe)\s*[:：]\s*/i, "")
      .replace(/#[\p{L}\p{N}_]+/gu, " ")
      .replace(/\p{Extended_Pictographic}/gu, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (cleaned.length >= 3 && cleaned.length <= 100) {
      return cleaned;
    }
  }
  return "";
}

// =====================================================================
// Stage 3: Conservative Enrichment
// =====================================================================

/**
 * Conservative merge. Only enriches the primary recipe with data from
 * secondary sources when confidence is HIGH.
 *
 * Rules:
 * - Never override an existing ingredient from primary
 * - Only ADD missing ingredients from secondary (high confidence only)
 * - Only CONFIRM uncertain quantities
 * - Preserve section structure from primary; NEVER flatten
 */
export function conservativeEnrich(
  primary: ParsedRecipe,
  secondaries: ClassifiedSource[]
): ParsedRecipe {
  // If primary already has good coverage, don't touch it
  if (primary.rawIngredientCount >= 5 && primary.rawStepCount >= 3) {
    return primary;
  }

  let enriched = { ...primary, sections: primary.sections.map((s) => ({ ...s })) };

  for (const secondary of secondaries) {
    if (!secondary.parsed) continue;
    if (secondary.parsed.rawIngredientCount < 2) continue;

    // Only enrich when the secondary is clearly structured (recipeLines
    // >= 4, steps >= 2). Per plan MERGE RULE 2 ("strong" secondary).
    const secondaryIsStrong =
      secondary.parsed.rawIngredientCount >= 4 && secondary.parsed.rawStepCount >= 2;
    if (!secondaryIsStrong) continue;

    // Section-aware enrichment. The helpers apply their own per-section
    // gating so a multi-section primary where one section is step-light
    // can still be augmented even when the global step count is high.
    enriched = fillMissingSteps(enriched, secondary.parsed);
    enriched = fillMissingIngredients(enriched, secondary.parsed);
  }

  return enriched;
}

// Find the primary section whose name canonicalizes to the same key as
// the given secondary section. Returns undefined when there is no match
// and the caller must decide whether to introduce a new section.
function findMatchingSection(
  primarySections: RecipeSection[],
  secondaryName: string
): RecipeSection | undefined {
  const target = normalizeForComparison(secondaryName);
  if (!target) {
    // Unnamed secondary section — match primary unnamed section if any.
    return primarySections.find((s) => !s.name.trim());
  }
  return primarySections.find(
    (s) => normalizeForComparison(s.name) === target
  );
}

/**
 * Section-aware step enrichment (plan §5 Fix S2, §7 Phase 3).
 *
 * For each secondary section that has steps, locate the matching
 * primary section by normalized name. If found, append missing steps
 * to THAT section. If no match is found, introduce a new section (we
 * NEVER append to the last section blindly — that was the original
 * structure-loss bug).
 *
 * Primary steps are only considered "low" at the section granularity:
 * a section with 0 or 1 steps can still be enriched by a secondary
 * that has a matching section with more steps.
 */
function fillMissingSteps(primary: ParsedRecipe, secondary: ParsedRecipe): ParsedRecipe {
  const newSections: RecipeSection[] = primary.sections.map((s) => ({
    ...s,
    ingredients: [...s.ingredients],
    steps: [...s.steps],
  }));
  if (newSections.length === 0) {
    newSections.push({ name: "", ingredients: [], steps: [] });
  }

  for (const secSection of secondary.sections) {
    if (secSection.steps.length === 0) continue;

    const match = findMatchingSection(newSections, secSection.name);

    if (match) {
      // Only enrich sections that are step-light.
      if (match.steps.length >= 2) continue;
      for (const step of secSection.steps) {
        const isDupe = match.steps.some(
          (existing) =>
            normalizeForComparison(existing.detail) ===
            normalizeForComparison(step.detail)
        );
        if (!isDupe) {
          match.steps.push({ ...step, section: match.name });
        }
      }
    } else if (primary.rawStepCount < 2) {
      // No section match AND primary is globally step-starved → introduce
      // the secondary section as a new entry. This respects MERGE RULE 5:
      // the secondary section has an explicit name (non-empty) and real
      // content. Unnamed secondary sections are appended as a new
      // unnamed group rather than merged into the last existing one.
      newSections.push({
        name: secSection.name || "",
        ingredients: [],
        steps: secSection.steps.map((s) => ({
          ...s,
          section: secSection.name || "",
        })),
      });
    }
  }

  let totalSteps = 0;
  for (const s of newSections) totalSteps += s.steps.length;

  return { ...primary, sections: newSections, rawStepCount: totalSteps };
}

/**
 * Section-aware ingredient enrichment (plan §5 Fix S3).
 *
 * For each secondary section, find the matching primary section by
 * normalized name. If found, add non-duplicate ingredients to THAT
 * section. If no match is found, apply MERGE RULE 5 for conservative
 * secondary section introduction:
 *   - The secondary section must have an explicit (non-empty) name.
 *   - It must contain ≥ 3 ingredients.
 *   - None of its ingredients may collide with an existing primary
 *     ingredient under a DIFFERENT section name (prevents re-grouping).
 *
 * Otherwise the secondary section's ingredients are discarded.
 */
function fillMissingIngredients(
  primary: ParsedRecipe,
  secondary: ParsedRecipe
): ParsedRecipe {
  const newSections: RecipeSection[] = primary.sections.map((s) => ({
    ...s,
    ingredients: [...s.ingredients],
    steps: [...s.steps],
  }));
  if (newSections.length === 0) {
    newSections.push({ name: "", ingredients: [], steps: [] });
  }

  // Map of normalized-name -> section name, used for collision detection.
  const ingredientToSection = new Map<string, string>();
  for (const s of newSections) {
    for (const ing of s.ingredients) {
      const key = normalizeForComparison(ing.name);
      if (key) ingredientToSection.set(key, s.name);
    }
  }

  const primaryHasNames = newSections.some((s) => s.name.trim().length > 0);

  for (const secSection of secondary.sections) {
    const match = findMatchingSection(newSections, secSection.name);

    if (match) {
      // Matching section → add non-duplicate ingredients directly.
      const existing = new Set(
        match.ingredients.map((i) => normalizeForComparison(i.name))
      );
      for (const ingredient of secSection.ingredients) {
        const key = normalizeForComparison(ingredient.name);
        if (!key || existing.has(key)) continue;
        match.ingredients.push({ ...ingredient, group: match.name });
        existing.add(key);
        ingredientToSection.set(key, match.name);
      }
      continue;
    }

    // MERGE RULE 5 — conservative secondary section introduction.
    const hasExplicitName = secSection.name.trim().length > 0;
    const hasSufficientIngredients = secSection.ingredients.length >= 3;
    if (!hasExplicitName || !hasSufficientIngredients) {
      // Unnamed / thin secondary section — only fold ingredients into
      // the primary's first section if the primary is globally ingredient-
      // starved (< 3) AND the primary has no named structure (avoids
      // mixing unnamed secondary content into a structured primary).
      if (primary.rawIngredientCount >= 3 || primaryHasNames) continue;
      const fallback = newSections[0];
      const existing = new Set(
        fallback.ingredients.map((i) => normalizeForComparison(i.name))
      );
      for (const ingredient of secSection.ingredients) {
        const key = normalizeForComparison(ingredient.name);
        if (!key || existing.has(key)) continue;
        fallback.ingredients.push({ ...ingredient, group: fallback.name });
        existing.add(key);
        ingredientToSection.set(key, fallback.name);
      }
      continue;
    }

    // Conflict check — no ingredient in the candidate section may
    // already live under a DIFFERENT section in the primary.
    const hasConflict = secSection.ingredients.some((ing) => {
      const key = normalizeForComparison(ing.name);
      if (!key) return false;
      const existingSection = ingredientToSection.get(key);
      return existingSection !== undefined && existingSection !== secSection.name;
    });
    if (hasConflict) continue;

    // Section-label near-duplicate check — do not introduce a section
    // whose normalized name collides with any existing primary section.
    const labelKey = normalizeForComparison(secSection.name);
    const labelDup = newSections.some(
      (s) => normalizeForComparison(s.name) === labelKey
    );
    if (labelDup) continue;

    // All gates pass — introduce the secondary section.
    const introduced: RecipeSection = {
      name: secSection.name,
      ingredients: secSection.ingredients.map((ing) => ({
        ...ing,
        group: secSection.name,
      })),
      steps: [],
    };
    newSections.push(introduced);
    for (const ing of introduced.ingredients) {
      const key = normalizeForComparison(ing.name);
      if (key) ingredientToSection.set(key, secSection.name);
    }
  }

  let totalIngredients = 0;
  for (const s of newSections) totalIngredients += s.ingredients.length;

  return { ...primary, sections: newSections, rawIngredientCount: totalIngredients };
}

function normalizeForComparison(text: string): string {
  return (text || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// =====================================================================
// Stage 4: Compile Final Recipe + Non-Degradation Guard
// =====================================================================

/**
 * Compiles a ParsedRecipe into a RecipeImportResult.
 * Enforces the NON-DEGRADATION INVARIANT: if the compiled result
 * is worse than the primary source, fall back to the cleaned primary.
 */
export function compileFinalRecipe(
  parsed: ParsedRecipe,
  input: NormalizerInput,
  primaryQuality: number
): CompilerResult {
  const allIngredients: RecipeIngredientDraft[] = [];
  const allSteps: Array<{ detail: string; section?: string }> = [];

  for (const section of parsed.sections) {
    for (const ingredient of section.ingredients) {
      if (ingredient.name.trim()) {
        allIngredients.push(safeNormalizeIngredient(ingredient));
      }
    }
    for (const step of section.steps) {
      if (step.detail.trim()) {
        allSteps.push(step);
      }
    }
  }

  const recipe = sanitizeRecipeImport({
    title: parsed.title || "",
    sourceUrl: input.sourceUrl ?? "",
    remoteImageUrl: input.remoteImageUrl ?? "",
    ingredientDrafts: allIngredients,
    stepDrafts: allSteps.map((s) => ({
      detail: s.detail,
      ...(s.section ? { section: s.section } : {}),
    })),
    notesText: "",
    prepTimeText: "",
    cookTimeText: "",
    servingsText: "",
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: allIngredients.length >= 5 && allSteps.length >= 3 ? "high" : "medium",
    needsWebFallback: allIngredients.length < 3 || allSteps.length < 2,
    searchQuery: parsed.title || "",
    inferredFromPhoto: false,
    flags: {
      usedExplicitIngredients: allIngredients.length > 0,
      usedInferredIngredients: false,
      generatedSteps: false,
      generatedNutrition: false,
      needsReview: false,
    },
  });

  const outputQuality = measureRecipeQuality(recipe);
  const llmNeeded = isCompilerOutputIncomplete(recipe);

  // NON-DEGRADATION INVARIANT
  if (outputQuality < primaryQuality * 0.85) {
    // Output is worse than primary — this should not happen with our
    // conservative pipeline, but guard against it.
    console.warn(
      `[recipeCompiler] Non-degradation guard triggered: outputQ=${outputQuality.toFixed(2)} < primaryQ=${primaryQuality.toFixed(2)}*0.85`
    );
  }

  return {
    recipe,
    primarySource: "caption", // Will be overridden by caller
    usedEnrichment: false,
    compilerUsed: true,
    llmNeeded,
  };
}

// =====================================================================
// Quality Measurement
// =====================================================================

/**
 * Measures recipe quality on a 0-1 scale. Used for the non-degradation
 * invariant and for deciding whether LLM is needed.
 */
export function measureRecipeQuality(recipe: RecipeImportResult): number {
  let score = 0;

  // Title
  if (recipe.title.trim().length > 3) score += 0.1;

  // Ingredients
  const ingredientCount = recipe.ingredientDrafts.length;
  if (ingredientCount >= 8) score += 0.25;
  else if (ingredientCount >= 5) score += 0.2;
  else if (ingredientCount >= 3) score += 0.15;
  else if (ingredientCount >= 1) score += 0.05;

  // Ingredient quality: do they have names?
  const namedIngredients = recipe.ingredientDrafts.filter((i) => i.name.trim().length >= 2);
  score += Math.min(0.1, (namedIngredients.length / Math.max(1, ingredientCount)) * 0.1);

  // Steps
  const stepCount = recipe.stepDrafts.length;
  if (stepCount >= 6) score += 0.25;
  else if (stepCount >= 4) score += 0.2;
  else if (stepCount >= 2) score += 0.1;
  else if (stepCount >= 1) score += 0.05;

  // Sections (bonus for structure)
  const hasGroups = recipe.ingredientDrafts.some((i) => (i.group ?? "").trim().length > 0);
  if (hasGroups) score += 0.1;

  const hasSections = recipe.stepDrafts.some((s) => (s.section ?? "").trim().length > 0);
  if (hasSections) score += 0.05;

  // Nutrition
  if (recipe.caloriesText && recipe.proteinText && recipe.carbsText && recipe.fatText) {
    score += 0.1;
  }

  // Penalties
  if (recipe.confidence === "low") score -= 0.1;
  if (recipe.needsWebFallback) score -= 0.05;

  return Math.max(0, Math.min(1, score));
}

/**
 * Determines if the compiler output is incomplete and LLM assistance
 * is needed AS A LAST RESORT.
 */
export function isCompilerOutputIncomplete(recipe: RecipeImportResult): boolean {
  return (
    recipe.ingredientDrafts.length < 3 ||
    recipe.stepDrafts.length < 2 ||
    !recipe.title.trim()
  );
}

// =====================================================================
// Safe Ingredient Normalization
// =====================================================================

/**
 * Normalizes an ingredient safely. Rules:
 * - If unsure → KEEP ORIGINAL
 * - Never invert unit/ingredient order
 * - If quantity is implausible → drop it (prefer no quantity over wrong one)
 * - Never reduce specificity
 */
function safeNormalizeIngredient(ingredient: RecipeIngredientDraft): RecipeIngredientDraft {
  let { amount, unit, name, nutritionQuery, group } = ingredient;

  // Fix unit/name swap: detect units in name field
  const asrCleaned = cleanIngredientNameField(name, unit || undefined, amount || undefined);
  if (asrCleaned.dropped) {
    return { amount: "", unit: "", name: "", nutritionQuery: "", group };
  }

  name = asrCleaned.name || name;
  if (!amount && asrCleaned.extractedAmount) amount = asrCleaned.extractedAmount;
  if (!unit && asrCleaned.extractedUnit) unit = normalizeFrenchUnit(asrCleaned.extractedUnit);

  // Quantity plausibility check
  if (amount && name) {
    const numericAmount = parseFloat(amount.replace(",", "."));
    if (Number.isFinite(numericAmount) && !isPlausibleQuantity(numericAmount, unit, name)) {
      // Drop the quantity — prefer no quantity over a wrong one
      amount = "";
      unit = "";
    }
  }

  // Normalize the name — KEEP ORIGINAL if unsure
  const normalized = normalizeFrenchIngredientName(name);
  const finalName = normalized.displayName || name;

  // Never reduce specificity: if original has more tokens, keep it
  const originalTokens = name.split(/\s+/).filter(Boolean).length;
  const normalizedTokens = finalName.split(/\s+/).filter(Boolean).length;
  const safeName = normalizedTokens < originalTokens ? name : finalName;

  return {
    amount,
    unit,
    name: safeName,
    nutritionQuery: nutritionQuery || safeName,
    group: group ?? "",
  };
}

/**
 * Checks if a quantity is plausible for a given ingredient.
 * Examples of implausible:
 *   - "30 salade" (30 lettuces?)
 *   - "500 oeufs" (500 eggs?)
 *   - "1000 sel" (1000 salt?)
 */
function isPlausibleQuantity(amount: number, unit: string, name: string): boolean {
  if (amount <= 0) return false;

  // If there's a unit, the quantity is likely reasonable
  const normalizedUnit = (unit || "").toLowerCase().trim();
  if (normalizedUnit && normalizedUnit !== "" && /^(?:g|kg|mg|ml|cl|dl|l|oz|lb|c\.\s*à|pincée|sachet|tasse)/.test(normalizedUnit)) {
    // Common metric units — high amounts are fine for g/ml but not for kg/l/c.à.s
    if (/^(?:g|mg|ml)$/.test(normalizedUnit) && amount <= 5000) return true;
    if (/^(?:kg|l)$/.test(normalizedUnit) && amount <= 10) return true;
    if (/^(?:cl|dl)$/.test(normalizedUnit) && amount <= 100) return true;
    if (amount <= 50) return true;
    return false;
  }

  // No unit — raw count. Very high counts are suspicious.
  const normalizedName = normalizeForComparison(name);

  // Common "countable" ingredients with reasonable ranges
  if (/(?:oeuf|oeufs|egg|eggs)/.test(normalizedName)) return amount <= 24;
  if (/(?:gousse|clove|garlic)/.test(normalizedName)) return amount <= 20;
  if (/(?:tranche|slice)/.test(normalizedName)) return amount <= 20;
  if (/(?:oignon|onion)/.test(normalizedName)) return amount <= 10;
  if (/(?:tomate|tomato)/.test(normalizedName)) return amount <= 20;
  if (/(?:pomme|apple|banane|banana)/.test(normalizedName)) return amount <= 20;

  // Generic: unitless quantities > 20 are suspicious for most ingredients
  return amount <= 20;
}

// =====================================================================
// Main Pipeline Entry Point
// =====================================================================

/**
 * Main compiler entry point. Runs the 4-stage deterministic pipeline.
 *
 * Returns a CompilerResult. If `llmNeeded` is true, the caller should
 * use LLM as a LAST RESORT to fill gaps.
 */
export function compileRecipeFromSources(input: NormalizerInput): CompilerResult {
  // Stage 1: Classify & elect primary
  const sources = classifySources(input);
  const primarySource = sources.find((s) => s.isPrimary);

  if (!primarySource) {
    return {
      recipe: sanitizeRecipeImport({
        title: "",
        sourceUrl: input.sourceUrl ?? "",
        remoteImageUrl: input.remoteImageUrl ?? "",
        ingredientDrafts: [],
        stepDrafts: [],
        notesText: "",
        prepTimeText: "",
        cookTimeText: "",
        servingsText: "",
        caloriesText: "",
        proteinText: "",
        carbsText: "",
        fatText: "",
        confidence: "low",
        needsWebFallback: true,
        searchQuery: "",
        inferredFromPhoto: false,
      }),
      primarySource: "caption",
      usedEnrichment: false,
      compilerUsed: true,
      llmNeeded: true,
    };
  }

  // Stage 2: Parse structure
  const parsed = primarySource.parsed ?? parseStructuredRecipe(primarySource.text);

  // Measure primary quality for non-degradation guard
  const primaryQualityRecipe = compileFinalRecipe(parsed, input, 1.0);
  const primaryQuality = measureRecipeQuality(primaryQualityRecipe.recipe);

  // Stage 3: Conservative enrichment
  const secondaries = sources.filter((s) => !s.isPrimary);
  const enriched = conservativeEnrich(parsed, secondaries);

  // Stage 4: Compile final recipe with non-degradation guard
  const result = compileFinalRecipe(enriched, input, primaryQuality);

  // Non-degradation check
  const finalQuality = measureRecipeQuality(result.recipe);
  if (finalQuality < primaryQuality * 0.85) {
    // Fallback to cleaned primary
    return {
      ...primaryQualityRecipe,
      primarySource: primarySource.kind,
      usedEnrichment: false,
      llmNeeded: isCompilerOutputIncomplete(primaryQualityRecipe.recipe),
    };
  }

  return {
    ...result,
    primarySource: primarySource.kind,
    usedEnrichment: enriched !== parsed,
    llmNeeded: isCompilerOutputIncomplete(result.recipe),
  };
}

// =====================================================================
// Helpers
// =====================================================================

// Digest-style one-liners like "Ingredients: 250g farine, 3 oeufs, 500ml
// lait" come from transcript-distillation. Split them so each ingredient
// becomes its own bullet line the section parser can classify.
const DIGEST_INGREDIENTS_RE = /^(?:ingredients?|ingrédients?|ings?)\s*[:：]\s*(.+)$/i;
const DIGEST_STEPS_RE = /^(?:steps?|étapes?|etapes?|instructions?|preparation|préparation|method)\s*[:：]\s*(.+)$/i;
const DIGEST_TITLE_RE = /^(?:dish|plat|recipe|recette|title|titre)\s*[:：]\s*(.+)$/i;

function expandDigestOneLiners(lines: string[]): string[] {
  const out: string[] = [];
  for (const line of lines) {
    const titleMatch = line.match(DIGEST_TITLE_RE);
    if (titleMatch && titleMatch[1].trim()) {
      out.push(titleMatch[1].trim());
      continue;
    }
    const ingMatch = line.match(DIGEST_INGREDIENTS_RE);
    if (ingMatch && ingMatch[1].includes(",")) {
      out.push("Ingrédients:");
      for (const part of ingMatch[1].split(/[,;]/).map((p) => p.trim()).filter(Boolean)) {
        out.push(`- ${part}`);
      }
      continue;
    }
    const stepMatch = line.match(DIGEST_STEPS_RE);
    if (stepMatch && stepMatch[1].includes(",")) {
      out.push("Étapes:");
      const parts = stepMatch[1].split(/[,;]/).map((p) => p.trim()).filter(Boolean);
      parts.forEach((part, idx) => out.push(`${idx + 1}. ${part}`));
      continue;
    }
    out.push(line);
  }
  return out;
}

// Convert schema.org Recipe JSON-LD entries into a bullet/numbered text
// form the section parser can consume. Returns "" when nothing recipe-
// shaped is found.
function extractRecipeFromStructuredData(raw: string[]): string {
  const lines: string[] = [];
  let title = "";

  const visit = (node: unknown): void => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    const obj = node as Record<string, unknown>;
    const type = obj["@type"];
    const isRecipe = typeof type === "string"
      ? /recipe/i.test(type)
      : Array.isArray(type) && type.some((t) => typeof t === "string" && /recipe/i.test(t));

    if (isRecipe) {
      if (!title && typeof obj.name === "string") title = obj.name.trim();
      const ings = obj.recipeIngredient;
      if (Array.isArray(ings)) {
        for (const ing of ings) {
          if (typeof ing === "string" && ing.trim()) {
            lines.push(`- ${ing.trim()}`);
          }
        }
      }
      const steps = obj.recipeInstructions;
      if (Array.isArray(steps)) {
        let idx = 1;
        for (const step of steps) {
          const detail = typeof step === "string"
            ? step
            : step && typeof step === "object"
              ? String((step as { text?: unknown }).text ?? "")
              : "";
          if (detail.trim()) {
            lines.push(`${idx}. ${detail.trim()}`);
            idx += 1;
          }
        }
      }
    }

    for (const value of Object.values(obj)) visit(value);
  };

  for (const entry of raw) {
    if (!entry || typeof entry !== "string") continue;
    try {
      visit(JSON.parse(entry));
    } catch {
      // Not JSON — skip (microdata HTML would be handled upstream).
    }
  }

  if (lines.length === 0) return "";
  return title ? `${title}\n\n${lines.join("\n")}` : lines.join("\n");
}

function collectCaptionText(input: NormalizerInput): string {
  // Caption is socialCaption + sharedText ONLY. socialDescription is
  // intentionally excluded here — TikTok/Instagram descriptions carry
  // creator bios, music attributions, promos, and branded noise that
  // contaminated the caption source in the previous pipeline. It is
  // surfaced as its own source via the sourceSanitizer. socialSubtitles
  // are likewise kept separate so ASR-grade content does not pollute
  // the highest-quality source.
  const parts = [input.socialCaption, input.sharedText]
    .filter((v): v is string => Boolean(v?.trim()))
    .map((v) => v.trim());

  // Dedupe — keep only unique substantial content
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const part of parts) {
    const key = normalizeForComparison(part);
    if (key.length > 10 && !seen.has(key)) {
      seen.add(key);
      unique.push(part);
    }
  }

  return unique.join("\n\n");
}

function collectWebText(input: NormalizerInput): string {
  const parts = [
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent,
  ]
    .filter((v): v is string => Boolean(v?.trim()))
    .map((v) => v.trim());

  if (parts.length === 0) return "";

  // Strip nav/cookie/sidebar/footer boilerplate before parsing so the
  // compiler's line classifier sees recipe-candidate lines only.
  return cleanWebText(parts.join("\n\n"));
}
