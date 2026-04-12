import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { mkdtemp } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import ffmpegStatic from "ffmpeg-static";

import { env, requireProvider } from "../config/env.js";
import { fetchRemoteBuffer, fetchRemoteFile } from "./generalPageService.js";
import {
  recipeImportSchema,
  sanitizeRecipeImport,
  type NormalizerInput,
  type RecipeImportResult
} from "../types/recipe.js";
import { compactTextBlocks, truncate, uniqueStrings } from "../utils/text.js";

const recipeJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "title",
    "sourceUrl",
    "remoteImageUrl",
    "ingredientDrafts",
    "stepDrafts",
    "notesText",
    "prepTimeText",
    "cookTimeText",
    "servingsText",
    "caloriesText",
    "proteinText",
    "carbsText",
    "fatText",
    "confidence",
    "needsWebFallback",
    "searchQuery",
    "inferredFromPhoto"
  ],
  properties: {
    title: { type: "string" },
    sourceUrl: { type: "string" },
    creatorHandle: { type: "string" },
    remoteImageUrl: { type: "string" },
    ingredientDrafts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["amount", "unit", "name", "nutritionQuery"],
        properties: {
          amount: { type: "string" },
          unit: { type: "string" },
          name: { type: "string" },
          nutritionQuery: { type: "string" }
        }
      }
    },
    stepDrafts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["detail", "section"],
        properties: {
          detail: { type: "string" },
          section: { type: "string" }
        }
      }
    },
    notesText: { type: "string" },
    prepTimeText: { type: "string" },
    cookTimeText: { type: "string" },
    servingsText: { type: "string" },
    caloriesText: { type: "string" },
    proteinText: { type: "string" },
    carbsText: { type: "string" },
    fatText: { type: "string" },
    confidence: {
      type: "string",
      enum: ["low", "medium", "high"]
    },
    confidenceScore: {
      type: "number",
      minimum: 0,
      maximum: 1
    },
    needsWebFallback: { type: "boolean" },
    searchQuery: { type: "string" },
    inferredFromPhoto: { type: "boolean" },
    flags: {
      type: "object",
      additionalProperties: false,
      required: [
        "usedExplicitIngredients",
        "usedInferredIngredients",
        "generatedSteps",
        "generatedNutrition",
        "needsReview"
      ],
      properties: {
        usedExplicitIngredients: { type: "boolean" },
        usedInferredIngredients: { type: "boolean" },
        generatedSteps: { type: "boolean" },
        generatedNutrition: { type: "boolean" },
        needsReview: { type: "boolean" }
      }
    }
  }
} as const;
const execFileAsync = promisify(execFile);
const ffmpegPath = ffmpegStatic as unknown as string | null;

