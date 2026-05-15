import Fastify from "fastify";
import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import rateLimit from "@fastify/rate-limit";
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
import { isSyntacticallySafeImportUrl, UnsafeUrlError } from "./utils/urlSecurity.js";
import { requireAuth } from "./middleware/auth.js";
import {
  consumeImportSlot,
  readEntitlement,
  QuotaExceededError
} from "./services/entitlementService.js";
import { registerRevenueCatWebhook } from "./routes/webhookRevenueCat.js";

const isProduction = env.APP_ENV === "production";

const app = Fastify({
  logger: {
    level: isProduction ? "info" : "debug",
    // Redact sensitive fields out of every log line. Pino accepts dotted
    // paths and wildcards; we mask anything that could leak a token, a
    // recipe payload or a raw image.
    redact: {
      paths: [
        "req.headers.authorization",
        "req.headers.cookie",
        'req.headers["x-api-key"]',
        "req.body.imageBase64",
        "req.body.image",
        "*.imageBase64",
        "*.serviceRoleKey",
        "*.openaiKey"
      ],
      remove: true
    }
  }
});

// CORS — Cooksy is a native iOS client. Native apps don't send an
// Origin header, so we can safely disable CORS in production. In dev we
// keep it permissive to support local web tooling / Postman.
await app.register(cors, {
  origin: isProduction ? false : true,
  credentials: false
});

await app.register(multipart, {
  limits: {
    fileSize: 12 * 1024 * 1024,
    files: 1
  }
});

// Rate limiting — backed by Fastify's default in-memory store. That's
// fine for a single Railway instance; if we ever scale horizontally
// we'll swap in a Redis store. Per-user buckets when an Authorization
// header is present, otherwise per-IP. Routes that need to opt out
// (e.g. the RevenueCat webhook) declare `config: { rateLimit: false }`.
await app.register(rateLimit, {
  global: true,
  max: 30,
  timeWindow: "1 minute",
  keyGenerator: (req) => {
    const authHeader = req.headers.authorization;
    if (typeof authHeader === "string" && authHeader.startsWith("Bearer ")) {
      // Hash-less user key: we slice the token so different sessions of
      // the same user share a bucket but we never log the raw JWT.
      return `u:${authHeader.slice(7, 27)}`;
    }
    return `ip:${req.ip}`;
  },
  errorResponseBuilder: () => ({
    error: "rate_limited",
    message: "Trop de requêtes, réessaie dans un instant."
  })
});

const urlImportSchema = z.object({
  url: z
    .string()
    .url()
    // Cheap synchronous SSRF guard. Rejects file://, localhost, literal
    // private IPs, etc. before any pipeline work runs. The authoritative
    // fetch-time check (DNS resolve + reserved-range block) lives in
    // utils/urlSecurity.ts and is enforced by the page/image fetchers.
    .refine(isSyntacticallySafeImportUrl, {
      message: "URL is not allowed."
    }),
  sharedText: z.string().optional(),
  previewMode: z.boolean().optional(),
  sharedMode: z.boolean().optional(),
  debug: z.boolean().optional()
});

// Base64 cap derived from the 12 MB photo limit: base64 inflates the
// binary by ~4/3, so a 12 MB image lands at ~16 MB of base64 payload.
// We pad to 20 MB to leave room for `data:image/...;base64,` prefixes
// and JSON envelope overhead, while still rejecting clearly oversized
// uploads at the schema layer (before the buffer reaches OpenAI).
const MAX_IMAGE_BASE64_LENGTH = 20 * 1024 * 1024;

// Allowed photo MIME types — JPEG / PNG / WebP cover every iOS export
// path. Anything else is almost certainly a malformed client or an
// attempt to push an unexpected payload through the vision model.
const ALLOWED_PHOTO_MIME_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp"
]);

const textImportSchema = z.object({
  text: z.string().min(1).max(50_000),
  imageBase64: z
    .string()
    .max(MAX_IMAGE_BASE64_LENGTH, "Image trop volumineuse.")
    .optional(),
  previewMode: z.boolean().optional(),
  sharedMode: z.boolean().optional()
});

const shoppingEnrichSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.string().max(200),
        article: z.string().min(1).max(200),
        category: z.string().max(100).optional()
      })
    )
    .min(1)
    .max(200)
});

app.get("/health", async () => {
  return {
    status: "ok",
    env: env.APP_ENV,
    providers: providerStatus
  };
});

// Read-only entitlement view. iOS uses it to render the import counter
// badge ("3 / 5 imports cette semaine") without consuming a slot.
app.get("/api/me/entitlement", { preHandler: requireAuth }, async (request) => {
  return readEntitlement(request.user!.id);
});

