import {
  sanitizeRecipeImport,
  type NormalizerInput,
  type RecipeImportResult
} from "../types/recipe.js";

export function fallbackRecipeFromContext(input: NormalizerInput): RecipeImportResult {
  if (input.mode === "url") {
    const structuredRecipe = structuredRecipeFromBlocks(input.pageStructuredData ?? []);
    if (structuredRecipe) {
      return sanitizeRecipeImport({
        ...structuredRecipe,
        sourceUrl: input.sourceUrl ?? structuredRecipe.sourceUrl,
        remoteImageUrl: input.remoteImageUrl || structuredRecipe.remoteImageUrl
      });
    }
  }

  const combinedText = [
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles,
    input.transcript,
    input.socialTitle,
    input.pageTitle,
    input.pageDescription,
    input.pageTextContent
  ]
    .filter((value): value is string => Boolean(value?.trim()))
    .join("\n\n");

  const parsed = parseRecipeText(combinedText);

  return sanitizeRecipeImport({
    ...parsed,
    sourceUrl: input.sourceUrl ?? "",
    remoteImageUrl: input.remoteImageUrl ?? "",
    notesText: parsed.notesText || buildFallbackNotes(input)
  });
}

export function isOpenAIUnavailable(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return message.includes("insufficient_quota") ||
    message.includes("rate limit") ||
    message.includes("429") ||
    message.includes("openai normalization failed") ||
    message.includes("openai");
}

export function structuredRecipeFromBlocks(blocks: string[]): RecipeImportResult | null {
  return extractStructuredRecipe(blocks);
}

function parseRecipeText(input: string): RecipeImportResult {
  const lines = heuristicLines(input);
  if (!lines.length) {
    return emptyRecipe();
  }

  let title = explicitTitle(lines) || fallbackTitle(lines);
  let ingredientLines: string[] = [];
  let stepLines: string[] = [];
  let noteLines: string[] = [];
  let currentSection: "header" | "ingredients" | "steps" | "notes" = "header";

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    if (isIngredientsHeader(line)) {
      currentSection = "ingredients";
      continue;
    }

    if (isStepsHeader(line)) {
      currentSection = "steps";
      continue;
    }

    if (isNotesHeader(line)) {
      currentSection = "notes";
      continue;
    }

    if (currentSection === "ingredients" && looksLikeStep(line) && !looksLikeIngredient(line)) {
      currentSection = "steps";
      stepLines.push(cleanedStepLine(line));
      continue;
    }

    if (currentSection === "header" && !title) {
      title = cleanedTitle(line);
      continue;
    }

    switch (currentSection) {
      case "ingredients":
        ingredientLines.push(cleanedListLine(line));
        break;
      case "steps":
        stepLines.push(cleanedStepLine(line));
        break;
      case "notes":
        noteLines.push(line);
        break;
      default:
        noteLines.push(line);
        break;
    }
  }

  if (!ingredientLines.length && !stepLines.length) {
    const candidateLines = lines
      .filter((line) => cleanedTitle(line) !== title)
      .filter((line) => !isLikelyNoise(line));

    ingredientLines = candidateLines.filter(looksLikeIngredient);
    stepLines = candidateLines
      .filter((line) => !looksLikeIngredient(line) && looksLikeStep(line))
      .map(cleanedStepLine);
  }

  return sanitizeRecipeImport({
    title: title || "Recette importee",
    sourceUrl: "",
    remoteImageUrl: "",
    ingredientDrafts: ingredientLines.map(parseIngredientLine).filter((item) => item.name.length > 0),
    stepDrafts: stepLines.map((detail) => ({ detail })).filter((step) => step.detail.length > 0),
    notesText: noteLines.join("\n"),
    prepTimeText: extractTime(input, /(?:prep|preparation|préparation)[^\d]*(\d{1,3})\s*min/i),
    cookTimeText: extractTime(input, /(?:cuisson|cook)[^\d]*(\d{1,3})\s*min/i),
    servingsText: extractTime(input, /(?:portions?|servings?|pour)\s*(\d{1,2})/i),
    caloriesText: "",
    proteinText: "",
    carbsText: "",
    fatText: "",
    confidence: ingredientLines.length >= 2 && stepLines.length >= 2 ? "medium" : "low",
    needsWebFallback: ingredientLines.length < 2 || stepLines.length < 2,
    searchQuery: title || "",
    inferredFromPhoto: false
  });
}

