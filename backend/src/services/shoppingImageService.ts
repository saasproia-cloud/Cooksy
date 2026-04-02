import { env, providerStatus } from "../config/env.js";

type ShoppingImageRequest = {
  id: string;
  article: string;
  category?: string;
};

type ShoppingImageResult = {
  id: string;
  imageUrl?: string;
  sourcePageUrl?: string;
};

const imageCache = new Map<string, ShoppingImageResult>();

// Comprehensive French → Spoonacular ingredient name mapping
// Spoonacular CDN: https://spoonacular.com/cdn/ingredients_100x100/{name}.jpg
const FRENCH_TO_SPOONACULAR: Record<string, string> = {
  // Farines & féculents
  "farine": "flour",
  "farine de ble": "flour",
  "farine t45": "flour",
  "farine t55": "flour",
  "farine complete": "whole-wheat-flour",
  "farine de mais": "cornmeal",
  "farine de riz": "rice-flour",
  "fecule de pomme de terre": "potato-starch",
  "fecule de mais": "cornstarch",
  "maizena": "cornstarch",
  "amidon": "cornstarch",
  "chapelure": "breadcrumbs",

  // Sucres & douceurs
  "sucre": "sugar",
  "sucre blanc": "sugar",
  "sucre en poudre": "sugar",
  "sucre glace": "powdered-sugar",
  "sucre roux": "brown-sugar",
  "cassonade": "brown-sugar",
  "miel": "honey",
  "sirop d erable": "maple-syrup",
  "sirop de sucre": "sugar",
  "vanille": "vanilla",
  "extrait de vanille": "vanilla",
  "gousse de vanille": "vanilla",
  "chocolat": "dark-chocolate",
  "chocolat noir": "dark-chocolate",
  "chocolat au lait": "milk-chocolate",
  "chocolat blanc": "white-chocolate",
  "cacao": "cocoa-powder",
  "poudre de cacao": "cocoa-powder",
  "nutella": "chocolate-hazelnut-spread",

  // Matières grasses
  "beurre": "butter",
  "beurre mou": "butter",
  "beurre demi sel": "butter",
  "margarine": "margarine",
  "huile": "vegetable-oil",
  "huile d olive": "olive-oil",
  "huile de tournesol": "sunflower-oil",
  "huile de colza": "canola-oil",
  "huile de coco": "coconut-oil",
  "huile de sesame": "sesame-oil",
  "creme": "heavy-cream",
  "creme fraiche": "sour-cream",
  "creme liquide": "heavy-cream",
  "creme entiere": "heavy-cream",

  // Produits laitiers
  "lait": "milk",
  "lait entier": "whole-milk",
  "lait demi ecreme": "milk",
  "lait ecreme": "milk",
  "lait de coco": "coconut-milk",
  "lait d amande": "almond-milk",
  "yaourt": "yogurt",
  "yaourt nature": "yogurt",
  "yaourt grec": "greek-yogurt",
  "fromage blanc": "cottage-cheese",
  "mascarpone": "mascarpone",
  "ricotta": "ricotta",
  "mozzarella": "mozzarella",
  "parmesan": "parmesan",
  "gruyere": "swiss-cheese",
  "emmental": "swiss-cheese",
  "cheddar": "cheddar-cheese",
  "brie": "brie",
  "camembert": "brie",
  "fromage de chevre": "goat-cheese",
  "feta": "feta",
  "comté": "swiss-cheese",
  "comte": "swiss-cheese",
  "roquefort": "blue-cheese",
  "fromage rape": "shredded-cheese",
  "fromage": "cheese",
  "fromage qui rit": "cream-cheese",
  "creme de gruyere": "cream-cheese",

  // Oeufs
  "oeuf": "egg",
  "oeufs": "egg",
  "jaune d oeuf": "egg-yolk",
  "blanc d oeuf": "egg-white",

  // Levures & poudres
  "levure": "active-dry-yeast",
  "levure de boulanger": "active-dry-yeast",
  "levure boulangere": "active-dry-yeast",
  "levure seche": "active-dry-yeast",
  "levure deshydratee": "active-dry-yeast",
  "levure chimique": "baking-powder",
  "bicarbonate": "baking-soda",
  "bicarbonate de soude": "baking-soda",

  // Sel & épices de base
  "sel": "salt",
  "poivre": "black-pepper",
  "poivre noir": "black-pepper",
  "paprika": "paprika",
  "cumin": "cumin",
  "coriandre": "coriander",
  "curry": "curry-powder",
  "curcuma": "turmeric",
  "cannelle": "cinnamon",
  "muscade": "nutmeg",
  "origan": "dried-oregano",
  "thym": "fresh-thyme",
  "romarin": "rosemary",
  "laurier": "bay-leaves",
  "basilic": "fresh-basil",
  "persil": "parsley",
  "ciboulette": "chives",
  "estragon": "tarragon",
  "menthe": "fresh-mint",
  "gingembre": "fresh-ginger",
  "piment": "chili-pepper",
  "piment de cayenne": "cayenne-pepper",
  "piment rouge": "red-chili-pepper",
  "piment espelette": "paprika",
  "herbes de provence": "herbes-de-provence",
  "ras el hanout": "ras-el-hanout",
  "safran": "saffron",
  "cardamome": "cardamom",
  "anis": "anise",
  "sumac": "sumac",
  "zaatar": "zaatar",
  "epices": "spices",

  // Condiments & sauces
  "sel de mer": "salt",
  "fleur de sel": "salt",
  "moutarde": "dijon-mustard",
  "moutarde de dijon": "dijon-mustard",
  "vinaigre": "white-wine-vinegar",
  "vinaigre balsamique": "balsamic-vinegar",
  "vinaigre de cidre": "apple-cider-vinegar",
  "vinaigre blanc": "white-vinegar",
  "sauce soja": "soy-sauce",
  "sauce worcestershire": "worcestershire-sauce",
  "sauce pimentee": "hot-sauce",
  "harissa": "chili-sauce",
  "ketchup": "ketchup",
  "mayonnaise": "mayonnaise",
  "sauce tomate": "tomato-sauce",
  "concentre de tomate": "tomato-paste",
  "tomates pelees": "canned-tomatoes",
  "tahini": "tahini",
  "pesto": "pesto",
  "tapenade": "olives",
  "sauce aigre douce": "sweet-and-sour-sauce",
  "sauce teriyaki": "soy-sauce",
  "sauce hoisin": "hoisin-sauce",

  // Liquides
  "eau": "water",
  "lait de coco en boite": "coconut-milk",
  "bouillon de poulet": "chicken-broth",
  "bouillon de legumes": "vegetable-broth",
  "bouillon de boeuf": "beef-broth",
  "vin blanc": "white-wine",
  "vin rouge": "red-wine",
  "biere": "beer",
  "rhum": "rum",
  "jus de citron": "lemon-juice",
  "jus d orange": "orange-juice",

  // Légumes
  "oignon": "onions",
  "oignon rouge": "red-onions",
  "echalote": "shallots",
  "ail": "garlic",
  "poireau": "leeks",
  "carotte": "carrots",
  "celeri": "celery",
  "pomme de terre": "russet-potatoes",
  "tomate": "tomatoes",
  "tomates cerises": "cherry-tomatoes",
  "poivron": "bell-pepper",
  "poivron rouge": "red-bell-pepper",
  "poivron vert": "green-bell-pepper",
  "courgette": "zucchini",
  "aubergine": "eggplant",
  "champignon": "mushrooms",
  "champignons de paris": "white-mushrooms",
  "champignon portobello": "portobello-mushroom",
  "epinard": "spinach",
  "salade": "romaine-lettuce",
  "laitue": "romaine-lettuce",
  "roquette": "arugula",
  "chou": "cabbage",
  "chou rouge": "red-cabbage",
  "chou fleur": "cauliflower",
  "brocoli": "broccoli",
  "concombre": "cucumber",
  "radis": "radishes",
  "betterave": "beets",
  "asperge": "asparagus",
  "petit pois": "peas",
  "haricot vert": "green-beans",
  "mais": "sweet-corn",
  "artichaut": "artichoke",
  "fenouil": "fennel",
  "navet": "turnip",
  "courge": "butternut-squash",
  "potiron": "pumpkin",
  "butternut": "butternut-squash",
  "avocat": "avocado",
  "olive": "olives",
  "olives noires": "olives",
  "olives vertes": "green-olives",
  "câpres": "capers",
  "capres": "capers",
  "cornichon": "pickles",
  "patate douce": "sweet-potato",

  // Fruits
  "citron": "lemon",
  "citron vert": "lime",
  "orange": "orange",
  "pomme": "apples",
  "poire": "pears",
  "banane": "banana",
  "fraise": "strawberries",
  "framboise": "raspberries",
  "myrtille": "blueberries",
  "cerise": "cherries",
  "raisin": "grapes",
  "mangue": "mango",
  "ananas": "pineapple",
  "kiwi": "kiwi",
  "peche": "peaches",
  "abricot": "apricots",
  "grenade": "pomegranate",
  "figue": "figs",
  "datte": "dates",
  "noix de coco": "coconut",

  // Protéines animales
  "poulet": "whole-chicken",
  "blanc de poulet": "chicken-breast",
  "filet de poulet": "chicken-breast",
  "cuisse de poulet": "chicken-thighs",
  "dinde": "turkey",
  "boeuf": "beef",
  "viande hachee": "ground-beef",
  "steak": "beef-steak",
  "veau": "veal",
  "porc": "pork",
  "lardons": "bacon",
  "bacon": "bacon",
  "jambon": "ham",
  "saucisse": "sausage",
  "merguez": "sausage",
  "chorizo": "chorizo",
  "agneau": "lamb",
  "saumon": "salmon",
  "filet de saumon": "salmon",
  "thon": "canned-tuna",
  "cabillaud": "cod",
  "bar": "sea-bass",
  "dorade": "sea-bream",
  "crevette": "shrimp",
  "gambas": "shrimp",
  "calamar": "squid",
  "moule": "mussels",
  "coquille saint jacques": "scallops",
  "sardine": "sardines",

  // Féculents & céréales
  "riz": "white-rice",
  "riz basmati": "basmati-rice",
  "riz arborio": "arborio-rice",
  "quinoa": "quinoa",
  "pates": "pasta",
  "spaghetti": "spaghetti",
  "tagliatelles": "pasta",
  "penne": "penne",
  "fusilli": "fusilli",
  "lasagnes": "lasagna",
  "couscous": "couscous",
  "boulgour": "bulgur",
  "pain": "bread",
  "pain de mie": "white-bread",
  "baguette": "french-baguette",
  "pain pita": "pita-bread",
  "naan": "naan-bread",
  "tortilla": "flour-tortilla",

  // Légumineuses
  "lentille": "lentils",
  "pois chiche": "chickpeas",
  "haricot blanc": "cannellini-beans",
  "haricot rouge": "kidney-beans",
  "haricot noir": "black-beans",
  "fève": "fava-beans",
  "edamame": "edamame",
  "tofu": "tofu",

  // Fruits secs & oléagineux
  "amande": "almonds",
  "noix": "walnuts",
  "noisette": "hazelnuts",
  "cajou": "cashews",
  "pistache": "pistachios",
  "cacahuete": "peanuts",
  "beurre de cacahuete": "peanut-butter",
  "graine de sesame": "sesame-seeds",
  "graine de tournesol": "sunflower-seeds",
  "graine de chia": "chia-seeds",
  "graine de lin": "flax-seeds",
  "raisin sec": "raisins",
  "abricot sec": "dried-apricots",
  "cranberry": "dried-cranberries",

  // Autres
  "gelatine": "gelatin",
  "agar agar": "agar",
  "levure alimentaire": "nutritional-yeast",
  "sauce fish": "fish-sauce",
};

