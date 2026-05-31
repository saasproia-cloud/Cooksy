import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import dotenv from "dotenv";
import { z } from "zod";

const envSearchPaths = [
  path.resolve(process.cwd(), ".env"),
  path.resolve(process.cwd(), ".env.local"),
  path.resolve(process.cwd(), "..", ".env"),
  path.resolve(process.cwd(), "..", ".env.local")
];

for (const envPath of envSearchPaths) {
  dotenv.config({ path: envPath, override: false });
}

// Railway (and most container platforms) don't allow uploading files —
// only environment variables. If the user provides the service-account
// JSON directly via GOOGLE_APPLICATION_CREDENTIALS_JSON, write it to a
// temp file at boot and point GOOGLE_APPLICATION_CREDENTIALS at it so the
// google-auth-library picks it up transparently. This runs BEFORE any
// google client is instantiated because env.ts is imported at startup.
function materializeGoogleCredentialsFromInlineJSON(): void {
  const inlineJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON?.trim();
  if (!inlineJson) {
    return;
  }

  try {
    // Accept either raw JSON or base64-encoded JSON (Railway sometimes
    // mangles multi-line secrets; base64 is the safe transport).
    let decoded = inlineJson;
    if (!decoded.startsWith("{")) {
      decoded = Buffer.from(inlineJson, "base64").toString("utf8");
    }
    JSON.parse(decoded); // validate

    const targetPath = path.join(os.tmpdir(), "cooksy-google-credentials.json");
    fs.writeFileSync(targetPath, decoded, { mode: 0o600 });
    process.env.GOOGLE_APPLICATION_CREDENTIALS = targetPath;
    console.info(
      `[env] Materialized GOOGLE_APPLICATION_CREDENTIALS_JSON -> ${targetPath}`
    );
  } catch (error) {
    console.warn(
      `[env] Failed to materialize GOOGLE_APPLICATION_CREDENTIALS_JSON (${(error as Error).message}); Google Speech-to-Text will stay disabled.`
    );
  }
}

materializeGoogleCredentialsFromInlineJSON();

// Railway (and some CI runners) inject env vars as empty strings when the
// variable is declared but unset. `z.enum().default()` only fires when the
// value is `undefined`, so an empty string would slip through to the enum
// validator and crash the boot. Coerce "" → undefined for the enum fields
// before validation so the `.default()` actually kicks in.
const emptyToUndefined = (value: unknown): unknown =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

