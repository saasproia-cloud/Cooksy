import Fastify from "fastify";
import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import { ZodError, z } from "zod";

import { env, BackendConfigurationError, providerStatus } from "./config/env.js";
import {
  importFromPhoto,
  importFromText,
  importFromUrl,
  RecipeImportNotFoodError
} from "./services/importService.js";
import { enrichShoppingImages } from "./services/shoppingImageService.js";
import { transcribeWithGoogleFromUrl } from "./services/googleSpeechService.js";
import {
  buildURLImportFailureResponse,
  buildURLImportResponse
} from "./services/urlImportResponseService.js";

const app = Fastify({
  logger: true
});

await app.register(cors, {
  origin: true
});

await app.register(multipart, {
  limits: {
    fileSize: 12 * 1024 * 1024,
    files: 1
  }
});

const urlImportSchema = z.object({
  url: z.string().url(),
  sharedText: z.string().optional(),
  previewMode: z.boolean().optional(),
  sharedMode: z.boolean().optional(),
  debug: z.boolean().optional()
});

const textImportSchema = z.object({
  text: z.string().min(1),
  imageBase64: z.string().optional(),
  previewMode: z.boolean().optional(),
  sharedMode: z.boolean().optional()
});

const shoppingEnrichSchema = z.object({
  items: z.array(z.object({
    id: z.string(),
    article: z.string().min(1),
    category: z.string().optional()
  })).min(1)
});

app.get("/health", async () => {
  return {
    status: "ok",
    env: env.APP_ENV,
    providers: providerStatus
  };
});

app.post("/api/import/url", async (request, reply) => {
  try {
    const body = urlImportSchema.parse(request.body);
    const debugRequested = body.debug === true
      || (request.query as Record<string, unknown> | undefined)?.debug === "true";
    const imported = await importFromUrl(body, {
      previewMode: body.previewMode,
      sharedMode: body.sharedMode,
      debug: debugRequested
    });
    const response = await buildURLImportResponse({
      recipe: imported.recipe,
      sourceUrl: body.url,
      debug: imported.debug
    });

    console.log("FINAL_RESPONSE", JSON.stringify(response, null, 2));
    reply.status(200);
    if (debugRequested && imported.pipelineTrace) {
      return { ...response, pipelineTrace: imported.pipelineTrace };
    }
    return response;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const errorType = error instanceof Error ? error.constructor.name : "Unknown";
    const isTimeout = errorMessage.toLowerCase().includes("timeout") ||
      errorMessage.toLowerCase().includes("aborted");
    console.error(
      `[IMPORT FAILURE] type=${errorType} timeout=${isTimeout} url=${(request.body as Record<string, unknown>)?.url ?? "(unknown)"} message=${errorMessage}`
    );
    request.log.error(error);
    const response = buildURLImportFailureResponse();
    console.log("FINAL_RESPONSE", JSON.stringify(response, null, 2));
    reply.status(200);
    return response;
  }
});

app.post("/api/import/text", async (request) => {
  const body = textImportSchema.parse(request.body);
  return importFromText({
    text: body.text,
    imageDataUrl: body.imageBase64 ? toDataUrl(body.imageBase64) : undefined
  }, {
    previewMode: body.previewMode,
    sharedMode: body.sharedMode
  });
});

app.post("/api/import/photo", async (request) => {
  const parts = request.parts();
  let imageBuffer: Buffer | null = null;

  for await (const part of parts) {
    if (part.type === "file" && part.fieldname === "image") {
      imageBuffer = await part.toBuffer();
    }
  }

  if (!imageBuffer) {
    throw new Error("No image file was provided.");
  }

  return importFromPhoto({
    imageDataUrl: `data:image/jpeg;base64,${imageBuffer.toString("base64")}`
  });
});

app.post("/api/shopping/enrich", async (request) => {
  const body = shoppingEnrichSchema.parse(request.body);
  return {
    items: await enrichShoppingImages(body.items)
  };
});

const googleSttTestSchema = z.object({
  url: z.string().url()
});

app.post("/api/test/google-stt", async (request, reply) => {
  const body = googleSttTestSchema.parse(request.body);
  const transcript = await transcribeWithGoogleFromUrl(body.url);
  console.log("[google-stt test] transcript:", transcript);
  reply.status(200);
  return { transcript };
});

app.setErrorHandler((error, request, reply) => {
  if (error instanceof ZodError) {
    reply.status(400).send({
      error: "Bad Request",
      details: error.flatten()
    });
    return;
  }

  if (error instanceof BackendConfigurationError) {
    reply.status(503).send({
      error: "Backend Misconfigured",
      message: error.message
    });
    return;
  }

  if (error instanceof RecipeImportNotFoodError) {
    reply.status(422).send({
      error: error.error,
      reason: error.reason
    });
    return;
  }

  const message = error instanceof Error ? error.message : "Unknown server error";
  request.log.error(error);
  reply.status(500).send({
    error: "Internal Server Error",
    message
  });
});

app.listen({
  host: "0.0.0.0",
  port: env.PORT
}).catch((error) => {
  app.log.error(error);
  process.exit(1);
});

function toDataUrl(base64Value: string): string {
  if (base64Value.startsWith("data:")) {
    return base64Value;
  }

  return `data:image/jpeg;base64,${base64Value}`;
}
