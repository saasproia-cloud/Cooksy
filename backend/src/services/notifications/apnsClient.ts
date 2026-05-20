import crypto from "node:crypto";
import http2 from "node:http2";

import { env, providerStatus } from "../../config/env.js";
import type { ApnsEnvironment } from "./types.js";

/**
 * Direct APNs HTTP/2 client.
 *
 * Why not a third-party lib?
 *   - We control all the moving parts (cert rotation, transient failures,
 *     bad-device-token handling) without taking an additional dependency
 *     that frequently goes stale around Node version bumps.
 *   - APNs over HTTP/2 + JWT is well-documented and stable since 2016.
 *     The whole client fits in ~150 lines.
 *
 * Auth model:
 *   We use the .p8 token-based auth, not the legacy provider certificate.
 *   A JWT is signed with the team's ES256 private key, with the kid =
 *   APNS_KEY_ID and iss = APNS_TEAM_ID. Apple recommends rotating the JWT
 *   roughly every 20–60 minutes (we use 45 min). Reuse the same JWT
 *   across requests during that window; signing too often gets you rate
 *   limited (TooManyProviderTokenUpdates).
 *
 * Connection model:
 *   One persistent HTTP/2 session per environment (sandbox vs production)
 *   reused across requests. APNs supports thousands of multiplexed
 *   streams on a single session. We re-open on session errors and on
 *   long-running idleness.
 */

const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com"
};

const JWT_TTL_SECONDS = 45 * 60;          // refresh well under Apple's 60-minute cap
const JWT_REFRESH_MARGIN_SECONDS = 30;    // refresh slightly early

type CachedJwt = {
  token: string;
  expiresAt: number; // epoch seconds
};
let cachedJwt: CachedJwt | null = null;

// Sessions are keyed by environment so we can serve sandbox builds and
// production builds in parallel from the same backend without crossing
// streams.
const sessions: Map<ApnsEnvironment, http2.ClientHttp2Session> = new Map();

/**
 * Convert the APNS_AUTH_KEY env var (PEM or base64-of-PEM) to a raw PEM
 * string. Apple ships .p8 as a PEM; some hosts (Railway) mangle multi-
 * line secrets, so we accept the base64-encoded form too.
 */
function readAuthKeyPem(): string {
  const raw = env.APNS_AUTH_KEY.trim();
  if (raw.startsWith("-----BEGIN")) {
    return raw;
  }
  try {
    return Buffer.from(raw, "base64").toString("utf8");
  } catch {
    return raw;
  }
}

/**
 * Build (or reuse) a valid APNs provider JWT. ES256-signed, kid + iss
 * matching the Apple Developer console identifiers. Cached for
 * JWT_TTL_SECONDS so we don't burn CPU and stay clear of Apple's "too
 * many token updates" rate limit.
 */
function getProviderJwt(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expiresAt - JWT_REFRESH_MARGIN_SECONDS > now) {
    return cachedJwt.token;
  }

  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const payload = { iss: env.APNS_TEAM_ID, iat: now };

  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  // ES256: SHA-256 over the signing input, signed with the EC P-256 private
  // key. Node returns a DER-encoded ASN.1 signature; APNs (like all JWTs)
  // wants raw R||S concatenation (64 bytes), so we convert.
  const signer = crypto.createSign("SHA256");
  signer.update(signingInput);
  signer.end();
  const derSig = signer.sign({
    key: readAuthKeyPem(),
    format: "pem",
    type: "pkcs8"
  });
  const rawSig = derToJoseSignature(derSig);
  const sigB64 = rawSig.toString("base64url");

  const token = `${signingInput}.${sigB64}`;
  cachedJwt = { token, expiresAt: now + JWT_TTL_SECONDS };
  return token;
}

/**
 * Convert a DER-encoded ECDSA signature to the raw 64-byte JOSE form
 * (R || S, big-endian, zero-padded to 32 bytes each). Node's crypto API
 * gives us DER; JWT requires the concatenated form.
 */
function derToJoseSignature(derSig: Buffer): Buffer {
  // DER ECDSA: SEQUENCE { INTEGER r, INTEGER s }.
  // Layout: 0x30 <total-len> 0x02 <r-len> <r> 0x02 <s-len> <s>
  let offset = 2; // skip 0x30 len
  if (derSig[1] === 0x81) offset = 3; // long-form length
  if (derSig[offset] !== 0x02) {
    throw new Error("Invalid DER signature: expected INTEGER tag for r");
  }
  const rLen = derSig[offset + 1];
  const rStart = offset + 2;
  const r = derSig.subarray(rStart, rStart + rLen);

  offset = rStart + rLen;
  if (derSig[offset] !== 0x02) {
    throw new Error("Invalid DER signature: expected INTEGER tag for s");
  }
  const sLen = derSig[offset + 1];
  const sStart = offset + 2;
  const s = derSig.subarray(sStart, sStart + sLen);

  // Zero-pad / left-trim to a fixed 32 bytes each (P-256).
  const rPadded = leftPadOrTrim(r, 32);
  const sPadded = leftPadOrTrim(s, 32);
  return Buffer.concat([rPadded, sPadded]);
}

function leftPadOrTrim(buf: Buffer, length: number): Buffer {
  if (buf.length === length) return buf;
  if (buf.length > length) return buf.subarray(buf.length - length);
  const out = Buffer.alloc(length, 0);
  buf.copy(out, length - buf.length);
  return out;
}

