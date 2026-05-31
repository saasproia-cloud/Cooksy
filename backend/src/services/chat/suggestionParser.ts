import { AssistantReplySchema, type AssistantReply } from "./chatTypes.js";

export class AssistantReplyParseError extends Error {
  constructor(message: string, public readonly raw: string) {
    super(message);
    this.name = "AssistantReplyParseError";
  }
}

/**
 * Extracts the JSON object from a raw model response and validates it
 * against the AssistantReply schema. The system prompt instructs the
 * model to reply with JSON only, but we still strip optional ```json
 * fences in case the model can't help itself.
 */
export function parseAssistantReply(raw: string): AssistantReply {
  const trimmed = raw.trim();
  const candidate = stripCodeFences(trimmed);

  let parsed: unknown;
  try {
    parsed = JSON.parse(candidate);
  } catch (error) {
    // Last-chance extraction: find the first balanced { ... } block.
    const extracted = extractFirstJsonObject(candidate);
    if (extracted == null) {
      throw new AssistantReplyParseError(
        `Assistant reply is not valid JSON: ${(error as Error).message}`,
        raw
      );
    }
    try {
      parsed = JSON.parse(extracted);
    } catch (innerError) {
      throw new AssistantReplyParseError(
        `Assistant reply JSON extraction failed: ${(innerError as Error).message}`,
        raw
      );
    }
  }

  const result = AssistantReplySchema.safeParse(parsed);
  if (!result.success) {
    throw new AssistantReplyParseError(
      `Assistant reply failed schema validation: ${result.error.message}`,
      raw
    );
  }
  return result.data;
}

function stripCodeFences(input: string): string {
  const fenceMatch = input.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenceMatch ? fenceMatch[1] : input;
}

function extractFirstJsonObject(input: string): string | null {
  const start = input.indexOf("{");
  if (start === -1) return null;

  let depth = 0;
  let inString = false;
  let escape = false;
  for (let i = start; i < input.length; i += 1) {
    const ch = input[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (ch === "\\") {
      escape = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch === "{") depth += 1;
    else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        return input.slice(start, i + 1);
      }
    }
  }
  return null;
}
