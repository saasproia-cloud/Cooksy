// =====================================================================
// sourceFusion — multi-source ingredient fusion + deterministic
// confidence scoring (Round 5 plan §4 + §4.3 + §4.6).
//
// Inputs : ingredient candidates extracted from caption, description,
//          audio digest, hashtags, and LLM inference.
// Output : a single deduplicated list of FusedIngredient with a
//          [0,1] confidence per item, plus a list of provenance tags.
//
// Hard constraints from the plan (CONTRAINTES 3 + 4) :
//   - Formula uses 4 terms, all calculable from static in-memory tables.
//     No network calls, no embeddings, no randomness.
//   - PROTECTED_INGREDIENTS (sel, poivre, huile, garniture, sauce,
//     topping, assaisonnement, herbes, épices, pour servir/déco/garniture)
//     are NEVER dropped, regardless of confidence.
//
// The formula (plan §4.3) :
//   ingredient_confidence =
//       0.40 * source_priority_score      // caption=1.0, description=0.85,
//                                         //   audio=0.65, hashtag=0.50,
//                                         //   inference=0.30
//     + 0.30 * agreement_score            // 1 source = 0.0, 2 = 0.6, 3+ = 1.0
//     + 0.20 * dish_coherence_score       // signature=1, neutre=0.6,
//                                         //   forbidden=-1, clamped [0,1]
//     + 0.10 * specificity_score          // generic=0.3, family=0.7,
//                                         //   specific=1.0 (default 0.7)
//
// Worked example (plan §4.4, also a unit test) :
//   caption : 2 eggs   →  weight 0.40
//   audio   : 4 eggs   →  weight 0.26
//   descr   : 4 eggs   →  weight 0.34
//   votes   : { "2": 0.40, "4": 0.60 }      → choose 4
//   confidence ≈ 0.97 (agreement of 2 sources + caption-grade priority)
//
// All public helpers are pure functions and 100 % unit-testable.
// =====================================================================

import type { RecipeIngredientDraft } from "../types/recipe.js";
import { canonicalizeIngredientKey } from "./ingredientNormalization.js";

// ---------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------

export type FusionSourceTag =
  | "caption"
  | "description"
  | "audio"
  | "hashtag"
  | "inference";

export interface FusionCandidate {
  draft: RecipeIngredientDraft;
  source: FusionSourceTag;
}

export interface FusionContext {
  /** The compiled recipe title, used for dish-coherence scoring. */
  dishTitle?: string;
}

export interface FusedIngredient {
  draft: RecipeIngredientDraft;
  /** Confidence in [0,1] computed by §4.3 formula. */
  confidence: number;
  /** Source tags that contributed at least one appearance. */
  provenance: FusionSourceTag[];
  /** True if the ingredient matches the PROTECTED_INGREDIENTS list. */
  isProtected: boolean;
}

export interface FusionResult {
  ingredients: FusedIngredient[];
  overallConfidence: number;
  droppedCount: number;
}

// ---------------------------------------------------------------------
// Static scoring tables (deterministic, no I/O)
// ---------------------------------------------------------------------

/** Per-source raw priority — plan §4.3. */
const SOURCE_PRIORITY: Record<FusionSourceTag, number> = {
  caption: 1.0,
  description: 0.85,
  audio: 0.65,
  hashtag: 0.5,
  inference: 0.3
};

