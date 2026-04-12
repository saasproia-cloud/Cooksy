import {
  hasSuspiciousRecipeTitle,
  importMissingParts,
  isLikelyMajorIngredient,
  minimumStepCountForRecipeTitle,
  normalizeLookup,
  recipeCookabilitySignals,
  type RecipeImportResult,
} from "../types/recipe.js";

// =====================================================================
// Strict recipe validator.
//
// Single source of truth for "is this recipe shippable?". The checks
// themselves mostly reuse existing helpers in types/recipe.ts; the
// value of this module is that it (a) produces a structured list of
// issues with machine-readable repair hints, (b) separates HARD issues
// (must repair) from SOFT issues (annotate flags), and (c) exposes a
// prompt formatter for the LLM repair pass.
// =====================================================================

export type StrictIssueCode =
  | "TITLE_GENERIC"
  | "TITLE_DRIFTED_FROM_DIGEST"
  | "INGREDIENTS_TOO_FEW"
  | "INGREDIENT_VAGUE"
  | "STEPS_TOO_FEW"
  | "STEP_FRAGMENT_NOISE"
  | "INGREDIENT_NOT_USED_IN_STEPS"
  | "STEP_REFERENCES_MISSING_INGREDIENT"
  | "NUTRITION_INCOMPLETE"
  | "SIGNATURE_GESTURE_MISSING";

export interface StrictIssue {
  code: StrictIssueCode;
  severity: "hard" | "soft";
  message: string;
  repairHint: string;
  offenders?: string[];
}

export interface StrictValidationContext {
  signatureGestures?: string[];
  digestDish?: string;
  digestExplicitIngredients?: string[];
  minimumSteps?: number;
}

export interface StrictValidationReport {
  ok: boolean;
  hardIssues: StrictIssue[];
  softIssues: StrictIssue[];
}

// ---------------------------------------------------------------------
// Noise patterns for step content. Intentionally narrow — must not fire
// on real cooking lines. Each pattern represents an obvious social-media
// artifact (CTA, hashtag, timestamp, URL fragment).
// ---------------------------------------------------------------------

const STEP_NOISE_PATTERNS: RegExp[] = [
  /\babonne[-\s]?toi\b/i,
  /\babonnez[-\s]?vous\b/i,
  /\blien\s+en\s+bio\b/i,
  /\blink\s+in\s+bio\b/i,
  /\bfollow\s+me\b/i,
  /\bsubscribe\b/i,
  /\bbon\s+app(?:étit)?\b/i,
  /\bà\s+vous\s+de\s+jouer\b/i,
  /#\w+/,
  /\bhttps?:\/\//i,
  /@[\p{L}\p{N}._-]{2,}/u,
  /\s-->\s/,
  /\b\d{1,2}:\d{2}\b(?!\s*(?:min|minute|heure|hour))/,
];

// ---------------------------------------------------------------------
// Bare category words that, standalone, are too vague to cook with.
// Qualified forms (sauce soja, fromage frais, pain burger) are fine
// and must never trigger this check.
// ---------------------------------------------------------------------

const BARE_VAGUE_CATEGORIES = new Set([
  "fromage",
  "viande",
  "sauce",
  "pain",
  "legumes",
  "legume",
  "poisson",
  "feculent",
  "feculents",
  "epice",
  "epices",
]);

function countTokens(value: string): number {
  return normalizeLookup(value).split(/\s+/).filter(Boolean).length;
}

function ingredientMatchTokens(name: string): string[] {
  const normalized = normalizeLookup(name);
  return normalized
    .split(/[\s,/-]+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 4);
}

function stepText(recipe: RecipeImportResult): string {
  return normalizeLookup(recipe.stepDrafts.map((step) => step.detail).join(" "));
}

function ingredientIsUsedInSteps(
  ingredientName: string,
  allStepText: string
): boolean {
  const tokens = ingredientMatchTokens(ingredientName);
  if (!tokens.length) return true; // nothing specific to match; don't penalize
  return tokens.some((token) => allStepText.includes(token));
}

