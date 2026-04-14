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

const rawEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  APP_ENV: z.enum(["development", "staging", "production"]).default("development"),
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
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional()
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
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional()
});

function isConfigured(value: string): boolean {
  return Boolean(value) && !value.startsWith("YOUR_");
}

const rawEnv = rawEnvSchema.parse(process.env);

export const env = envSchema.parse({
  ...rawEnv,
  BACKEND_BASE_URL: resolveBackendBaseURL(rawEnv)
});

export const providerStatus = {
  openAI: isConfigured(env.OPENAI_API_KEY),
  apify: isConfigured(env.APIFY_TOKEN),
  serpApi: isConfigured(env.SERPAPI_KEY),
  usda: isConfigured(env.USDA_API_KEY),
  googleSpeech: Boolean(env.GOOGLE_APPLICATION_CREDENTIALS?.trim())
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
    serpApi: "SERPAPI_KEY",
    usda: "USDA_API_KEY",
    googleSpeech: "GOOGLE_APPLICATION_CREDENTIALS"
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