/** Specificity tier table — used by §4.3 term 4. Default = 0.7 (family). */
const SPECIFICITY_TIER: Record<string, number> = {
  // ── Generic (0.3) ────────────────────────────────────
  viande: 0.3,
  fromage: 0.3,
  legume: 0.3,
  legumes: 0.3,
  poisson: 0.3,
  pain: 0.3,
  sauce: 0.3,
  epice: 0.3,
  epices: 0.3,
  feculents: 0.3,
  // ── Family (0.7) ─────────────────────────────────────
  poulet: 0.7,
  boeuf: 0.7,
  porc: 0.7,
  agneau: 0.7,
  saumon: 0.7,
  thon: 0.7,
  mozzarella: 0.7,
  parmesan: 0.7,
  cheddar: 0.7,
  emmental: 0.7,
  comte: 0.7,
  tomate: 0.7,
  tomates: 0.7,
  oignon: 0.7,
  oignons: 0.7,
  carotte: 0.7,
  carottes: 0.7,
  patates: 0.7,
  "pommes de terre": 0.7,
  riz: 0.7,
  pates: 0.7,
  farine: 0.7,
  // ── Specific (1.0) ───────────────────────────────────
  "blanc de poulet": 1.0,
  "blancs de poulet": 1.0,
  "cuisse de poulet": 1.0,
  "filet de poulet": 1.0,
  "pave de saumon": 1.0,
  ribeye: 1.0,
  "faux filet": 1.0,
  bavette: 1.0,
  entrecote: 1.0,
  guanciale: 1.0,
  pancetta: 1.0,
  lardons: 1.0,
  "lard fume": 1.0,
  provolone: 1.0,
  ricotta: 1.0,
  mascarpone: 1.0,
  burrata: 1.0,
  pecorino: 1.0,
  manchego: 1.0,
  feta: 1.0,
  rigatoni: 1.0,
  penne: 1.0,
  tagliatelle: 1.0,
  pappardelle: 1.0,
  farfalle: 1.0,
  orecchiette: 1.0,
  fusilli: 1.0,
  spaghetti: 1.0,
  linguine: 1.0,
  gochujang: 1.0,
  harissa: 1.0,
  miso: 1.0,
  "ras el hanout": 1.0,
  "garam masala": 1.0,
  "cajun seasoning": 1.0,
  "melange cajun": 1.0,
  panko: 1.0,
  chapelure: 1.0,
  // ── Protected basics treated as specific (1.0) so they never
  //    drag confidence down — the protection logic handles them
  //    separately, but in their own right they're cooking essentials.
  sel: 1.0,
  poivre: 1.0,
  huile: 1.0,
  "huile d olive": 1.0,
  beurre: 1.0,
  sucre: 1.0,
  eau: 1.0
};

/** Default tier when an ingredient is not in the table. */
const SPECIFICITY_DEFAULT = 0.7;

// ---------------------------------------------------------------------
// PROTECTED_INGREDIENTS (CONTRAINTE 3) — never drop, regardless of score
//
// Implementation uses diacritic-folded substring matching rather than
// regex \b boundaries because JS \b is ASCII-only and would miss
// uppercase-accent forms like "Épices" / "Décoration".
// ---------------------------------------------------------------------

const PROTECTED_KEYWORDS: readonly string[] = [
  "sel",
  "poivre",
  "huile",
  "garniture",
  "sauce",
  "topping",
  "assaisonnement",
  "herbe",            // herbes, herbe aromatique
  "epice",            // epices, mélange d'épices
  "pour servir",
  "pour la deco",     // pour la déco, pour la décoration
  "pour la garniture",
  "pour decorer"
];

function diacriticFold(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();
}

/** Returns true if the ingredient name should NEVER be dropped. */
export function isProtectedIngredient(name: string): boolean {
  if (!name) return false;
  const folded = diacriticFold(name);
  return PROTECTED_KEYWORDS.some((kw) => folded.includes(kw));
}

// ---------------------------------------------------------------------
// Confidence formula — deterministic, no I/O
// ---------------------------------------------------------------------

/** Source-priority term — plan §4.3 term 1. Returns [0,1]. */
export function sourcePriorityScore(sources: ReadonlyArray<FusionSourceTag>): number {
  if (sources.length === 0) return 0;
  // Pick the strongest source available (max), not the average — a single
  // caption mention should outweigh a noisy audio mention.
  let best = 0;
  for (const s of sources) {
    const score = SOURCE_PRIORITY[s] ?? 0;
    if (score > best) best = score;
  }
  return best;
}

/** Agreement term — plan §4.3 term 2. Returns [0,1]. */
export function agreementScore(sources: ReadonlyArray<FusionSourceTag>): number {
  // Distinct sources, not raw count — 3 caption mentions = 1 source.
  const distinct = new Set(sources).size;
  if (distinct <= 1) return 0;
  if (distinct === 2) return 0.6;
  return 1;
}

/**
 * Dish-coherence term — plan §4.3 term 3. Returns [0,1].
 *
 * Signature ingredients for the dish push toward 1.0; forbidden push toward
 * 0.0; neutral stays at the calibrated midpoint 0.6 (matching the formula's
 * "neutre=0.6" parameter so that the absence of a coherence signal does not
 * drag the score down).
 */