export async function normalizeRecipeFromContext(
  input: NormalizerInput,
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  requireProvider("openAI");
  const imageDataUrl = await resolveNormalizationImageDataUrl(input, options?.timeoutMs);

  const normalizedRecipe = await requestStructuredRecipeFromOpenAI({
    userPrompt: buildNormalizationPrompt(input),
    imageDataUrl,
    timeoutMs: options?.timeoutMs,
    systemInstructions: [
      "# RÔLE",
      "Tu reconstruis la recette EXACTE de la vidéo, PAS une recette générique du même plat.",
      "Le test de réussite : un utilisateur qui regarde la vidéo doit reconnaître TON titre, TES ingrédients et TES étapes comme étant ceux de la vidéo, pas une version standardisée trouvable sur Marmiton.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma. Écris en français.",
      "",
      "# PRINCIPE DE FIDÉLITÉ (LE PLUS IMPORTANT)",
      "La VIDÉO est la source de vérité absolue. Ta mission n'est PAS de générer une recette canonique du plat, mais de transcrire fidèlement ce que le cuisinier de la vidéo fait, avec ses ingrédients spécifiques et ses gestes signature.",
      "Tu n'inventes RIEN. Tu ne génériscises RIEN. Tu ne supprimes RIEN d'utile.",
      "Tu ne combles que les manques techniques triviaux (sel, poivre, huile de cuisson, eau, préchauffage évident).",
      "Si la vidéo n'est clairement pas alimentaire, renvoie un résultat vide avec confidence='low'.",
      "",
      "# SOURCES (HIÉRARCHIE STRICTE)",
      "1. **Digest audio structuré** (champs DISH, SPECIFICITY, INGREDIENTS_EXPLICIT, INGREDIENTS_IMPLIED, ACTIONS_SEQUENCE, SIGNATURE_GESTURES, NOISE_DETECTED) : SOURCE DE VÉRITÉ ABSOLUE quand il est présent. Tu DOIS le respecter intégralement. INGREDIENTS_EXPLICIT et ACTIONS_SEQUENCE sont à reproduire fidèlement.",
      "2. Légende / description / sous-titres / hashtags sociaux : confirment et complètent le digest.",
      "3. Transcript audio brut : référence pour les détails que le digest aurait laissés passer.",
      "4. Pages web fallback : SEULEMENT pour combler une recette identifiée mais incomplète. JAMAIS pour remplacer la recette de la vidéo par une version 'standard' du même plat.",
      "5. Connaissance générale du plat : DERNIER recours, uniquement pour des évidences techniques (sel, poivre, huile de cuisson, eau). JAMAIS pour des ingrédients signature.",
      "",
      "# RÈGLE ANTI-COPIE BRUTE",
      "Ne copie JAMAIS un fragment parlé brut dans `ingredientDraft.name` ou `stepDraft.detail`.",
      "Si un nom d'ingrédient ressemble à une phrase parlée ('à café', 'à soupe', 'ce moment-là', 'en plusieurs fois', 'papier journal', 'et après ça'), c'est un artefact : corrige-le ou jette-le.",
      "Interprète 'à café' = 'cuillère à café', 'à soupe' = 'cuillère à soupe'.",
      "Les ustensiles (papier, film, assiette, poêle, rouleau, spatule) ne sont JAMAIS des ingrédients.",
      "Aucun fragment listé dans NOISE_DETECTED du digest ne doit apparaître dans la recette.",
      "",
      "# TITRE",
      "Le titre = le nom complet et SPÉCIFIQUE du plat de la vidéo. JAMAIS un mot de catégorie seul.",
      "",
      "❌ 'Sandwich'             ✓ 'Philly cheesesteak'",
      "❌ 'Burger'               ✓ 'Smash burger cheddar bacon'",
      "❌ 'Pizza'                ✓ 'Pizza tartiflette à la poêle'",
      "❌ 'Tacos'                ✓ 'Tacos al pastor'",
      "❌ 'Salade'               ✓ 'Salade César au poulet grillé'",
      "❌ 'Pasta' / 'Pâtes'      ✓ 'Pâtes carbonara'",
      "❌ 'Wrap'                 ✓ 'Wrap poulet César'",
      "❌ 'Curry'                ✓ 'Butter chicken'",
      "",
      "Si DISH du digest est précis (SPECIFICITY=high), tu DOIS le réutiliser tel quel.",
      "Si DISH est vague mais que SIGNATURE_GESTURES ou INGREDIENTS_EXPLICIT révèlent le vrai plat, compose le titre depuis ces indices.",
      "Si même là c'est impossible : `needsWebFallback=true` + `searchQuery` riche basé sur head + ingrédients distinctifs.",
      "Pas de liste d'ingrédients dans le titre, pas de hashtags, pas d'URL. Si un auteur social est connu, renseigne `creatorHandle` au format @nom.",
      "",
      "# INGRÉDIENTS — RÈGLE DE FIDÉLITÉ",
      "**RÈGLE 1 (CRITIQUE)** — TOUT ingrédient présent dans INGREDIENTS_EXPLICIT du digest DOIT figurer dans `ingredientDrafts` avec le NOM EXACT prononcé. Interdiction absolue de génériciser :",
      "  ❌ 'provolone' → 'fromage'",
      "  ❌ 'baguette à hoagie' → 'pain'",
      "  ❌ 'ribeye' / 'entrecôte' → 'viande de bœuf'",
      "  ❌ 'Kiri' → 'fromage frais'",
      "  ❌ 'gochujang' → 'sauce piquante'",
      "  ❌ 'panko' → 'chapelure'",
      "  ❌ 'burrata' → 'mozzarella'",
      "",
      "**RÈGLE 2** — Tu peux AJOUTER des ingrédients seulement s'ils sont :",
      "  (a) techniquement nécessaires et triviaux (sel, poivre, huile de cuisson, eau),",
      "  (b) clairement implicites (sauter à la poêle ⇒ huile/beurre),",
      "  (c) listés dans INGREDIENTS_IMPLIED du digest.",
      "Tout ingrédient ajouté doit être marqué via `flags.usedInferredIngredients=true`.",
      "",
      "**RÈGLE 3** — Tu ne peux JAMAIS supprimer un ingrédient du digest sous prétexte qu'il 'complique' ou n'est 'pas standard' pour le plat. La vidéo a la priorité.",
      "",
      "**RÈGLE 4** — Quantités : reproduis celles prononcées. Sinon, estime de façon réaliste pour 4 portions et indique brièvement '(estimé)' dans `notesText`.",
      "",
      "**Format** — un seul ingrédient par objet `ingredientDraft`, jamais plusieurs fusionnés. Jamais '/', ',', '+', '&', 'et' ou '...' dans le `name`.",
      "`nutritionQuery` = nom court en anglais USDA (ex: 'provolone cheese', 'ribeye steak', 'gochujang').",
      "",
      "# ÉTAPES — RÈGLE DE FIDÉLITÉ",
      "**RÈGLE 1** — Les étapes DOIVENT suivre l'ordre et le contenu de ACTIONS_SEQUENCE du digest. Tu adaptes le style (impératif culinaire propre, max 2-3 phrases par étape) mais tu ne réinventes PAS la séquence.",
      "",
      "**RÈGLE 2** — Tout SIGNATURE_GESTURE du digest DOIT apparaître comme étape distincte avec son détail (ex : 'Aplatir le steak haché à la spatule sur la plancha brûlante 30 secondes pour obtenir une croûte caramélisée' — pas juste 'cuire le steak').",
      "",
      "**RÈGLE 3** — Tu peux ajouter des étapes UNIQUEMENT si elles sont :",
      "  (a) indispensables techniquement et absentes (préchauffer, repos, dressage),",
      "  (b) implicites visuellement.",
      "Tu marques alors `flags.generatedSteps=true`.",
      "",
      "**RÈGLE 4** — Aucune étape ne doit contenir : timestamps, flèches '-->', 'abonne-toi', 'bon app', 'lien en bio', hashtags, 'ce moment-là', phrases parlées brutes, ni d'éléments listés dans NOISE_DETECTED du digest.",
      "",
      "**RÈGLE 5** — Si ACTIONS_SEQUENCE contient moins de 4 actions, complète avec les phases implicites strictement nécessaires (préparation des ingrédients, cuisson, dressage) et marque `flags.generatedSteps=true`.",
      "",
      "Minimum 6 étapes pour un plat standard. Indique température et durée quand elles sont mentionnées dans le digest ou raisonnablement déductibles. Chaque étape = une seule action concrète.",
      "",
      "# SECTIONS",
      "Si la recette comporte des sous-préparations distinctes (Marinade, Sauce, Pâte, Garniture, Dressage), renseigne `section` pour la PREMIÈRE étape de chaque sous-préparation. Laisse vide pour une recette linéaire.",
      "",
      "# NUTRITION",
      "Obligatoire pour tout contenu alimentaire : `caloriesText`, `proteinText`, `carbsText`, `fatText` avec une estimation réaliste par portion, cohérente avec les ingrédients finaux.",
      "Vérifie la cohérence calories / macros ; corrige plutôt que renvoyer une nutrition vide.",
      "",
      "# FLAGS",
      "`flags.usedExplicitIngredients` = true si au moins un ingrédient vient du digest/texte explicite (devrait être true dans 99% des cas).",
      "`flags.usedInferredIngredients` = true si tu as ajouté des ingrédients non listés.",
      "`flags.generatedSteps` = true si tu as ajouté ou reformulé librement des étapes au-delà de ACTIONS_SEQUENCE.",
      "`flags.generatedNutrition` = true pour toute recette alimentaire.",
      "`confidenceScore` entre 0 et 1 selon la solidité du plat détecté et la part de déduction.",
      "",
      "# VALIDATION FINALE — FIDÉLITÉ (OBLIGATOIRE avant d'émettre le JSON)",
      "Vérifie ces 7 points point par point. Si l'un échoue, CORRIGE avant d'émettre :",
      "",
      "[FID-1] Chaque entrée de INGREDIENTS_EXPLICIT du digest est présente dans `ingredientDrafts` avec son nom spécifique. Si une entrée manque, AJOUTE-LA.",
      "[FID-2] Chaque entrée de ACTIONS_SEQUENCE du digest a un step correspondant dans le bon ordre. Si une étape manque, AJOUTE-LA.",
      "[FID-3] Chaque SIGNATURE_GESTURE du digest est présent dans une étape avec son détail.",
      "[FID-4] Aucun fragment de NOISE_DETECTED n'apparaît dans `title`, `ingredientDrafts`, `stepDrafts` ou `notesText`.",
      "[FID-5] Aucun nom d'ingrédient n'a été génériquisé (provolone→fromage, ribeye→bœuf, panko→chapelure, gochujang→sauce piquante, etc.).",
      "[FID-6] Le titre n'est pas un mot de catégorie seul (sandwich, burger, pizza, pasta, salade, tacos, wrap, bowl, curry, ramen, gratin, quiche, omelette).",
      "[FID-7] Si tu as ajouté des ingrédients/étapes au-delà du digest, `flags.usedInferredIngredients` et `flags.generatedSteps` sont à true et tu listes brièvement dans `notesText` ce qui est inféré.",
      "",
      "Ne renvoie JAMAIS une recette qui s'éloigne du digest sans raison technique justifiable. Si la recette est encore incomplète malgré le contexte, enrichis-la plutôt que d'activer `needsWebFallback` en échappatoire — sauf si le titre reste générique malgré tes efforts."
    ]
  });

  return sanitizeRecipeImport({
    ...normalizedRecipe,
    creatorHandle: normalizedRecipe.creatorHandle || input.socialAuthor
  });
}

