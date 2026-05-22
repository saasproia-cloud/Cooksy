// =====================================================================
// foodTermGate — dual-gate filter for ingredient-candidate lines.
//
// A candidate line is accepted as a plausible ingredient ONLY IF it
// passes BOTH gates:
//
//   Gate A (shape):   the line has an ingredient-like structural shape
//                     (bullet/quantity prefix, or short non-narrative
//                     non-title non-CTA form). This rejects branded
//                     product names ("Kiri Studio Pro Edition"),
//                     article-like titles ("The best cheesecake in
//                     Paris"), imperative cooking prose, and social
//                     CTAs even when they contain a food token.
//
//   Gate B (food):    the line contains at least one known food token
//                     (from the synonym table, the all-ingredients
//                     catalog, or the extra pantry/international
//                     allowlist). This rejects non-food short lines
//                     ("PC", "Photo editor", "AI videos for Mac")
//                     even when they match the bullet shape.
//
// Acceptance = Gate A AND Gate B. Either gate alone is insufficient.
// =====================================================================

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  INGREDIENT_SYNONYM_TABLE,
  canonicalizeIngredientKey,
} from "./ingredientNormalization.js";

// ---------------------------------------------------------------------
// Food-token allowlist.
//
// Seeded from three sources, then frozen at module load:
//   1. Synonym-table keys (canonical form, hundreds of FR entries).
//   2. all-ingredients.json catalog (550+ entries at repo root).
//   3. Static seed list below — core pantry, international, and
//      brand food names that may not appear in the catalog.
//
// Multi-word keys are also split into individual tokens so that a line
// containing just "poulet" or "provolone" still triggers. The whole
// multi-word key is kept too, so "blanc de poulet" and other compound
// forms are matched when tokenized back.
// ---------------------------------------------------------------------