function extractStructuredRecipe(blocks: string[]): RecipeImportResult | null {
  for (const block of blocks) {
    const parsed = parseStructuredRecipeBlock(block);
    if (parsed) {
      return parsed;
    }
  }

  return null;
}

function parseStructuredRecipeBlock(block: string): RecipeImportResult | null {
  const cleaned = block
    .replaceAll("<!--", "")
    .replaceAll("-->", "")
    .replaceAll("<![CDATA[", "")
    .replaceAll("]]>", "")
    .trim();

  if (!cleaned) {
    return null;
  }

  try {
    const object = JSON.parse(cleaned) as unknown;
    const recipeObject = findRecipeObject(object);
    if (!recipeObject) {
      return null;
    }

    return sanitizeRecipeImport({
      title: stringValue(recipeObject.name) ?? "Recette importee",
      sourceUrl: "",
      remoteImageUrl: imageUrl(recipeObject.image) ?? "",
      ingredientDrafts: stringArray(recipeObject.recipeIngredient).map(parseIngredientLine),
      stepDrafts: instructions(recipeObject.recipeInstructions)
        .map((detail) => ({ detail }))
        .filter((step) => step.detail.length > 0),
      notesText: stringValue(recipeObject.description) ?? "",
      prepTimeText: durationInMinutes(stringValue(recipeObject.prepTime)),
      cookTimeText: durationInMinutes(stringValue(recipeObject.cookTime)),
      servingsText: stringValue(recipeObject.recipeYield) ?? "",
      caloriesText: stringValue(recipeObject.nutrition?.calories) ?? "",
      proteinText: stringValue(recipeObject.nutrition?.proteinContent) ?? "",
      carbsText: stringValue(recipeObject.nutrition?.carbohydrateContent) ?? "",
      fatText: stringValue(recipeObject.nutrition?.fatContent) ?? "",
      confidence: "high",
      needsWebFallback: false,
      searchQuery: "",
      inferredFromPhoto: false
    });
  } catch {
    return null;
  }
}

function findRecipeObject(value: unknown): Record<string, any> | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const recipe = findRecipeObject(item);
      if (recipe) {
        return recipe;
      }
    }
    return null;
  }

  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, any>;
  if (isRecipeType(record["@type"])) {
    return record;
  }

  if (Array.isArray(record["@graph"])) {
    for (const item of record["@graph"]) {
      const recipe = findRecipeObject(item);
      if (recipe) {
        return recipe;
      }
    }
  }

  for (const child of Object.values(record)) {
    const recipe = findRecipeObject(child);
    if (recipe) {
      return recipe;
    }
  }

  return null;
}

function isRecipeType(value: unknown): boolean {
  if (typeof value === "string") {
    return value.toLowerCase() === "recipe";
  }

  if (Array.isArray(value)) {
    return value.some((entry) => typeof entry === "string" && entry.toLowerCase() === "recipe");
  }

  return false;
}

function stringValue(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || null;
  }

  if (typeof value === "number") {
    return String(value);
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const nested = stringValue(entry);
      if (nested) {
        return nested;
      }
    }
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return stringValue(record.value) ?? stringValue(record.text) ?? stringValue(record.name) ?? null;
  }

  return null;
}

function stringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map((entry) => stringValue(entry)).filter((entry): entry is string => Boolean(entry));
  }

  const single = stringValue(value);
  return single ? [single] : [];
}

function imageUrl(value: unknown): string | null {
  if (typeof value === "string") {
    return value.trim() || null;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const nested = imageUrl(entry);
      if (nested) {
        return nested;
      }
    }
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return stringValue(record.url) ?? stringValue(record.contentUrl) ?? stringValue(record.thumbnailUrl) ?? null;
  }

  return null;
}