app.post(
  "/api/import/url",
  { preHandler: requireAuth },
  async (request, reply) => {
  try {
    // Authoritative quota check. Free users get 5 imports / week,
    // premium 100. The iOS counter is decorative — the cap is enforced
    // here regardless of what the client believes.
    await consumeImportSlot(request.user!.id);

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

    request.log.info(
      { event: "import.url.success", hasDebug: debugRequested },
      "URL import succeeded"
    );
    reply.status(200);
    if (debugRequested && imported.pipelineTrace) {
      return { ...response, pipelineTrace: imported.pipelineTrace };
    }
    return response;
  } catch (error) {
    if (error instanceof RecipeImportNotFoodError) {
      // Surface the explicit not_food / not_enough_info reason so the iOS
      // client can render its dedicated failure screen instead of the
      // generic "import failed" envelope.
      throw error;
    }
    if (error instanceof QuotaExceededError) {
      // Bubble the 402 up to the error handler so the client sees the
      // real status code (and the entitlement snapshot) — not a 200
      // wrapped failure envelope.
      throw error;
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    const errorType = error instanceof Error ? error.constructor.name : "Unknown";
    const isTimeout = errorMessage.toLowerCase().includes("timeout") ||
      errorMessage.toLowerCase().includes("aborted");
    request.log.error(
      {
        event: "import.url.failure",
        errorType,
        isTimeout,
        // We intentionally do NOT log the inbound URL here in production —
        // it may contain user-identifying short links.
        message: isProduction ? undefined : errorMessage
      },
      "URL import failed"
    );
    const response = buildURLImportFailureResponse();
    reply.status(200);
    return response;
  }
});

app.post(
  "/api/import/text",
  { preHandler: requireAuth },
  async (request) => {
    await consumeImportSlot(request.user!.id);
    const body = textImportSchema.parse(request.body);
    return importFromText({
      text: body.text,
      imageDataUrl: body.imageBase64 ? toDataUrl(body.imageBase64) : undefined
    }, {
      previewMode: body.previewMode,
      sharedMode: body.sharedMode
    });
  }
);

app.post(
  "/api/import/photo",
  { preHandler: requireAuth },
  async (request, reply) => {
    await consumeImportSlot(request.user!.id);
    const parts = request.parts();
    let imageBuffer: Buffer | null = null;
    let imageMimeType: string | null = null;

    for await (const part of parts) {
      if (part.type === "file" && part.fieldname === "image") {
        // Validate the declared MIME type BEFORE buffering the file —
        // the @fastify/multipart `fileSize` limit (12 MB) is the second
        // line of defence. We reject anything outside the JPEG/PNG/WebP
        // set so unexpected payloads (HEIC, GIF, SVG, octet-stream)
        // never reach the vision model.
        const declaredMime = (part.mimetype || "").toLowerCase();
        if (!ALLOWED_PHOTO_MIME_TYPES.has(declaredMime)) {
          reply.status(415);
          return {
            error: "unsupported_media_type",
            message: "Seules les images JPEG, PNG et WebP sont acceptées."
          };
        }
        imageMimeType = declaredMime === "image/jpg" ? "image/jpeg" : declaredMime;
        imageBuffer = await part.toBuffer();
      }
    }

    if (!imageBuffer || !imageMimeType) {
      reply.status(400);
      return {
        error: "missing_image",
        message: "Aucune image n'a été transmise."
      };
    }

    return importFromPhoto({
      imageDataUrl: `data:${imageMimeType};base64,${imageBuffer.toString("base64")}`
    });
  }
);

app.post(
  "/api/shopping/enrich",
  { preHandler: requireAuth },
  async (request) => {
    const body = shoppingEnrichSchema.parse(request.body);
    return {
      items: await enrichShoppingImages(body.items)
    };
  }
);

// RevenueCat webhook (no JWT — protected by shared-secret check inside
// the handler). Idempotent via webhook_events table.
await registerRevenueCatWebhook(app);

// Diagnostic endpoints are intentionally restricted to non-production
// environments. They can leak raw transcripts and rack up Google STT
// charges if abused, so we wall them off behind APP_ENV.
if (!isProduction) {
  const googleSttTestSchema = z.object({
    url: z.string().url()
  });

  app.post("/api/test/google-stt", async (request, reply) => {
    const body = googleSttTestSchema.parse(request.body);
    const transcript = await transcribeWithGoogleFromUrl(body.url);
    request.log.debug(
      { event: "test.google-stt.success", length: transcript?.length ?? 0 },
      "Google STT diagnostic invoked"
    );
    reply.status(200);
    return { transcript };
  });
}

app.setErrorHandler((error, request, reply) => {
  if (error instanceof ZodError) {
    reply.status(400).send({
      error: "Bad Request",
      details: error.flatten()
    });
    return;
  }

  if (error instanceof QuotaExceededError) {
    // 402 Payment Required is the canonical "you need to upgrade" code.
    // We include the snapshot so the iOS app can update the badge
    // counter immediately and surface a paywall.
    reply.status(402).send({
      error: "quota_exceeded",
      ...error.snapshot
    });
    return;
  }

  if (error instanceof UnsafeUrlError) {
    // Any URL that fails the SSRF guard surfaces a flat 400. We expose
    // the reason code (machine-friendly) but never the resolved IP — no
    // need to confirm the network layout of internal targets.
    reply.status(400).send({
      error: "invalid_url",
      reason: error.reason
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
