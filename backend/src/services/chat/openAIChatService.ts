import { env, requireProvider } from "../../config/env.js";

/**
 * Lightweight OpenAI Chat Completions client for the Premium chat
 * assistant. Reuses the existing OPENAI_API_KEY (already configured for
 * recipe extraction) — no new vendor relationship to manage.
 *
 * Implements:
 *   - JSON-forced responses via `response_format: { type: "json_object" }`.
 *     OpenAI guarantees a syntactically valid JSON object; we then
 *     validate against our Zod schema in suggestionParser.
 *   - 25 s timeout + 1 retry on 5xx / network errors.
 *   - Prompt caching is automatic on the OpenAI side when the same
 *     system prompt prefix is sent across requests (no special header
 *     needed).
 */

const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const DEFAULT_TIMEOUT_MS = 25_000;

export type OpenAIChatRole = "system" | "user" | "assistant";

export type OpenAIChatMessage = {
  role: OpenAIChatRole;
  content: string;
};

export type OpenAIChatCallOptions = {
  messages: OpenAIChatMessage[];
  maxTokens?: number;
  temperature?: number;
  /** Aborts the request after this many ms. Defaults to 25 s. */
  timeoutMs?: number;
};

export type OpenAIChatUsage = {
  promptTokens: number;
  completionTokens: number;
  cachedPromptTokens: number;
};

export type OpenAIChatResponse = {
  text: string;
  finishReason: string | null;
  usage: OpenAIChatUsage;
};

export class OpenAIChatError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "OpenAIChatError";
  }
}

export async function callOpenAIChat(
  options: OpenAIChatCallOptions
): Promise<OpenAIChatResponse> {
  requireProvider("openAI");

  const body = {
    model: env.CHAT_MODEL,
    messages: options.messages,
    temperature: options.temperature ?? 0.4,
    max_tokens: options.maxTokens ?? 1024,
    // Force a syntactically valid JSON object. Our suggestionParser
    // still validates the shape against the AssistantReply Zod schema.
    response_format: { type: "json_object" }
  };

  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  // 1 retry on 5xx / network failure. Never retry on 4xx — those mean
  // the request itself is bad and retrying just doubles the bill.
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      return await postOnce(body, timeoutMs);
    } catch (error) {
      lastError = error;
      if (error instanceof OpenAIChatError && error.status < 500 && error.status !== 429) {
        throw error;
      }
      if (attempt === 0) {
        await new Promise((resolve) => setTimeout(resolve, 400));
      }
    }
  }
  throw lastError instanceof Error ? lastError : new Error("OpenAI chat call failed");
}

async function postOnce(body: unknown, timeoutMs: number): Promise<OpenAIChatResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${env.OPENAI_API_KEY}`
      },
      body: JSON.stringify(body),
      signal: controller.signal
    });

    if (!response.ok) {
      const text = await safeReadText(response);
      throw new OpenAIChatError(response.status, text || response.statusText);
    }

    const json = (await response.json()) as {
      choices?: Array<{
        message?: { content?: string | null };
        finish_reason?: string;
      }>;
      usage?: {
        prompt_tokens?: number;
        completion_tokens?: number;
        prompt_tokens_details?: { cached_tokens?: number };
      };
    };

    const text = json.choices?.[0]?.message?.content ?? "";

    return {
      text,
      finishReason: json.choices?.[0]?.finish_reason ?? null,
      usage: {
        promptTokens: json.usage?.prompt_tokens ?? 0,
        completionTokens: json.usage?.completion_tokens ?? 0,
        cachedPromptTokens: json.usage?.prompt_tokens_details?.cached_tokens ?? 0
      }
    };
  } finally {
    clearTimeout(timer);
  }
}

async function safeReadText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "";
  }
}