export async function enrichShoppingImages(items: ShoppingImageRequest[]): Promise<ShoppingImageResult[]> {
  const uniqueItems = items.filter((item, index, array) => {
    return array.findIndex((candidate) => candidate.id === item.id) === index;
  });

  const results = await Promise.all(uniqueItems.map((item) => searchImageForItem(item)));
  return results;
}

async function searchImageForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  const cacheKey = `${item.article.toLowerCase()}::${item.category ?? ""}`;
  const cached = imageCache.get(cacheKey);
  if (cached) {
    return { ...cached, id: item.id };
  }

  const result = await searchRemoteImage(item);

  imageCache.set(cacheKey, result);
  return { ...result, id: item.id };
}

async function searchRemoteImage(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  // 1. Try Spoonacular CDN first (fast, no API key, clean white-background images)
  const spoonacularResult = await trySpoonacularCDN(item);
  if (spoonacularResult.imageUrl) {
    return spoonacularResult;
  }

  // 2. Try Wikipedia with English translated name
  const wikimediaResult = await searchWikimediaForItem(item);
  if (wikimediaResult.imageUrl) {
    return wikimediaResult;
  }

  // 3. Fall back to SerpAPI if configured
  const serpApiResult = await searchSerpApiForItem(item);
  if (serpApiResult.imageUrl) {
    return serpApiResult;
  }

  return { id: item.id };
}

