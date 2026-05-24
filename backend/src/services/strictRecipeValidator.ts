import {
  hasSuspiciousRecipeTitle,
  importMissingParts,
  isLikelyMajorIngredient,
  minimumStepCountForRecipeTitle,
  normalizeLookup,
  recipeCookabilitySignals,
  type RecipeImportResult,
} from "../types/recipe.js";
import { containsFoodSignal } from "./foodTermGate.js";
import { isProtectedIngredient } from "./sourceFusion.js";

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
  | "TITLE_INCOHERENT_WITH_INGREDIENTS"
  | "INGREDIENTS_TOO_FEW"
  | "INGREDIENT_VAGUE"
  | "INGREDIENT_UNIT_SWAP"
  | "INGREDIENT_INCOHERENT_WITH_DISH"
  | "QUANTITY_IMPLAUSIBLE"
  | "IMPLAUSIBLE_QUANTITY"
  | "SPECIFICITY_REDUCED"
  | "SECTION_LOST"
  | "STEPS_TOO_FEW"
  | "STEP_FRAGMENT_NOISE"
  | "INGREDIENT_NOT_USED_IN_STEPS"
  | "STEP_REFERENCES_MISSING_INGREDIENT"
  | "NUTRITION_INCOMPLETE"
  | "SIGNATURE_GESTURE_MISSING"
  | "NON_FOOD_INGREDIENT"
  | "SECTION_INGREDIENT_MISMATCH"
  | "DUPLICATE_CROSS_SECTION";

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
  /** If the input had sections, pass the count here for SECTION_LOST detection */
  inputSectionCount?: number;
  /** Original ingredient names from primary source for SPECIFICITY_REDUCED detection */
  originalIngredientNames?: string[];
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

// ---------------------------------------------------------------------
// Dish ↔ ingredient coherence tables.
//
// Two complementary tables wired into the strict validator:
//
//  - DISH_SIGNATURE_INGREDIENTS: if the title matches a known dish, the
//    recipe should contain at least one of the listed signature
//    ingredients. Missing signatures = the title is probably wrong (e.g.
//    title says "crêpes" but ingredients have no flour/eggs/milk → likely
//    titled wrong from heuristics).
//
//  - DISH_FORBIDDEN_INGREDIENTS: ingredients that should never appear in
//    the matched dish (e.g. "chou" in a "tacos" recipe). When matched, the
//    LLM probably hallucinated.
// ---------------------------------------------------------------------

const DISH_SIGNATURE_INGREDIENTS: ReadonlyArray<{
  pattern: RegExp;
  signatures: ReadonlyArray<string>;
  label: string;
}> = [
  { pattern: /\bcrepes?\b/i, signatures: ["farine", "oeufs", "œufs", "lait"], label: "crêpes" },
  { pattern: /\bpancakes?\b/i, signatures: ["farine", "oeufs", "œufs", "lait", "levure"], label: "pancakes" },
  { pattern: /\bgaufres?\b/i, signatures: ["farine", "oeufs", "œufs", "lait", "levure"], label: "gaufres" },
  { pattern: /\bcarbonara\b/i, signatures: ["pates", "pâtes", "spaghetti", "rigatoni", "linguine", "guanciale", "pancetta", "lardons", "oeufs", "œufs"], label: "carbonara" },
  { pattern: /\blasagnes?\b/i, signatures: ["lasagne", "viande", "boeuf", "bœuf", "bechamel", "béchamel", "tomate"], label: "lasagnes" },
  { pattern: /\btacos?\b/i, signatures: ["tortilla", "viande", "poulet", "boeuf", "bœuf", "porc"], label: "tacos" },
  { pattern: /\bquesadillas?\b/i, signatures: ["tortilla", "fromage", "cheddar", "mozzarella"], label: "quesadilla" },
  { pattern: /\bburger\b/i, signatures: ["pain", "bun", "viande", "boeuf", "bœuf", "poulet", "fromage"], label: "burger" },
  { pattern: /\btiramisu\b/i, signatures: ["mascarpone", "biscuits", "cafe", "café", "oeufs", "œufs"], label: "tiramisu" },
  { pattern: /\bcheesecake\b/i, signatures: ["fromage", "philadelphia", "mascarpone", "ricotta", "biscuits", "beurre"], label: "cheesecake" },
  { pattern: /\brisotto\b/i, signatures: ["riz", "arborio", "bouillon", "parmesan"], label: "risotto" },
  { pattern: /\bquiche\b/i, signatures: ["pate", "pâte", "oeufs", "œufs", "creme", "crème", "lait"], label: "quiche" },
];