export function dishCoherenceScore(args: {
  canonicalName: string;
  dishTitle?: string;
}): number {
  const { canonicalName, dishTitle } = args;
  if (!dishTitle) return 0.6;
  // Fold accents on BOTH title and ingredient before regex testing — JS
  // \b is ASCII-only so "crêpes" wouldn't match /\bcrepes\b/ without
  // folding. Folding ensures the table works for any FR accent form.
  const title = diacriticFold(dishTitle);
  const name = diacriticFold(canonicalName);

  // Forbidden: name must NOT appear in this dish family.
  for (const [pattern, forbidden] of DISH_FORBIDDEN) {
    if (pattern.test(title) && forbidden.some((f) => name.includes(diacriticFold(f)))) {
      return 0; // forbidden → clamp to 0 (raw value would be -1)
    }
  }

  // Signature: at least one signature ingredient for this dish family.
  for (const [pattern, signatures] of DISH_SIGNATURES) {
    if (pattern.test(title) && signatures.some((s) => name.includes(diacriticFold(s)))) {
      return 1;
    }
  }

  return 0.6;
}

/** Specificity term — plan §4.3 term 4. Returns [0,1]. */
export function specificityScore(canonicalName: string): number {
  if (!canonicalName) return SPECIFICITY_DEFAULT;
  const key = canonicalName.trim().toLowerCase();
  const tier = SPECIFICITY_TIER[key];
  return tier !== undefined ? tier : SPECIFICITY_DEFAULT;
}

/**
 * Computes the full confidence score (plan §4.3 formula). All inputs are
 * static / in-memory; the same arguments always produce the same number.
 */
export function computeIngredientConfidence(args: {
  sources: ReadonlyArray<FusionSourceTag>;
  canonicalName: string;
  dishTitle?: string;
}): number {
  const sp = sourcePriorityScore(args.sources);
  const ag = agreementScore(args.sources);
  const dc = dishCoherenceScore({
    canonicalName: args.canonicalName,
    dishTitle: args.dishTitle
  });
  const sc = specificityScore(args.canonicalName);
  const raw = 0.4 * sp + 0.3 * ag + 0.2 * dc + 0.1 * sc;
  // Clamp [0,1] defensively. With current weights, the value cannot exceed
  // 1.0 nor fall below 0.0 in practice, but we guard for future tuning.
  if (raw < 0) return 0;
  if (raw > 1) return 1;
  // Round to 4 decimals for stable test snapshots.
  return Math.round(raw * 10_000) / 10_000;
}

// ---------------------------------------------------------------------
// Dish coherence tables (inlined — small enough to keep here, will move
// to a master DB in the Ultimate phase per plan §6).
// ---------------------------------------------------------------------

const DISH_SIGNATURES: ReadonlyArray<readonly [RegExp, ReadonlyArray<string>]> = [
  [/\bcrepes?\b/i, ["farine", "oeufs", "œufs", "lait"]],
  [/\bpancakes?\b/i, ["farine", "oeufs", "œufs", "lait", "levure"]],
  [/\bcarbonara\b/i, ["pates", "guanciale", "pancetta", "lardons", "oeufs", "parmesan"]],
  [/\bbolognaise\b|\bbolognese\b/i, ["boeuf hache", "tomate", "carotte", "oignon"]],
  [/\blasagne[s]?\b/i, ["lasagne", "viande hachee", "bechamel", "tomate"]],
  [/\btacos?\b/i, ["tortilla", "viande", "fromage"]],
  [/\bnaan\b/i, ["farine", "yaourt", "levure"]],
  [/\bpaella\b/i, ["riz", "safran", "poulet", "fruits de mer"]],
  [/\brisotto\b/i, ["riz", "bouillon", "parmesan"]],
  [/\bpizza\b/i, ["pate", "tomate", "mozzarella"]],
  [/\bramen\b/i, ["nouilles", "bouillon", "oeuf"]],
  [/\bsushi[s]?\b/i, ["riz", "poisson", "algue"]],
  [/\bcurry\b/i, ["epices", "lait de coco", "viande"]],
  [/\bbiryani\b/i, ["riz", "epices", "viande"]],
  [/\bfajitas?\b/i, ["tortilla", "poulet", "poivron", "oignon"]]
];

const DISH_FORBIDDEN: ReadonlyArray<readonly [RegExp, ReadonlyArray<string>]> = [
  [/\btacos?\b/i, ["chou", "choucroute"]],
  [/\bcarbonara\b/i, ["creme", "lait"]],
  [/\bpizza\b/i, ["pates"]],
  [/\bsushi[s]?\b/i, ["fromage"]]
];

// ---------------------------------------------------------------------
// Fusion engine
// ---------------------------------------------------------------------

/**
 * Default drop threshold (plan §4.6). An ingredient whose confidence is
 * strictly below this AND whose only provenance is "inference" gets
 * dropped — unless it is in PROTECTED_INGREDIENTS.
 */