function instructions(value: unknown): string[] {
  if (typeof value === "string") {
    const cleaned = cleanedStepLine(value);
    return cleaned ? [cleaned] : [];
  }

  if (Array.isArray(value)) {
    return value.flatMap((entry) => instructions(entry));
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (record.text) {
      return instructions(record.text);
    }
    if (record.itemListElement) {
      return instructions(record.itemListElement);
    }
    if (record.name) {
      return instructions(record.name);
    }
  }

  return [];
}

function durationInMinutes(value: string | null): string {
  if (!value) {
    return "";
  }

  const normalized = value.toUpperCase();
  const match = normalized.match(/P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?/);
  if (!match) {
    return "";
  }

  const days = Number(match[1] ?? 0);
  const hours = Number(match[2] ?? 0);
  const minutes = Number(match[3] ?? 0);
  const total = days * 24 * 60 + hours * 60 + minutes;
  return total > 0 ? String(total) : "";
}

function normalizedLines(input: string): string[] {
  return input
    .replaceAll("\r\n", "\n")
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

function heuristicLines(input: string): string[] {
  const directLines = normalizedLines(input);
  const expandedInput = input
    .replaceAll("\r\n", "\n")
    .replace(/[•·▪◦●]/g, "\n- ")
    .replace(/\s*[|;]+\s*/g, "\n")
    .replace(
      /\b(ingredients?|ingrédients?|instructions?|étapes?|etapes|préparation|preparation|method|méthode|methode)\b\s*:/giu,
      "\n$1\n"
    )
    .replace(/(?:^|\s)(\d+[\).\-\:])\s*/g, "\n$1 ")
    .replace(
      /([.!?])\s+(?=(?:ajouter|mélanger|melanger|cuire|faire|verser|laisser|chauffer|mettre|servir|quand|maintenant|on va|add|mix|cook|stir|serve|ingredients?|instructions?|étapes?|etapes|préparation|preparation|\d+[.)-]))/giu,
      "$1\n"
    )
    .replace(
      /,\s+(?=(?:\d+(?:[.,]\d+)?|\d+\/\d+)\s*(?:g|kg|ml|cl|l|cas|cac|c\s*a\s*s|c\s*a\s*c|tablespoons?|teaspoons?|cups?|lb|lbs|oz)\b)/giu,
      "\n"
    );

  const expandedLines = normalizedLines(expandedInput);
  return uniqueNonEmptyLines(expandedLines.length >= directLines.length ? expandedLines : directLines);
}

function uniqueNonEmptyLines(lines: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const line of lines) {
    if (seen.has(line)) {
      continue;
    }

    seen.add(line);
    result.push(line);
  }

  return result;
}

function explicitTitle(lines: string[]): string | null {
  for (const line of lines) {
    if (/^(titre|title)\s*:/i.test(line)) {
      return cleanedTitle(line);
    }
  }
  return null;
}

function fallbackTitle(lines: string[]): string {
  for (const line of lines) {
    if (!isSectionHeader(line)) {
      const cleaned = cleanedTitle(line);
      if (cleaned) {
        return cleaned;
      }
    }
  }
  return "";
}

function isSectionHeader(line: string): boolean {
  return isIngredientsHeader(line) || isStepsHeader(line) || isNotesHeader(line);
}

function isIngredientsHeader(line: string): boolean {
  return matches(line, ["ingredients", "ingrédients", "ingredient", "liste des ingrédients"]) ||
    /^(?:ingredients?|ingrédients?)(?:\s+.+)?[:：]\s*$/i.test(line);
}

function isStepsHeader(line: string): boolean {
  return matches(line, ["instructions", "étapes", "etapes", "préparation", "preparation", "méthode", "methode", "directions", "marche a suivre", "marche à suivre"]);
}

function isNotesHeader(line: string): boolean {
  return matches(line, ["notes", "astuces", "conseils"]);
}

function matches(line: string, patterns: string[]): boolean {
  const normalized = line.toLowerCase().replace(/^[:\s\-•]+|[:\s\-•]+$/g, "");
  return patterns.includes(normalized);
}

