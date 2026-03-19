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

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  APP_ENV: z.enum(["development", "staging", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  OPENAI_API_KEY: z.string().default("YOUR_OPENAI_API_KEY"),
  APIFY_TOKEN: z.string().default("YOUR_APIFY_TOKEN"),
  SERPAPI_KEY: z.string().default("YOUR_SERPAPI_KEY"),
  BACKEND_BASE_URL: z.string().url().default("http://localhost:3000"),
  OPENAI_RECIPE_MODEL: z.string().default("gpt-5-mini"),
  OPENAI_TRANSCRIPTION_MODEL: z.string().default("gpt-4o-transcribe"),
  APIFY_TIKTOK_ACTOR_ID: z.string().default("clockworks/tiktok-scraper"),
  APIFY_INSTAGRAM_ACTOR_ID: z.string().default("apify/instagram-api-scraper"),
  APIFY_PINTEREST_ACTOR_ID: z.string().default("devcake/pinterest-pin-scraping")
});

function isConfigured(value: string): boolean {
  return Boolean(value) && !value.startsWith("YOUR_");
}

export const env = envSchema.parse(process.env);

export const providerStatus = {
  openAI: isConfigured(env.OPENAI_API_KEY),
  apify: isConfigured(env.APIFY_TOKEN),
  serpApi: isConfigured(env.SERPAPI_KEY)
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
    serpApi: "SERPAPI_KEY"
  }[provider];

  throw new BackendConfigurationError(
    `${envName} is not configured. Replace the placeholder in backend/.env before using this endpoint.`
  );
}
