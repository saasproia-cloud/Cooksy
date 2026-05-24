// =====================================================================
// tokenUsageTracker — per-request OpenAI token accounting.
//
// Uses AsyncLocalStorage so every nested async call inside one import
// request can `record(...)` token usage without threading a context
// argument through 12 function signatures. The Fastify route handler
// wraps each /api/import/* invocation with `runWithCounters(...)`, and
// the importService telemetry hook reads totals via `currentTotals()`.
//
// Costs are computed from a static price table so a quick env override
// (or model swap) is enough to keep numbers honest. Prices are USD per
// 1M tokens as of 2026-05.
// =====================================================================

import { AsyncLocalStorage } from "node:async_hooks";

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  model: string;
}

export interface AggregatedUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  /** USD cost estimate, computed from PRICING_USD_PER_M_TOKENS. */
  estimatedCostUsd: number;
  /** Per-model breakdown so we can spot a single hot path inflating bills. */
  callsByModel: Record<string, { calls: number; promptTokens: number; completionTokens: number }>;
}

interface Counter {
  promptTokens: number;
  completionTokens: number;
  byModel: Map<string, { calls: number; promptTokens: number; completionTokens: number }>;
}

const storage = new AsyncLocalStorage<Counter>();

/**
 * USD pricing per 1M tokens, input / output. Conservative — overestimate
 * is safer than underestimate when surfacing cost telemetry to operators.
 * Update the table when OpenAI pricing changes.
 */
const PRICING_USD_PER_M_TOKENS: Record<string, { input: number; output: number }> = {
  // GPT-4.1 family
  "gpt-4.1": { input: 2.0, output: 8.0 },
  "gpt-4.1-mini": { input: 0.4, output: 1.6 },
  "gpt-4.1-nano": { input: 0.1, output: 0.4 },
  // GPT-4o family
  "gpt-4o": { input: 2.5, output: 10.0 },
  "gpt-4o-mini": { input: 0.15, output: 0.6 },
  // GPT-5 family (forward-compatible — pricing extrapolated from 4.x)
  "gpt-5": { input: 2.5, output: 10.0 },
  "gpt-5-mini": { input: 0.4, output: 1.6 },
  "gpt-5-nano": { input: 0.1, output: 0.4 },
  // Transcription
  "gpt-4o-transcribe": { input: 0.006, output: 0.0 }, // priced per minute, see audio path
  // Fallback default for unknown models — uses GPT-4.1 pricing so we
  // never silently under-bill in telemetry.
  default: { input: 2.0, output: 8.0 }
};

function priceFor(model: string): { input: number; output: number } {
  // Try exact match first, then strip trailing suffix (e.g. "gpt-4o-2024-08").
  if (PRICING_USD_PER_M_TOKENS[model]) return PRICING_USD_PER_M_TOKENS[model]!;
  const lower = model.toLowerCase();
  for (const key of Object.keys(PRICING_USD_PER_M_TOKENS)) {
    if (lower.startsWith(key)) return PRICING_USD_PER_M_TOKENS[key]!;
  }
  return PRICING_USD_PER_M_TOKENS.default!;
}

/**
 * Runs the callback inside a fresh token-counter scope. Any nested
 * `recordUsage(...)` call during `fn` is aggregated. Returns whatever
 * `fn` returns.
 */
export function runWithCounters<T>(fn: () => Promise<T> | T): Promise<T> {
  const counter: Counter = {
    promptTokens: 0,
    completionTokens: 0,
    byModel: new Map()
  };
  return new Promise<T>((resolve, reject) => {
    storage.run(counter, () => {
      Promise.resolve(fn()).then(resolve, reject);
    });
  });
}

/** Records one OpenAI call's usage in the active counter. No-op outside scope. */
export function recordUsage(usage: TokenUsage): void {
  const counter = storage.getStore();
  if (!counter) return;
  counter.promptTokens += usage.promptTokens;
  counter.completionTokens += usage.completionTokens;
  const bucket = counter.byModel.get(usage.model) ?? {
    calls: 0,
    promptTokens: 0,
    completionTokens: 0
  };
  bucket.calls += 1;
  bucket.promptTokens += usage.promptTokens;
  bucket.completionTokens += usage.completionTokens;
  counter.byModel.set(usage.model, bucket);
}

/** Returns the aggregated totals for the active scope, or zeros outside. */
export function currentTotals(): AggregatedUsage {
  const counter = storage.getStore();
  if (!counter) {
    return {
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
      estimatedCostUsd: 0,
      callsByModel: {}
    };
  }

  let cost = 0;
  const callsByModel: AggregatedUsage["callsByModel"] = {};
  for (const [model, bucket] of counter.byModel.entries()) {
    const price = priceFor(model);
    cost += (bucket.promptTokens / 1_000_000) * price.input;
    cost += (bucket.completionTokens / 1_000_000) * price.output;
    callsByModel[model] = {
      calls: bucket.calls,
      promptTokens: bucket.promptTokens,
      completionTokens: bucket.completionTokens
    };
  }

  return {
    promptTokens: counter.promptTokens,
    completionTokens: counter.completionTokens,
    totalTokens: counter.promptTokens + counter.completionTokens,
    // Round to 5 decimals (0.00001 $ = 1/100 of a cent) — finer is noise.
    estimatedCostUsd: Math.round(cost * 100_000) / 100_000,
    callsByModel
  };
}

/** Helper: parse OpenAI Responses API `usage` block into TokenUsage. */
export function parseResponsesUsage(
  json: Record<string, unknown>,
  modelHint: string
): TokenUsage | null {
  const usage = (json as { usage?: Record<string, unknown> }).usage;
  if (!usage || typeof usage !== "object") return null;
  const inputTokens = numberOrZero(usage.input_tokens) || numberOrZero(usage.prompt_tokens);
  const outputTokens = numberOrZero(usage.output_tokens) || numberOrZero(usage.completion_tokens);
  if (inputTokens === 0 && outputTokens === 0) return null;
  return {
    promptTokens: inputTokens,
    completionTokens: outputTokens,
    totalTokens: inputTokens + outputTokens,
    model: modelHint
  };
}

function numberOrZero(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