function cleanedTitle(line: string): string {
  const cleaned = line.replace(/^(titre|title)\s*:\s*/i, "").trim();
  return isGenericSocialTitle(cleaned) ? "" : cleaned;
}

function cleanedListLine(line: string): string {
  return line.replace(/^\s*[-•*]\s*/u, "").trim();
}

function cleanedStepLine(line: string): string {
  return line.replace(/^\s*(\d+[\).\-\s]+|[-•*]\s*)/u, "").trim();
}

function looksLikeIngredient(line: string): boolean {
  const cleaned = cleanedListLine(line);
  if (!cleaned) {
    return false;
  }
  if (looksLikeStep(cleaned)) {
    return false;
  }
  if (/^\d+([,./]\d+)?/.test(cleaned)) {
    return true;
  }

  const lower = cleaned.toLowerCase();
  const units = ["g", "kg", "ml", "l", "c a s", "cas", "cuillere", "tasse", "verre", "pincee"];
  return units.some((unit) => lower.includes(unit)) || cleaned.split(" ").length <= 6;
}

function looksLikeStep(line: string): boolean {
  const cleaned = cleanedStepLine(line).toLowerCase();
  if (!cleaned) {
    return false;
  }
  if (/^\s*(\d+[\).\-\s]+|[-•*]\s*)/.test(line)) {
    return true;
  }

  const verbs = [
    "melanger", "mélanger", "ajouter", "faire", "cuire", "verser", "laisser",
    "chauffer", "former", "mettre", "fouetter", "mixer", "decouper", "découper",
    "rotir", "rôtir", "servir", "prechauffer", "préchauffer", "remuer", "incorporer",
    "puis", "ensuite", "etaler", "étaler", "etalez", "étalez", "rouler", "plier",
    "garnir", "repartir", "répartir", "napper", "saisir", "faire revenir", "laisser cuire",
    "on va", "quand", "maintenant"
  ];
  return verbs.some((verb) => cleaned.startsWith(verb));
}

function isLikelyNoise(line: string): boolean {
  const lower = line.toLowerCase();
  return lower.includes("http://") ||
    lower.includes("https://") ||
    lower.startsWith("#") ||
    lower.includes("tiktok") ||
    lower.includes("instagram");
}

function isGenericSocialTitle(line: string): boolean {
  const normalized = line
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();

  return normalized === "tiktok - make your day" ||
    normalized === "make your day" ||
    normalized === "tiktok" ||
    normalized.endsWith(" sur tiktok") ||
    normalized.endsWith(" on tiktok") ||
    normalized.startsWith("watch more trending videos") ||
    normalized.startsWith("regarde plus de videos");
}

function parseIngredientLine(line: string): { amount: string; unit: string; name: string; nutritionQuery: string } {
  const cleaned = cleanedListLine(line);
  const tokens = cleaned.split(" ").filter(Boolean);

  if (!tokens.length) {
    return { amount: "", unit: "", name: "", nutritionQuery: "" };
  }

  if (tokens.length === 1) {
    return { amount: "", unit: "", name: cleaned, nutritionQuery: cleaned };
  }

  const compactQuantity = splitCompactQuantityAndUnit(tokens[0]);
  if (compactQuantity) {
    const name = cleanedIngredientName(tokens.slice(1).join(" "));
    return {
      amount: compactQuantity.amount,
      unit: compactQuantity.unit,
      name,
      nutritionQuery: name
    };
  }

  const quantity = leadingQuantity(tokens);
  if (!quantity) {
    return { amount: "", unit: "", name: cleaned, nutritionQuery: cleaned };
  }

  const unit = leadingUnit(tokens, quantity.nextIndex);
  const nameStartIndex = unit ? unit.nextIndex : quantity.nextIndex;
  const name = cleanedIngredientName(tokens.slice(nameStartIndex).join(" "));

  return {
    amount: quantity.amount,
    unit: unit?.unit ?? "",
    name,
    nutritionQuery: name
  };
}