export async function reviewRecipeCookability(
  input: {
    draft: RecipeImportResult;
    context: NormalizerInput;
  },
  options?: {
    timeoutMs?: number;
  }
): Promise<RecipeImportResult> {
  requireProvider("openAI");

  const sanitizedDraft = sanitizeRecipeImport(input.draft);
  const imageDataUrl = await resolveNormalizationImageDataUrl(input.context, options?.timeoutMs);

  const reviewedRecipe = await requestStructuredRecipeFromOpenAI({
    userPrompt: buildCookabilityReviewPrompt(sanitizedDraft, input.context),
    imageDataUrl,
    timeoutMs: options?.timeoutMs,
    systemInstructions: [
      "Tu relis une recette déjà structurée et tu vérifies qu'une personne peut réellement la cuisiner du début à la fin.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma.",
      "Écris en français.",
      "Commence par valider le plat détecté: si le titre n'est pas un vrai plat mais que le contexte culinaire en révèle un, remplace le titre par le nom du plat.",
      "Si le contexte n'est clairement pas alimentaire, renvoie un résultat vide et n'essaie pas de sauver artificiellement une recette.",
      "Le titre doit rester court, naturel et limité au nom du plat.",
      "Conserve creatorHandle quand un auteur social crédible est disponible.",
      "Ne garde que des ingrédients réellement utiles pour cuisiner le plat.",
      "Chaque objet ingredientDraft doit représenter un seul ingrédient. Si tu vois 'emmental/cornichon', 'sauce + salade' ou toute liste dans un seul name, sépare-les en plusieurs objets.",
      "Si la recette a moins de 3 ingrédients valides ou moins de 2 étapes valides, abandonne cette extraction faible et reconstruis une recette complète autour du plat détecté.",
      "Les étapes doivent couvrir la préparation, la cuisson et l'assemblage de façon suffisante pour que la recette soit faisable. Vise au minimum 6 étapes détaillées (idéalement 6 à 12 selon la complexité du plat) avec une seule action par étape.",
      "Revois les étapes à partir des ingrédients retenus: chaque ingrédient principal doit être utilisé ou explicitement signalé comme garniture.",
      "Ignore le style oral et les formulations de la vidéo: réécris les étapes proprement depuis la liste finale d'ingrédients au lieu de recopier ce qui est dit.",
      "Garde les ingrédients explicitement mentionnés quand ils sont plausibles, puis complète seulement les manques essentiels à partir du plat détecté.",
      "Si un ingrédient essentiel ou une étape essentielle manque mais est clairement implicite dans le contexte, ajoute-le.",
      "Si plusieurs sources web sont disponibles dans le contexte, compare-les et reconstruis une version cohérente du plat en gardant les ingrédients et étapes les plus récurrents.",
      "N'ajoute pas d'éléments fantaisistes: toute déduction doit être raisonnable et, si besoin, brièvement signalée dans notesText.",
      "Supprime tout bruit social, hashtags, URLs, outros, CTA et timestamps.",
      "Déduis prudemment les portions ou petites quantités implicites si cela rend la recette et la nutrition plus cohérentes.",
      "Renseigne confidenceScore entre 0 et 1 et mets à jour les flags pour refléter les ingrédients explicites, les ingrédients inférés, les étapes générées et la nutrition générée.",
      "Ne laisse jamais une recette alimentaire sans nutrition: estime toujours calories, protéines, glucides et lipides à partir de la version finale.",
      "Vérifie aussi que calories, protéines, glucides et lipides restent cohérents entre eux; si les macros ne collent pas raisonnablement avec les calories, corrige-les au lieu de vider la nutrition.",
      "Si la recette comporte des sous-préparations distinctes (marinade, sauce, pâte, garniture, dressage), renseigne le champ section de la première étape de chaque sous-préparation avec un label court comme 'Marinade', 'Sauce', 'Pâte', 'Garniture', 'Dressage'. Les étapes suivantes de la même sous-préparation ont section vide.",
      "Ne force pas de section si la recette suit un déroulé linéaire simple.",
      "Chaque étape de cuisson doit inclure la température ou l'intensité du feu quand c'est pertinent (par ex. 'à feu moyen', '180 °C').",
      "Chaque étape impliquant une durée doit mentionner un temps indicatif (par ex. '5 minutes', 'environ 10 min').",
      "Chaque ingrédient principal doit apparaître nommément dans au moins une étape. Vérifie cette règle avant de finaliser le JSON."
    ]
  });

  return sanitizeRecipeImport({
    ...reviewedRecipe,
    creatorHandle: reviewedRecipe.creatorHandle || sanitizedDraft.creatorHandle || input.context.socialAuthor
  });
}