function base64url(value: string | Buffer): string {
  return Buffer.from(value as string).toString("base64url");
}

/**
 * Acquire (or open) the persistent HTTP/2 session for the given env.
 */
function getSession(environment: ApnsEnvironment): http2.ClientHttp2Session {
  const existing = sessions.get(environment);
  if (existing && !existing.closed && !existing.destroyed) {
    return existing;
  }
  const session = http2.connect(APNS_HOSTS[environment]);
  session.on("error", (err) => {
    console.warn("[apns] session error", { environment, message: err.message });
    sessions.delete(environment);
  });
  session.on("close", () => {
    sessions.delete(environment);
  });
  // We don't need keep-alive timers — APNs idles cleanly and we'll
  // re-open on demand. But guard against ECONNRESET under low traffic
  // by sending an HTTP/2 PING every 5 minutes.
  const pingTimer = setInterval(() => {
    if (session.closed || session.destroyed) {
      clearInterval(pingTimer);
      return;
    }
    session.ping(() => undefined);
  }, 5 * 60 * 1000);
  pingTimer.unref();
  sessions.set(environment, session);
  return session;
}

export type ApnsSendResult = {
  statusCode: number;
  body: string;
  apnsId: string | null;
  reason: string | null;
};

export type ApnsPayload = {
  title: string;
  body: string;
  deepLink?: string | null;
  threadId?: string;
  badge?: number;
  sound?: string;
  /**
   * Extra custom keys delivered alongside `aps`. Used to round-trip the
   * dispatch_id so iOS can beacon back open/tap.
   */
  customData?: Record<string, unknown>;
  /**
   * apns-push-type: "alert" (default) for user-visible, "background" for silent.
   */
  pushType?: "alert" | "background";
  /**
   * apns-priority: 10 (immediate, default) or 5 (eco — APNs may bundle).
   */
  priority?: 5 | 10;
  /**
   * Optional expiration; APNs drops the message if undeliverable after.
   * Defaults to 1 day.
   */
  expiresAt?: Date;
};

/**
 * Send a single APNs push to a device token.
 *
 * Returns the raw status code so callers can decide what to do:
 *   - 200            → delivered to APNs (the device may still be offline)
 *   - 410            → token is gone; caller must mark `disabled_at`
 *   - 400 BadDeviceToken / DeviceTokenNotForTopic → mark disabled too
 *   - 429            → caller should back off and retry
 *   - 500/503        → transient; caller should retry with jitter
 *
 * The caller is responsible for logging and DB writes — this function
 * stays narrowly focused on the transport.
 */
export async function sendApnsPush(
  apnsToken: string,
  payload: ApnsPayload,
  environment: ApnsEnvironment = env.APNS_ENVIRONMENT
): Promise<ApnsSendResult> {
  if (!providerStatus.apns) {
    throw new Error(
      "APNs credentials are not configured. Set APNS_AUTH_KEY / APNS_KEY_ID / APNS_TEAM_ID / APNS_BUNDLE_ID."
    );
  }

  const apsPayload: Record<string, unknown> = {
    aps: {
      alert: {
        title: payload.title,
        body: payload.body
      },
      sound: payload.sound ?? "default",
      "thread-id": payload.threadId,
      ...(typeof payload.badge === "number" ? { badge: payload.badge } : {})
    }
  };
  if (payload.deepLink) {
    apsPayload["cooksy_deep_link"] = payload.deepLink;
  }
  if (payload.customData) {
    Object.assign(apsPayload, payload.customData);
  }

  const session = getSession(environment);
  const expirationEpoch = payload.expiresAt
    ? Math.floor(payload.expiresAt.getTime() / 1000)
    : Math.floor(Date.now() / 1000) + 24 * 3600;

  const headers: Record<string, string | number> = {
    ":method": "POST",
    ":path": `/3/device/${apnsToken}`,
    authorization: `bearer ${getProviderJwt()}`,
    "apns-topic": env.APNS_BUNDLE_ID,
    "apns-push-type": payload.pushType ?? "alert",
    "apns-priority": String(payload.priority ?? 10),
    "apns-expiration": String(expirationEpoch),
    "content-type": "application/json"
  };

  const bodyJson = JSON.stringify(apsPayload);

  return new Promise((resolve, reject) => {
    const req = session.request(headers);
    let responseStatus = 0;
    let apnsId: string | null = null;
    let body = "";

    req.on("response", (resHeaders) => {
      responseStatus = Number(resHeaders[":status"] ?? 0);
      const idHeader = resHeaders["apns-id"];
      apnsId = typeof idHeader === "string" ? idHeader : null;
    });
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      let reason: string | null = null;
      if (responseStatus >= 400 && body) {
        try {
          const parsed = JSON.parse(body) as { reason?: string };
          reason = parsed.reason ?? null;
        } catch {
          // Non-JSON body, ignore.
        }
      }
      resolve({ statusCode: responseStatus, body, apnsId, reason });
    });
    req.on("error", reject);

    req.write(bodyJson);
    req.end();
  });
}

/**
 * Close all persistent HTTP/2 sessions. Useful in tests; in production
 * the sessions are reaped on process exit automatically.
 */
export function shutdownApnsClient(): void {
  for (const session of sessions.values()) {
    session.close();
  }
  sessions.clear();
  cachedJwt = null;
}
