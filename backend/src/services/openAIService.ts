import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { mkdtemp } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import ffmpegStatic from "ffmpeg-static";

import { env, requireProvider } from "../config/env.js";
import { fetchRemoteBuffer } from "./generalPageService.js";
import {
  recipeImportSchema,
  sanitizeRecipeImport,
  type NormalizerInput,
  type RecipeImportResult
} from "../types/recipe.js";
import { compactTextBlocks, truncate } from "../utils/text.js";

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
        required: ["detail"],
        properties: {
          detail: { type: "string" }
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
    needsWebFallback: { type: "boolean" },
    searchQuery: { type: "string" },
    inferredFromPhoto: { type: "boolean" }
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

  const contents: Array<Record<string, string>> = [
    {
      type: "input_text",
      text: buildNormalizationPrompt(input)
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
              text: [
                "Tu transformes du contenu social, des photos et des textes libres en recette exploitable.",
                "Réponds uniquement avec un JSON valide respectant strictement le schéma.",
                "Écris en français.",
                "Normalise les ingrédients en amount / unit / name.",
                "Chaque ingrédient doit aussi contenir nutritionQuery, une requête USDA courte en anglais comme 'olive oil' ou 'chicken breast'.",
                "N'utilise jamais du texte d'article, des appels à l'action ou des éléments sociaux comme ingrédients ou étapes.",
                "Les étapes doivent être courtes, actionnables et purement culinaires.",
                "Si les valeurs nutritionnelles ne sont pas clairement fournies, laisse caloriesText/proteinText/carbsText/fatText vides.",
                "Si le contenu est partiel, reconstruis une recette plausible mais honnête.",
                "Si la recette reste trop incertaine, mets confidence='low', needsWebFallback=true et fournis searchQuery."
              ].join(" ")
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
    signal: AbortSignal.timeout(options?.timeoutMs ?? 60_000)
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI normalization failed (${response.status}): ${errorBody}`);
  }

  const json = await response.json() as { output_text?: string };
  if (!json.output_text) {
    throw new Error("OpenAI normalization returned an empty output_text payload.");
  }

  const parsed = recipeImportSchema.parse(JSON.parse(json.output_text));
  return sanitizeRecipeImport(parsed);
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

  return [
    `Mode d'import : ${input.mode}`,
    input.sourceUrl ? `URL source : ${input.sourceUrl}` : "",
    input.remoteImageUrl ? `Image distante probable : ${input.remoteImageUrl}` : "",
    input.pageTitle ? `Titre page : ${truncate(input.pageTitle, 180)}` : "",
    input.pageDescription ? `Description page : ${truncate(input.pageDescription, 420)}` : "",
    input.socialTitle ? `Titre social : ${truncate(input.socialTitle, 180)}` : "",
    input.socialAuthor ? `Auteur social : ${truncate(input.socialAuthor, 80)}` : "",
    input.socialCaption ? `Caption social : ${truncate(input.socialCaption, 1200)}` : "",
    input.socialDescription ? `Description sociale : ${truncate(input.socialDescription, 800)}` : "",
    input.socialPageText ? `Texte social récupéré : ${truncate(input.socialPageText, 1600)}` : "",
    input.sharedText ? `Texte partagé : ${truncate(input.sharedText, 1600)}` : "",
    input.socialSubtitles ? `Sous-titres récupérés : ${truncate(input.socialSubtitles, 1800)}` : "",
    input.transcript ? `Transcription audio : ${truncate(input.transcript, 2600)}` : "",
    input.pageTextContent ? `Texte page : ${truncate(input.pageTextContent, 1200)}` : "",
    structuredDataText ? `Données structurées : ${structuredDataText}` : "",
    [
      "Consignes métier :",
      "- Donne un titre court et naturel.",
      "- Garde uniquement des ingrédients utiles à cuisiner, un ingrédient par ligne.",
      "- nutritionQuery doit être un nom d'aliment court en anglais exploitable par USDA.",
      "- Donne des étapes actionnables, numérotables et pas trop longues.",
      "- Si une transcription audio est présente et que la légende est pauvre, appuie-toi en priorité sur l'audio pour reconstruire la recette.",
      "- N'invente pas des ingrédients absents de la transcription ou de la légende sans le signaler brièvement dans notesText.",
      "- Ignore les boutons, pubs, 'Read More', 'View post', hashtags et textes people/news/fashion/travel.",
      "- Si le contenu décrit seulement un plat ou une photo, infère une recette maison plausible.",
      "- Note dans notesText ce qui est une déduction ou ce qui manque.",
      "- searchQuery doit être une requête courte exploitable si une recherche web est nécessaire."
    ].join("\n")
  ]
    .filter(Boolean)
    .join("\n\n");
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
