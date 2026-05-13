import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// =====================================================================
// Ingredient & unit normalization for the recipe-import pipeline.
//
// Two layers, FR-first, strictly non-generifying:
//   1. A hand-curated synonym table that cleans up casing/accents/plurals
//      of common spoken forms (e.g. "oeufs" -> "Œufs", "blanc de poulet"
//      -> "Blanc de poulet"). Keeps specific names intact (Provolone,
//      Ribeye, Panko, Gochujang). Never collapses a specific name into
//      a category word.
//   2. A defensive catalog cross-check against the existing
//      "images ingredients/all-ingredients.json" file shipped at the
//      repo root. If that file is missing or malformed, the module
//      gracefully falls back to synonym-map-only behavior; nothing in
//      the pipeline depends on the catalog being loadable.
// =====================================================================

export interface NormalizedIngredientName {
  displayName: string;      // canonical FR-cased display, e.g. "Œufs"
  canonicalKey: string;     // lowercase, unaccented, for dedupe lookups
  matchedCatalog: boolean;  // true if found in all-ingredients.json
  catalogImageSlug?: string;
}

interface CatalogEntry {
  displayName: string;
  imageSlug: string;
}

// ---------------------------------------------------------------------
// Canonicalization helper used for every key in both tables.
// ---------------------------------------------------------------------

