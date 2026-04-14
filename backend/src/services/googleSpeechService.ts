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

export async function transcribeWithGoogleFromUrl(
  mediaUrl: string,
  options?: {
    maxDurationSeconds?: number;
    maxFileBytes?: number;
    mediaFetchTimeoutMs?: number;
  }
): Promise<string | null> {
  if (!mediaUrl) {
    return null;
  }

  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), "cooksy-gstt-"));
  const sourcePath = path.join(tempDirectory, "source.bin");
  const audioPath = path.join(tempDirectory, "audio.wav");
  const maxFileBytes = options?.maxFileBytes ?? 40 * 1024 * 1024;
  const maxDurationSeconds = options?.maxDurationSeconds ?? 180;

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

    const client = new speech.SpeechClient();
    const [operation] = await client.longRunningRecognize({
      config: {
        encoding: "LINEAR16",
        sampleRateHertz: 16000,
        languageCode: "fr-FR",
        enableAutomaticPunctuation: true,
        audioChannelCount: 1
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

    console.log("[googleSpeech] transcript:", transcript || "(empty)");

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
