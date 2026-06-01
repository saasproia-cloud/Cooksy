import { randomUUID } from "node:crypto";

import { env } from "../../config/env.js";
import { getSupabaseServiceRoleClient } from "../../config/supabase.js";

import { callOpenAIChat, type OpenAIChatMessage } from "./openAIChatService.js";
import { buildRecipeContext, serializeRecipeContext } from "./recipeContextBuilder.js";
import { ASSISTANT_SYSTEM_PROMPT } from "./systemPrompt.js";
import { parseAssistantReply } from "./suggestionParser.js";
import { reconcileNutritionForSwap } from "./nutritionRecalc.js";
import {
  type AssistantReply,
  type IngredientSwapDiff,
  type PendingModification,
  type RecipeContext,
  type ScalePortionsDiff
} from "./chatTypes.js";

/**
 * The backend is stateless on recipes: the iOS client owns the recipe
 * library (stored locally as JSON) and ships the relevant recipe payload
 * with every chat request. The backend only persists:
 *   - chat threads & messages (so the conversation survives sessions)
 *   - recipe_modifications (audit log + future "history" UI)
 *
 * Applying / reverting modifications happens here too — but on the
 * caller-provided recipe payload, returning the mutated payload for the
 * iOS app to persist locally.
 */

export class ChatNotPremiumError extends Error {
  constructor() {
    super("Premium subscription required");
    this.name = "ChatNotPremiumError";
  }
}

export class ChatRateLimitedError extends Error {
  constructor(public readonly messagesSent: number, public readonly cap: number) {
    super("Hourly chat cap reached");
    this.name = "ChatRateLimitedError";
  }
}

export class ChatMessageNotFoundError extends Error {
  constructor() {
    super("Chat message not found or not owned by user");
    this.name = "ChatMessageNotFoundError";
  }
}

export class ChatModificationNotFoundError extends Error {
  constructor() {
    super("Recipe modification not found or not owned by user");
    this.name = "ChatModificationNotFoundError";
  }
}

export type ChatSendResult = {
  threadId: string;
  assistantMessage: PersistedChatMessage;
};

export type PersistedChatMessage = {
  id: string;
  threadId: string;
  role: "user" | "assistant" | "system";
  contentText: string | null;
  suggestionsJson: AssistantReply["suggestions"] | null;
  pendingModificationJson: PendingModification | null;
  createdAt: string;
};

// ---------------------------------------------------------------------------
// Inbound recipe payload — the compact shape the iOS app sends with each
// chat request. Mirrors RecipeContext + a per-ingredient "isSwapped"
// signal (computed client-side from the origin* fields).
// ---------------------------------------------------------------------------
export type InboundRecipePayload = {
  recipeId: string;
  title: string;
  servings: string | null;
  prepTimeMinutes: number | null;
  cookTimeMinutes: number | null;
  ingredients: Array<{
    id: string;
    name: string;
    amount: string | null;
    unit: string | null;
    originName: string | null;
  }>;
  steps: Array<{ id: string; title: string | null; detail: string }>;
  nutritionPerServing: RecipeContext["nutritionPerServing"];
  allergens: string[];
  appliedModifications: Array<{ id: string; summary: string; kind: string; appliedAt: string }>;
};

// ---------------------------------------------------------------------------
// sendUserMessage — main entry point for /api/chat/message
// ---------------------------------------------------------------------------
export async function sendUserMessage(args: {
  userId: string;
  recipe: InboundRecipePayload;
  userMessage: string;
  threadId?: string;
}): Promise<ChatSendResult> {
  const supabase = getSupabaseServiceRoleClient();
  await assertPremium(args.userId);
  await consumeChatQuota(args.userId);

  const context = inboundToContext(args.recipe);
  const threadId = args.threadId
    ?? await getOrCreateThread({ userId: args.userId, recipeId: args.recipe.recipeId });

  await supabase.from("chat_messages").insert({
    thread_id: threadId,
    user_id: args.userId,
    recipe_id: args.recipe.recipeId,
    role: "user",
    content_text: args.userMessage
  });

  const history = await loadRecentHistory({
    threadId,
    limit: env.CHAT_MAX_HISTORY_TURNS * 2
  });

  const assistantText = await runModel({ context, history, userMessage: args.userMessage });
  const parsed = parseAssistantReply(assistantText);

  const inserted = await supabase
    .from("chat_messages")
    .insert({
      thread_id: threadId,
      user_id: args.userId,
      recipe_id: args.recipe.recipeId,
      role: "assistant",
      content_text: parsed.reply,
      suggestions_json: parsed.suggestions ?? null,
      // When the assistant emits an add_components diff in its reply,
      // persist it directly so the iOS bubble renders the orange
      // "Ajouter à la recette" CTA without a second turn.
      pending_modification_json: parsed.pendingModification ?? null
    })
    .select("id, thread_id, role, content_text, suggestions_json, pending_modification_json, created_at")
    .single();

  if (inserted.error || !inserted.data) {
    throw new Error(`Failed to persist assistant message: ${inserted.error?.message ?? "unknown"}`);
  }

  return {
    threadId,
    assistantMessage: rowToMessage(inserted.data)
  };
}