/**
 * Pre-pass that turns a raw, speech-to-text French audio transcript into a
 * clean structured digest. The goal is to take cognitive load off the main
 * reconstruction call: the distiller fixes obvious transcription artifacts
 * (e.g. "à café" -> "cuillère à café"), drops filler/outro chunks, and hands
 * the normalizer a pre-cleaned list of dish name, ingredients, and actions.
 *
 * Returns `null` when the transcript is too short to be worth distilling or
 * when the LLM call fails: callers must fall back to the raw transcript.
 */
export async function distillTranscriptForRecipe(
  transcript: string,
  options?: {
    timeoutMs?: number;
    sourceUrl?: string;
    socialTitle?: string;
  }
): Promise<string | null> {
  const trimmed = transcript.trim();
  if (trimmed.length < 200) {
    return null;
  }

  requireProvider("openAI");

  const userPrompt = [
    "Voici la transcription audio brute d'une vidéo TikTok/Instagram de cuisine en français.",
    "Elle est parlée, bruyante, avec des répétitions, des phrases inachevées et des erreurs de reconnaissance vocale.",
    options?.socialTitle ? `Titre social : ${truncate(options.socialTitle, 180)}` : "",
    options?.sourceUrl ? `URL : ${options.sourceUrl}` : "",
    "",
    "Transcription :",
    truncate(trimmed, 6000),
    "",
    "MISSION : produire un digest STRUCTURÉ qui sera la source de vérité pour reconstruire la VRAIE recette de la vidéo (pas une recette générique).",
    "",
    "Tu dois extraire EXACTEMENT, en français, dans cet ordre, en respectant la mise en forme :",
    "",
    "1. DISH: le nom le plus PRÉCIS et COMPLET prononcé ou clairement identifiable.",
    "   - Conserve TOUS les descripteurs : nom régional ('Philly', 'napolitaine', 'thaï'), ingrédient signature ('cheddar bacon', 'truffe'), méthode ('smash', 'à la poêle'), origine.",
    "   - INTERDIT de simplifier en un mot de catégorie seul. ❌ 'Sandwich' / ✓ 'Philly cheesesteak'. ❌ 'Burger' / ✓ 'Smash burger cheddar bacon'. ❌ 'Pizza' / ✓ 'Pizza tartiflette à la poêle'.",
    "   - Si le cuisinier n'annonce pas le nom mais que les ingrédients/gestes le révèlent clairement, compose le nom toi-même à partir de ces indices.",
    "   - Si vraiment aucun descripteur n'est identifiable, écris 'INCONNU'.",
    "",
    "2. SPECIFICITY: un seul mot parmi 'high', 'medium', 'low'.",
    "   - 'high' = nom composé précis, clairement annoncé ou évident.",
    "   - 'medium' = plat reconnaissable mais avec hésitation.",
    "   - 'low' = mot générique seul ou plat indéterminé.",
    "",
    "3. INGREDIENTS_EXPLICIT: UNIQUEMENT les ingrédients réellement prononcés ou montrés dans la vidéo.",
    "   - Format : '- <nom exact prononcé, en français> [quantité si donnée] [marque si donnée]'",
    "   - Garde les noms SPÉCIFIQUES : 'provolone' (pas 'fromage'), 'baguette à hoagie' (pas 'pain'), 'ribeye' (pas 'bœuf'), 'gochujang' (pas 'sauce piquante'), 'panko' (pas 'chapelure'), 'Kiri' reste 'Kiri'.",
    "   - Corrige les artefacts de transcription : 'à café' → 'cuillère à café', 'à soupe' → 'cuillère à soupe', 'oeufs oeufs' → 'œufs'.",
    "   - Ne liste PAS d'éléments non comestibles (papier, film, assiette, poêle, spatule).",
    "   - Une seule occurrence par ingrédient.",
    "",
    "4. INGREDIENTS_IMPLIED: ingrédients NON prononcés mais techniquement nécessaires (sel, poivre, huile de cuisson, eau, beurre quand on voit faire revenir, etc.).",
    "   - Format : '- <ingrédient> (probable)'",
    "   - Reste très restrictif : seulement les évidences techniques.",
    "",
    "5. ACTIONS_SEQUENCE: la séquence EXACTE des actions du cuisinier, dans l'ordre, numérotée.",
    "   - Format : '1. <verbe à l'impératif> + <objet> + <détail> [+ durée/température si dits]'",
    "   - Reformule en style culinaire propre, NE recopie JAMAIS une phrase parlée brute.",
    "   - Inclus toutes les phases visibles : préparation, repos, façonnage, cuisson, friture, sauce, assemblage, dressage.",
    "   - Si une phase est techniquement implicite mais clairement nécessaire (ex: préchauffer, laisser reposer la pâte), ajoute-la.",
    "   - Préserve les détails distinctifs : températures, durées, retournements, gestes signature.",
    "",
    "6. SIGNATURE_GESTURES: les gestes ou techniques DISTINCTIFS de cette vidéo qui ne seraient pas dans une recette générique du même plat.",
    "   - Exemples : 'aplatir le steak à la spatule sur la plancha (smash)', 'flamber au cognac', 'griller la baguette au beurre face intérieure', 'caraméliser les oignons 20 minutes', 'panure double œuf-panko'.",
    "   - Format : '- <geste avec son détail spécifique>'",
    "   - Si rien de distinctif, laisse la section vide ('- aucun').",
    "",
    "7. NOISE_DETECTED: tous les éléments du transcript que tu as délibérément ignorés (pubs, calls-to-action, hors-sujet, bavardage).",
    "   - Liste explicitement : 'abonne-toi', 'like la vidéo', 'lien en bio', 'code promo', 'follow', 'swipe up', 'n'oublie pas de', 'fais-le toi-même', salutations, anecdotes hors-cuisine.",
    "   - Format : '- <fragment ignoré>'",
    "   - Cette section permettra de vérifier qu'aucun de ces fragments ne se retrouvera dans la recette finale.",
    "",
    "RÈGLES STRICTES :",
    "- Ne mélange JAMAIS un élément de NOISE_DETECTED dans une autre section.",
    "- Ne génériscise JAMAIS un nom d'ingrédient prononcé.",
    "- Ne saute aucune section (laisse vide avec '- aucun' si rien à mettre).",
    "",
    "Format de sortie EXACT (texte brut, sans JSON, sans markdown, sans introduction) :",
    "",
    "DISH: <nom complet et précis>",
    "SPECIFICITY: <high|medium|low>",
    "",
    "INGREDIENTS_EXPLICIT:",
    "- <ingrédient 1 avec quantité si donnée>",
    "- <ingrédient 2>",
    "",
    "INGREDIENTS_IMPLIED:",
    "- <ingrédient implicite 1> (probable)",
    "",
    "ACTIONS_SEQUENCE:",
    "1. <action 1>",
    "2. <action 2>",
    "",
    "SIGNATURE_GESTURES:",
    "- <geste distinctif 1>",
    "",
    "NOISE_DETECTED:",
    "- <fragment ignoré 1>"
  ].filter(Boolean).join("\n");

  const systemPrompt = [
    "Tu es un assistant spécialisé en analyse de transcripts audio de recettes de cuisine en français.",
    "Ton unique rôle est de produire un DIGEST STRUCTURÉ qui sera la source de vérité pour reconstruire la VRAIE recette de la vidéo.",
    "Tu ne rédiges JAMAIS la recette finale, tu produis seulement le digest.",
    "Réponds en texte brut, sans introduction, sans markdown, sans JSON, sans commentaires, en suivant EXACTEMENT le format demandé.",
    "Tu dois corriger silencieusement les erreurs évidentes de reconnaissance vocale française (ex: 'à café' = 'cuillère à café').",
    "PRINCIPE DE FIDÉLITÉ : la vidéo est la source de vérité. Tu n'inventes RIEN, tu ne génériscises RIEN, tu ne supprimes RIEN d'utile.",
    "Tu sépares STRICTEMENT ce qui est explicite (prononcé/montré) de ce qui est implicite (inféré techniquement)."
  ].join("\n");

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: env.OPENAI_RECIPE_MODEL,
        temperature: 0.1,
        max_output_tokens: 2500,
        input: [
          {
            role: "system",
            content: [{ type: "input_text", text: systemPrompt }]
          },
          {
            role: "user",
            content: [{ type: "input_text", text: userPrompt }]
          }
        ]
      }),
      signal: AbortSignal.timeout(options?.timeoutMs ?? 12_000)
    });

    if (!response.ok) {
      return null;
    }

    const json = await response.json() as Record<string, unknown>;
    const text = resolveOpenAIOutputText(json);
    if (!text) {
      return null;
    }

    const cleaned = text.trim();
    return cleaned.length > 40 ? cleaned : null;
  } catch {
    return null;
  }
}