const rawEnvSchema = z.object({
  NODE_ENV: z.preprocess(
    emptyToUndefined,
    z.enum(["development", "test", "production"]).default("production")
  ),
  APP_ENV: z.preprocess(
    emptyToUndefined,
    z.enum(["development", "staging", "production"]).default("production")
  ),
  PORT: z.coerce.number().int().positive().default(3000),
  OPENAI_API_KEY: z.string().default("YOUR_OPENAI_API_KEY"),
  APIFY_TOKEN: z.string().default("YOUR_APIFY_TOKEN"),
  SERPAPI_KEY: z.string().default("YOUR_SERPAPI_KEY"),
  USDA_API_KEY: z.string().default("YOUR_USDA_API_KEY"),
  BACKEND_BASE_URL: z.string().optional(),
  RAILWAY_PUBLIC_DOMAIN: z.string().optional(),
  OPENAI_RECIPE_MODEL: z.string().default("gpt-4.1"),
  OPENAI_TRANSCRIPTION_MODEL: z.string().default("gpt-4o-transcribe"),
  APIFY_TIKTOK_ACTOR_ID: z.string().default("clockworks/tiktok-scraper"),
  APIFY_INSTAGRAM_ACTOR_ID: z.string().default("apify/instagram-api-scraper"),
  APIFY_PINTEREST_ACTOR_ID: z.string().default("devcake/pinterest-pin-scraping"),
  // Toggle for the Apify "Option 2" subtitle download path. Defaults to
  // enabled — set APIFY_SUBTITLES_ENABLED=false to emergency-disable
  // the VTT subtitle fetch (e.g. if a creator's subtitle host is causing
  // timeouts) without redeploying code.
  APIFY_SUBTITLES_ENABLED: z.preprocess(
    emptyToUndefined,
    z.enum(["true", "false"]).default("true")
  ),
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
  GOOGLE_APPLICATION_CREDENTIALS_JSON: z.string().optional(),
  // Supabase — required for user authentication, entitlements lookup,
  // and RevenueCat webhook persistence. Without these, all
  // /api/import/* endpoints will refuse to start.
  SUPABASE_URL: z.string().default("YOUR_SUPABASE_URL"),
  SUPABASE_ANON_KEY: z.string().default("YOUR_SUPABASE_ANON_KEY"),
  SUPABASE_SERVICE_ROLE_KEY: z.string().default("YOUR_SUPABASE_SERVICE_ROLE_KEY"),
  // RevenueCat — shared secret configured in the RevenueCat dashboard
  // for the Cooksy webhook. Used to authenticate incoming webhook calls.
  REVENUECAT_WEBHOOK_SECRET: z.string().default("YOUR_REVENUECAT_WEBHOOK_SECRET"),
  // APNs — Apple Push credentials used by the push service to talk
  // HTTP/2 + JWT-signed requests to api.push.apple.com (production) or
  // api.sandbox.push.apple.com (debug builds). All four are required for
  // outbound push to work; absent any one of them, push goes into
  // "log-only" mode (we still record dispatches with skip_reason).
  APNS_AUTH_KEY: z.string().default("YOUR_APNS_AUTH_KEY"),       // PEM contents of the .p8, or base64 of it
  APNS_KEY_ID: z.string().default("YOUR_APNS_KEY_ID"),           // 10-char Apple key id
  APNS_TEAM_ID: z.string().default("YOUR_APNS_TEAM_ID"),         // 10-char Apple team id
  APNS_BUNDLE_ID: z.string().default("YOUR_APNS_BUNDLE_ID"),     // e.g. com.cooksy.ios
  APNS_ENVIRONMENT: z.preprocess(
    emptyToUndefined,
    z.enum(["production", "sandbox"]).default("production")
  ),
  // Premium chat assistant — reuses OPENAI_API_KEY (already configured
  // for recipe extraction). CHAT_MODEL picks which OpenAI chat model to
  // use; default is gpt-4.1-mini for the price/quality sweet spot on
  // French instruction-following + JSON-mode output.
  CHAT_MODEL: z.string().default("gpt-4.1-mini"),
  CHAT_MAX_HISTORY_TURNS: z.coerce.number().int().positive().default(6),
  CHAT_HOURLY_CAP: z.coerce.number().int().positive().default(60)
});

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]),
  APP_ENV: z.enum(["development", "staging", "production"]),
  PORT: z.coerce.number().int().positive(),
  OPENAI_API_KEY: z.string(),
  APIFY_TOKEN: z.string(),
  SERPAPI_KEY: z.string(),
  USDA_API_KEY: z.string(),
  BACKEND_BASE_URL: z.string().url(),
  RAILWAY_PUBLIC_DOMAIN: z.string().optional(),
  OPENAI_RECIPE_MODEL: z.string(),
  OPENAI_TRANSCRIPTION_MODEL: z.string(),
  APIFY_TIKTOK_ACTOR_ID: z.string(),
  APIFY_INSTAGRAM_ACTOR_ID: z.string(),
  APIFY_PINTEREST_ACTOR_ID: z.string(),
  APIFY_SUBTITLES_ENABLED: z.enum(["true", "false"]),
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
  GOOGLE_APPLICATION_CREDENTIALS_JSON: z.string().optional(),
  SUPABASE_URL: z.string(),
  SUPABASE_ANON_KEY: z.string(),
  SUPABASE_SERVICE_ROLE_KEY: z.string(),
  REVENUECAT_WEBHOOK_SECRET: z.string(),
  APNS_AUTH_KEY: z.string(),
  APNS_KEY_ID: z.string(),
  APNS_TEAM_ID: z.string(),
  APNS_BUNDLE_ID: z.string(),
  APNS_ENVIRONMENT: z.enum(["production", "sandbox"]),
  CHAT_MODEL: z.string(),
  CHAT_MAX_HISTORY_TURNS: z.coerce.number().int().positive(),
  CHAT_HOURLY_CAP: z.coerce.number().int().positive()
});

function isConfigured(value: string): boolean {
  return Boolean(value) && !value.startsWith("YOUR_");
}

const rawEnv = rawEnvSchema.parse(process.env);

export const env = envSchema.parse({
  ...rawEnv,
  BACKEND_BASE_URL: resolveBackendBaseURL(rawEnv)
});