const DISH_FORBIDDEN_INGREDIENTS: ReadonlyArray<{
  pattern: RegExp;
  forbidden: ReadonlyArray<string>;
  label: string;
}> = [
  { pattern: /\btacos?\b/i, forbidden: ["chou", "choucroute", "endive"], label: "tacos" },
  { pattern: /\bcarbonara\b/i, forbidden: ["creme", "crème", "lait"], label: "carbonara" },
  { pattern: /\bpizza\b/i, forbidden: ["pates", "pâtes", "riz"], label: "pizza" },
  { pattern: /\bcrepes?\b/i, forbidden: ["riz", "boulgour", "quinoa"], label: "crêpes" },
  { pattern: /\btiramisu\b/i, forbidden: ["viande", "poulet", "boeuf", "bœuf", "porc"], label: "tiramisu" },
];

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

const CANDIDATE_NOUNS: ReadonlyArray<{ pattern: RegExp; label: string; synonyms: ReadonlyArray<string> }> = [
  // Cheeses and dairy
  { pattern: /\bprovolone\b/, label: "provolone", synonyms: ["provolone"] },
  { pattern: /\bmozzarella\b/, label: "mozzarella", synonyms: ["mozzarella"] },
  { pattern: /\bparmesan\b/, label: "parmesan", synonyms: ["parmesan", "parmigiano"] },
  { pattern: /\bpecorino\b/, label: "pecorino", synonyms: ["pecorino"] },
  { pattern: /\bricotta\b/, label: "ricotta", synonyms: ["ricotta"] },
  { pattern: /\bfeta\b/, label: "feta", synonyms: ["feta"] },
  { pattern: /\bburrata\b/, label: "burrata", synonyms: ["burrata"] },
  { pattern: /\bcheddar\b/, label: "cheddar", synonyms: ["cheddar"] },
  { pattern: /\bgruyere\b/, label: "gruyere", synonyms: ["gruyere", "gruyère"] },
  { pattern: /\bemmental\b/, label: "emmental", synonyms: ["emmental"] },
  { pattern: /\bhalloumi\b/, label: "halloumi", synonyms: ["halloumi"] },
  { pattern: /\bmascarpone\b/, label: "mascarpone", synonyms: ["mascarpone"] },
  { pattern: /\bfromages?\b/, label: "fromage", synonyms: ["fromage", "cheese", "cheddar", "mozzarella", "parmesan", "feta", "gruyere", "provolone", "mascarpone"] },
  { pattern: /\byaourts?\b/, label: "yaourt", synonyms: ["yaourt", "yogurt", "fromage blanc"] },
  { pattern: /\bcremes?\b/, label: "crème", synonyms: ["creme", "crème", "cream"] },
  { pattern: /\blaits?\b/, label: "lait", synonyms: ["lait", "milk"] },
  { pattern: /\bbeurres?\b/, label: "beurre", synonyms: ["beurre", "butter"] },
  { pattern: /\boeufs?\b/, label: "œufs", synonyms: ["oeuf", "œuf", "egg"] },

  // Meats and fish
  { pattern: /\bribeye\b/, label: "ribeye", synonyms: ["ribeye"] },
  { pattern: /\bentrecote\b/, label: "entrecôte", synonyms: ["entrecote", "entrecôte"] },
  { pattern: /\bbavette\b/, label: "bavette", synonyms: ["bavette"] },
  { pattern: /\bguanciale\b/, label: "guanciale", synonyms: ["guanciale"] },
  { pattern: /\bpancetta\b/, label: "pancetta", synonyms: ["pancetta"] },
  { pattern: /\bchorizo\b/, label: "chorizo", synonyms: ["chorizo"] },
  { pattern: /\bpoulets?\b/, label: "poulet", synonyms: ["poulet", "chicken"] },
  { pattern: /\bboeufs?\b/, label: "bœuf", synonyms: ["boeuf", "bœuf", "beef", "steak hache", "ground beef"] },
  { pattern: /\bsteaks?\b/, label: "steak", synonyms: ["steak", "bavette", "entrecote", "ribeye"] },
  { pattern: /\bporcs?\b/, label: "porc", synonyms: ["porc", "pork"] },
  { pattern: /\blards?\b/, label: "lard", synonyms: ["lard", "bacon", "pancetta", "guanciale"] },
  { pattern: /\bagneaux?\b/, label: "agneau", synonyms: ["agneau", "lamb"] },
  { pattern: /\bdindes?\b/, label: "dinde", synonyms: ["dinde", "turkey"] },
  { pattern: /\bcanards?\b/, label: "canard", synonyms: ["canard", "duck"] },
  { pattern: /\bsaumons?\b/, label: "saumon", synonyms: ["saumon", "salmon"] },
  { pattern: /\bthons?\b/, label: "thon", synonyms: ["thon", "tuna"] },
  { pattern: /\bcabillauds?\b/, label: "cabillaud", synonyms: ["cabillaud", "cod"] },
  { pattern: /\bcrevettes?\b/, label: "crevettes", synonyms: ["crevette", "shrimp", "prawn"] },
  { pattern: /\bmoules\b/, label: "moules", synonyms: ["moule", "mussel"] },

  // Starches and grains
  { pattern: /\bp[aâ]tes?\b/, label: "pâtes", synonyms: ["pate", "pâte", "pasta", "spaghetti", "penne", "tagliatelle", "linguine", "fusilli", "rigatoni", "macaroni", "ravioli", "gnocchi", "lasagne"] },
  { pattern: /\bspaghettis?\b/, label: "spaghetti", synonyms: ["spaghetti"] },
  { pattern: /\bpennes?\b/, label: "penne", synonyms: ["penne"] },
  { pattern: /\btagliatelles?\b/, label: "tagliatelle", synonyms: ["tagliatelle"] },
  { pattern: /\briz\b/, label: "riz", synonyms: ["riz", "rice", "arborio", "basmati"] },
  { pattern: /\bquinoa\b/, label: "quinoa", synonyms: ["quinoa"] },
  { pattern: /\bboulgour\b/, label: "boulgour", synonyms: ["boulgour", "bulgur"] },
  { pattern: /\bsemoule\b/, label: "semoule", synonyms: ["semoule", "couscous"] },
  { pattern: /\bcouscous\b/, label: "couscous", synonyms: ["couscous", "semoule"] },
  { pattern: /\bfarines?\b/, label: "farine", synonyms: ["farine", "flour"] },
  { pattern: /\bsucres?\b/, label: "sucre", synonyms: ["sucre", "sugar"] },

  // Alliums and vegetables
  { pattern: /\bails?\b/, label: "ail", synonyms: ["ail", "garlic"] },
  { pattern: /\boignons?\b/, label: "oignon", synonyms: ["oignon", "onion"] },
  { pattern: /\bechalotes?\b/, label: "échalote", synonyms: ["echalote", "échalote", "shallot"] },
  { pattern: /\btomates?\b/, label: "tomate", synonyms: ["tomate", "tomato"] },
  { pattern: /\bcarottes?\b/, label: "carotte", synonyms: ["carotte", "carrot"] },
  { pattern: /\bcourgettes?\b/, label: "courgette", synonyms: ["courgette", "zucchini"] },
  { pattern: /\baubergines?\b/, label: "aubergine", synonyms: ["aubergine", "eggplant"] },
  { pattern: /\bpoivrons?\b/, label: "poivron", synonyms: ["poivron", "pepper", "bell pepper", "capsicum"] },
  { pattern: /\bchampignons?\b/, label: "champignon", synonyms: ["champignon", "mushroom"] },
  { pattern: /\bepinards\b/, label: "épinards", synonyms: ["epinard", "épinard", "spinach"] },
  { pattern: /\bpatates?\b/, label: "patate", synonyms: ["patate", "pomme de terre", "potato"] },

  // Sweet / aroma
  { pattern: /\bchocolats?\b/, label: "chocolat", synonyms: ["chocolat", "chocolate", "cacao", "cocoa"] },
  { pattern: /\bvanilles?\b/, label: "vanille", synonyms: ["vanille", "vanilla"] },
  { pattern: /\bmiels?\b/, label: "miel", synonyms: ["miel", "honey"] },
  { pattern: /\bcitrons?\b/, label: "citron", synonyms: ["citron", "lemon"] },
  { pattern: /\boranges?\b/, label: "orange", synonyms: ["orange"] },

  // Other exotic
  { pattern: /\bgochujang\b/, label: "gochujang", synonyms: ["gochujang"] },
  { pattern: /\bsriracha\b/, label: "sriracha", synonyms: ["sriracha"] },
  { pattern: /\bharissa\b/, label: "harissa", synonyms: ["harissa"] },
  { pattern: /\bmiso\b/, label: "miso", synonyms: ["miso"] },
  { pattern: /\btahini\b/, label: "tahini", synonyms: ["tahini"] },
  { pattern: /\bpanko\b/, label: "panko", synonyms: ["panko"] },
  { pattern: /\bwasabi\b/, label: "wasabi", synonyms: ["wasabi"] },
  { pattern: /\bkimchi\b/, label: "kimchi", synonyms: ["kimchi"] },
];