export async function transcribeMediaFromUrl(
  mediaUrl?: string,
  options?: {
    mediaFetchTimeoutMs?: number;
    transcriptionTimeoutMs?: number;
    maxDurationSeconds?: number;
    maxFileBytes?: number;
  }
): Promise<string | null> {
  if (!mediaUrl) {
    return null;
  }

  requireProvider("openAI");

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), "cooksy-media-"));
  const sourcePath = path.join(tempDirectory, "source.bin");
  const audioPath = path.join(tempDirectory, "audio.m4a");
  const maxFileBytes = options?.maxFileBytes ?? 40 * 1024 * 1024;

  try {
    const videoBuffer = await fetchRemoteBuffer(mediaUrl, maxFileBytes, {
      timeoutMs: options?.mediaFetchTimeoutMs
    });
    await fs.writeFile(sourcePath, videoBuffer);
    await extractAudio(sourcePath, audioPath, {
      maxDurationSeconds: options?.maxDurationSeconds
    });

    const audioBuffer = await fs.readFile(audioPath);
    if (audioBuffer.byteLength === 0 || audioBuffer.byteLength > 25 * 1024 * 1024) {
      return null;
    }

    const formData = new FormData();
    formData.append("model", env.OPENAI_TRANSCRIPTION_MODEL);
    formData.append("file", new File([audioBuffer], "cooksy-audio.m4a", { type: "audio/mp4" }));
    formData.append("language", "fr");
    formData.append(
      "prompt",
      "Transcription d'une vidéo de recette de cuisine en français (parfois mots anglais). Vocabulaire attendu : farine, levure, eau, sel, sucre, œufs, beurre, huile d'olive, ail, oignon, échalote, poulet, bœuf, porc, agneau, poisson, saumon, thon, cabillaud, crevettes, tomate, courgette, aubergine, fromage, yaourt, crème, lait, basilic, persil, coriandre, paprika, cumin, curcuma, gingembre, poivre, chapelure, panko, mayonnaise, sauce, épices cajuns, Sriracha, gochujang, miso, dashi, mirin, soja, sésame, miel, sirop d'érable, ketchup, moutarde. Plats internationaux : Philly cheesesteak, smash burger, cheeseburger, hoagie, birria, tacos al pastor, quesadilla, enchilada, fajitas, burrito, gyros, shawarma, kebab, falafel, hummus, pita, naan, butter chicken, tikka masala, curry rouge, pad thaï, ramen, pho, bibimbap, kimchi, gyoza, sushi, poke bowl, carbonara, bolognese, lasagne, gnocchi, risotto, focaccia, bruschetta, tiramisu, chimichurri, tzatziki, tahini, pesto, ratatouille, cassoulet, tartiflette, raclette, croque-monsieur, quiche lorraine. Fromages spécifiques : provolone, mozzarella, burrata, ricotta, mascarpone, parmesan, pecorino, gorgonzola, gruyère, comté, emmental, reblochon, raclette, brie, camembert, chèvre, feta, halloumi, manchego, cheddar, monterey jack. Marques fréquentes : Kiri, Boursin, Philadelphia, Knorr, Maggi, Tabasco, Heinz, Hellmann's, Lay's, Doritos. Coupes de viande : entrecôte, faux-filet, ribeye, picanha, bavette, onglet, paleron, joue de bœuf, jarret, magret, suprême. Charcuteries : prosciutto, pancetta, chorizo, salami, jambon de Parme, lardons, bacon, guanciale. Unités : cuillère à soupe, cuillère à café, pincée, gramme, kilo, litre, millilitre, tasse, verre. Verbes : préparer, mélanger, ajouter, cuire, faire revenir, pétrir, laisser reposer, étaler, frire, dorer, assaisonner, couper, éplucher, émincer, saler, poivrer, servir, smasher, caraméliser, déglacer, flamber, mariner, paner, paner, glacer, napper, poêler, rôtir, mijoter, blanchir."
    );

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.OPENAI_API_KEY}`
      },
      body: formData,
      signal: AbortSignal.timeout(options?.transcriptionTimeoutMs ?? 60_000)
    });

    if (!response.ok) {
      return null;
    }

    const json = await response.json() as { text?: string };
    return json.text?.trim() || null;
  } finally {
    await fs.rm(tempDirectory, { recursive: true, force: true });
  }
}

function buildNormalizationPrompt(input: NormalizerInput): string {
  const structuredDataText = input.pageStructuredData?.length
    ? compactTextBlocks(input.pageStructuredData.slice(0, 2), 2400)
    : "";
  const socialTextBlocks = uniqueStrings([
    input.sharedText,
    input.socialCaption,
    input.socialDescription,
    input.socialPageText,
    input.socialSubtitles
  ]);
  const primarySocialText = socialTextBlocks[0];
  const secondarySocialText = socialTextBlocks[1];
  const tertiarySocialText = socialTextBlocks[2];
  const isSparseSocialText = !primarySocialText || primarySocialText.length < 50;
  const hasDigest = Boolean(input.transcriptDigest && input.transcriptDigest.trim().length > 40);
  const transcriptLabel = hasDigest
    ? "Transcription audio brute (référence secondaire, déjà résumée dans le digest ci-dessus)"
    : isSparseSocialText
      ? "Source principale (audio)"
      : "Transcription audio";

  return [
    `Mode d'import : ${input.mode}`,
    input.sourceUrl ? `URL source : ${input.sourceUrl}` : "",
    input.remoteImageUrl ? `Image distante probable : ${input.remoteImageUrl}` : "",
    input.pageTitle ? `Titre page : ${truncate(input.pageTitle, 180)}` : "",
    input.pageDescription ? `Description page : ${truncate(input.pageDescription, 420)}` : "",
    input.socialTitle ? `Titre social : ${truncate(input.socialTitle, 180)}` : "",
    input.socialAuthor ? `Auteur social : ${truncate(input.socialAuthor, 80)}` : "",
    primarySocialText ? `Texte social principal : ${truncate(primarySocialText, 1800)}` : "",
    secondarySocialText ? `Contexte social secondaire : ${truncate(secondarySocialText, 900)}` : "",
    tertiarySocialText ? `Contexte social additionnel : ${truncate(tertiarySocialText, 700)}` : "",
    hasDigest
      ? `Digest audio nettoyé (SOURCE PRIORITAIRE pour plat, ingrédients et séquence d'étapes) :\n${truncate(input.transcriptDigest!.trim(), 2200)}`
      : "",
    input.transcript ? `${transcriptLabel} : ${truncate(input.transcript, 2600)}` : "",
    input.pageTextContent ? `Texte web / sources : ${truncate(input.pageTextContent, 2200)}` : "",
    structuredDataText ? `Données structurées : ${structuredDataText}` : "",
    [
      "Consignes opérationnelles (le system prompt définit la stratégie de fidélité, ces consignes sont de l'opérationnel) :",
      "- Si le digest audio structuré est présent dans le contexte, c'est ta SOURCE DE VÉRITÉ : applique la VALIDATION FINALE FID-1 à FID-7.",
      "- Si le digest est absent, exploite directement la transcription audio brute, puis la légende, puis les sources web. Même hiérarchie de fidélité.",
      "- Préserve toujours les ingrédients spécifiques nommés (provolone, panko, gochujang, ribeye, burrata, Kiri…) — ne les remplace JAMAIS par des génériques.",
      "- nutritionQuery = nom court en anglais USDA.",
      "- searchQuery = requête courte exploitable basée sur le nom de plat précis + ingrédients distinctifs (ex: 'philly cheesesteak provolone hoagie'), pas juste 'sandwich'.",
      "- Pour tout contenu culinaire, fournis toujours calories, protéines, glucides et lipides cohérents avec les ingrédients finaux.",
      "- Pas de timestamps, flèches '-->', URLs, hashtags, boutons, pubs, 'Read More', 'View post', 'abonne-toi', 'lien en bio' dans le titre/ingrédients/étapes.",
      "- Si tu déduis un ingrédient ou une quantité absente, signale-le brièvement dans notesText.",
      "- Si le titre reste générique malgré le contexte, mets needsWebFallback=true et formule un searchQuery riche."
    ].join("\n")
  ]
    .filter(Boolean)
    .join("\n\n");
}

