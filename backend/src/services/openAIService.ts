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
      "Tu transformes du contenu social, des photos et des textes libres en recette exploitable.",
      "Réponds uniquement avec un JSON valide respectant strictement le schéma.",
      "Écris en français.",
      "Commence toujours par décider s'il s'agit de contenu culinaire et, si oui, identifie d'abord un nom de plat précis.",
      "Si le contenu n'est clairement pas alimentaire, ne fabrique pas de recette: renvoie un résultat vide, confidence='low' et aucun ingrédient ni aucune étape exploitables.",
      "Dès qu'un plat crédible est identifié, n'échoue jamais tôt: reconstruis une recette exploitable autour de ce plat.",
      "Le titre doit contenir uniquement le nom court de la recette, sans liste d'ingrédients, sans hashtags, sans URL et sans texte social.",
      "Si l'auteur social est connu, renseigne creatorHandle au format @nom.",
      "Normalise les ingrédients en amount / unit / name.",
      "Chaque objet ingredientDraft doit représenter un seul ingrédient. N'écris jamais plusieurs ingrédients dans name, même avec '/', ',', '+', '&', 'et' ou '...'.",
      "Chaque ingrédient doit aussi contenir nutritionQuery, une requête USDA courte en anglais comme 'olive oil' ou 'chicken breast'.",
      "Utilise d'abord les ingrédients explicitement mentionnés dans le texte partagé, la légende, les hashtags, les métadonnées sociales et le texte de page.",
      "Si le plat est identifié mais que des ingrédients manquent, complète-les intelligemment avec des ingrédients crédibles et standards pour ce plat.",
      "Si l'extraction explicite donne moins de 3 ingrédients valides ou moins de 2 étapes valides, jette cette extraction faible et reconstruis la recette complète à partir du plat détecté.",
      "La recette finale doit toujours contenir un titre propre, des ingrédients structurés réalistes, au moins 3 étapes utiles et un déroulé cohérent.",
      "Pour les plats non triviaux, vise au moins 5 ingrédients réalistes.",
      "N'utilise jamais du texte d'article, des appels à l'action ou des éléments sociaux comme ingrédients ou étapes.",
      "Les étapes doivent être courtes, actionnables et purement culinaires. Chaque étape doit décrire une seule action concrète.",
      "La recette doit contenir au minimum 8 étapes détaillées pour un plat standard, 10-12 pour un plat complexe. Ne compresse jamais plusieurs actions en une seule étape.",
      "Décompose les étapes longues en micro-étapes: par exemple, 'Préparez la pâte' doit devenir 'Mélanger la farine et le sel', 'Ajouter les œufs un à un', 'Pétrir jusqu'à obtenir une pâte lisse'.",
      "Ne recopie jamais d'horodatage, de flèches VTT, de hashtags, de phrases d'intro/outro ou de phrases comme 'bon app' dans les étapes.",
      "Utilise la légende, la description, les sous-titres et la photo comme indices pour identifier le plat, ses composants et les quantités implicites.",
      "Quand une transcription audio est présente et que le texte social est court ou absent, traite l'audio comme source principale pour identifier le plat, les ingrédients et les étapes.",
      "La transcription audio ne doit pas être recopiée mot pour mot dans les étapes: reformule dans un style culinaire clair, mais respecte le plat, les ingrédients et les proportions mentionnés à l'oral.",
      "Après avoir établi la liste finale des ingrédients, réécris toutes les étapes depuis zéro à partir de cette liste: chaque ingrédient principal doit être utilisé dans une étape logique.",
      "Avant de finaliser le JSON, vérifie qu'une personne peut réellement cuisiner le plat du début à la fin avec les ingrédients et les étapes fournis.",
      "Si des ingrédients essentiels ou des étapes essentielles sont clairement implicites dans le contexte, ajoute-les au lieu de laisser une recette inutilisable.",
      "Les étapes doivent couvrir au minimum la préparation, la cuisson et l'assemblage ou le dressage si le plat l'exige.",
      "Si les étapes manquent mais que le contexte culinaire est clair, reconstruis des étapes plausibles et concrètes sans inventer n'importe quoi.",
      "Si des quantités ménagères simples ou un nombre de portions sont évidents à déduire du plat ou des ingrédients, complète-les prudemment pour obtenir une recette exploitable et une nutrition cohérente.",
      "Si les ingrédients ou les étapes manquent mais que le plat est identifiable via le titre, l'audio, les sous-titres, la photo ou le contexte social, reconstruis d'abord la recette complète avant d'activer un éventuel fallback.",
      "Quand plusieurs sources web sont présentes dans le contexte, compare-les et retiens la version la plus cohérente et la plus commune du plat au lieu de recopier la source la plus courte.",
      "Les valeurs nutritionnelles doivent venir de la recette finale et de ses quantités, jamais du texte social ou de l'audio seul.",
      "Vérifie que calories, protéines, glucides et lipides restent cohérents entre eux; si les macros ne collent pas raisonnablement avec les calories, corrige-les au lieu de laisser une nutrition vide.",
      "La nutrition est obligatoire pour tout contenu alimentaire: renseigne caloriesText/proteinText/carbsText/fatText avec une estimation réaliste cohérente avec les ingrédients, les quantités et les portions.",
      "Renseigne confidenceScore entre 0 et 1 selon la solidité du plat détecté, des ingrédients explicites et des déductions nécessaires.",
      "Renseigne flags.usedExplicitIngredients à true si tu conserves au moins un ingrédient explicitement mentionné.",
      "Renseigne flags.usedInferredIngredients à true si tu ajoutes des ingrédients plausibles non listés explicitement.",
      "Renseigne flags.generatedSteps à true si tu réécris ou reconstruis les étapes.",
      "Renseigne flags.generatedNutrition à true pour toute recette alimentaire.",
      "Si le contenu est partiel, reconstruis une recette plausible mais honnête.",
      "N'utilise pas needsWebFallback comme échappatoire à un contenu culinaire incomplet: livre d'abord une vraie recette exploitable.",
      "Si la recette comporte des sous-préparations distinctes (marinade, sauce, pâte, garniture, dressage), renseigne le champ section de la première étape de chaque sous-préparation avec un label court comme 'Marinade', 'Sauce', 'Pâte', 'Garniture', 'Dressage'. Les étapes suivantes de la même sous-préparation ont section vide.",
      "Ne force pas de section si la recette suit un déroulé linéaire simple.",
      "Chaque étape de cuisson doit inclure la température ou l'intensité du feu quand c'est pertinent (par ex. 'à feu moyen', '180 °C').",
      "Chaque étape impliquant une durée doit mentionner un temps indicatif (par ex. '5 minutes', 'environ 10 min').",
      "Chaque ingrédient principal doit apparaître nommément dans au moins une étape. Vérifie cette règle avant de finaliser le JSON."
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
  const transcriptLabel = isSparseSocialText ? "Source principale (audio)" : "Transcription audio";

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
      input: [
        {
          role: "system",
          content: [
            {
              type: "input_text",
              text: input.systemInstructions.join(" ")
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
