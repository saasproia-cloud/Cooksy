import { execFile } from "node:child_process";
import { mkdtemp, rm, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import ffmpegStatic from "ffmpeg-static";
import speech from "@google-cloud/speech";

import { fetchRemoteBuffer } from "./generalPageService.js";

const execFileAsync = promisify(execFile);
const ffmpegPath = ffmpegStatic as unknown as string | null;

// Cuisine vocabulary phrases that benefit from speech-recognition biasing.
// Google's `speechContexts.phrases` dramatically improves recognition of
// named ingredients, brands, techniques and units that Whisper-style generic
// models often mis-transcribe (provolone → "provo lone", panko → "banco",
// gochujang → "go go gang", etc.).
const KITCHEN_SPEECH_PHRASES: string[] = [
  "cuillère à soupe", "cuillère à café", "pincée", "gramme", "millilitre", "litre",
  "provolone", "panko", "gochujang", "burrata", "mascarpone", "ricotta", "parmesan",
  "mozzarella", "cheddar", "feta", "halloumi", "comté", "gruyère", "emmental", "kiri",
  "sauce barbecue", "sauce soja", "sauce sriracha", "sauce yaourt", "sauce crémeuse",
  "mayonnaise", "moutarde", "ketchup", "miel", "vinaigre balsamique", "jus de citron",
  "blanc de poulet", "escalope de poulet", "cuisse de poulet", "ribeye", "entrecôte",
  "faux-filet", "bavette", "onglet", "picanha", "magret", "bœuf haché", "porc",
  "saumon", "crevettes", "cabillaud", "thon", "encornet",
  "ail", "oignon", "échalote", "gingembre", "citronnelle", "coriandre", "persil",
  "basilic", "thym", "romarin", "laurier", "paprika", "curcuma", "cumin", "origan",
  "farine", "levure", "fécule", "sucre", "cassonade", "œufs", "beurre", "crème fraîche",
  "huile d'olive", "huile de sésame", "huile de tournesol",
  "tomate cerise", "courgette", "aubergine", "poivron", "champignon", "brocoli", "épinard",
  "marinade", "sauce", "garniture", "dressage", "montage", "pâte", "pâte à pizza",
  "pâte brisée", "pâte feuilletée", "chapelure", "cornflakes", "pain burger", "baguette",
  "émincer", "ciseler", "hacher", "tailler", "râper", "presser", "mélanger", "fouetter",
  "monter", "incorporer", "saler", "poivrer", "assaisonner", "mariner", "paner", "enrober",
  "saisir", "dorer", "revenir", "mijoter", "caraméliser", "déglacer", "réduire", "flamber",
  "rôtir", "dresser", "napper", "parsemer", "décorer", "cuire à feu doux", "cuire à feu vif",
  "philly cheesesteak", "smash burger", "chicken burger", "butter chicken", "tikka masala",
  "carbonara", "bolognese", "lasagne", "risotto", "ramen", "pad thaï", "poke bowl"
];

export async function transcribeWithGoogleFromUrl(
  mediaUrl: string,
  options?: {
    maxDurationSeconds?: number;
    maxFileBytes?: number;
    mediaFetchTimeoutMs?: number;
    languageHint?: string;
  }
): Promise<string | null> {
  if (!mediaUrl) {
    return null;
  }

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), "cooksy-gstt-"));
  const sourcePath = path.join(tempDirectory, "source.bin");
  const audioPath = path.join(tempDirectory, "audio.wav");
  const maxFileBytes = options?.maxFileBytes ?? 40 * 1024 * 1024;
  const maxDurationSeconds = options?.maxDurationSeconds ?? 300;

  try {
    const videoBuffer = await fetchRemoteBuffer(mediaUrl, maxFileBytes, {
      timeoutMs: options?.mediaFetchTimeoutMs
    });
    await writeFile(sourcePath, videoBuffer);

    await extractAudioToWav(sourcePath, audioPath, maxDurationSeconds);

    const audioBuffer = await readFile(audioPath);
    if (audioBuffer.byteLength === 0) {
      return null;
    }

    const primaryLanguage = options?.languageHint === "en" ? "en-US" : "fr-FR";
    const alternativeLanguage = primaryLanguage === "fr-FR" ? ["en-US"] : ["fr-FR"];

    const client = new speech.SpeechClient();
    const [operation] = await client.longRunningRecognize({
      config: {
        encoding: "LINEAR16",
        sampleRateHertz: 16000,
        languageCode: primaryLanguage,
        alternativeLanguageCodes: alternativeLanguage,
        enableAutomaticPunctuation: true,
        audioChannelCount: 1,
        model: "latest_long",
        useEnhanced: true,
        speechContexts: [
          {
            phrases: KITCHEN_SPEECH_PHRASES,
            boost: 15
          }
        ]
      },
      audio: {
        content: audioBuffer.toString("base64")
      }
    });

    const [response] = await operation.promise();
    const transcript = (response.results ?? [])
      .map((result) => result.alternatives?.[0]?.transcript ?? "")
      .join(" ")
      .trim();

    console.log(`[googleSpeech] transcript length=${transcript.length} lang=${primaryLanguage}`);

    return transcript.length > 0 ? transcript : null;
  } finally {
    await rm(tempDirectory, { recursive: true, force: true });
  }
}

async function extractAudioToWav(
  sourcePath: string,
  destinationPath: string,
  maxDurationSeconds: number
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
    String(maxDurationSeconds),
    "-c:a",
    "pcm_s16le",
    destinationPath
  ]);
}