async function trySpoonacularCDN(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  // The category may contain the English nutritionQuery (sent from the updated iOS app)
  // Otherwise translate from French using our mapping
  const englishName = resolveEnglishName(item.article, item.category);
  if (!englishName) {
    return { id: item.id };
  }

  const imageSlug = toSpoonacularSlug(englishName);
  if (!imageSlug) {
    return { id: item.id };
  }

  const imageUrl = `https://spoonacular.com/cdn/ingredients_250x250/${imageSlug}.jpg`;

  try {
    const response = await fetch(imageUrl, {
      method: "HEAD",
      signal: AbortSignal.timeout(4_000)
    });

    if (response.ok) {
      return {
        id: item.id,
        imageUrl,
        sourcePageUrl: "https://spoonacular.com"
      };
    }

    // If the exact slug doesn't exist, try a simplified version
    const simpleSlug = imageSlug.split("-").slice(0, 2).join("-");
    if (simpleSlug !== imageSlug) {
      const simpleUrl = `https://spoonacular.com/cdn/ingredients_250x250/${simpleSlug}.jpg`;
      const simpleResponse = await fetch(simpleUrl, {
        method: "HEAD",
        signal: AbortSignal.timeout(3_000)
      });

      if (simpleResponse.ok) {
        return {
          id: item.id,
          imageUrl: simpleUrl,
          sourcePageUrl: "https://spoonacular.com"
        };
      }
    }

    return { id: item.id };
  } catch {
    return { id: item.id };
  }
}