const EXTRA_FOOD_SEED: ReadonlyArray<string> = [
  // Core FR pantry
  "oeuf", "oeufs", "lait", "beurre", "fromage", "yaourt", "creme",
  "farine", "sucre", "sel", "poivre", "huile", "vinaigre", "moutarde",
  "eau", "glace", "miel", "chocolat", "cacao", "levure", "vanille",
  "cannelle", "gingembre", "ail", "oignon", "persil", "basilic",
  "ciboulette", "coriandre", "menthe", "thym", "laurier", "romarin",
  "safran", "cumin", "curry", "curcuma", "paprika", "piment",

  // Proteins
  "poulet", "dinde", "canard", "lapin", "veau", "agneau", "porc",
  "boeuf", "bœuf", "steak", "entrecote", "ribeye", "bavette",
  "filet", "rumsteck", "tournedos", "cote", "cotelette", "escalope",
  "hache", "haches", "hachee", "hachees", "saucisse", "saucisson",
  "chorizo", "jambon", "bacon", "lardons", "guanciale", "pancetta",
  "pastrami", "charcuterie",

  // Fish & seafood
  "poisson", "saumon", "thon", "cabillaud", "morue", "bar", "dorade",
  "truite", "sardine", "sardines", "anchois", "maquereau", "lieu",
  "merlu", "crevette", "crevettes", "moule", "moules", "coquille",
  "coquilles", "homard", "langouste", "calamar", "calamars",
  "poulpe", "encornet", "pétoncle", "saint-jacques",

  // Cheeses
  "mozzarella", "provolone", "cheddar", "feta", "parmesan", "pecorino",
  "emmental", "gruyere", "gruyère", "comte", "comté", "brie",
  "camembert", "roquefort", "bleu", "chevre", "chèvre", "ricotta",
  "mascarpone", "burrata", "halloumi", "manchego", "gouda", "edam",
  "reblochon", "raclette", "kiri", "boursin", "philadelphia",
  "stracciatella",

  // Vegetables
  "tomate", "tomates", "concombre", "carotte", "carottes", "courgette",
  "courgettes", "aubergine", "aubergines", "poivron", "poivrons",
  "salade", "laitue", "roquette", "epinard", "epinards", "chou",
  "brocoli", "chou-fleur", "artichaut", "asperge", "asperges",
  "poireau", "poireaux", "celeri", "céleri", "navet", "navets",
  "radis", "betterave", "potiron", "courge", "butternut", "citrouille",
  "mais", "maïs", "haricot", "haricots", "petits-pois", "pois",
  "lentille", "lentilles", "pois chiche", "pois-chiches", "avocat",
  "champignon", "champignons", "echalote", "échalote", "gousse",

  // Fruits
  "pomme", "pommes", "poire", "poires", "banane", "bananes", "orange",
  "oranges", "citron", "citrons", "lime", "pamplemousse", "fraise",
  "fraises", "framboise", "framboises", "myrtille", "myrtilles",
  "cerise", "cerises", "raisin", "raisins", "peche", "pêche",
  "abricot", "abricots", "prune", "prunes", "kiwi", "mangue",
  "ananas", "figue", "figues", "datte", "dattes", "noix", "amande",
  "amandes", "noisette", "noisettes", "cacahuete", "cacahuètes",
  "pistache", "pistaches", "pignon", "pignons",

  // Grains / starches
  "riz", "pate", "pâtes", "pates", "pasta", "spaghetti", "penne",
  "fusilli", "farfalle", "tagliatelle", "linguine", "rigatoni",
  "ravioli", "gnocchi", "lasagne", "macaroni", "nouilles", "nouille",
  "semoule", "couscous", "boulgour", "quinoa", "orge", "avoine",
  "ble", "blé", "mais", "polenta", "tapioca", "panko", "chapelure",
  "pomme de terre", "patate", "patates", "frite", "frites",

  // Breads
  "pain", "baguette", "brioche", "ciabatta", "focaccia", "pita",
  "naan", "tortilla", "wrap", "bagel", "hoagie", "bun", "buns",
  "muffin", "pancake", "crêpe", "crepe", "gaufre",

  // Sauces / condiments / international
  "sauce", "ketchup", "mayonnaise", "mayo", "bbq", "soja", "teriyaki",
  "sriracha", "tabasco", "harissa", "gochujang", "miso", "tahini",
  "hummus", "houmous", "wasabi", "kimchi", "sauerkraut", "pesto",
  "aioli", "tzatziki",

  // Sugars / syrups / misc sweet
  "sirop", "erable", "érable", "confiture", "gelee", "gelée",
  "cassonade", "nutella", "praline", "meringue", "ganache",
  "chantilly", "creme-fraiche",

  // Fats / oils
  "olive", "tournesol", "colza", "arachide", "sesame", "sésame",
  "coco", "noisette", "noix",

  // Drinks (used in recipes)
  "vin", "biere", "bière", "cidre", "rhum", "cognac", "whisky",
  "porto", "madere", "bouillon", "fond", "fumet",

  // English common tokens (EN recipes)
  "egg", "eggs", "milk", "butter", "cream", "cheese", "flour",
  "sugar", "salt", "pepper", "oil", "vinegar", "honey", "syrup",
  "chicken", "beef", "pork", "lamb", "turkey", "duck", "bacon",
  "ham", "sausage", "fish", "salmon", "tuna", "shrimp", "prawn",
  "lobster", "scallop", "crab", "tomato", "onion", "garlic", "ginger",
  "carrot", "celery", "cucumber", "lettuce", "spinach", "kale",
  "broccoli", "cauliflower", "pepper", "potato", "rice", "pasta",
  "noodle", "noodles", "bread", "flour", "dough", "yeast", "apple",
  "banana", "orange", "lemon", "lime", "berry", "berries", "strawberry",
  "raspberry", "blueberry", "cherry", "grape", "peach", "plum",
  "pineapple", "mango", "avocado", "mushroom", "mushrooms", "zucchini",
  "eggplant", "corn", "bean", "beans", "chickpea", "chickpeas",
  "lentil", "lentils", "quinoa", "oats", "oatmeal", "almond", "walnut",
  "pistachio", "peanut", "hazelnut", "pecan", "cashew", "soy", "tofu",
  "tempeh", "miso", "kimchi", "seaweed", "nori", "sesame", "olive",

  // Baking & leavening agents (EN + FR) — these are legitimate recipe
  // ingredients that were missing from the seed, causing lines like
  // "1 tbsp baking powder" or "¼ cup water" to fail the food gate.
  "water", "baking", "powder", "soda", "bicarbonate", "cornstarch",
  "cornflour", "starch", "fecule", "fécule", "maizena", "gelatin",
  "gelatine", "gelatine", "shortening", "lard", "ghee", "margarine",
  "buttermilk", "babeurre", "creme-fraiche", "sourdough", "levain",
  "seasoning", "assaisonnement", "stock", "broth", "bouillon-cube",
  "molasses", "melasse", "mélasse", "treacle", "cornmeal", "semolina",
  "breadcrumb", "breadcrumbs", "crouton", "croutons", "cornflakes",
  "panko", "graham", "biscuit", "biscuits", "speculoos", "spéculoos",
  "marshmallow", "guimauve", "caramel", "fudge", "praline", "nougat",
  "oregano", "origan", "cayenne", "rosemary", "sage", "sauge",
  "dill", "aneth", "tarragon", "estragon", "chive", "chives",
  "nutmeg", "muscade", "clove", "cloves", "girofle", "cardamom",
  "cardamome", "allspice", "fennel", "fenouil", "anise", "anis",
  "turmeric", "coriander", "cilantro", "parsley", "basil", "thyme",
  "mint", "bayleaf", "worcestershire", "mirin", "dashi", "fishsauce",
];

