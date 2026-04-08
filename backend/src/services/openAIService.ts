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
        "generatedNutrition"
      ],
      properties: {
        usedExplicitIngredients: { type: "boolean" },
        usedInferredIngredients: { type: "boolean" },
        generatedSteps: { type: "boolean" },
        generatedNutrition: { type: "boolean" }
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
      "Tu transformes du contenu social (TikTok, Instagram), des photos et des textes libres en recettes de cuisine réellement exploitables.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma. Écris en français.",
      "",
      "# PRINCIPE FONDAMENTAL",
      "Ta sortie doit permettre à un utilisateur de cuisiner le plat de A à Z SANS regarder la vidéo source. Tu RECONSTRUIS une recette propre, tu ne résumes pas le transcript.",
      "Si le contenu n'est clairement pas alimentaire, renvoie un résultat vide avec confidence='low'.",
      "Dès qu'un plat crédible est identifié, reconstruis une recette complète autour de ce plat — n'abandonne jamais au milieu.",
      "",
      "# SOURCES (ORDRE DE PRIORITÉ)",
      "1. Digest audio nettoyé (`Digest audio nettoyé` dans le contexte) : c'est la source PRIORITAIRE quand il est présent. Il contient déjà le plat, les ingrédients et les actions dans l'ordre.",
      "2. Légende / description / sous-titres / hashtags sociaux : confirment le plat et les quantités.",
      "3. Transcript audio brut : référence SECONDAIRE quand le digest est présent. N'utilise le transcript brut comme source principale QUE si le digest est absent.",
      "4. Titre / image / données structurées page : complètent quand le reste est sparse.",
      "",
      "# RÈGLE ANTI-COPIE (CRITIQUE)",
      "Ne copie JAMAIS un fragment textuel brut du transcript audio dans `ingredientDraft.name` ou `stepDraft.detail`.",
      "Si un nom d'ingrédient ressemble à une phrase parlée ('à café', 'à soupe', 'ce moment-là', 'en plusieurs fois', 'papier journal', 'et après ça'), c'est un artefact de transcription : corrige-le ou jette-le.",
      "Interprète 'à café' comme 'cuillère à café', 'à soupe' comme 'cuillère à soupe', et reconstitue les quantités correctement.",
      "Les ustensiles (papier, film, assiette, poêle, rouleau) ne sont JAMAIS des ingrédients.",
      "",
      "# TITRE",
      "Court, naturel, limité au nom du plat. Pas de liste d'ingrédients, pas de hashtags, pas d'URL.",
      "Si le transcript audio mentionne un nom composé précis ('pizza tartiflette à la poêle', 'sandwich naan au poulet frit', 'smash burger au cheddar'), utilise ce nom EXACT, pas une version simplifiée comme 'pizza' ou 'burger'.",
      "Si un auteur social est connu, renseigne `creatorHandle` au format @nom.",
      "",
      "# INGRÉDIENTS",
      "Normalise chaque ingrédient en `{amount, unit, name, nutritionQuery}`.",
      "Un seul ingrédient par objet `ingredientDraft`. Jamais '/', ',', '+', '&', 'et' ou '...' dans le `name`.",
      "`nutritionQuery` = requête USDA courte en anglais (ex: 'olive oil', 'chicken breast', 'smoked paprika').",
      "D'abord les ingrédients explicitement mentionnés dans le digest / la légende / les sous-titres. Ensuite seulement, complète avec des ingrédients standards crédibles pour le plat détecté.",
      "Pour un plat non-trivial, vise au minimum 5 ingrédients réalistes ; pour un plat complet avec sauce et garniture, 10-15 ingrédients est normal.",
      "Si l'extraction explicite donne moins de 3 ingrédients valides, reconstruis une liste complète à partir du plat détecté.",
      "",
      "# ÉTAPES",
      "Chaque étape = une seule action concrète, courte, actionnable, culinaire. Pas de commentaires, pas d'oral, pas d'outros.",
      "Minimum 8 étapes pour un plat standard, 10-13 pour un plat complet avec plusieurs sous-préparations (pâte, cuisson, panure, friture, sauce, assemblage).",
      "Décompose les étapes longues en micro-étapes : 'Préparer la pâte' → 'Mélanger la farine et le sel', 'Ajouter l'eau tiède et la levure', 'Pétrir 10 minutes', 'Laisser reposer 1 heure'.",
      "Couvre TOUJOURS toutes les phases implicites par les ingrédients : si la liste contient farine + levure, il DOIT y avoir une phase de préparation de pâte et de repos. Si elle contient viande crue + chapelure, il DOIT y avoir panure + friture. Si elle contient beurre + sauce piquante + miel, il DOIT y avoir une étape de préparation de sauce.",
      "Après avoir finalisé la liste d'ingrédients, réécris toutes les étapes DEPUIS ZÉRO en te basant sur cette liste. Chaque ingrédient principal doit apparaître nommément dans au moins une étape.",
      "Indique la température ou l'intensité du feu quand c'est pertinent ('à feu moyen', '180 °C').",
      "Indique un temps indicatif quand une durée est impliquée ('5 minutes', 'environ 10 min').",
      "Ne recopie JAMAIS d'horodatage, flèches VTT, hashtags, 'bon app', 'abonne-toi' ou phrases oralisées.",
      "",
      "# SECTIONS",
      "Si la recette comporte des sous-préparations distinctes (Marinade, Sauce, Pâte, Garniture, Dressage), renseigne `section` pour la PREMIÈRE étape de chaque sous-préparation avec un label court. Laisse `section` vide pour les étapes suivantes du même bloc.",
      "Ne force pas de sections pour une recette linéaire simple.",
      "",
      "# NUTRITION",
      "Obligatoire pour tout contenu alimentaire : renseigne `caloriesText`, `proteinText`, `carbsText`, `fatText` avec une estimation réaliste par portion, cohérente avec les ingrédients et les quantités de la recette finale.",
      "Vérifie que calories / protéines / glucides / lipides sont cohérents entre eux ; corrige plutôt que renvoyer une nutrition vide.",
      "",
      "# FLAGS",
      "`flags.usedExplicitIngredients` = true si au moins un ingrédient vient du texte/digest explicite.",
      "`flags.usedInferredIngredients` = true si tu as ajouté des ingrédients plausibles non listés.",
      "`flags.generatedSteps` = true si tu as réécrit ou reconstruit les étapes.",
      "`flags.generatedNutrition` = true pour toute recette alimentaire.",
      "`confidenceScore` entre 0 et 1 selon la solidité du plat détecté et la part de déduction.",
      "",
      "# VALIDATION FINALE (OBLIGATOIRE avant d'émettre le JSON)",
      "1. Le titre est un vrai nom de plat court.",
      "2. Aucun ingrédient ne ressemble à un fragment de transcript ('à café', 'ce moment', 'papier journal', etc.).",
      "3. Aucune étape ne contient de 'à ce moment-là', de double virgule, ni de liste à la Bonnet d'ingrédients mélangés ('ajoute pain, farine, sucre, œufs, mayo').",
      "4. Chaque phase implicite par la liste d'ingrédients est présente dans les étapes.",
      "5. Chaque ingrédient principal apparaît nommément dans au moins une étape.",
      "6. La nutrition est renseignée et cohérente.",
      "Si la recette est encore incomplète malgré le contexte, enrichis-la plutôt que d'activer `needsWebFallback` en échappatoire."
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
      "Les étapes doivent couvrir la préparation, la cuisson et l'assemblage de façon suffisante pour que la recette soit faisable. Vise au minimum 8 étapes détaillées avec une seule action par étape.",
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
    "Voici la transcription audio brute d'une vidéo TikTok de cuisine en français.",
    "Elle est parlée, bruyante, avec des répétitions, des phrases inachevées et des erreurs de reconnaissance vocale.",
    options?.socialTitle ? `Titre social : ${truncate(options.socialTitle, 180)}` : "",
    options?.sourceUrl ? `URL : ${options.sourceUrl}` : "",
    "",
    "Transcription :",
    truncate(trimmed, 4000),
    "",
    "Extrais UNIQUEMENT, en français, et dans cet ordre :",
    "1. DISH: le nom du plat tel que le cuisinier l'identifie (court, naturel, par ex. 'Sandwich naan au poulet frit').",
    "2. INGREDIENTS: la liste des ingrédients réellement mentionnés par le cuisinier, un par ligne, format '- <nom propre> [quantité si donnée]'.",
    "   - Corrige les artefacts de transcription évidents : 'à café' → 'cuillère à café', 'à soupe' → 'cuillère à soupe', 'oeufs oeufs' → 'œufs', 'Kiri' reste 'Kiri', etc.",
    "   - Ne liste PAS d'éléments non comestibles (papier journal, film, assiette…).",
    "   - Ne liste qu'une seule fois chaque ingrédient, même s'il apparaît dans plusieurs étapes.",
    "3. ACTIONS: la séquence ordonnée des actions culinaires décrites (une ligne par action, format '- <verbe à l'impératif> …').",
    "   - Ne recopie AUCUNE phrase du transcript telle quelle : reformule en style culinaire propre.",
    "   - Inclus toutes les phases que le cuisinier exécute (préparation, repos, façonnage, cuisson, friture, sauce, assemblage, dressage).",
    "   - Si une phase est implicite mais clairement nécessaire (ex: laisser reposer la pâte), ajoute-la.",
    "",
    "Format de sortie attendu (texte brut, sans JSON, sans markdown) :",
    "DISH: <nom du plat>",
    "",
    "INGREDIENTS:",
    "- <ingrédient 1>",
    "- <ingrédient 2>",
    "",
    "ACTIONS:",
    "- <action 1>",
    "- <action 2>"
  ].filter(Boolean).join("\n");

  const systemPrompt = [
    "Tu es un assistant spécialisé en reformulation de transcripts audio de recettes de cuisine en français.",
    "Ton unique rôle est de nettoyer un transcript bruité et d'en extraire le nom du plat, les ingrédients et les actions.",
    "Tu ne rédiges JAMAIS la recette finale, tu produis seulement un digest.",
    "Réponds en texte brut, sans introduction, sans markdown, sans JSON, sans commentaires.",
    "Tu dois corriger silencieusement les erreurs évidentes de reconnaissance vocale française (ex: 'à café' = 'cuillère à café')."
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
        max_output_tokens: 1500,
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
      "Transcription d'une vidéo de recette de cuisine en français. Vocabulaire attendu : farine, levure, eau, sel, sucre, œufs, beurre, huile d'olive, ail, oignon, poulet, bœuf, poisson, tomate, fromage, yaourt, crème, lait, basilic, persil, paprika, poivre, chapelure, mayonnaise, sauce, épices cajuns, Sriracha, miel, ketchup, moutarde. Unités : cuillère à soupe, cuillère à café, pincée, gramme, kilo, litre, millilitre, tasse, verre. Verbes : préparer, mélanger, ajouter, cuire, faire revenir, pétrir, laisser reposer, étaler, frire, dorer, assaisonner, couper, éplucher, émincer, saler, poivrer, servir."
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
      "Consignes métier :",
      "- Donne un titre court et naturel, par exemple 'Smash burger simple'.",
      "- Si un titre social contient aussi des ingrédients, garde uniquement le nom du plat.",
      "- Garde uniquement des ingrédients utiles à cuisiner, un ingrédient par ligne.",
      "- nutritionQuery doit être un nom d'aliment court en anglais exploitable par USDA.",
      "- Donne des étapes actionnables, numérotables et pas trop longues.",
      "- Avant de t'arrêter, vérifie qu'une personne peut vraiment refaire la recette avec ce que tu fournis.",
      "- Si la recette n'est pas faisable telle quelle, ajoute les ingrédients ou étapes essentiels qui sont clairement implicites dans le contexte.",
      "- La transcription audio sert d'indice principal quand le texte social est court ou absent: identifie le plat, les ingrédients et les quantités mentionnés à l'oral, puis reformule les étapes dans un style culinaire propre.",
      "- Si le transcript audio mentionne un nom de plat précis (ex: 'pizza tartiflette à la poêle', 'smash burger au cheddar'), conserve ce nom composé exact comme titre final, pas une version simplifiée comme 'pizza' ou 'burger'.",
      "- Si le transcript audio décrit des ingrédients spécifiques (lardons, reblochon, crème fraîche, cheddar fondu, oignons caramélisés), utilise exactement ces ingrédients et ne les remplace pas par des ingrédients génériques du plat de base.",
      "- Une fois la liste des ingrédients finalisée, réécris les étapes depuis zéro en fonction de ces ingrédients et d'un déroulé culinaire logique.",
      "- Si des quantités ménagères simples ou le nombre de portions sont évidents, complète-les prudemment au lieu de laisser une recette inutilisable.",
      "- Si tu déduis un ingrédient ou une quantité absente du texte brut, signale-le brièvement dans notesText.",
      "- Si le plat est identifiable mais que la recette est trop incomplète, formule searchQuery autour du nom du plat pour permettre une vraie recherche web de secours.",
      "- Si plusieurs sources web sont présentes dans le contexte, compare-les et synthétise la version la plus cohérente et la plus commune du plat.",
      "- La nutrition doit dépendre de la recette finale et de ses quantités, jamais de la vidéo seule.",
      "- Pour tout contenu culinaire, fournis toujours calories, protéines, glucides et lipides avec une estimation réaliste et cohérente par portion.",
      "- Ne mets jamais de timestamps, de flèches '-->', d'URLs ou de hashtags dans le titre, les ingrédients ou les étapes.",
      "- Ignore les boutons, pubs, 'Read More', 'View post', hashtags et textes people/news/fashion/travel.",
      "- Si le contenu décrit seulement un plat ou une photo, infère une recette maison plausible.",
      "- Note dans notesText ce qui est une déduction ou ce qui manque.",
      "- searchQuery doit être une requête courte exploitable si une recherche web est nécessaire."
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
    "- Si plusieurs sources web sont présentes, compare-les et garde la version des ingrédients et des étapes la plus cohérente entre elles.",
    "- Réécris les étapes pour qu'elles suivent la liste d'ingrédients finale et qu'elles utilisent chaque ingrédient principal.",
    "- N'imite jamais le ton parlé de la vidéo et ne recopie pas ses phrases: transforme le tout en vraie méthode de recette.",
    "- Si des étapes essentielles manquent, ajoute-les dans le bon ordre pour qu'un client puisse vraiment cuisiner le plat.",
    "- Garde un titre très court, juste le nom du plat.",
    "- Ne laisse pas une recette composée seulement de sauces, d'épices ou d'une moitié de process si le plat principal demande autre chose.",
    "- Supprime tout texte social, CTA, hashtags, commentaires, timestamps et formulations inutiles.",
    "- Si tu fais une déduction raisonnable, note-le brièvement dans notesText.",
    "- Si des portions ou petites quantités implicites sont évidentes, complète-les prudemment pour que la recette et la nutrition soient cohérentes.",
      "- Vérifie que calories, protéines, glucides et lipides restent cohérents entre eux; si les macros ne collent pas raisonnablement avec les calories, corrige-les au lieu de renvoyer une nutrition vide.",
    "- Si malgré tout le contexte reste trop faible, mets confidence='low', needsWebFallback=true et fournis searchQuery."
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