function resolveEnglishName(frenchArticle: string, categoryHint?: string): string | undefined {
  // If category looks like an English word (from nutritionQuery), use it directly
  if (categoryHint && isLikelyEnglish(categoryHint)) {
    return categoryHint;
  }

  // Normalize the French article and look up in mapping
  const normalized = normalizeQueryText(frenchArticle);
  const directMatch = FRENCH_TO_SPOONACULAR[normalized];
  if (directMatch) {
    return directMatch;
  }

  // Try matching individual words from the article
  const words = normalized.split(" ");
  for (const word of words) {
    if (word.length >= 3) {
      const wordMatch = FRENCH_TO_SPOONACULAR[word];
      if (wordMatch) {
        return wordMatch;
      }
    }
  }

  // If article looks like English already, use it as-is
  if (isLikelyEnglish(frenchArticle)) {
    return frenchArticle;
  }

  return undefined;
}

function isLikelyEnglish(text: string): boolean {
  const normalized = text.toLowerCase();
  // Common English food words that indicate it's already in English
  const englishSignals = [
    "butter", "flour", "sugar", "salt", "oil", "milk", "egg", "cream",
    "chicken", "beef", "pork", "fish", "salmon", "shrimp",
    "garlic", "onion", "tomato", "cheese", "bread", "rice", "pasta",
    "powder", "sauce", "juice", "vinegar", "yeast", "pepper"
  ];
  return englishSignals.some((signal) => normalized.includes(signal));
}

function toSpoonacularSlug(englishName: string): string {
  return englishName
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, " ")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