// ---------------------------------------------------------------------
// Connector tokens — excluded from single-token food lookup because they
// are grammatical glue, not food signals on their own.
// ---------------------------------------------------------------------

const CONNECTOR_TOKENS: ReadonlySet<string> = new Set([
  "de", "du", "des", "le", "la", "les", "un", "une", "au", "aux",
  "a", "à", "et", "ou", "d", "l", "ce", "cette", "en", "dans",
  "pour", "avec", "sans", "sur", "sous", "par",
  "of", "the", "and", "or", "with", "for", "in", "on", "at", "to",
]);

const FOOD_TOKEN_SET: ReadonlySet<string> = (() => {
  const set = new Set<string>();

  const add = (raw: string) => {
    const key = canonicalizeIngredientKey(raw);
    if (!key) return;
    set.add(key);
    // Also index individual non-connector tokens so a line can match on
    // any meaningful sub-token of a compound entry.
    for (const tok of key.split(" ")) {
      if (tok && !CONNECTOR_TOKENS.has(tok) && tok.length >= 2) {
        set.add(tok);
      }
    }
  };

  // 1. Synonym-table keys + values.
  for (const [key, value] of INGREDIENT_SYNONYM_TABLE) {
    add(key);
    add(value);
  }

  // 2. Catalog entries (best-effort — failures fall back gracefully).
  try {
    const catalogEntries = loadCatalogNamesDefensive();
    for (const name of catalogEntries) {
      add(name);
    }
  } catch {
    // Swallow — allowlist remains usable from synonyms + seed.
  }

  // 3. Static seed.
  for (const term of EXTRA_FOOD_SEED) {
    add(term);
  }

  return set;
})();

// ---------------------------------------------------------------------
// Public: containsFoodSignal — Gate B primitive.
// ---------------------------------------------------------------------