export const DROP_CONFIDENCE_THRESHOLD = 0.3;

/**
 * Merges multi-source candidates into a single deduplicated list with
 * confidence scores. Ingredients are bucketed by canonicalKey of their
 * name — synonyms collapse, so "œufs" + "Oeufs" + "eggs" land together.
 */
export function fuseIngredientCandidates(
  candidates: ReadonlyArray<FusionCandidate>,
  context: FusionContext = {}
): FusionResult {
  // Bucket by canonical key.
  const buckets = new Map<
    string,
    {
      drafts: RecipeIngredientDraft[];
      sources: FusionSourceTag[];
    }
  >();
  const orderedKeys: string[] = [];

  for (const cand of candidates) {
    const rawName = cand.draft.name?.trim() ?? "";
    if (!rawName) continue;
    const key = canonicalizeIngredientKey(rawName);
    if (!key) continue;

    const bucket = buckets.get(key);
    if (!bucket) {
      buckets.set(key, { drafts: [cand.draft], sources: [cand.source] });
      orderedKeys.push(key);
    } else {
      bucket.drafts.push(cand.draft);
      bucket.sources.push(cand.source);
    }
  }

  let droppedCount = 0;
  const fused: FusedIngredient[] = [];

  for (const key of orderedKeys) {
    const bucket = buckets.get(key);
    if (!bucket) continue;

    const confidence = computeIngredientConfidence({
      sources: bucket.sources,
      canonicalName: key,
      dishTitle: context.dishTitle
    });
    const protectedFlag = isProtectedIngredient(bucket.drafts[0]?.name ?? "") ||
      isProtectedIngredient(key);

    // Conflict resolution: weighted vote per (quantity, unit). The weight
    // is each appearance's source priority. Ties → first occurrence wins
    // (preserves caption order under Caption-First).
    const resolved = resolveQuantityAndUnit(bucket.drafts, bucket.sources);

    // Drop low-confidence inference-only ingredients UNLESS protected.
    const onlyInference = bucket.sources.every((s) => s === "inference");
    if (
      confidence < DROP_CONFIDENCE_THRESHOLD &&
      onlyInference &&
      !protectedFlag
    ) {
      droppedCount += 1;
      continue;
    }

    fused.push({
      draft: resolved,
      confidence,
      provenance: Array.from(new Set(bucket.sources)),
      isProtected: protectedFlag
    });
  }

  const overallConfidence =
    fused.length === 0
      ? 0
      : Math.round(
          (fused.reduce((acc, f) => acc + f.confidence, 0) / fused.length) *
            10_000
        ) / 10_000;

  return { ingredients: fused, overallConfidence, droppedCount };
}

// ---------------------------------------------------------------------
// Quantity/unit conflict resolution (worked example: 2 eggs vs 4 eggs)
// ---------------------------------------------------------------------

/**
 * Picks the most-supported (quantity, unit) pair across the bucket using
 * a deterministic weighted vote. Returns the FIRST draft whose payload
 * matches the winning pair — so the returned object keeps original
 * display casing and `group`.
 */
function resolveQuantityAndUnit(
  drafts: ReadonlyArray<RecipeIngredientDraft>,
  sources: ReadonlyArray<FusionSourceTag>
): RecipeIngredientDraft {
  if (drafts.length === 1) return drafts[0]!;

  // Tally votes per (amount, unit) signature.
  const votes = new Map<string, number>();
  for (let i = 0; i < drafts.length; i += 1) {
    const draft = drafts[i]!;
    const src = sources[i] ?? "inference";
    const sig = `${(draft.amount ?? "").trim()}|${(draft.unit ?? "").trim()}`;
    const weight = SOURCE_PRIORITY[src] ?? 0;
    votes.set(sig, (votes.get(sig) ?? 0) + weight);
  }

  // Find the heaviest signature. Stable iteration order preserves caption-first
  // tie-breaking when weights are equal.
  let bestSig: string | null = null;
  let bestWeight = -1;
  for (const [sig, weight] of votes) {
    if (weight > bestWeight) {
      bestSig = sig;
      bestWeight = weight;
    }
  }

  // Pick the first draft that matches the winning signature.
  for (let i = 0; i < drafts.length; i += 1) {
    const draft = drafts[i]!;
    const sig = `${(draft.amount ?? "").trim()}|${(draft.unit ?? "").trim()}`;
    if (sig === bestSig) return draft;
  }
  return drafts[0]!;
}
