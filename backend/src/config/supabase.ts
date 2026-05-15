import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { env, providerStatus } from "./env.js";

/**
 * Two Supabase clients, two different trust boundaries.
 *
 *   `anonClient`         — uses the public anon key. The only thing we
 *                          use it for is `auth.getUser(jwt)` to validate
 *                          the bearer token a mobile request carries.
 *                          It cannot read or write protected tables.
 *
 *   `serviceRoleClient`  — uses the service-role key. Bypasses RLS.
 *                          ONLY used by trusted server-side code paths:
 *                          the entitlement service (reading/writing
 *                          `user_entitlements`) and the RevenueCat
 *                          webhook handler. It must never be exposed to
 *                          the iOS bundle.
 *
 * Lazily constructed so the rest of the codebase can still boot when
 * Supabase env vars are placeholders (e.g. unit tests, doctor script).
 * Call `requireProvider("supabase")` before accessing them in
 * production code paths.
 */

let cachedAnonClient: SupabaseClient | null = null;
let cachedServiceRoleClient: SupabaseClient | null = null;

export function getSupabaseAnonClient(): SupabaseClient {
  if (cachedAnonClient) {
    return cachedAnonClient;
  }
  if (!providerStatus.supabase) {
    throw new Error(
      "Supabase is not configured (missing SUPABASE_URL / SUPABASE_ANON_KEY)."
    );
  }
  cachedAnonClient = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false
    }
  });
  return cachedAnonClient;
}

export function getSupabaseServiceRoleClient(): SupabaseClient {
  if (cachedServiceRoleClient) {
    return cachedServiceRoleClient;
  }
  if (!providerStatus.supabase) {
    throw new Error(
      "Supabase is not configured (missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)."
    );
  }
  cachedServiceRoleClient = createClient(
    env.SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false
      },
      db: {
        schema: "public"
      }
    }
  );
  return cachedServiceRoleClient;
}