function foldLigatures(value: string): string {
  return value.replace(/œ/gi, "oe").replace(/æ/gi, "ae");
}

function stepReferencesUnknownIngredients(
  step: string,
  ingredientBlob: string
): string[] {
  const normalized = normalizeLookup(foldLigatures(step));
  const offenders: string[] = [];

  for (const entry of CANDIDATE_NOUNS) {
    if (!entry.pattern.test(normalized)) {
      continue;
    }
    const hasMatch = entry.synonyms.some((synonym) =>
      ingredientBlob.includes(normalizeLookup(synonym))
    );
    if (!hasMatch) {
      offenders.push(entry.label);
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

  // --- Title ↔ ingredient coherence ---
  // Title says "crêpes" but no flour/eggs/milk anywhere → title is wrong.
  if (recipe.title) {
    const ingredientBlobLower = normalizeLookup(
      foldLigatures(recipe.ingredientDrafts.map((i) => i.name ?? "").join(" "))
    );
    for (const entry of DISH_SIGNATURE_INGREDIENTS) {
      if (!entry.pattern.test(recipe.title)) continue;
      const hasAnySignature = entry.signatures.some((sig) =>
        ingredientBlobLower.includes(normalizeLookup(sig))
      );
      if (!hasAnySignature) {
        hardIssues.push({
          code: "TITLE_INCOHERENT_WITH_INGREDIENTS",
          severity: "hard",
          message: `Le titre "${recipe.title}" évoque "${entry.label}" mais aucun ingrédient signature (${entry.signatures.slice(0, 4).join(", ")}…) n'est présent.`,
          repairHint: `Soit reprends le titre depuis le digest DISH ou les ingrédients dominants, soit ajoute les ingrédients signature attendus pour "${entry.label}".`,
        });
        break;
      }
    }
  }

  // --- Ingredient ↔ dish coherence (hallucination guard) ---
  // Title says "tacos" but ingredients include "chou" → likely hallucinated.
  if (recipe.title) {
    const incoherentOffenders: string[] = [];
    for (const dish of DISH_FORBIDDEN_INGREDIENTS) {
      if (!dish.pattern.test(recipe.title)) continue;
      for (const ing of recipe.ingredientDrafts) {
        const key = normalizeLookup(ing.name ?? "");
        if (!key) continue;
        if (countTokens(ing.name) >= 2) continue; // qualified names are usually fine
        if (dish.forbidden.some((f) => normalizeLookup(f) === key)) {
          incoherentOffenders.push(ing.name);
        }
      }
    }
    if (incoherentOffenders.length > 0) {
      hardIssues.push({
        code: "INGREDIENT_INCOHERENT_WITH_DISH",
        severity: "hard",
        message: `Ingrédients incohérents avec le plat "${recipe.title}": ${incoherentOffenders.join(", ")}.`,
        repairHint: "Vérifie le digest et le contexte vidéo : ces ingrédients ressemblent à une hallucination. Supprime-les ou remplace-les par les ingrédients réellement présents.",
        offenders: incoherentOffenders,
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

  // --- Ingredient coverage in steps (L4 coherence — Round 5 plan §5.1) ---
  // CONTRAINTE 3 : protected ingredients (sel/poivre/huile/garniture/sauce/
  // topping/assaisonnement/herbes/épices/pour servir…) are NEVER flagged
  // here, even if no step mentions them — the creator's intent is implicit
  // in the name itself. Additionally, ingredients sitting inside an
  // explicit named section are kept (the section header IS the intent).
  const allStepText = stepText(recipe);
  const unusedIngredients: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    if (!isLikelyMajorIngredient(ingredient.name)) continue;
    if (isProtectedIngredient(ingredient.name)) continue;
    const insideNamedSection = Boolean((ingredient.group ?? "").trim());
    if (insideNamedSection) continue;
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
  const ingredientBlob = normalizeLookup(
    foldLigatures(recipe.ingredientDrafts.map((ingredient) => ingredient.name ?? "").join(" | "))
  );
  const unknownStepOffenders = new Set<string>();
  for (const step of recipe.stepDrafts) {
    for (const offender of stepReferencesUnknownIngredients(step.detail, ingredientBlob)) {
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

  // --- Unit/name swap detection ---
  const unitSwapOffenders: string[] = [];
  const UNIT_FRAGMENTS_IN_NAME = /^(?:à\s+(?:soupe|café)|cuillère|cuilleres?|c\.\s*à\s*(?:s|c)|cas|cac|grammes?|gramme|pincée|pincees?|sachet|tablespoon|teaspoon|tbsp|tsp|cup)\b/i;
  const LEADING_NUMBER_IN_NAME = /^\d+(?:[.,]\d+)?(?:\s|$)/;
  const ORPHAN_ARTICLE_PREFIX = /^(?:de\s+la\s|du\s|d['’])/i;
  const PURE_QUANTITY = /^\d+(?:[.,]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|oz|lb)?$/i;
  for (const ingredient of recipe.ingredientDrafts) {
    const name = ingredient.name.trim();
    if (!name) continue;
    if (
      UNIT_FRAGMENTS_IN_NAME.test(name) ||
      LEADING_NUMBER_IN_NAME.test(name) ||
      ORPHAN_ARTICLE_PREFIX.test(name) ||
      PURE_QUANTITY.test(name)
    ) {
      unitSwapOffenders.push(ingredient.name);
    }
  }
  if (unitSwapOffenders.length > 0) {
    hardIssues.push({
      code: "INGREDIENT_UNIT_SWAP",
      severity: "hard",
      message: `Unité/quantité détectée dans le nom d'ingrédient: ${unitSwapOffenders.join(", ")}.`,
      repairHint: "Déplace l'unité/quantité dans les champs amount/unit et garde uniquement le nom de l'ingrédient dans name. Retire les préfixes 'de la', 'du', 'd''.",
      offenders: unitSwapOffenders,
    });
  }

  // --- Non-food ingredient (hard, plan §9) ---
  const nonFoodOffenders: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    const name = ingredient.name?.trim();
    if (!name) continue;
    if (!containsFoodSignal(name)) {
      nonFoodOffenders.push(name);
    }
  }
  if (nonFoodOffenders.length > 0) {
    hardIssues.push({
      code: "NON_FOOD_INGREDIENT",
      severity: "hard",
      message: `Ingrédients non alimentaires détectés: ${nonFoodOffenders.join(", ")}.`,
      repairHint: "Supprime les entrées qui ne sont pas des aliments (logiciels, marques non-alimentaires, CTAs, descriptions du créateur).",
      offenders: nonFoodOffenders,
    });
  }

  // --- Implausible quantity (hard, plan §9) ---
  // Amount > 20 AND unit is empty AND name is a singular common ingredient.
  const implausibleQuantityOffenders: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    const amount = parseFloat((ingredient.amount ?? "").replace(",", "."));
    if (!Number.isFinite(amount) || amount <= 20) continue;
    const unit = (ingredient.unit ?? "").trim();
    if (unit.length > 0) continue;
    const tokenCount = (ingredient.name ?? "").trim().split(/\s+/).filter(Boolean).length;
    if (tokenCount === 0 || tokenCount > 2) continue;
    implausibleQuantityOffenders.push(`${ingredient.amount} ${ingredient.name}`.trim());
  }
  if (implausibleQuantityOffenders.length > 0) {
    hardIssues.push({
      code: "IMPLAUSIBLE_QUANTITY",
      severity: "hard",
      message: `Quantités invraisemblables (nombre sans unité sur ingrédient singulier): ${implausibleQuantityOffenders.join(", ")}.`,
      repairHint: "Supprime la quantité ou ajoute une unité correcte. Exemple: '30 salade' doit devenir '1 salade' ou 'salade' seule.",
      offenders: implausibleQuantityOffenders,
    });
  }

  // --- Quantity plausibility ---
  const implausibleOffenders: string[] = [];
  for (const ingredient of recipe.ingredientDrafts) {
    const amount = parseFloat((ingredient.amount ?? "").replace(",", "."));
    if (!Number.isFinite(amount) || amount <= 0) continue;
    const unitLow = (ingredient.unit ?? "").trim().toLowerCase();
    const hasMetricUnit = /^(?:g|kg|mg|ml|cl|dl|l|oz|lb|c\.|pincée|sachet|tasse)/.test(unitLow);
    // Unitless counts > 30 are suspicious for any ingredient
    if (!hasMetricUnit && amount > 30) {
      implausibleOffenders.push(`${ingredient.amount} ${ingredient.name}`);
    }
    // Metric sanity: > 5kg or > 5l is suspicious
    if (/^(?:kg|l)$/.test(unitLow) && amount > 5) {
      implausibleOffenders.push(`${ingredient.amount}${unitLow} ${ingredient.name}`);
    }
  }
  if (implausibleOffenders.length > 0) {
    softIssues.push({
      code: "QUANTITY_IMPLAUSIBLE",
      severity: "soft",
      message: `Quantités suspectes: ${implausibleOffenders.join(", ")}.`,
      repairHint: "Vérifie ces quantités. Préfère supprimer la quantité plutôt que garder une valeur incorrecte.",
      offenders: implausibleOffenders,
    });
  }

  // --- Section loss detection ---
  if (ctx.inputSectionCount && ctx.inputSectionCount >= 2) {
    const outputSections = new Set(
      recipe.ingredientDrafts
        .map((i) => (i.group ?? "").trim())
        .filter(Boolean)
    );
    const outputStepSections = new Set(
      recipe.stepDrafts
        .map((s) => (s.section ?? "").trim())
        .filter(Boolean)
    );
    const totalOutputSections = Math.max(outputSections.size, outputStepSections.size);
    if (totalOutputSections < 2) {
      hardIssues.push({
        code: "SECTION_LOST",
        severity: "hard",
        message: `L'entrée avait ${ctx.inputSectionCount} sections mais la sortie n'en a que ${totalOutputSections}.`,
        repairHint: "Restaure les sections (group/section) perdues. Les sous-préparations distinctes doivent être préservées.",
      });
    }
  }

  // --- Cross-section duplicate ingredient (soft, plan §9) ---
  // Same normalized ingredient appearing in multiple sections with the same
  // quantity/unit is almost always an enrichment bug. Different quantities
  // are legitimate (e.g. "oignon" in both marinade and garniture).
  const ingredientGroupMap = new Map<string, Array<{ group: string; amount: string; unit: string }>>();
  for (const ing of recipe.ingredientDrafts) {
    const key = normalizeLookup(ing.name ?? "");
    if (!key) continue;
    const group = (ing.group ?? "").trim();
    const amount = (ing.amount ?? "").trim();
    const unit = (ing.unit ?? "").trim();
    const bucket = ingredientGroupMap.get(key) ?? [];
    bucket.push({ group, amount, unit });
    ingredientGroupMap.set(key, bucket);
  }
  const crossSectionOffenders: string[] = [];
  for (const [name, entries] of ingredientGroupMap) {
    if (entries.length < 2) continue;
    const distinctGroups = new Set(entries.map((e) => e.group).filter(Boolean));
    if (distinctGroups.size < 2) continue;
    const signatures = new Set(entries.map((e) => `${e.amount}|${e.unit}`));
    if (signatures.size === 1) {
      crossSectionOffenders.push(name);
    }
  }
  if (crossSectionOffenders.length > 0) {
    softIssues.push({
      code: "DUPLICATE_CROSS_SECTION",
      severity: "soft",
      message: `Ingrédient dupliqué à l'identique dans plusieurs sections: ${crossSectionOffenders.join(", ")}.`,
      repairHint: "Soit fusionne les sections, soit ajuste la quantité pour différencier l'usage (sections multiples avec la même quantité = souvent un bug d'enrichissement).",
      offenders: crossSectionOffenders,
    });
  }

  // --- Section/ingredient mismatch (soft, plan §9) ---
  // For each named section with ≥ 2 ingredients, at least one ingredient
  // should be referenced by that section's steps. Otherwise the section is
  // probably detached from the cooking narrative.
  const sectionIngredientOffenders: string[] = [];
  const sectionsByName = new Map<string, { ingredients: string[]; stepsText: string[] }>();
  for (const ing of recipe.ingredientDrafts) {
    const group = (ing.group ?? "").trim();
    if (!group) continue;
    const entry = sectionsByName.get(group) ?? { ingredients: [], stepsText: [] };
    entry.ingredients.push(normalizeLookup(ing.name ?? ""));
    sectionsByName.set(group, entry);
  }
  for (const step of recipe.stepDrafts) {
    const section = (step.section ?? "").trim();
    if (!section) continue;
    const entry = sectionsByName.get(section) ?? { ingredients: [], stepsText: [] };
    entry.stepsText.push(normalizeLookup(step.detail ?? ""));
    sectionsByName.set(section, entry);
  }
  for (const [sectionName, entry] of sectionsByName) {
    if (entry.ingredients.length < 2 || entry.stepsText.length === 0) continue;
    const joinedSteps = entry.stepsText.join(" ");
    const anyReferenced = entry.ingredients.some((ing) => {
      if (!ing) return false;
      const head = ing.split(/\s+/)[0];
      return head.length >= 3 && joinedSteps.includes(head);
    });
    if (!anyReferenced) {
      sectionIngredientOffenders.push(sectionName);
    }
  }
  if (sectionIngredientOffenders.length > 0) {
    softIssues.push({
      code: "SECTION_INGREDIENT_MISMATCH",
      severity: "soft",
      message: `Sections dont les ingrédients ne sont référencés dans aucune étape: ${sectionIngredientOffenders.join(", ")}.`,
      repairHint: "Ajoute une étape qui utilise explicitement au moins un ingrédient de la section, ou retire la section si elle n'apporte rien à la préparation.",
      offenders: sectionIngredientOffenders,
    });
  }

  // --- Specificity reduction detection ---
  if (ctx.originalIngredientNames?.length) {
    const reducedOffenders: string[] = [];
    for (const original of ctx.originalIngredientNames) {
      const origTokens = normalizeLookup(original).split(/\s+/).filter(Boolean);
      if (origTokens.length < 2) continue; // Single-word ingredients can't be reduced
      // Check if any current ingredient is a single-word generification of this multi-word original
      const wasReduced = recipe.ingredientDrafts.some((current) => {
        const currentTokens = normalizeLookup(current.name).split(/\s+/).filter(Boolean);
        if (currentTokens.length >= origTokens.length) return false;
        // The current name is shorter AND its tokens are a subset of the original
        return currentTokens.every((t) => origTokens.includes(t));
      });
      if (wasReduced) {
        reducedOffenders.push(original);
      }
    }
    if (reducedOffenders.length > 0) {
      softIssues.push({
        code: "SPECIFICITY_REDUCED",
        severity: "soft",
        message: `Ingrédients dont la spécificité a été réduite: ${reducedOffenders.join(", ")}.`,
        repairHint: "Garde le nom spécifique original (ex: 'provolone' pas 'fromage', 'ribeye' pas 'steak').",
        offenders: reducedOffenders,
      });
    }
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