// Try a token against the food set with progressive plural-strip
// fallbacks. Handles common FR/EN plural forms ("oignons" -> "oignon",
// "choux" -> "chou", "tomatoes" -> "tomato") without building a full
// lemmatizer.
function tokenMatchesFoodSet(token: string): boolean {
  if (token.length < 2) return false;
  if (FOOD_TOKEN_SET.has(token)) return true;

  // EN "-es" / "-ies" plurals
  if (token.length >= 4 && token.endsWith("ies")) {
    const candidate = token.slice(0, -3) + "y";
    if (FOOD_TOKEN_SET.has(candidate)) return true;
  }
  if (token.length >= 4 && token.endsWith("es")) {
    const candidate = token.slice(0, -2);
    if (FOOD_TOKEN_SET.has(candidate)) return true;
  }

  // FR/EN trailing "-s" plural
  if (token.length >= 3 && token.endsWith("s")) {
    const candidate = token.slice(0, -1);
    if (FOOD_TOKEN_SET.has(candidate)) return true;
  }

  // FR trailing "-x" plural (choux, poireaux, noyaux)
  if (token.length >= 3 && token.endsWith("x")) {
    const candidate = token.slice(0, -1);
    if (FOOD_TOKEN_SET.has(candidate)) return true;
    if (token.endsWith("eaux")) {
      const eal = token.slice(0, -4) + "eau";
      if (FOOD_TOKEN_SET.has(eal)) return true;
    }
  }

  return false;
}