function buildCookabilityReviewPrompt(
  draft: RecipeImportResult,
  context: NormalizerInput
): string {
  return [
    "Recette structurée actuelle :",
    JSON.stringify(draft, null, 2),
    "",
    "Contexte source :",
    buildNormalizationPrompt(context),
    "",
    "Checklist obligatoire :",
    "- Vérifie si la recette est réellement faisable du début à la fin.",
    "- Vérifie qu'aucun ingredientDraft ne contient plusieurs ingrédients fusionnés; si c'est le cas, sépare-les.",
    "- Si des ingrédients essentiels manquent, ajoute-les quand ils sont clairement implicites dans le titre, la légende, la transcription, les données structurées ou l'image.",
    "- Si plusieurs sources web sont présentes, compare-les et garde la version la plus cohérente entre elles.",
    "- N'imite jamais le ton parlé de la vidéo et ne recopie pas ses phrases : transforme en vraie méthode de recette.",
    "- Si des étapes essentielles manquent, ajoute-les dans le bon ordre pour qu'un client puisse vraiment cuisiner le plat.",
    "- Supprime tout texte social, CTA, hashtags, commentaires, timestamps et formulations inutiles.",
    "- Si tu fais une déduction raisonnable, note-le brièvement dans notesText.",
    "- Vérifie que calories, protéines, glucides et lipides restent cohérents entre eux ; corrige plutôt que renvoyer une nutrition vide.",
    "",
    "CHECKLIST FIDÉLITÉ VIDÉO (en plus de la cookabilité — applique-la si un digest audio structuré est présent dans le contexte) :",
    "",
    "1. Compare `title` aux champs DISH et SIGNATURE_GESTURES du digest. Si le titre est plus générique que ce que le digest permettait (ex: titre = 'Sandwich' alors que DISH = 'Philly cheesesteak'), REMPLACE-LE par le DISH précis.",
    "",
    "2. Pour chaque entrée de INGREDIENTS_EXPLICIT du digest, vérifie qu'elle est dans `ingredientDrafts` avec son nom EXACT. Si 'provolone' est dans le digest et 'fromage' est dans la recette, CORRIGE en 'provolone'. Pareil pour 'panko'/'chapelure', 'ribeye'/'bœuf', 'gochujang'/'sauce piquante', 'baguette à hoagie'/'pain', 'burrata'/'mozzarella', 'Kiri'/'fromage frais'.",
    "",
    "3. Vérifie que la séquence `stepDrafts` respecte l'ordre de ACTIONS_SEQUENCE. Réordonne si nécessaire.",
    "",
    "4. Vérifie que tous les SIGNATURE_GESTURES sont présents dans une étape avec leur détail. Sinon, ajoute les étapes manquantes dans le bon ordre.",
    "",
    "5. Supprime de title/ingredientDrafts/stepDrafts/notesText tout terme listé dans NOISE_DETECTED qui aurait fui dans la recette ('abonne-toi', 'lien en bio', 'code promo', etc.).",
    "",
    "6. Le titre n'est jamais un mot de catégorie seul (sandwich, burger, pizza, pasta, salade, tacos, wrap, bowl, curry, ramen, gratin, quiche, omelette). S'il l'est, recompose un titre précis depuis DISH ou les ingrédients distinctifs.",
    "",
    "7. Si après corrections la recette est toujours plus générique que le digest et que tu ne peux pas la corriger toi-même, mets `confidence='low'`, `needsWebFallback=true` et fournis un `searchQuery` précis basé sur DISH + 2-3 ingrédients distinctifs."
  ].join("\n");
}