function stepReferencesUnknownIngredients(
  step: string,
  knownTokens: Set<string>
): string[] {
  const normalized = normalizeLookup(step);
  const offenders: string[] = [];

  const CANDIDATE_NOUNS = [
    "provolone", "mozzarella", "parmesan", "pecorino", "ricotta", "feta",
    "burrata", "cheddar", "gruyere", "emmental", "halloumi", "mascarpone",
    "ribeye", "entrecote", "bavette", "guanciale", "pancetta", "chorizo",
    "gochujang", "sriracha", "harissa", "miso", "tahini", "panko",
    "wasabi", "kimchi", "yuzu", "togarashi", "tamarin",
  ];

  for (const noun of CANDIDATE_NOUNS) {
    if (normalized.includes(noun) && !knownTokens.has(noun)) {
      offenders.push(noun);
    }
  }

  return offenders;
}

// ---------------------------------------------------------------------
// Main entry — validateStrictRecipe
// ---------------------------------------------------------------------

export function validateStrictRecipe(
  recipe: RecipeImportResult,
  ctx: StrictValidationContext = {}
): StrictValidationReport {
  const hardIssues: StrictIssue[] = [];
  const softIssues: StrictIssue[] = [];

  // --- Title ---
  if (hasSuspiciousRecipeTitle(recipe.title)) {
    hardIssues.push({
      code: "TITLE_GENERIC",
      severity: "hard",
      message: `Titre trop générique ou bruité: "${recipe.title}".`,
      repairHint:
        "Rends le titre spécifique en te basant sur le plat détecté (ex: 'Philly Cheesesteak' au lieu de 'Sandwich').",
    });
  }

  if (ctx.digestDish && recipe.title) {
    const digestKey = normalizeLookup(ctx.digestDish);
    const titleKey = normalizeLookup(recipe.title);
    if (digestKey && titleKey && !titleKey.includes(digestKey) && !digestKey.includes(titleKey)) {
      softIssues.push({
        code: "TITLE_DRIFTED_FROM_DIGEST",
        severity: "soft",
        message: `Le titre "${recipe.title}" diverge du plat détecté "${ctx.digestDish}".`,
        repairHint: `Vérifie que le titre reflète bien le plat "${ctx.digestDish}".`,
      });
    }
  }

  // --- Counts ---
  const minSteps = ctx.minimumSteps ?? minimumStepCountForRecipeTitle(recipe.title);
  const missing = importMissingParts(recipe);
  if (missing.includes("ingredients")) {
    hardIssues.push({
      code: "INGREDIENTS_TOO_FEW",
      severity: "hard",
      message: "Liste d'ingrédients trop courte pour un plat cuisinable.",
      repairHint:
        "Complète la liste d'ingrédients avec ceux nécessaires au plat détecté, en gardant les noms spécifiques (provolone, ribeye, panko...).",
    });
  }
  if (missing.includes("steps") || recipe.stepDrafts.length < minSteps) {
    hardIssues.push({
      code: "STEPS_TOO_FEW",
      severity: "hard",
      message: `Il manque des étapes: ${recipe.stepDrafts.length}/${minSteps} minimum.`,
      repairHint: `Ajoute des étapes détaillées pour atteindre au moins ${minSteps} étapes, en couvrant préparation → cuisson → dressage.`,
    });
  }

  // --- Vague ingredients ---
  const vagueOffenders: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    const key = normalizeLookup(ingredient.name);
    if (!key) continue;
    if (countTokens(ingredient.name) >= 2) continue; // qualified = specific
    if (BARE_VAGUE_CATEGORIES.has(key)) {
      vagueOffenders.push(ingredient.name);
    }
  }
  if (vagueOffenders.length) {
    softIssues.push({
      code: "INGREDIENT_VAGUE",
      severity: "soft",
      message: `Ingrédients trop vagues: ${vagueOffenders.join(", ")}.`,
      repairHint:
        "Précise chaque ingrédient vague (ex: 'fromage' → 'provolone' ou 'cheddar', 'viande' → 'bœuf haché').",
      offenders: vagueOffenders,
    });
  }

  // --- Ingredient coverage in steps ---
  const allStepText = stepText(recipe);
  const unusedIngredients: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    if (!isLikelyMajorIngredient(ingredient.name)) continue;
    if (!ingredientIsUsedInSteps(ingredient.name, allStepText)) {
      unusedIngredients.push(ingredient.name);
    }
  }
  if (unusedIngredients.length > 0) {
    hardIssues.push({
      code: "INGREDIENT_NOT_USED_IN_STEPS",
      severity: "hard",
      message: `Ingrédients non référencés dans les étapes: ${unusedIngredients.join(", ")}.`,
      repairHint: `Chaque ingrédient principal doit apparaître nommément dans au moins une étape. Ajoute-les aux étapes existantes ou supprime-les de la liste s'ils ne servent pas.`,
      offenders: unusedIngredients,
    });
  }

  // --- Steps referencing unknown ingredients ---
  const knownTokens = new Set<string>();
  for (const ingredient of recipe.ingredientDrafts) {
    for (const token of ingredientMatchTokens(ingredient.name)) {
      knownTokens.add(token);
    }
  }
  const unknownStepOffenders = new Set<string>();
  for (const step of recipe.stepDrafts) {
    for (const offender of stepReferencesUnknownIngredients(step.detail, knownTokens)) {
      unknownStepOffenders.add(offender);
    }
  }
  if (unknownStepOffenders.size > 0) {
    const offenders = Array.from(unknownStepOffenders);
    hardIssues.push({
      code: "STEP_REFERENCES_MISSING_INGREDIENT",
      severity: "hard",
      message: `Étapes mentionnent des ingrédients absents de la liste: ${offenders.join(", ")}.`,
      repairHint: `Ajoute ces ingrédients à ingredientDrafts avec une quantité réaliste, ou reformule les étapes pour les retirer.`,
      offenders,
    });
  }

  // --- Noise in steps ---
  const noisyStepIndexes: string[] = [];
  recipe.stepDrafts.forEach((step, idx) => {
    if (STEP_NOISE_PATTERNS.some((pattern) => pattern.test(step.detail))) {
      noisyStepIndexes.push(`#${idx + 1}`);
    }
  });
  if (noisyStepIndexes.length > 0) {
    hardIssues.push({
      code: "STEP_FRAGMENT_NOISE",
      severity: "hard",
      message: `Fragments sociaux/bruit détectés dans les étapes ${noisyStepIndexes.join(", ")}.`,
      repairHint:
        "Supprime les hashtags, CTA ('abonne-toi', 'lien en bio'), URLs, mentions @ et timestamps des étapes. Garde uniquement les instructions de cuisine.",
      offenders: noisyStepIndexes,
    });
  }

  // --- Nutrition ---
  const nutritionMissing = [
    !recipe.caloriesText && "calories",
    !recipe.proteinText && "protéines",
    !recipe.carbsText && "glucides",
    !recipe.fatText && "lipides",
  ].filter(Boolean) as string[];
  if (nutritionMissing.length > 0) {
    hardIssues.push({
      code: "NUTRITION_INCOMPLETE",
      severity: "hard",
      message: `Nutrition incomplète: ${nutritionMissing.join(", ")} manquant.`,
      repairHint:
        "Estime calories, protéines, glucides et lipides par portion à partir des ingrédients finaux. Ne laisse jamais ces champs vides pour une recette alimentaire.",
    });
  }

  // --- Signature gestures ---
  if (ctx.signatureGestures?.length) {
    const missingGestures = ctx.signatureGestures.filter((gesture) => {
      const gestureKey = normalizeLookup(gesture);
      if (!gestureKey) return false;
      return !allStepText.includes(gestureKey.split(" ")[0] ?? gestureKey);
    });
    if (missingGestures.length > 0) {
      softIssues.push({
        code: "SIGNATURE_GESTURE_MISSING",
        severity: "soft",
        message: `Gestes signature manquants: ${missingGestures.join("; ")}.`,
        repairHint: `Intègre ces gestes distinctifs comme étapes explicites: ${missingGestures.join("; ")}.`,
        offenders: missingGestures,
      });
    }
  }

  return {
    ok: hardIssues.length === 0,
    hardIssues,
    softIssues,
  };
}

// ---------------------------------------------------------------------
// Prompt formatter for the LLM repair pass.
// ---------------------------------------------------------------------

export function summarizeIssuesForRepairPrompt(issues: StrictIssue[]): string {
  if (!issues.length) return "";
  return issues
    .map((issue, idx) => {
      const offenders = issue.offenders?.length
        ? ` [offenders: ${issue.offenders.join(", ")}]`
        : "";
      return `${idx + 1}. ${issue.code} — ${issue.message}${offenders}\n   → ${issue.repairHint}`;
    })
    .join("\n");
}
