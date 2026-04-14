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
import {
  normalizeFrenchUnit,
  cleanIngredientNameField,
  normalizeFrenchIngredientName,
} from "./ingredientNormalization.js";

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
    sources.push({
      kind: "structured_data",
      isPrimary: false,
      text: structuredText,
      parsed: null, // structured data uses a different parser path
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
  // HARD RULE: If caption contains a structured recipe, it IS the primary.
  const caption = sources.find((s) => s.kind === "caption");
  if (caption?.parsed && isCaptionStructuredRecipe(caption.parsed)) {
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
 * A caption qualifies as a structured recipe when it has explicit
 * ingredient-like content. This is the HARD gate.
 */
export function isCaptionStructuredRecipe(parsed: ParsedRecipe): boolean {
  return parsed.rawIngredientCount >= 3 && parsed.rawStepCount >= 1;
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
  const cleaned = normalizeWhitespace(text || "").trim();
  if (!cleaned) {
    return emptyParsedRecipe();
  }

  const lines = cleaned.split(/\n/).map((l) => l.trim()).filter(Boolean);
  if (!lines.length) {
    return emptyParsedRecipe();
  }

  const title = extractTitle(lines);
  const sections = parseSections(lines);
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

// Structural header: a short line ending with ":" that's followed by
// ingredient-like or list-like lines
function isStructuralSectionHeader(line: string, nextLines: string[]): string | null {
  // Pattern: "Word(s):" or "Word(s) :" with at most 4 words
  const colonMatch = line.match(/^([A-Za-zÀ-ÿ\s'']{2,40})\s*[:：]\s*$/);
  if (!colonMatch) return null;

  const label = colonMatch[1].trim();
  // Must be followed by at least 1 ingredient-like or list-like line
  const nextRelevant = nextLines.slice(0, 3);
  const hasListFollowing = nextRelevant.some(
    (l) => looksLikeIngredientLine(l) || /^[-•*]\s/.test(l) || /^\d+[.)]\s/.test(l)
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
  // "- 200g farine", "• 3 oeufs", "* sel"
  /^[-•*]\s+/,
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

  // Check structural patterns
  for (const pattern of INGREDIENT_LINE_PATTERNS) {
    if (pattern.test(trimmed)) return true;
  }

  // Short lines (≤ 6 words) without verbs are likely ingredients
  const words = trimmed.split(/\s+/).filter(Boolean);
  if (words.length <= 5 && words.length >= 1 && !containsCookingVerb(trimmed)) {
    return true;
  }

  return false;
}

// --- Step Detection ---

const COOKING_VERB_PATTERN = /\b(?:cuire|cuisson|chauffer|mélanger|couper|ajouter|verser|laisser|servir|assaisonner|préchauffer|faire|préparer|incorporer|pétrir|étaler|malaxer|saisir|griller|caraméliser|retourner|garnir|napper|finir|enrober|diluer|disposer|réchauffer|rouler|rabattre|cook|mix|heat|add|pour|serve|bake|fry|grill|roast|sauté|sear|whisk|stir|fold|knead|chop|dice|mince|slice|marinate|season|simmer|boil|blanch|broil|braise|deglaze|reduce|melt|beat|cream|blend|stuff|brush|drizzle|toss|layer|spread|wrap|roll|assemble|plate|garnish)\b/i;

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

      // Handle inline header: "Sauce: crème, moutarde, citron"
      const inlineContent = line.replace(/^[A-Za-zÀ-ÿ\s'']+[:：]\s*/, "").trim();
      if (inlineContent) {
        // Split inline content as comma-separated ingredients
        const parts = inlineContent.split(/[,;]/).map((p) => p.trim()).filter(Boolean);
        for (const part of parts) {
          currentSection.ingredients.push(
            parseIngredientFromLine(part, sectionLabel)
          );
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
    const isIngredient = looksLikeIngredientLine(line);
    const isStep = looksLikeStepLine(line);

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

function parseIngredientFromLine(line: string, group: string): RecipeIngredientDraft {
  let cleaned = line
    .replace(/^[-•*]\s+/, "")
    .replace(/^\d+[.)]\s+/, "")
    .trim();

  // Extract amount and unit from prefix
  let amount = "";
  let unit = "";

  // Pattern: "200g", "200 g", "3", "1/2"
  const amountUnitMatch = cleaned.match(
    /^(\d+(?:[.,/]\d+)?|[¼½¾⅓⅔⅛])\s*(g|kg|mg|ml|cl|dl|l|c\.\s*à\s*(?:s|c)|cas|cac|cuillères?\s*à\s*(?:soupe|café)|pincée|sachet|tranche|gousse|tasse|oz|lb|tbsp|tsp|cup)?\s*(?:de\s+|d['']\s*)?/i
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

function extractTitle(lines: string[]): string {
  // First non-empty line that doesn't look like an ingredient, step, or section header
  for (const line of lines.slice(0, 5)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (looksLikeIngredientLine(trimmed)) continue;
    if (looksLikeStepLine(trimmed)) continue;
    if (/^(?:ingrédients?|ingredients?|étapes?|steps?|instructions?)\s*[:：]?\s*$/i.test(trimmed)) continue;
    if (matchSectionHeader(trimmed, lines.slice(1))) continue;

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

    // Only enrich if the secondary is clearly structured and we're missing data
    const secondaryIsStrong =
      secondary.parsed.rawIngredientCount >= 4 && secondary.parsed.rawStepCount >= 2;
    if (!secondaryIsStrong) continue;

    // Fill missing steps (only if primary has very few)
    if (enriched.rawStepCount < 2) {
      enriched = fillMissingSteps(enriched, secondary.parsed);
    }

    // Fill missing ingredients (only in the default section, conservative)
    if (enriched.rawIngredientCount < 3) {
      enriched = fillMissingIngredients(enriched, secondary.parsed);
    }
  }

  return enriched;
}

function fillMissingSteps(primary: ParsedRecipe, secondary: ParsedRecipe): ParsedRecipe {
  // Only fill if primary has < 2 steps
  if (primary.rawStepCount >= 2) return primary;

  // Find sections in secondary that have steps
  const newSections = primary.sections.map((s) => ({ ...s }));
  if (newSections.length === 0) {
    newSections.push({ name: "", ingredients: [], steps: [] });
  }

  // Add steps from secondary to the last section
  const lastSection = newSections[newSections.length - 1];
  for (const secSection of secondary.sections) {
    for (const step of secSection.steps) {
      // Avoid duplicating existing steps
      const isDupe = lastSection.steps.some(
        (existing) => normalizeForComparison(existing.detail) === normalizeForComparison(step.detail)
      );
      if (!isDupe) {
        lastSection.steps.push({ ...step });
      }
    }
  }

  let totalSteps = 0;
  for (const s of newSections) totalSteps += s.steps.length;

  return { ...primary, sections: newSections, rawStepCount: totalSteps };
}

function fillMissingIngredients(primary: ParsedRecipe, secondary: ParsedRecipe): ParsedRecipe {
  if (primary.rawIngredientCount >= 3) return primary;

  const newSections = primary.sections.map((s) => ({ ...s, ingredients: [...s.ingredients] }));
  if (newSections.length === 0) {
    newSections.push({ name: "", ingredients: [], steps: [] });
  }

  const existingNames = new Set(
    newSections.flatMap((s) => s.ingredients.map((i) => normalizeForComparison(i.name)))
  );

  const targetSection = newSections[0]; // Add to first/default section
  for (const secSection of secondary.sections) {
    for (const ingredient of secSection.ingredients) {
      const key = normalizeForComparison(ingredient.name);
      if (key && !existingNames.has(key)) {
        targetSection.ingredients.push({ ...ingredient, group: targetSection.name });
        existingNames.add(key);
      }
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

function collectCaptionText(input: NormalizerInput): string {
  const parts = [
    input.socialCaption,
    input.sharedText,
    input.socialDescription,
    input.socialSubtitles,
  ]
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

  return parts.join("\n\n");
}