// ---------------------------------------------------------------------------
// selectSuggestion — user tapped one of the suggestion chips.
// ---------------------------------------------------------------------------
export async function selectSuggestion(args: {
  userId: string;
  messageId: string;
  optionId: string;
  recipe: InboundRecipePayload;
}): Promise<{ assistantMessage: PersistedChatMessage }> {
  const supabase = getSupabaseServiceRoleClient();
  await assertPremium(args.userId);
  await consumeChatQuota(args.userId);

  const sourceMessage = await loadMessageOwnedBy(args.userId, args.messageId);
  const suggestions = sourceMessage.suggestionsJson;
  if (!suggestions) {
    throw new Error("Source message has no suggestions to select from.");
  }
  const option = suggestions.options.find((opt) => opt.id === args.optionId);
  if (!option) {
    throw new Error(`Selected option not found: ${args.optionId}`);
  }

  const context = inboundToContext(args.recipe);
  const history = await loadRecentHistory({
    threadId: sourceMessage.threadId,
    limit: env.CHAT_MAX_HISTORY_TURNS * 2
  });

  const intent = `L'utilisateur a sélectionné : ${option.label} (${option.shortImpact}).`;
  const elaborationText = await runModel({
    context,
    history,
    userMessage: intent
  });
  const elaboration = parseAssistantReply(elaborationText);

  const pending = synthesizePendingModification({
    context,
    suggestions,
    option
  });

  const inserted = await supabase
    .from("chat_messages")
    .insert({
      thread_id: sourceMessage.threadId,
      user_id: args.userId,
      recipe_id: sourceMessage.recipeId,
      role: "assistant",
      content_text: elaboration.reply,
      pending_modification_json: pending
    })
    .select("id, thread_id, role, content_text, suggestions_json, pending_modification_json, created_at")
    .single();

  if (inserted.error || !inserted.data) {
    throw new Error(`Failed to persist elaboration message: ${inserted.error?.message ?? "unknown"}`);
  }

  return { assistantMessage: rowToMessage(inserted.data) };
}

// ---------------------------------------------------------------------------
// applyModification — applies the diff to the caller-provided recipe and
// returns the mutated recipe + a server-side modification id.
// ---------------------------------------------------------------------------
export async function applyModification(args: {
  userId: string;
  recipe: InboundRecipePayload;
  pendingModification: PendingModification;
  threadId?: string;
}): Promise<{ modificationId: string; recipe: MutatedRecipe }> {
  const supabase = getSupabaseServiceRoleClient();
  await assertPremium(args.userId);

  const mutated = applyDiffToInboundRecipe(args.recipe, args.pendingModification);

  const { data: modificationRow, error: modificationError } = await supabase
    .from("recipe_modifications")
    .insert({
      id: args.pendingModification.modificationId,
      user_id: args.userId,
      recipe_id: args.recipe.recipeId,
      thread_id: args.threadId ?? null,
      kind: args.pendingModification.diff.kind,
      summary: args.pendingModification.summary,
      payload_jsonb: args.pendingModification
    })
    .select("id")
    .single();

  if (modificationError || !modificationRow) {
    throw new Error(`Failed to persist modification: ${modificationError?.message ?? "unknown"}`);
  }

  return {
    modificationId: modificationRow.id,
    recipe: mutated
  };
}

