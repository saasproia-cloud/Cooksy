import type { FastifyReply, FastifyRequest } from "fastify";

import { getSupabaseAnonClient } from "../config/supabase.js";

/**
 * Authenticated request shape. Routes that pass through
 * {@link requireAuth} get a guaranteed `request.user`. We attach a small
 * subset of the Supabase user object so downstream code does not need
 * to re-query Supabase for the basics.
 */
export type AuthenticatedUser = {
  id: string;
  email: string | null;
};

declare module "fastify" {
  interface FastifyRequest {
    user?: AuthenticatedUser;
  }
}

const BEARER_REGEX = /^Bearer\s+(.+)$/i;

function extractBearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header || typeof header !== "string") {
    return null;
  }
  const match = header.match(BEARER_REGEX);
  return match?.[1]?.trim() ?? null;
}

/**
 * Fastify preHandler that gates a route behind a valid Supabase JWT.
 *
 * Behavior:
 *   - No Authorization header / no Bearer token → 401 `missing_token`
 *   - Token rejected by Supabase                → 401 `invalid_token`
 *   - Otherwise, populates `request.user`       → continue
 *
 * The token is verified by Supabase itself (`auth.getUser(token)`)
 * which means rotated keys, banned users, and expired tokens are all
 * handled centrally — no JWT secret needs to live on the backend.
 */
export async function requireAuth(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const token = extractBearerToken(request);
  if (!token) {
    reply.status(401).send({ error: "missing_token" });
    return;
  }

  let supabase;
  try {
    supabase = getSupabaseAnonClient();
  } catch (error) {
    request.log.error(
      { event: "auth.misconfigured", message: (error as Error).message },
      "Supabase client unavailable for auth check"
    );
    reply.status(503).send({ error: "auth_unavailable" });
    return;
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) {
    request.log.info(
      { event: "auth.rejected", reason: error?.message ?? "no_user" },
      "Bearer token rejected"
    );
    reply.status(401).send({ error: "invalid_token" });
    return;
  }

  request.user = {
    id: data.user.id,
    email: data.user.email ?? null
  };
}