function isGoogleCredentialsReadable(credentialsPath: string | undefined): boolean {
  const trimmed = credentialsPath?.trim();
  if (!trimmed) {
    return false;
  }

  try {
    const stats = fs.statSync(trimmed);
    if (!stats.isFile()) {
      console.warn(
        `[env] GOOGLE_APPLICATION_CREDENTIALS=${trimmed} exists but is not a file; Google Speech-to-Text disabled.`
      );
      return false;
    }
    return true;
  } catch (error) {
    console.warn(
      `[env] GOOGLE_APPLICATION_CREDENTIALS=${trimmed} not readable (${(error as Error).message}); Google Speech-to-Text disabled.`
    );
    return false;
  }
}

export const providerStatus = {
  openAI: isConfigured(env.OPENAI_API_KEY),
  apify: isConfigured(env.APIFY_TOKEN),
  // Apify "Option 2" — fetch the VTT subtitles produced server-side and
  // surface them as `subtitlesText`. Toggle via APIFY_SUBTITLES_ENABLED.
  apifySubtitles: isConfigured(env.APIFY_TOKEN) && env.APIFY_SUBTITLES_ENABLED === "true",
  serpApi: isConfigured(env.SERPAPI_KEY),
  usda: isConfigured(env.USDA_API_KEY),
  googleSpeech: isGoogleCredentialsReadable(env.GOOGLE_APPLICATION_CREDENTIALS),
  supabase:
    isConfigured(env.SUPABASE_URL) &&
    isConfigured(env.SUPABASE_ANON_KEY) &&
    isConfigured(env.SUPABASE_SERVICE_ROLE_KEY),
  revenueCatWebhook: isConfigured(env.REVENUECAT_WEBHOOK_SECRET),
  apns:
    isConfigured(env.APNS_AUTH_KEY) &&
    isConfigured(env.APNS_KEY_ID) &&
    isConfigured(env.APNS_TEAM_ID) &&
    isConfigured(env.APNS_BUNDLE_ID)
};

export class BackendConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BackendConfigurationError";
  }
}

export function requireProvider(provider: keyof typeof providerStatus): void {
  if (providerStatus[provider]) {
    return;
  }

  const envName = {
    openAI: "OPENAI_API_KEY",
    apify: "APIFY_TOKEN",
    apifySubtitles: "APIFY_TOKEN+APIFY_SUBTITLES_ENABLED",
    serpApi: "SERPAPI_KEY",
    usda: "USDA_API_KEY",
    googleSpeech: "GOOGLE_APPLICATION_CREDENTIALS",
    supabase: "SUPABASE_URL/SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY",
    revenueCatWebhook: "REVENUECAT_WEBHOOK_SECRET",
    apns: "APNS_AUTH_KEY/APNS_KEY_ID/APNS_TEAM_ID/APNS_BUNDLE_ID"
  }[provider];

  throw new BackendConfigurationError(
    `${envName} is not configured. Replace the placeholder in backend/.env before using this endpoint.`
  );
}

function resolveBackendBaseURL(rawEnv: z.infer<typeof rawEnvSchema>): string {
  const explicitBaseURL = normalizeValidURLLikeValue(rawEnv.BACKEND_BASE_URL);
  if (explicitBaseURL) {
    return explicitBaseURL;
  }

  const railwayPublicDomain = normalizeValidURLLikeValue(rawEnv.RAILWAY_PUBLIC_DOMAIN);
  if (railwayPublicDomain) {
    return railwayPublicDomain;
  }

  return `http://localhost:${rawEnv.PORT}`;
}

function normalizeValidURLLikeValue(value?: string): string | undefined {
  const cleanedValue = cleanEnvString(value);
  if (!cleanedValue) {
    return undefined;
  }

  const normalizedValue = normalizeURLLikeValue(cleanedValue);
  if (!normalizedValue) {
    return undefined;
  }

  return URL.canParse(normalizedValue) ? normalizedValue : undefined;
}

function normalizeURLLikeValue(cleanedValue: string): string | undefined {
  if (/^https?:\/\//i.test(cleanedValue)) {
    return cleanedValue;
  }

  if (/^(localhost|127\.0\.0\.1|0\.0\.0\.0)(:\d+)?(\/.*)?$/i.test(cleanedValue)) {
    return `http://${cleanedValue}`;
  }

  if (/^[a-z0-9.-]+\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(cleanedValue)) {
    return `https://${cleanedValue}`;
  }

  return cleanedValue;
}

function cleanEnvString(value?: string): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }

  if (
    (trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    const unwrapped = trimmed.slice(1, -1).trim();
    return unwrapped || undefined;
  }

  return trimmed;
}