// ---------------------------------------------------------------------------
// revertModification — restores the snapshot for a given modification.
// ---------------------------------------------------------------------------
export async function revertModification(args: {
  userId: string;
  modificationId: string;
  recipe: InboundRecipePayload;
}): Promise<{ recipe: MutatedRecipe }> {
  const supabase = getSupabaseServiceRoleClient();
  await assertPremium(args.userId);

  const { data: modRow, error: modError } = await supabase
    .from("recipe_modifications")
    .select("*")
    .eq("id", args.modificationId)
    .eq("user_id", args.userId)
    .maybeSingle();

  if (modError) {
    throw new Error(`Failed to load modification: ${modError.message}`);
  }
  if (!modRow) {
    throw new ChatModificationNotFoundError();
  }
  if (modRow.reverted_at) {
    throw new Error("Modification already reverted.");
  }

  const payload = modRow.payload_jsonb as PendingModification;
  const reverted = revertDiffOnInboundRecipe(args.recipe, payload);

  await supabase
    .from("recipe_modifications")
    .update({ reverted_at: new Date().toISOString() })
    .eq("id", modRow.id);

  return { recipe: reverted };
}

// ---------------------------------------------------------------------------
// loadHistoryForRecipe — GET /api/chat/history?recipeId=
// ---------------------------------------------------------------------------
export async function loadHistoryForRecipe(args: {
  userId: string;
  recipeId: string;
}): Promise<{ threadId: string | null; messages: PersistedChatMessage[] }> {
  const supabase = getSupabaseServiceRoleClient();
  const { data: thread, error: threadError } = await supabase
    .from("chat_threads")
    .select("id")
    .eq("user_id", args.userId)
    .eq("recipe_id", args.recipeId)
    .maybeSingle();
  if (threadError) {
    throw new Error(`Failed to load chat thread: ${threadError.message}`);
  }
  if (!thread) {
    return { threadId: null, messages: [] };
  }

  const { data: rows, error: messagesError } = await supabase
    .from("chat_messages")
    .select("id, thread_id, role, content_text, suggestions_json, pending_modification_json, created_at")
    .eq("thread_id", thread.id)
    .order("created_at", { ascending: true });

  if (messagesError) {
    throw new Error(`Failed to load chat messages: ${messagesError.message}`);
  }

  return {
    threadId: thread.id,
    messages: (rows ?? []).map(rowToMessage)
  };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

async function assertPremium(userId: string): Promise<void> {
  const supabase = getSupabaseServiceRoleClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("is_premium")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to read premium status: ${error.message}`);
  }
  if (!data?.is_premium) {
    throw new ChatNotPremiumError();
  }
}

async function consumeChatQuota(userId: string): Promise<void> {
  const supabase = getSupabaseServiceRoleClient();
  const windowHour = currentHourStart();
  const { data, error } = await supabase.rpc("consume_chat_quota", {
    target_user_id: userId,
    window_hour: windowHour,
    hourly_cap: env.CHAT_HOURLY_CAP
  });
  if (error) {
    throw new Error(`Failed to consume chat quota: ${error.message}`);
  }
  const row = Array.isArray(data) ? data[0] : data;
  const messagesSent = typeof row?.messages_sent === "number" ? row.messages_sent : 0;
  const allowed = row?.allowed !== false;
  if (!allowed) {
    throw new ChatRateLimitedError(messagesSent, env.CHAT_HOURLY_CAP);
  }
}

async function getOrCreateThread(args: {
  userId: string;
  recipeId: string;
}): Promise<string> {
  const supabase = getSupabaseServiceRoleClient();
  const { data: existing } = await supabase
    .from("chat_threads")
    .select("id")
    .eq("user_id", args.userId)
    .eq("recipe_id", args.recipeId)
    .maybeSingle();

  if (existing?.id) {
    return existing.id;
  }

  const { data: created, error: insertError } = await supabase
    .from("chat_threads")
    .insert({ user_id: args.userId, recipe_id: args.recipeId })
    .select("id")
    .single();

  if (insertError || !created?.id) {
    throw new Error(`Failed to create chat thread: ${insertError?.message ?? "unknown"}`);
  }
  return created.id;
}

async function loadRecentHistory(args: {
  threadId: string;
  limit: number;
}): Promise<OpenAIChatMessage[]> {
  const supabase = getSupabaseServiceRoleClient();
  const { data, error } = await supabase
    .from("chat_messages")
    .select("role, content_text")
    .eq("thread_id", args.threadId)
    .order("created_at", { ascending: false })
    .limit(args.limit);

  if (error) {
    throw new Error(`Failed to load chat history: ${error.message}`);
  }

  const ordered = (data ?? []).slice().reverse();
  const messages: OpenAIChatMessage[] = [];
  for (const row of ordered) {
    const role = row.role === "assistant" ? "assistant" : "user";
    const content = row.content_text;
    if (typeof content !== "string" || content.trim().length === 0) continue;
    messages.push({ role, content });
  }
  return messages;
}

async function runModel(args: {
  context: RecipeContext;
  history: OpenAIChatMessage[];
  userMessage: string;
}): Promise<string> {
  // OpenAI is fine with a single system message — sending the static
  // assistant prompt first and the recipe context as a second system
  // block keeps the structure readable; OpenAI's automatic prompt
  // caching kicks in on the stable prefix across requests.
  const messages: OpenAIChatMessage[] = [
    { role: "system", content: ASSISTANT_SYSTEM_PROMPT },
    { role: "system", content: serializeRecipeContext(args.context) },
    ...args.history,
    { role: "user", content: args.userMessage }
  ];

  const result = await callOpenAIChat({
    messages,
    temperature: 0.4,
    maxTokens: 1024
  });
  return result.text;
}

// ---------------------------------------------------------------------------
// Inbound recipe → RecipeContext shim
// ---------------------------------------------------------------------------

function inboundToContext(recipe: InboundRecipePayload): RecipeContext {
  return {
    recipeId: recipe.recipeId,
    title: recipe.title,
    servings: recipe.servings ?? null,
    prepTimeMinutes: recipe.prepTimeMinutes ?? null,
    cookTimeMinutes: recipe.cookTimeMinutes ?? null,
    ingredients: recipe.ingredients.map((ing) => ({
      id: ing.id,
      name: ing.name,
      amount: ing.amount ?? null,
      unit: ing.unit ?? null,
      isSwapped: Boolean(ing.originName),
      originName: ing.originName ?? null
    })),
    steps: recipe.steps.map((step) => ({
      id: step.id,
      title: step.title ?? null,
      detail: step.detail
    })),
    nutritionPerServing: recipe.nutritionPerServing ?? null,
    allergens: recipe.allergens ?? [],
    appliedModifications: recipe.appliedModifications ?? []
  };
}

// ---------------------------------------------------------------------------
// Pending modification synthesis
// ---------------------------------------------------------------------------

function synthesizePendingModification(args: {
  context: RecipeContext;
  suggestions: NonNullable<AssistantReply["suggestions"]>;
  option: { id: string; label: string; shortImpact: string };
}): PendingModification {
  const modificationId = randomUUID();

  if (args.suggestions.kind === "ingredient_swap") {
    const target = args.suggestions.target;
    const ingredientId = target?.ingredientId;
    if (!ingredientId) {
      throw new Error("ingredient_swap suggestion is missing target.ingredientId");
    }
    const current = args.context.ingredients.find((i) => i.id === ingredientId);
    if (!current) {
      throw new Error(`Ingredient ${ingredientId} not found in current recipe`);
    }
    const diff: IngredientSwapDiff = {
      kind: "ingredient_swap",
      ingredientId,
      before: {
        name: current.name,
        amount: current.amount,
        unit: current.unit
      },
      after: {
        name: args.option.label,
        amount: current.amount,
        unit: current.unit
      },
      stepRewrites: rewriteStepsForSwap({
        context: args.context,
        ingredientId,
        beforeName: current.name,
        afterName: args.option.label
      }),
      nutritionBefore: args.context.nutritionPerServing,
      nutritionAfter: reconcileNutritionForSwap(args.context, args.context.nutritionPerServing)
    };
    return {
      modificationId,
      summary: `Remplacer ${current.name} par ${args.option.label}`,
      diff,
      confirmLabel: "Modifier la recette"
    };
  }

  const factor = parseScaleOption(args.option.label);
  const diff: ScalePortionsDiff = {
    kind: "scale_portions",
    factor,
    before: { servings: args.context.servings },
    after: { servings: scaleServingsLabel(args.context.servings, factor) },
    ingredientPatches: args.context.ingredients
      .map((ing) => {
        const scaledAmount = scaleAmountString(ing.amount, factor);
        if (scaledAmount === ing.amount) return null;
        return {
          ingredientId: ing.id,
          before: { name: ing.name, amount: ing.amount, unit: ing.unit },
          after: { name: ing.name, amount: scaledAmount, unit: ing.unit }
        };
      })
      .filter((patch): patch is NonNullable<typeof patch> => patch != null)
  };
  return {
    modificationId,
    summary: `Ajuster les portions ×${factor}`,
    diff,
    confirmLabel: "Modifier la recette"
  };
}

function rewriteStepsForSwap(args: {
  context: RecipeContext;
  ingredientId: string;
  beforeName: string;
  afterName: string;
}): IngredientSwapDiff["stepRewrites"] {
  const rewrites: IngredientSwapDiff["stepRewrites"] = [];
  const pattern = new RegExp(`\\b${escapeRegExp(args.beforeName)}\\b`, "gi");
  for (const step of args.context.steps) {
    if (!pattern.test(step.detail)) continue;
    const rewritten = step.detail.replace(pattern, args.afterName);
    if (rewritten === step.detail) continue;
    rewrites.push({
      stepId: step.id,
      beforeDetail: step.detail,
      afterDetail: rewritten
    });
  }
  return rewrites;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function parseScaleOption(label: string): number {
  const match = label.match(/×\s*(\d+(?:[\.,]\d+)?)/);
  if (!match) return 1;
  const parsed = Number.parseFloat(match[1].replace(",", "."));
  if (!Number.isFinite(parsed) || parsed <= 0) return 1;
  return parsed;
}

function scaleAmountString(amount: string | null, factor: number): string | null {
  if (!amount) return amount;
  const match = amount.match(/^(\d+(?:[\.,]\d+)?)(.*)$/);
  if (!match) return amount;
  const numeric = Number.parseFloat(match[1].replace(",", "."));
  if (!Number.isFinite(numeric)) return amount;
  const scaled = numeric * factor;
  const rounded = Math.round(scaled * 100) / 100;
  const formatted = Number.isInteger(rounded) ? `${rounded}` : `${rounded}`.replace(".", ",");
  return `${formatted}${match[2]}`;
}

function scaleServingsLabel(servings: string | null, factor: number): string | null {
  if (!servings) return servings;
  const match = servings.match(/^(\d+(?:[\.,]\d+)?)(.*)$/);
  if (!match) return servings;
  const numeric = Number.parseFloat(match[1].replace(",", "."));
  if (!Number.isFinite(numeric)) return servings;
  const scaled = Math.round(numeric * factor);
  return `${scaled}${match[2]}`;
}

// ---------------------------------------------------------------------------
// Recipe mutators on the inbound payload
// ---------------------------------------------------------------------------

export type MutatedRecipe = {
  ingredients: InboundRecipePayload["ingredients"];
  steps: InboundRecipePayload["steps"];
  nutritionPerServing: RecipeContext["nutritionPerServing"];
  allergens: string[];
  servings: string | null;
};

function applyDiffToInboundRecipe(
  recipe: InboundRecipePayload,
  pending: PendingModification
): MutatedRecipe {
  const ingredients = recipe.ingredients.map((ing) => ({ ...ing }));
  const steps = recipe.steps.map((step) => ({ ...step }));
  let nutrition = recipe.nutritionPerServing ? { ...recipe.nutritionPerServing } : null;
  let allergens = recipe.allergens ? [...recipe.allergens] : [];
  let servings = recipe.servings;

  if (pending.diff.kind === "ingredient_swap") {
    const diff = pending.diff;
    const target = ingredients.find((ing) => ing.id === diff.ingredientId);
    if (target) {
      // First swap snapshots the original; subsequent swaps preserve it.
      if (!target.originName) {
        target.originName = target.name ?? null;
      }
      target.name = diff.after.name;
      target.amount = diff.after.amount ?? null;
      target.unit = diff.after.unit ?? null;
    }
    for (const rewrite of diff.stepRewrites) {
      const step = steps.find((s) => s.id === rewrite.stepId);
      if (step) step.detail = rewrite.afterDetail;
    }
    if (diff.nutritionAfter) {
      nutrition = { ...(nutrition ?? {}), ...diff.nutritionAfter };
    }
    if (diff.allergensAfter !== undefined) {
      allergens = diff.allergensAfter ?? [];
    }
  } else if (pending.diff.kind === "scale_portions") {
    const diff = pending.diff;
    for (const patch of diff.ingredientPatches) {
      const target = ingredients.find((ing) => ing.id === patch.ingredientId);
      if (!target) continue;
      target.amount = patch.after.amount ?? null;
      target.unit = patch.after.unit ?? null;
    }
    if (diff.after.servings != null) {
      servings = diff.after.servings;
    }
  } else if (pending.diff.kind === "add_components") {
    const diff = pending.diff;
    for (const ing of diff.addedIngredients) {
      ingredients.push({
        id: ing.id,
        name: ing.name,
        amount: ing.amount ?? null,
        unit: ing.unit ?? null,
        originName: null
      });
    }
    for (const step of diff.addedSteps) {
      steps.push({
        id: step.id,
        title: step.title ?? null,
        detail: step.detail
      });
    }
    if (diff.nutritionDelta) {
      nutrition = { ...(nutrition ?? {}), ...diff.nutritionDelta };
    }
    for (const a of diff.allergensAdded) {
      if (!allergens.includes(a)) allergens.push(a);
    }
  }

  return { ingredients, steps, nutritionPerServing: nutrition, allergens, servings };
}

function revertDiffOnInboundRecipe(
  recipe: InboundRecipePayload,
  pending: PendingModification
): MutatedRecipe {
  const ingredients = recipe.ingredients.map((ing) => ({ ...ing }));
  const steps = recipe.steps.map((step) => ({ ...step }));
  let nutrition = recipe.nutritionPerServing ? { ...recipe.nutritionPerServing } : null;
  let allergens = recipe.allergens ? [...recipe.allergens] : [];
  let servings = recipe.servings;

  if (pending.diff.kind === "ingredient_swap") {
    const diff = pending.diff;
    const target = ingredients.find((ing) => ing.id === diff.ingredientId);
    if (target) {
      target.name = diff.before.name;
      target.amount = diff.before.amount ?? null;
      target.unit = diff.before.unit ?? null;
      target.originName = null;
    }
    for (const rewrite of diff.stepRewrites) {
      const step = steps.find((s) => s.id === rewrite.stepId);
      if (step) step.detail = rewrite.beforeDetail;
    }
    if (diff.nutritionBefore) {
      nutrition = { ...(nutrition ?? {}), ...diff.nutritionBefore };
    }
    if (diff.allergensBefore !== undefined) {
      allergens = diff.allergensBefore ?? [];
    }
  } else if (pending.diff.kind === "scale_portions") {
    const diff = pending.diff;
    for (const patch of diff.ingredientPatches) {
      const target = ingredients.find((ing) => ing.id === patch.ingredientId);
      if (!target) continue;
      target.amount = patch.before.amount ?? null;
      target.unit = patch.before.unit ?? null;
    }
    if (diff.before.servings != null) {
      servings = diff.before.servings;
    }
  } else if (pending.diff.kind === "add_components") {
    // Reverse the addition: drop the rows whose ids match what we added.
    // Nutrition / allergens are best-effort — we never reverse a nutrition
    // delta exactly (would require persisting the pre-delta snapshot too).
    const diff = pending.diff;
    const addedIngIds = new Set(diff.addedIngredients.map((i) => i.id));
    const addedStepIds = new Set(diff.addedSteps.map((s) => s.id));
    return {
      ingredients: ingredients.filter((i) => !addedIngIds.has(i.id)),
      steps: steps.filter((s) => !addedStepIds.has(s.id)),
      nutritionPerServing: nutrition,
      allergens: allergens.filter((a) => !diff.allergensAdded.includes(a)),
      servings
    };
  }

  return { ingredients, steps, nutritionPerServing: nutrition, allergens, servings };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type DbChatMessageRow = {
  id: string;
  thread_id: string;
  role: string;
  content_text: string | null;
  suggestions_json: unknown;
  pending_modification_json: unknown;
  created_at: string;
};

function rowToMessage(row: DbChatMessageRow): PersistedChatMessage {
  return {
    id: row.id,
    threadId: row.thread_id,
    role: row.role === "assistant" || row.role === "system" ? row.role : "user",
    contentText: row.content_text ?? null,
    suggestionsJson: (row.suggestions_json as AssistantReply["suggestions"]) ?? null,
    pendingModificationJson: (row.pending_modification_json as PendingModification | null) ?? null,
    createdAt: row.created_at
  };
}

async function loadMessageOwnedBy(userId: string, messageId: string): Promise<{
  id: string;
  threadId: string;
  recipeId: string;
  suggestionsJson: AssistantReply["suggestions"] | null;
}> {
  const supabase = getSupabaseServiceRoleClient();
  const { data, error } = await supabase
    .from("chat_messages")
    .select("id, thread_id, recipe_id, suggestions_json, user_id")
    .eq("id", messageId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to load chat message: ${error.message}`);
  }
  if (!data || data.user_id !== userId) {
    throw new ChatMessageNotFoundError();
  }
  return {
    id: data.id,
    threadId: data.thread_id,
    recipeId: data.recipe_id,
    suggestionsJson: (data.suggestions_json as AssistantReply["suggestions"]) ?? null
  };
}

function currentHourStart(): string {
  const now = new Date();
  const hour = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
    now.getUTCHours()
  ));
  return hour.toISOString();
}