export function canonicalizeIngredientKey(value: string): string {
  return value
    .toLocaleLowerCase("fr-FR")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/œ/g, "oe")
    .replace(/æ/g, "ae")
    .replace(/['’`]/g, " ")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// ---------------------------------------------------------------------
// Synonym table — raw canonical key -> canonical FR display name.
//
// Hard rules (enforced by the non-generification guard below):
//   - No value is a bare single-word category (fromage / viande / sauce
//     / pain / legumes / poisson). Qualified forms like "sauce soja",
//     "fromage frais", "pain burger" are fine because they are specific.
//   - Nothing in here collapses a specific ingredient to a less specific
//     one (provolone -> fromage is forbidden).
// ---------------------------------------------------------------------

const RAW_SYNONYMS: ReadonlyArray<readonly [string, string]> = [
  // Volailles
  ["blanc de poulet", "Blanc de poulet"],
  ["blancs de poulet", "Blancs de poulet"],
  ["filet de poulet", "Filet de poulet"],
  ["cuisse de poulet", "Cuisse de poulet"],
  ["cuisses de poulet", "Cuisses de poulet"],
  ["poulet", "Poulet"],
  ["dinde", "Dinde"],

  // Boeuf & porc
  ["steak hache", "Steak haché"],
  ["steaks haches", "Steaks hachés"],
  ["boeuf hache", "Boeuf haché"],
  ["bœuf hache", "Boeuf haché"],
  ["entrecote", "Entrecôte"],
  ["ribeye", "Ribeye"],
  ["faux filet", "Faux-filet"],
  ["bavette", "Bavette"],
  ["lard fume", "Lard fumé"],
  ["lardons", "Lardons"],
  ["guanciale", "Guanciale"],
  ["pancetta", "Pancetta"],

  // Poissons
  ["saumon", "Saumon"],
  ["pave de saumon", "Pavé de saumon"],
  ["thon", "Thon"],
  ["cabillaud", "Cabillaud"],
  ["crevettes", "Crevettes"],

  // Oeufs
  ["oeuf", "Oeuf"],
  ["oeufs", "Oeufs"],
  ["jaune d oeuf", "Jaune d'oeuf"],
  ["jaunes d oeufs", "Jaunes d'oeufs"],
  ["blanc d oeuf", "Blanc d'oeuf"],
  ["blancs d oeufs", "Blancs d'oeufs"],

  // Légumes
  ["tomate", "Tomate"],
  ["tomates", "Tomates"],
  ["tomate cerise", "Tomate cerise"],
  ["tomates cerises", "Tomates cerises"],
  ["oignon", "Oignon"],
  ["oignon rouge", "Oignon rouge"],
  ["oignon jaune", "Oignon jaune"],
  ["oignon nouveau", "Oignon nouveau"],
  ["echalote", "Échalote"],
  ["echalotes", "Échalotes"],
  ["ail", "Ail"],
  ["gousse d ail", "Gousse d'ail"],
  ["gousses d ail", "Gousses d'ail"],
  ["gingembre", "Gingembre"],
  ["gingembre frais", "Gingembre frais"],
  ["poivron rouge", "Poivron rouge"],
  ["poivron vert", "Poivron vert"],
  ["poivron jaune", "Poivron jaune"],
  ["courgette", "Courgette"],
  ["aubergine", "Aubergine"],
  ["champignons", "Champignons"],
  ["champignons de paris", "Champignons de Paris"],

  // Herbes
  ["persil", "Persil"],
  ["persil plat", "Persil plat"],
  ["coriandre", "Coriandre"],
  ["coriandre fraiche", "Coriandre fraîche"],
  ["basilic", "Basilic"],
  ["basilic frais", "Basilic frais"],
  ["ciboulette", "Ciboulette"],
  ["menthe", "Menthe"],
  ["thym", "Thym"],
  ["romarin", "Romarin"],
  ["laurier", "Laurier"],

  // Fromages (toujours spécifiques)
  ["provolone", "Provolone"],
  ["mozzarella", "Mozzarella"],
  ["mozzarella di bufala", "Mozzarella di bufala"],
  ["burrata", "Burrata"],
  ["parmesan", "Parmesan"],
  ["pecorino", "Pecorino"],
  ["pecorino romano", "Pecorino Romano"],
  ["cheddar", "Cheddar"],
  ["feta", "Feta"],
  ["emmental", "Emmental"],
  ["gruyere", "Gruyère"],
  ["comte", "Comté"],
  ["chevre frais", "Chèvre frais"],
  ["fromage frais", "Fromage frais"],
  ["mascarpone", "Mascarpone"],
  ["ricotta", "Ricotta"],
  ["halloumi", "Halloumi"],

  // Produits laitiers
  ["yaourt grec", "Yaourt grec"],
  ["yaourt nature", "Yaourt nature"],
  ["creme fraiche", "Crème fraîche"],
  ["creme liquide", "Crème liquide"],
  ["creme entiere", "Crème entière"],
  ["lait entier", "Lait entier"],
  ["lait demi ecreme", "Lait demi-écrémé"],
  ["beurre", "Beurre"],
  ["beurre demi sel", "Beurre demi-sel"],
  ["beurre doux", "Beurre doux"],

  // Céréales & féculents
  ["riz basmati", "Riz basmati"],
  ["riz thai", "Riz thaï"],
  ["riz complet", "Riz complet"],
  ["riz rond", "Riz rond"],
  ["pates", "Pâtes"],
  ["spaghetti", "Spaghetti"],
  ["tagliatelles", "Tagliatelles"],
  ["linguine", "Linguine"],
  ["penne", "Penne"],
  ["rigatoni", "Rigatoni"],
  ["pate a pizza", "Pâte à pizza"],
  ["pate brisee", "Pâte brisée"],
  ["pate feuilletee", "Pâte feuilletée"],
  ["pommes de terre", "Pommes de terre"],
  ["pomme de terre", "Pomme de terre"],
  ["farine", "Farine"],
  ["farine de ble", "Farine de blé"],
  ["semoule", "Semoule"],
  ["boulgour", "Boulgour"],
  ["quinoa", "Quinoa"],
  ["panko", "Panko"],
  ["chapelure", "Chapelure"],

  // Pains
  ["pain burger", "Pain burger"],
  ["pains burger", "Pains burger"],
  ["pain a hot dog", "Pain à hot-dog"],
  ["baguette", "Baguette"],
  ["pain complet", "Pain complet"],
  ["pain de mie", "Pain de mie"],
  ["pita", "Pita"],
  ["naan", "Naan"],
  ["tortilla", "Tortilla"],
  ["wrap", "Wrap"],

  // Sauces & condiments (toujours qualifiés)
  ["sauce soja", "Sauce soja"],
  ["sauce soja sucree", "Sauce soja sucrée"],
  ["sauce tomate", "Sauce tomate"],
  ["sauce piquante", "Sauce piquante"],
  ["sauce bbq", "Sauce BBQ"],
  ["ketchup", "Ketchup"],
  ["moutarde", "Moutarde"],
  ["moutarde de dijon", "Moutarde de Dijon"],
  ["mayonnaise", "Mayonnaise"],
  ["vinaigre balsamique", "Vinaigre balsamique"],
  ["vinaigre de cidre", "Vinaigre de cidre"],
  ["vinaigre de riz", "Vinaigre de riz"],
  ["huile d olive", "Huile d'olive"],
  ["huile de sesame", "Huile de sésame"],
  ["huile de tournesol", "Huile de tournesol"],
  ["huile de coco", "Huile de coco"],
  ["gochujang", "Gochujang"],
  ["sriracha", "Sriracha"],
  ["harissa", "Harissa"],
  ["miso", "Miso"],
  ["tahini", "Tahini"],

  // Assaisonnements
  ["sel", "Sel"],
  ["sel fin", "Sel fin"],
  ["fleur de sel", "Fleur de sel"],
  ["poivre noir", "Poivre noir"],
  ["poivre moulu", "Poivre moulu"],
  ["paprika", "Paprika"],
  ["paprika fume", "Paprika fumé"],
  ["cumin", "Cumin"],
  ["curcuma", "Curcuma"],
  ["curry", "Curry"],
  ["piment d espelette", "Piment d'Espelette"],

  // Sucres & sucrants
  ["sucre", "Sucre"],
  ["sucre en poudre", "Sucre en poudre"],
  ["sucre roux", "Sucre roux"],
  ["cassonade", "Cassonade"],
  ["miel", "Miel"],
  ["sirop d erable", "Sirop d'érable"],
];

const SYNONYM_TABLE: Map<string, string> = (() => {
  const map = new Map<string, string>();
  for (const [rawKey, display] of RAW_SYNONYMS) {
    map.set(canonicalizeIngredientKey(rawKey), display);
  }
  return map;
})();

export const INGREDIENT_SYNONYM_TABLE: ReadonlyMap<string, string> = SYNONYM_TABLE;

// ---------------------------------------------------------------------
// Non-generification guard.
//
// A synonym value is forbidden if, stripped of whitespace and lower-
// cased, it collapses to a BARE category word. Qualified forms like
// "sauce soja" or "fromage frais" are specific and allowed.
// ---------------------------------------------------------------------

const BARE_CATEGORY_BLOCKLIST = new Set([
  "fromage",
  "viande",
  "sauce",
  "pain",
  "legumes",
  "legume",
  "poisson",
  "feculent",
  "feculents",
  "huile",
  "epice",
  "epices",
]);

export function assertNoGenerification(
  table: ReadonlyMap<string, string> = SYNONYM_TABLE
): void {
  for (const [key, value] of table) {
    const canonicalValue = canonicalizeIngredientKey(value);
    if (BARE_CATEGORY_BLOCKLIST.has(canonicalValue)) {
      throw new Error(
        `[ingredientNormalization] Forbidden generification in synonym table: ${key} -> ${value}`
      );
    }
  }
}

// Run the guard at module load so mistakes fail fast in dev/test.
assertNoGenerification();

// ---------------------------------------------------------------------
// Defensive catalog loader — all-ingredients.json.
//
// The pipeline MUST never crash because the catalog file is missing or
// malformed. On any failure we log once and fall back to synonym-only
// behavior.
// ---------------------------------------------------------------------

type CatalogMap = Map<string, CatalogEntry>;

const CATALOG_RELATIVE_PATH = "images ingredients/all-ingredients.json";
let cachedCatalog: CatalogMap | null | undefined;
let catalogWarningLogged = false;

function resolveCatalogPath(): string | null {
  const candidates: string[] = [];

  try {
    const here = fileURLToPath(import.meta.url);
    const backendRoot = path.resolve(path.dirname(here), "..", "..", "..");
    candidates.push(path.join(backendRoot, CATALOG_RELATIVE_PATH));
    candidates.push(path.join(backendRoot, "..", CATALOG_RELATIVE_PATH));
  } catch {
    // fileURLToPath can fail in unusual runtimes — we just skip.
  }

  const cwd = process.cwd();
  candidates.push(path.join(cwd, CATALOG_RELATIVE_PATH));
  candidates.push(path.join(cwd, "..", CATALOG_RELATIVE_PATH));

  for (const candidate of candidates) {
    try {
      readFileSync(candidate); // existence probe
      return candidate;
    } catch {
      continue;
    }
  }

  return null;
}

function loadCatalog(): CatalogMap | null {
  if (cachedCatalog !== undefined) {
    return cachedCatalog;
  }

  const catalogPath = resolveCatalogPath();
  if (!catalogPath) {
    if (!catalogWarningLogged) {
      console.warn(
        "[ingredientNormalization] all-ingredients.json not found; falling back to synonym-map-only mode."
      );
      catalogWarningLogged = true;
    }
    cachedCatalog = null;
    return null;
  }

  try {
    const raw = readFileSync(catalogPath, "utf-8");
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      throw new Error("catalog is not an array");
    }

    const map: CatalogMap = new Map();
    for (const entry of parsed) {
      if (!entry || typeof entry !== "object") continue;
      const name = typeof (entry as { name?: unknown }).name === "string"
        ? ((entry as { name: string }).name)
        : null;
      const image = typeof (entry as { image?: unknown }).image === "string"
        ? ((entry as { image: string }).image)
        : "";
      if (!name || !name.trim()) continue;

      const key = canonicalizeIngredientKey(name);
      if (!key || map.has(key)) continue;

      map.set(key, {
        displayName: toDisplayCase(name),
        imageSlug: image.trim(),
      });
    }

    cachedCatalog = map;
    return map;
  } catch (err) {
    if (!catalogWarningLogged) {
      console.warn(
        `[ingredientNormalization] Failed to load all-ingredients.json: ${(err as Error).message}; falling back to synonym-map-only mode.`
      );
      catalogWarningLogged = true;
    }
    cachedCatalog = null;
    return null;
  }
}

function toDisplayCase(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return trimmed;
  return trimmed.charAt(0).toLocaleUpperCase("fr-FR") + trimmed.slice(1);
}

// ---------------------------------------------------------------------
// Public API — normalizeFrenchIngredientName
//
// 1. Try the synonym table (best curation, exact keyed).
// 2. Try the catalog (wider coverage, lowest quality bar).
//    SPECIFICITY GUARD: if the catalog match has FEWER tokens than the
//    raw input, we prefer the raw input — never collapse a specific
//    name into a less specific one.
// 3. Otherwise return the raw input, lightly cleaned, matchedCatalog=false.
// ---------------------------------------------------------------------

export function normalizeFrenchIngredientName(raw: string): NormalizedIngredientName {
  const cleaned = raw.replace(/\s+/g, " ").trim();
  if (!cleaned) {
    return { displayName: "", canonicalKey: "", matchedCatalog: false };
  }

  const key = canonicalizeIngredientKey(cleaned);
  if (!key) {
    return { displayName: cleaned, canonicalKey: "", matchedCatalog: false };
  }

  const synonymHit = SYNONYM_TABLE.get(key);
  if (synonymHit) {
    return {
      displayName: synonymHit,
      canonicalKey: canonicalizeIngredientKey(synonymHit),
      matchedCatalog: false,
    };
  }

  const catalog = loadCatalog();
  if (catalog) {
    const catalogHit = catalog.get(key);
    if (catalogHit) {
      const rawTokens = key.split(" ").filter(Boolean).length;
      const catalogTokens = canonicalizeIngredientKey(catalogHit.displayName)
        .split(" ")
        .filter(Boolean).length;
      if (catalogTokens >= rawTokens) {
        return {
          displayName: catalogHit.displayName,
          canonicalKey: canonicalizeIngredientKey(catalogHit.displayName),
          matchedCatalog: true,
          catalogImageSlug: catalogHit.imageSlug || undefined,
        };
      }
      // Catalog entry is less specific than input — keep raw.
    }
  }

  return {
    displayName: cleaned,
    canonicalKey: key,
    matchedCatalog: false,
  };
}

// ---------------------------------------------------------------------
// Unit normalization — fix common spoken / abbreviated French units
// without changing any unit that already looks proper.
// ---------------------------------------------------------------------

const UNIT_SYNONYMS: ReadonlyArray<readonly [RegExp, string]> = [
  [/^à\s+café$/i, "c. à café"],
  [/^a\s+cafe$/i, "c. à café"],
  [/^cuillere?\s+a\s+cafe$/i, "c. à café"],
  [/^cuillère?\s+à\s+café$/i, "c. à café"],
  [/^cc$/i, "c. à café"],
  [/^càc$/i, "c. à café"],
  [/^à\s+soupe$/i, "c. à soupe"],
  [/^a\s+soupe$/i, "c. à soupe"],
  [/^cuillere?\s+a\s+soupe$/i, "c. à soupe"],
  [/^cuillère?\s+à\s+soupe$/i, "c. à soupe"],
  [/^cs$/i, "c. à soupe"],
  [/^càs$/i, "c. à soupe"],
  [/^gr$/i, "g"],
  [/^gramme?s?$/i, "g"],
  [/^kilo$/i, "kg"],
  [/^kilos$/i, "kg"],
  [/^kilogrammes?$/i, "kg"],
  [/^litres?$/i, "l"],
  [/^millilitres?$/i, "ml"],
  [/^centilitres?$/i, "cl"],
];

export function normalizeFrenchUnit(raw: string): string {
  const trimmed = raw.replace(/\s+/g, " ").trim();
  if (!trimmed) return "";

  for (const [pattern, replacement] of UNIT_SYNONYMS) {
    if (pattern.test(trimmed)) {
      return replacement;
    }
  }

  // Lowercase common metric units when they appear alone.
  if (/^(?:g|kg|mg|ml|cl|dl|l|oz|lb|lbs)$/i.test(trimmed)) {
    return trimmed.toLowerCase();
  }

  return trimmed;
}

// ---------------------------------------------------------------------
// cleanIngredientNameField — universal ASR-artifact sanitizer for
// ingredient NAME fields. Handles the common pattern where a noisy
// Whisper transcript leaks unit or quantity tokens INTO the name field
// while leaving the unit/amount fields empty:
//
//   {name: "à soupe huile",   unit: ""}  ->  {name: "Huile", unit: "c. à soupe"}
//   {name: "300 g farine",    unit: ""}  ->  {name: "Farine", unit: "g", amount: "300"}
//   {name: "Oeufs Oeufs"}               ->  {name: "Œufs"}
//
// Also collapses same-word head duplications ("farine farine", "huile
// huile") and drops names that reduce to a bare unit word.
// ---------------------------------------------------------------------

export interface CleanedIngredientNameField {
  name: string;
  extractedUnit?: string;
  extractedAmount?: string;
  dropped?: boolean;
}

// Leading amount shapes: "300", "300,5", "1/2", vulgar fractions.
const LEADING_AMOUNT_RE = /^\s*(\d+(?:[.,]\d+)?(?:\s*\/\s*\d+)?|\d+\/\d+|[¼½¾⅓⅔⅛⅕⅖⅗⅘⅙⅚⅐⅑⅒])\s+/;

// Leading unit shapes that commonly leak into ASR name fields. Each
// entry maps a regex tested against the *start* of the lowercased,
// diacritic-folded working copy to a normalized unit label.
const NAME_LEADING_UNIT_PATTERNS: ReadonlyArray<readonly [RegExp, string]> = [
  [/^cuilleres?\s+a\s+soupe\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à soupe"],
  [/^cuilleres?\s+a\s+cafe\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à café"],
  [/^c\.?\s*a\.?\s*s\.?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à soupe"],
  [/^c\.?\s*a\.?\s*c\.?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à café"],
  // Short forms without "à": `c.s`, `c.c`, `c s`, `c c`. Common on
  // TikTok captions (e.g. "2 c.s de sauce soja sucrée").
  [/^c\.?\s*s\.?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à soupe"],
  [/^c\.?\s*c\.?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à café"],
  [/^cas\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à soupe"],
  [/^cac\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à café"],
  [/^a\s+soupe\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à soupe"],
  [/^a\s+cafe\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "c. à café"],
  [/^tablespoons?\b\s*(?:of\s+)?/, "c. à soupe"],
  [/^teaspoons?\b\s*(?:of\s+)?/, "c. à café"],
  [/^tbsp\b\s*(?:of\s+)?/, "c. à soupe"],
  [/^tsp\b\s*(?:of\s+)?/, "c. à café"],
  [/^grammes?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "g"],
  [/^gr\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "g"],
  [/^kilogrammes?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "kg"],
  [/^kilos?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "kg"],
  [/^kg\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "kg"],
  [/^millilitres?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "ml"],
  [/^centilitres?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "cl"],
  [/^litres?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "l"],
  [/^ml\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "ml"],
  [/^cl\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "cl"],
  [/^dl\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "dl"],
  [/^pincees?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "pincée"],
  [/^gousses?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "gousse"],
  [/^cloves?\b\s*(?:of\s+)?/, "gousse"],
  [/^tranches?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "tranche"],
  [/^sachets?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "sachet"],
  [/^tasses?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "tasse"],
  [/^cups?\b\s*(?:of\s+)?/, "tasse"],
  [/^pieces?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, ""],
  [/^unites?\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, ""],
  // Bare metric token after stripping a number: "g farine" -> "farine".
  [/^g\b\s*(?:de\s+|d\s+|du\s+|des\s+)?/, "g"],
];

// After cleanup, if the name reduces to one of these pure unit words it
// is meaningless on its own — caller should drop the ingredient.
const BARE_UNIT_NAME_BLOCKLIST = new Set([
  "soupe",
  "cafe",
  "cuillere",
  "cuilleres",
  "gramme",
  "grammes",
  "pincee",
  "pincees",
  "sachet",
  "sachets",
  "piece",
  "pieces",
  "tranche",
  "tranches",
  "tasse",
  "tasses",
  "unite",
  "unites",
]);

function foldForMatch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/œ/gi, "oe")
    .replace(/æ/gi, "ae")
    .replace(/['’`]/g, " ")
    .replace(/\s+/g, " ")
    .toLowerCase()
    .trim();
}

function toFrenchDisplayCase(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return trimmed;
  return trimmed.charAt(0).toLocaleUpperCase("fr-FR") + trimmed.slice(1);
}

export function cleanIngredientNameField(
  raw: string,
  currentUnit?: string,
  currentAmount?: string
): CleanedIngredientNameField {
  if (!raw) {
    return { name: "", dropped: true };
  }

  const original = raw.replace(/\s+/g, " ").trim();
  if (!original) {
    return { name: "", dropped: true };
  }

  let working = original;
  let mutated = false;
  let extractedAmount: string | undefined;
  let extractedUnit: string | undefined;

  // 1. Pull a leading amount if present (only when the caller has none).
  const folded = () => foldForMatch(working);
  const amountMatch = folded().match(LEADING_AMOUNT_RE);
  if (amountMatch && !currentAmount) {
    extractedAmount = amountMatch[1].replace(/\s+/g, "");
    working = working.replace(/^\s*\S+\s+/, "").trim();
    mutated = true;
  } else if (amountMatch) {
    // Caller already has an amount; still strip the numeric prefix from the name.
    working = working.replace(/^\s*\S+\s+/, "").trim();
    mutated = true;
  }

  // 2. Pull a leading unit token — run repeatedly so "c a s de huile"
  //    style can compound (rare but cheap to handle).
  for (let pass = 0; pass < 2; pass += 1) {
    const lowered = folded();
    let matched = false;
    for (const [pattern, replacement] of NAME_LEADING_UNIT_PATTERNS) {
      const m = lowered.match(pattern);
      if (m) {
        working = working.slice(m[0].length).trim();
        if (!extractedUnit && replacement) {
          extractedUnit = replacement;
        }
        matched = true;
        mutated = true;
        break;
      }
    }
    if (!matched) break;
  }

  // 3. Strip a lingering leading "de la / du / d' / de" article that the
  //    unit match may have left behind (only if we actually extracted a unit).
  if (mutated) {
    const afterArticle = working
      .replace(/^\s*(?:de\s+la\s+|de\s+l['’\s]\s*|du\s+|des\s+|de\s+|d['’\s]\s*|l['’\s]\s*)/i, "")
      .trim();
    if (afterArticle !== working) {
      working = afterArticle;
    }
  }

  if (!working) {
    return { name: "", extractedUnit, extractedAmount, dropped: true };
  }

  // 4. Collapse immediate head-word duplications ("Oeufs Oeufs",
  //    "Farine farine", "huile huile"). Fold for comparison so "Œufs
  //    oeufs" also collapses.
  const tokens = working.split(/\s+/);
  if (tokens.length >= 2 && foldForMatch(tokens[0]) === foldForMatch(tokens[1])) {
    tokens.splice(1, 1);
    working = tokens.join(" ");
    mutated = true;
  }

  // 5. Bare-unit guard — if the remainder is just a unit word, drop it.
  const barefold = foldForMatch(working);
  if (BARE_UNIT_NAME_BLOCKLIST.has(barefold)) {
    return { name: "", extractedUnit, extractedAmount, dropped: true };
  }

  // 6. Normalize 'oeufs'/'oeuf' head-word to œufs/œuf for display.
  const headFolded = foldForMatch(tokens[0] ?? working);
  if (headFolded === "oeufs") {
    working = working.replace(/^oeufs/i, "œufs");
    mutated = true;
  } else if (headFolded === "oeuf") {
    working = working.replace(/^oeuf/i, "œuf");
    mutated = true;
  }

  // Only apply display-case transform when we actually changed something;
  // otherwise preserve the caller's casing so downstream normalizers can
  // still match against lowercase keys.
  const finalName = mutated ? toFrenchDisplayCase(working) : working;

  return {
    name: finalName,
    extractedUnit,
    extractedAmount,
  };
}

// ---------------------------------------------------------------------
// stripSocialNoise — conservative caption/text pre-filter.
//
// Only strips fragments that cannot plausibly be cooking content:
//   - hashtags at end of line
//   - whole-line CTA strings (abonne-toi, lien en bio, subscribe...)
//   - isolated timestamps on non-cooking lines
//   - trailing emoji runs at end of line
//
// When in doubt, leaves content alone — the downstream LLM and strict
// validator handle deeper cleanup.
// ---------------------------------------------------------------------

const WHOLE_LINE_CTA = [
  /^\s*abonne[-\s]?(?:toi|vous)\b.*$/i,
  /^\s*abonnez[-\s]?vous\b.*$/i,
  /^\s*suis[-\s]?moi\b.*$/i,
  /^\s*follow\s+me\b.*$/i,
  /^\s*subscribe\b.*$/i,
  /^\s*lien\s+en\s+bio\b.*$/i,
  /^\s*link\s+in\s+bio\b.*$/i,
  /^\s*bon\s+app(?:[eé]tit)?\s*!?\s*$/i,
  /^\s*(?:a|à)\s+vous\s+de\s+jouer\s*!?\s*$/i,
  /^\s*n[' ]?oublie(?:z)?\s+pas\s+de\s+(?:liker|partager|commenter).*$/i,
  /^\s*enjoy\s*!?\s*$/i,
];

const COOKING_VERB_HINT = /\b(?:cuire|cuisson|chauffer|chauffez|m[eé]langer|couper|ajouter|verser|laisser|servir|go[uû]ter|assaisonner|pr[eé]chauffer|faire|prepare|cook|mix|heat|add|pour|serve|bake|fry|grill|roast|saute|sear)\b/i;

const TIMESTAMP_RE = /\b\d{1,2}:\d{2}\b/;
const TRAILING_HASHTAGS_RE = /(?:\s|^)#\w[\w-]*\b/gu;
const TRAILING_EMOJI_RUN_RE = /\s*[\p{Extended_Pictographic}\p{Emoji_Presentation}\u200d\ufe0f]+\s*$/gu;

export function stripSocialNoise(raw: string): string {
  if (!raw || !raw.trim()) return raw;

  const lines = raw.split(/\r?\n/);
  const out: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) {
      out.push(line);
      continue;
    }

    // Whole-line CTAs — drop outright.
    if (WHOLE_LINE_CTA.some((re) => re.test(trimmed))) {
      continue;
    }

    // Timestamp-only line (e.g. "0:32", "1:05") with no cooking verbs.
    if (TIMESTAMP_RE.test(trimmed) && !COOKING_VERB_HINT.test(trimmed) && trimmed.length <= 12) {
      continue;
    }

    // Strip trailing hashtags and trailing emoji runs. Leaves interior
    // content untouched.
    let cleaned = line.replace(TRAILING_HASHTAGS_RE, "");
    cleaned = cleaned.replace(TRAILING_EMOJI_RUN_RE, "");
    out.push(cleaned.trimEnd());
  }

  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}
