import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../middleware/auth.js";
import {
  ChatMessageNotFoundError,
  ChatModificationNotFoundError,
  ChatNotPremiumError,
  ChatRateLimitedError,
  applyModification,
  loadHistoryForRecipe,
  revertModification,
  selectSuggestion,
  sendUserMessage
} from "../services/chat/chatAssistantService.js";
import { OpenAIChatError } from "../services/chat/openAIChatService.js";
import { AssistantReplyParseError } from "../services/chat/suggestionParser.js";
import { NutritionPatchSchema, PendingModificationSchema } from "../services/chat/chatTypes.js";

/**
 * Premium chat assistant routes.
 *
 *   GET    /api/chat/history?recipeId=…
 *   POST   /api/chat/message  { recipe, userMessage, threadId? }
 *   POST   /api/chat/select   { messageId, optionId, recipe }
 *   POST   /api/chat/apply    { recipe, pendingModification, threadId? }
 *   POST   /api/chat/revert   { modificationId, recipe }
 *
 * The iOS client owns the recipe library (local JSON) — it ships the
 * compact recipe payload in every request. The backend persists chat
 * threads, messages, and modification audit rows.
 */

const CHAT_BURST_RATE_LIMIT = { max: 20, timeWindow: "1 minute" } as const;

const recipePayloadSchema = z.object({
  recipeId: z.string().uuid(),
  title: z.string().min(1).max(200),
  servings: z.string().nullable(),
  prepTimeMinutes: z.number().int().nonnegative().nullable(),
  cookTimeMinutes: z.number().int().nonnegative().nullable(),
  ingredients: z.array(
    z.object({
      id: z.string().uuid(),
      name: z.string().min(1).max(200),
      amount: z.string().nullable(),
      unit: z.string().nullable(),
      originName: z.string().nullable()
    })
  ).max(80),
  steps: z.array(
    z.object({
      id: z.string().uuid(),
      title: z.string().nullable(),
      detail: z.string().min(1).max(1_500)
    })
  ).max(40),
  nutritionPerServing: NutritionPatchSchema.nullable(),
  allergens: z.array(z.string().max(40)).max(20),
  appliedModifications: z.array(
    z.object({
      id: z.string().uuid(),
      summary: z.string(),
      kind: z.string(),
      appliedAt: z.string()
    })
  ).max(40)
});

const messageSchema = z.object({
  recipe: recipePayloadSchema,
  userMessage: z.string().min(1).max(2_000),
  threadId: z.string().uuid().optional()
});

const selectSchema = z.object({
  recipe: recipePayloadSchema,
  messageId: z.string().uuid(),
  optionId: z.string().min(1).max(64)
});

const applySchema = z.object({
  recipe: recipePayloadSchema,
  pendingModification: PendingModificationSchema,
  threadId: z.string().uuid().optional()
});

const revertSchema = z.object({
  recipe: recipePayloadSchema,
  modificationId: z.string().uuid()
});

const historyQuerySchema = z.object({
  recipeId: z.string().uuid()
});

export async function registerChatRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/api/chat/history",
    {
      preHandler: requireAuth,
      config: { rateLimit: CHAT_BURST_RATE_LIMIT }
    },
    async (request) => {
      const { recipeId } = historyQuerySchema.parse(request.query);
      return loadHistoryForRecipe({
        userId: request.user!.id,
        recipeId
      });
    }
  );

  app.post(
    "/api/chat/message",
    {
      preHandler: requireAuth,
      config: { rateLimit: CHAT_BURST_RATE_LIMIT }
    },
    async (request, reply) => {
      const body = messageSchema.parse(request.body);
      try {
        const result = await sendUserMessage({
          userId: request.user!.id,
          recipe: body.recipe,
          userMessage: body.userMessage,
          threadId: body.threadId
        });
        request.log.info(
          { event: "chat.message_sent", threadId: result.threadId },
          "chat message handled"
        );
        return result;
      } catch (error) {
        return mapChatError(error, reply);
      }
    }
  );

  app.post(
    "/api/chat/select",
    {
      preHandler: requireAuth,
      config: { rateLimit: CHAT_BURST_RATE_LIMIT }
    },
    async (request, reply) => {
      const body = selectSchema.parse(request.body);
      try {
        const result = await selectSuggestion({
          userId: request.user!.id,
          messageId: body.messageId,
          optionId: body.optionId,
          recipe: body.recipe
        });
        request.log.info(
          { event: "chat.suggestion_tapped", optionId: body.optionId },
          "chat suggestion selected"
        );
        return result;
      } catch (error) {
        return mapChatError(error, reply);
      }
    }
  );

  app.post(
    "/api/chat/apply",
    {
      preHandler: requireAuth,
      config: { rateLimit: CHAT_BURST_RATE_LIMIT }
    },
    async (request, reply) => {
      const body = applySchema.parse(request.body);
      try {
        const result = await applyModification({
          userId: request.user!.id,
          recipe: body.recipe,
          pendingModification: body.pendingModification,
          threadId: body.threadId
        });
        request.log.info(
          { event: "chat.modification_applied", modificationId: result.modificationId },
          "chat modification applied"
        );
        return result;
      } catch (error) {
        return mapChatError(error, reply);
      }
    }
  );

  app.post(
    "/api/chat/revert",
    {
      preHandler: requireAuth,
      config: { rateLimit: CHAT_BURST_RATE_LIMIT }
    },
    async (request, reply) => {
      const body = revertSchema.parse(request.body);
      try {
        const result = await revertModification({
          userId: request.user!.id,
          modificationId: body.modificationId,
          recipe: body.recipe
        });
        request.log.info(
          { event: "chat.modification_reverted", modificationId: body.modificationId },
          "chat modification reverted"
        );
        return result;
      } catch (error) {
        return mapChatError(error, reply);
      }
    }
  );
}

function mapChatError(error: unknown, reply: import("fastify").FastifyReply): never | unknown {
  if (error instanceof ChatNotPremiumError) {
    reply.status(402).send({ error: "premium_required" });
    return reply;
  }
  if (error instanceof ChatRateLimitedError) {
    reply.status(429).send({
      error: "chat_rate_limited",
      messagesSent: error.messagesSent,
      cap: error.cap
    });
    return reply;
  }
  if (error instanceof ChatMessageNotFoundError) {
    reply.status(404).send({ error: "message_not_found" });
    return reply;
  }
  if (error instanceof ChatModificationNotFoundError) {
    reply.status(404).send({ error: "modification_not_found" });
    return reply;
  }
  if (error instanceof AssistantReplyParseError) {
    reply.status(502).send({
      error: "assistant_unparseable",
      message: "L'assistant n'a pas pu structurer sa réponse. Réessaie."
    });
    return reply;
  }
  if (error instanceof OpenAIChatError) {
    if (error.status === 429 || error.status >= 500) {
      reply.status(503).send({
        error: "assistant_unavailable",
        message: "L'assistant est temporairement indisponible. Réessaie dans un instant."
      });
      return reply;
    }
    reply.status(502).send({
      error: "assistant_error",
      message: "L'assistant a renvoyé une erreur inattendue."
    });
    return reply;
  }
  throw error;
}