function splitCompactQuantityAndUnit(token: string): { amount: string; unit: string } | null {
  const compactMatch = token.match(/^(\d+(?:[.,]\d+)?)([a-zA-Z]+)$/);
  if (!compactMatch) {
    return null;
  }

  const [, amount, rawUnit] = compactMatch;
  const normalizedUnit = normalizeUnit(rawUnit);
  if (!normalizedUnit || !knownIngredientUnits.has(normalizedUnit)) {
    return null;
  }

  return { amount, unit: rawUnit };
}

function leadingQuantity(tokens: string[]): { amount: string; nextIndex: number } | null {
  const first = tokens[0] ?? "";
  const second = tokens[1] ?? "";

  if (isSimpleQuantity(first)) {
    if (isFraction(second)) {
      return { amount: `${first} ${second}`, nextIndex: 2 };
    }
    return { amount: first, nextIndex: 1 };
  }

  if (isFraction(first)) {
    return { amount: first, nextIndex: 1 };
  }

  return null;
}

function leadingUnit(tokens: string[], startIndex: number): { unit: string; nextIndex: number } | null {
  const first = tokens[startIndex] ?? "";
  const second = tokens[startIndex + 1] ?? "";
  const third = tokens[startIndex + 2] ?? "";

  const threeTokenCandidate = normalizeUnit(`${first} ${second} ${third}`);
  if (threeTokenCandidate && knownIngredientUnits.has(threeTokenCandidate)) {
    return {
      unit: [first, second, third].join(" "),
      nextIndex: startIndex + 3
    };
  }

  const twoTokenCandidate = normalizeUnit(`${first} ${second}`);
  if (twoTokenCandidate && knownIngredientUnits.has(twoTokenCandidate)) {
    return {
      unit: [first, second].join(" "),
      nextIndex: startIndex + 2
    };
  }

  const oneTokenCandidate = normalizeUnit(first);
  if (oneTokenCandidate && knownIngredientUnits.has(oneTokenCandidate)) {
    return {
      unit: first,
      nextIndex: startIndex + 1
    };
  }

  return null;
}

function cleanedIngredientName(name: string): string {
  return name
    .replace(/^(?:d'|d’)/i, "")
    .replace(/^(?:de|du|des|a|à)\s+/i, "")
    .replace(/^(?:la|le|les|un|une)\s+/i, "")
    .trim();
}

function isSimpleQuantity(token: string): boolean {
  return /^\d+(?:[.,]\d+)?$/.test(token);
}

function isFraction(token: string): boolean {
  return /^\d+\/\d+$/.test(token);
}

function normalizeUnit(token: string): string {
  return token
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[().]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const knownIngredientUnits = new Set([
  "g",
  "kg",
  "mg",
  "ml",
  "cl",
  "dl",
  "l",
  "oz",
  "lb",
  "lbs",
  "cup",
  "cups",
  "tbsp",
  "tsp",
  "c a s",
  "c a c",
  "c a soupe",
  "c a cafe",
  "cas",
  "cac",
  "cuil",
  "cuill",
  "cuillere",
  "cuilleres",
  "cuilleree",
  "cuillerees",
  "cuillere a soupe",
  "cuilleres a soupe",
  "cuillere a cafe",
  "cuilleres a cafe",
  "tablespoon",
  "tablespoons",
  "teaspoon",
  "teaspoons",
  "verre",
  "verres",
  "tasse",
  "tasses",
  "pincee",
  "pincees",
  "piece",
  "pieces",
  "tranche",
  "tranches",
  "branche",
  "branches",
  "botte",
  "bottes",
  "sachet",
  "sachets",
  "boite",
  "boites"
]);

function extractTime(input: string, pattern: RegExp): string {
  return input.match(pattern)?.[1] ?? "";
}

function emptyRecipe(): RecipeImportResult {
  return {
    title: "",
    sourceUrl: "",
    remoteImageUrl: "",
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
    inferredFromPhoto: false
  };
}

function buildFallbackNotes(input: NormalizerInput): string {
  if (input.mode === "url") {
    return "Recette reconstituée avec le parseur de secours du backend.";
  }

  if (input.mode === "photo") {
    return "Analyse photo limitée sans IA distante.";
  }

  return "Recette reconstituée avec le parseur de secours du backend.";
}