async function requestStructuredRecipeFromOpenAI(input: {
  userPrompt: string;
  imageDataUrl?: string;
  timeoutMs?: number;
  systemInstructions: string[];
}): Promise<RecipeImportResult> {
  const contents: Array<Record<string, string>> = [
    {
      type: "input_text",
      text: input.userPrompt
    }
  ];

  if (input.imageDataUrl) {
    contents.push({
      type: "input_image",
      image_url: input.imageDataUrl
    });
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${env.OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: env.OPENAI_RECIPE_MODEL,
      temperature: 0.2,
      max_output_tokens: 4000,
      input: [
        {
          role: "system",
          content: [
            {
              type: "input_text",
              text: input.systemInstructions.join("\n")
            }
          ]
        },
        {
          role: "user",
          content: contents
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "cooksy_recipe_import",
          schema: recipeJsonSchema,
          strict: true
        }
      }
    }),
    signal: AbortSignal.timeout(input.timeoutMs ?? 60_000)
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI normalization failed (${response.status}): ${errorBody}`);
  }

  const json = await response.json() as Record<string, unknown>;
  const outputText = resolveOpenAIOutputText(json);
  if (!outputText) {
    console.error(
      "[openAIService] Unexpected OpenAI response structure:",
      JSON.stringify(json).slice(0, 800)
    );
    throw new Error("OpenAI normalization returned an empty output_text payload.");
  }

  const parsed = recipeImportSchema.parse(JSON.parse(outputText));
  return sanitizeRecipeImport(parsed);
}

async function extractAudio(
  sourcePath: string,
  destinationPath: string,
  options?: {
    maxDurationSeconds?: number;
  }
): Promise<void> {
  if (!ffmpegPath) {
    throw new Error("ffmpeg-static is not available.");
  }

  await execFileAsync(ffmpegPath, [
    "-y",
    "-i",
    sourcePath,
    "-vn",
    "-ac",
    "1",
    "-ar",
    "16000",
    "-t",
    String(options?.maxDurationSeconds ?? 180),
    "-c:a",
    "aac",
    "-b:a",
    "96k",
    destinationPath
  ]);
}

async function resolveNormalizationImageDataUrl(
  input: Pick<NormalizerInput, "imageDataUrl" | "remoteImageUrl">,
  timeoutMs?: number
): Promise<string | undefined> {
  if (input.imageDataUrl?.trim()) {
    return input.imageDataUrl;
  }

  if (!input.remoteImageUrl?.trim()) {
    return undefined;
  }

  const imageTimeoutMs = boundedImageFetchTimeout(timeoutMs);
  if (!imageTimeoutMs) {
    return undefined;
  }

  try {
    const payload = await fetchRemoteFile(input.remoteImageUrl, 5 * 1024 * 1024, {
      timeoutMs: imageTimeoutMs
    });
    const mimeType = normalizedImageMimeType(payload.contentType, input.remoteImageUrl);
    if (!mimeType) {
      return undefined;
    }

    return `data:${mimeType};base64,${payload.buffer.toString("base64")}`;
  } catch {
    return undefined;
  }
}

function boundedImageFetchTimeout(timeoutMs?: number): number | undefined {
  if (!timeoutMs) {
    return 4_000;
  }

  if (timeoutMs < 3_500) {
    return undefined;
  }

  return Math.max(1_500, Math.min(4_000, Math.floor(timeoutMs * 0.2)));
}

function normalizedImageMimeType(contentType?: string, url?: string): string | undefined {
  const rawType = contentType?.split(";")[0]?.trim().toLowerCase();
  if (rawType?.startsWith("image/")) {
    return rawType;
  }

  const lowercaseUrl = url?.toLowerCase() ?? "";
  if (lowercaseUrl.includes(".png")) {
    return "image/png";
  }
  if (lowercaseUrl.includes(".webp")) {
    return "image/webp";
  }
  if (lowercaseUrl.includes(".gif")) {
    return "image/gif";
  }
  if (lowercaseUrl.includes(".heic") || lowercaseUrl.includes(".heif")) {
    return "image/heic";
  }
  if (lowercaseUrl.includes(".avif")) {
    return "image/avif";
  }

  return "image/jpeg";
}

function resolveOpenAIOutputText(json: Record<string, unknown>): string | undefined {
  // Top-level convenience property (most common)
  if (typeof json.output_text === "string" && json.output_text.trim()) {
    return json.output_text.trim();
  }

  // Nested structure: output[].content[].text
  if (Array.isArray(json.output)) {
    for (const outputItem of json.output) {
      if (!outputItem || typeof outputItem !== "object") {
        continue;
      }

      const item = outputItem as Record<string, unknown>;

      // Direct text on output item
      if (typeof item.text === "string" && item.text.trim()) {
        return item.text.trim();
      }

      // Nested content array
      if (Array.isArray(item.content)) {
        for (const contentItem of item.content) {
          if (!contentItem || typeof contentItem !== "object") {
            continue;
          }

          const content = contentItem as Record<string, unknown>;
          if (typeof content.text === "string" && content.text.trim()) {
            return content.text.trim();
          }
        }
      }
    }
  }

  return undefined;
}