export function containsFoodSignal(name: string): boolean {
  if (!name) return false;
  const key = canonicalizeIngredientKey(name);
  if (!key) return false;

  // Whole-string match (e.g. "blanc de poulet").
  if (FOOD_TOKEN_SET.has(key)) return true;

  // Token-level match — any meaningful sub-token (with plural fallback).
  const tokens = key.split(" ").filter(Boolean);
  for (const tok of tokens) {
    if (CONNECTOR_TOKENS.has(tok)) continue;
    if (tokenMatchesFoodSet(tok)) return true;
  }

  // Bigram / trigram match for compounds not split into bigrams at load.
  for (let i = 0; i < tokens.length - 1; i += 1) {
    const bi = `${tokens[i]} ${tokens[i + 1]}`;
    if (FOOD_TOKEN_SET.has(bi)) return true;
    if (i < tokens.length - 2) {
      const tri = `${bi} ${tokens[i + 2]}`;
      if (FOOD_TOKEN_SET.has(tri)) return true;
    }
  }

  // Structural hints — FR compound prefixes.
  if (/\b(?:blanc|filet|cuisse|cuisses|pav[eé]|escalope|sauce|jus|bouillon|fond)\s+(?:de|d['’ ]|du|des)\s+[a-zà-ÿ]+/i.test(name)) {
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------
// Public: foodSignalScore — rough 0..1 density of food tokens.
// ---------------------------------------------------------------------

export function foodSignalScore(text: string): number {
  if (!text) return 0;
  const key = canonicalizeIngredientKey(text);
  if (!key) return 0;

  const tokens = key.split(" ").filter(Boolean);
  if (tokens.length === 0) return 0;

  let foodHits = 0;
  let meaningfulTokens = 0;

  for (const tok of tokens) {
    if (CONNECTOR_TOKENS.has(tok)) continue;
    if (tok.length < 2) continue;
    meaningfulTokens += 1;
    if (tokenMatchesFoodSet(tok)) foodHits += 1;
  }

  if (meaningfulTokens === 0) return 0;
  return Math.min(1, foodHits / meaningfulTokens);
}

// ---------------------------------------------------------------------
// Gate A primitives.
// ---------------------------------------------------------------------

const BULLET_PREFIX_RE = /^\s*(?:[-–—*•·●◦▪■]+|\d+[.)])\s+/;
const LEADING_VULGAR_FRACTION_RE = /^\s*[¼½¾⅓⅔⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚⅐⅑⅒]\s+/;
const LEADING_QUANTITY_RE = /^\s*\d+(?:[.,]\d+)?(?:\s*\/\s*\d+)?(?:\s*[-–—]\s*\d+(?:[.,]\d+)?)?\s*[a-zà-ÿ%]{0,4}\s+/i;

// Cooking verbs at the START of the line (imperative) → narrative, not ingredient.
const LEADING_COOKING_VERB_RE = /^\s*(?:pr[eé]chauffez|pr[eé]chauffer|faites?|faire|cuisez|cuisinez|cuire|m[eé]langez|m[eé]langer|coupez|couper|[eé]mincez|[eé]mincer|ajoutez|ajouter|versez|verser|laissez|laisser|servez|servir|go[uû]tez|go[uû]ter|assaisonnez|assaisonner|chauffez|chauffer|battez|battre|fouettez|fouetter|hachez|hacher|r[eé]duisez|r[eé]duire|incorporez|incorporer|saupoudrez|saupoudrer|nappez|napper|d[eé]glacez|d[eé]glacer|saisissez|saisir|rissolez|rissoler|dorez|dorer|caram[eé]lisez|caram[eé]liser|mixez|mixer|mouillez|mouiller|arrosez|arroser|salez|saler|poivrez|poivrer|r[aâ]pez|r[aâ]per|garnissez|garnir|montez|monter|dressez|dresser|d[eé]corez|d[eé]corer|[eé]pluchez|[eé]plucher|lavez|laver|rincez|rincer|[eé]grainez|[eé]grainer|fondez|fondre|beurrez|beurrer|huilez|huiler|cover|prepare|cook|mix|heat|add|pour|serve|bake|fry|grill|roast|saute|sear|stir|chop|slice|dice|mince|preheat|place|put|set|bring|remove|transfer|combine|whisk|beat|fold)\b/i;

// Article / title structures that should never be ingredient lines.
const ARTICLE_TITLE_RE = /^\s*(?:the\s+best|the\s+top|the\s+ultimate|top\s+\d+|best\s+\d+|my\s+(?:favou?rite|best)|le\s+meilleur|la\s+meilleure|les\s+meilleur(?:e?s)?|mon\s+(?:meilleur|top)|ma\s+meilleure|top\s+\d+|les\s+\d+\s+meilleur)/i;

// Social CTAs, subscribe-bait, link-in-bio style fragments.
const SOCIAL_CTA_RE = /\b(?:abonne[- ]?toi|abonnez[- ]?vous|suis[- ]?moi|follow\s+me|subscribe|lien\s+en\s+bio|link\s+in\s+bio|check\s+my|regarde\s+ma|swipe\s+up)\b/i;

// Sentence-internal sentence-end punctuation → narrative prose, not a
// single ingredient line. Requires at least 2 lowercase letters before
// the punctuation so abbreviations like "c.", "1.", "à.", "mlle." are
// not mistaken for a sentence boundary. Also requires the next word to
// start with a letter/digit (not another punctuation run).
const INTERNAL_SENTENCE_END_RE = /[a-zà-ÿ]{2,}[.!?]\s+[A-ZÀ-Ý0-9\p{L}]/u;

// Product / brand pattern: ≥ 3 consecutive Title-Case words with no
// lowercase connector between them (e.g. "Kiri Studio Pro Edition",
// "Photo Editor Pro", "iPhone Pro Max Ultra"). Rejects even when one
// of the tokens is a food word.
const PRODUCT_NAME_RE = /(?:^|\s)(?:[A-ZÀ-Ý][\w'’-]+(?:\s+[A-ZÀ-Ý][\w'’-]+){2,})(?:\s|$)/;

// Known product/brand suffix markers.
const PRODUCT_SUFFIX_RE = /\b(?:pro|plus|max|ultra|edition|studio|app|version|vers?\.|v\d+|\d{2,4}k|premium|deluxe|lite|mini|for\s+mac|for\s+pc|ai\s+video|ai\s+videos)\b/i;

const MAX_SHAPE_TOKEN_COUNT = 10;

// ---------------------------------------------------------------------
// Public: hasPlausibleIngredientShape — Gate A primitive.
// ---------------------------------------------------------------------

export function hasPlausibleIngredientShape(line: string): boolean {
  if (!line) return false;
  const trimmed = line.replace(/\s+/g, " ").trim();
  if (!trimmed) return false;

  // Hard rejects regardless of prefix.
  if (SOCIAL_CTA_RE.test(trimmed)) return false;
  if (ARTICLE_TITLE_RE.test(trimmed)) return false;
  if (LEADING_COOKING_VERB_RE.test(trimmed)) return false;
  if (PRODUCT_SUFFIX_RE.test(trimmed)) return false;

  // Sentence-internal end-of-sentence punctuation → narrative.
  if (INTERNAL_SENTENCE_END_RE.test(trimmed)) return false;

  // Product-name-shape (3+ consecutive TitleCase words). Computed AFTER
  // the cooking-verb guard so "Faites revenir Les Oignons" is caught as
  // a cooking verb first.
  if (PRODUCT_NAME_RE.test(trimmed)) return false;

  // Positive shapes — any of these pass.
  if (BULLET_PREFIX_RE.test(trimmed)) return true;
  if (LEADING_VULGAR_FRACTION_RE.test(trimmed)) return true;
  if (LEADING_QUANTITY_RE.test(trimmed)) return true;

  // Short-form fallback: compact line that doesn't look like prose.
  const tokenCount = trimmed.split(/\s+/).filter(Boolean).length;
  if (tokenCount === 0) return false;
  if (tokenCount > MAX_SHAPE_TOKEN_COUNT) return false;

  // A line that is a full sentence (ends with . ! ?) is almost never a
  // standalone ingredient — but do allow a trailing "." after a single
  // very short form ("Sel.").
  if (/[.!?]$/.test(trimmed) && tokenCount > 2) return false;

  return true;
}

// ---------------------------------------------------------------------
// Public: passesDualGate — A AND B.
// ---------------------------------------------------------------------

export function passesDualGate(line: string): boolean {
  if (!line) return false;
  if (!hasPlausibleIngredientShape(line)) return false;
  if (!containsFoodSignal(line)) return false;
  return true;
}

// ---------------------------------------------------------------------
// Defensive catalog loader — mirrors the shape of ingredientNormalization
// but only pulls display names. Isolated here so a missing catalog does
// not break the gate.
// ---------------------------------------------------------------------

const CATALOG_RELATIVE_PATH = "images ingredients/all-ingredients.json";

function loadCatalogNamesDefensive(): string[] {
  const candidates: string[] = [];

  try {
    const here = fileURLToPath(import.meta.url);
    const backendRoot = path.resolve(path.dirname(here), "..", "..", "..");
    candidates.push(path.join(backendRoot, CATALOG_RELATIVE_PATH));
    candidates.push(path.join(backendRoot, "..", CATALOG_RELATIVE_PATH));
  } catch {
    // ignore
  }

  const cwd = process.cwd();
  candidates.push(path.join(cwd, CATALOG_RELATIVE_PATH));
  candidates.push(path.join(cwd, "..", CATALOG_RELATIVE_PATH));

  for (const candidate of candidates) {
    try {
      const raw = readFileSync(candidate, "utf-8");
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) continue;
      const names: string[] = [];
      for (const entry of parsed) {
        if (!entry || typeof entry !== "object") continue;
        const name = (entry as { name?: unknown }).name;
        if (typeof name === "string" && name.trim()) {
          names.push(name);
        }
      }
      if (names.length > 0) return names;
    } catch {
      continue;
    }
  }

  return [];
}

// Exposed for tests that want to inspect coverage.
export function __foodTokenSetSize(): number {
  return FOOD_TOKEN_SET.size;
}