async function searchSerpApiForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  if (!providerStatus.serpApi) {
    return { id: item.id };
  }

  try {
    const englishName = resolveEnglishName(item.article, item.category);
    const query = englishName
      ? `${englishName} ingredient food isolated white background`
      : buildShoppingQuery(item.article, item.category);

    const params = new URLSearchParams({
      engine: "google_images",
      q: query,
      safe: "active",
      ijn: "0",
      api_key: env.SERPAPI_KEY
    });

    const response = await fetch(`https://serpapi.com/search.json?${params.toString()}`, {
      signal: AbortSignal.timeout(20_000)
    });

    if (!response.ok) {
      return { id: item.id };
    }

    const json = await response.json() as {
      images_results?: Array<{
        original?: string;
        thumbnail?: string;
        link?: string;
      }>;
    };

    const bestImage = json.images_results?.find((entry) => entry.original || entry.thumbnail);
    return {
      id: item.id,
      imageUrl: bestImage?.original ?? bestImage?.thumbnail,
      sourcePageUrl: bestImage?.link
    };
  } catch {
    return { id: item.id };
  }
}

async function searchWikimediaForItem(item: ShoppingImageRequest): Promise<ShoppingImageResult> {
  const englishName = resolveEnglishName(item.article, item.category);
  const queries = buildWikimediaQueries(item.article, item.category, englishName);

  for (const query of queries) {
    const result = await searchWikimediaQuery(item.id, query);
    if (result.imageUrl) {
      return result;
    }
  }

  return { id: item.id };
}

async function searchWikimediaQuery(id: string, query: string): Promise<ShoppingImageResult> {
  try {
    const params = new URLSearchParams({
      action: "query",
      generator: "search",
      gsrsearch: query,
      gsrlimit: "3",
      prop: "pageimages",
      piprop: "thumbnail",
      pithumbsize: "360",
      format: "json",
      origin: "*"
    });

    const response = await fetch(`https://en.wikipedia.org/w/api.php?${params.toString()}`, {
      signal: AbortSignal.timeout(10_000)
    });

    if (!response.ok) {
      return { id };
    }

    const json = await response.json() as {
      query?: {
        pages?: Record<string, {
          pageid?: number;
          title?: string;
          thumbnail?: {
            source?: string;
          };
        }>;
      };
    };

    const pages = Object.values(json.query?.pages ?? {})
      .filter((page) => page.thumbnail?.source)
      .filter((page) => !looksLikeWikimediaNoise(page.title))
      .sort((lhs, rhs) => {
        const lhsTitle = (lhs.title ?? "").length;
        const rhsTitle = (rhs.title ?? "").length;
        return lhsTitle - rhsTitle;
      });

    const bestPage = pages[0];
    if (!bestPage?.thumbnail?.source) {
      return { id };
    }

    return {
      id,
      imageUrl: bestPage.thumbnail.source,
      sourcePageUrl: bestPage.pageid
        ? `https://en.wikipedia.org/?curid=${bestPage.pageid}`
        : undefined
    };
  } catch {
    return { id };
  }
}

function buildShoppingQuery(article: string, category?: string): string {
  const suffix = category ? `${category} ingredient` : "ingredient";
  return `${article} ${suffix} food photo`;
}

function buildWikimediaQueries(article: string, category?: string, englishName?: string): string[] {
  const queries: string[] = [];

  // Prefer English queries on en.wikipedia.org
  if (englishName) {
    queries.push(englishName);
    queries.push(`${englishName} ingredient`);
    queries.push(`${englishName} food`);
  }

  const articleQuery = normalizeQueryText(article);
  const categoryQuery = normalizeQueryText(category);

  if (articleQuery && !englishName) {
    queries.push(articleQuery);
    queries.push(`${articleQuery} ingredient`);
    if (categoryQuery && articleQuery !== categoryQuery) {
      queries.push(`${articleQuery} ${categoryQuery}`);
    }
  }

  return [...new Set(queries.map((q) => q.trim()).filter(Boolean))];
}

function normalizeQueryText(value?: string): string {
  return (value ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function looksLikeWikimediaNoise(title?: string): boolean {
  const normalized = normalizeQueryText(title);
  if (!normalized) {
    return true;
  }

  return normalized.startsWith("list of ") ||
    normalized.startsWith("category ") ||
    normalized.startsWith("template ") ||
    normalized.startsWith("help ");
}
