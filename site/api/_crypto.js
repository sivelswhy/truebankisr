// Shared crypto for every relay (Max, Leumi): decrypting what the browser
// encrypted, encrypting the answer back, and sealing a session so the bank
// password is not needed on every refresh.
//
// Two separate keys:
// - RELAY_PRIVATE_KEY (RSA): wraps the one-time AES key the browser generates
//   per request. Needed so every warm instance can decrypt (they don't share
//   memory). Make one: `node keygen.js | vercel env add RELAY_PRIVATE_KEY production`.
// - SESSION_SECRET (AES-256): seals a session token (the bank's cookies,
//   never the password) so the server stays stateless: the token *is* the
//   state, encrypted. Make one: `node session-keygen.js | vercel env add SESSION_SECRET production`.
// Locally, both are made fresh at startup if missing, so old tokens and a
// restarted dev server don't mix.

import {
  constants, createCipheriv, createDecipheriv, createPrivateKey, createPublicKey,
  generateKeyPairSync, privateDecrypt, randomBytes,
} from "node:crypto";

let cachedRelayKey;
export function relayKey() {
  if (cachedRelayKey) return cachedRelayKey;
  const env = process.env.RELAY_PRIVATE_KEY;
  if (env) {
    const pem = env.includes("BEGIN") ? env.replace(/\\n/g, "\n") : Buffer.from(env, "base64").toString("utf8");
    cachedRelayKey = createPrivateKey(pem);
  } else if (process.env.VERCEL) {
    throw new Error("RELAY_PRIVATE_KEY is not set");
  } else {
    cachedRelayKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
  }
  return cachedRelayKey;
}

/** The public half, as a JWK the browser's `crypto.subtle.importKey` accepts. */
export function publicKeyJWK() {
  return createPublicKey(relayKey()).export({ format: "jwk" });
}

let cachedSessionSecret;
function sessionSecret() {
  if (cachedSessionSecret) return cachedSessionSecret;
  const env = process.env.SESSION_SECRET;
  if (env) {
    cachedSessionSecret = Buffer.from(env, "base64");
  } else if (process.env.VERCEL) {
    throw new Error("SESSION_SECRET is not set");
  } else {
    cachedSessionSecret = randomBytes(32);
  }
  if (cachedSessionSecret.length !== 32) throw new Error("SESSION_SECRET must be 32 bytes");
  return cachedSessionSecret;
}

const MAX_AGE_MS = 60_000;
const seen = new Map(); // iv → time, so a captured request cannot be replayed

/**
 * Decrypts the browser's envelope: `{ v:1, k, iv, ct }`, `k` RSA-OAEP-wrapped
 * AES-256 key, `ct` AES-GCM of a JSON object that must carry `ts` (freshness)
 * and `responseKey` (base64, 32 bytes: the server encrypts its answer with it,
 * so the answer is unreadable without it either). Returns the parsed object,
 * or null when it is missing, malformed, stale, or a replay.
 */
export function openEnvelope(text) {
  try {
    const { v, k, iv, ct } = JSON.parse(text);
    if (v !== 1 || ![k, iv, ct].every((x) => typeof x === "string")) return null;
    const aesKey = privateDecrypt({ key: relayKey(), padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" }, Buffer.from(k, "base64"));
    const data = Buffer.from(ct, "base64");
    if (aesKey.length !== 32 || data.length < 17) return null;
    const decipher = createDecipheriv("aes-256-gcm", aesKey, Buffer.from(iv, "base64"));
    decipher.setAuthTag(data.subarray(data.length - 16));
    const plain = JSON.parse(Buffer.concat([decipher.update(data.subarray(0, data.length - 16)), decipher.final()]).toString("utf8"));
    const { ts, responseKey } = plain;
    const now = Date.now();
    if (typeof ts !== "number" || Math.abs(now - ts) > MAX_AGE_MS) return null;
    if (typeof responseKey !== "string" || Buffer.from(responseKey, "base64").length !== 32) return null;
    for (const [key, time] of seen) if (now - time > MAX_AGE_MS * 2) seen.delete(key);
    if (seen.has(iv)) return null;
    seen.set(iv, now);
    return plain;
  } catch {
    return null;
  }
}

/** Encrypts the answer with the one-time key the browser sent: `{ iv, ct }`, both base64. */
export function sealAnswer(responseKeyB64, obj) {
  const key = Buffer.from(responseKeyB64, "base64");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ct = Buffer.concat([cipher.update(JSON.stringify(obj), "utf8"), cipher.final(), cipher.getAuthTag()]);
  return JSON.stringify({ iv: iv.toString("base64"), ct: ct.toString("base64") });
}

/**
 * Seals a session (cookies, never the password) with the server's own secret:
 * an opaque token the client holds and replays, so the next refresh skips the
 * login. `scope` says which bank it is for, so one token cannot be reused for
 * the other relay.
 */
export function sealSession(payload, ttlMs) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", sessionSecret(), iv);
  const body = JSON.stringify({ ...payload, exp: Date.now() + ttlMs });
  const ct = Buffer.concat([cipher.update(body, "utf8"), cipher.final(), cipher.getAuthTag()]);
  return Buffer.concat([iv, ct]).toString("base64");
}

/** Opens a session token: the payload, or null when it is malformed, forged, or expired. */
export function openSession(token, scope) {
  try {
    const raw = Buffer.from(token, "base64");
    const iv = raw.subarray(0, 12);
    const data = raw.subarray(12);
    const decipher = createDecipheriv("aes-256-gcm", sessionSecret(), iv);
    decipher.setAuthTag(data.subarray(data.length - 16));
    const payload = JSON.parse(Buffer.concat([decipher.update(data.subarray(0, data.length - 16)), decipher.final()]).toString("utf8"));
    if (payload.scope !== scope || typeof payload.exp !== "number" || Date.now() > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}

/** Best effort, per warm instance: a few login attempts a minute per IP, so the relay is not a convenient tool to guess a password. */
export function makeLoginLimiter(max = 4) {
  const attempts = new Map();
  return function limited(ip) {
    const now = Date.now();
    const recent = (attempts.get(ip) ?? []).filter((t) => now - t < 60_000);
    recent.push(now);
    attempts.set(ip, recent);
    if (attempts.size > 5000) attempts.clear();
    return recent.length > max;
  };
}

// The static page can be hosted elsewhere (GitHub Pages) while this relay
// stays on Vercel: these are the pages allowed to call it cross-origin, on
// top of the relay's own origin (always allowed, same-site).
export const ALLOWED_ORIGINS = ["https://sivelswhy.github.io"];

export const allowedOrigin = (origin) => ALLOWED_ORIGINS.includes(origin);

export function corsHeaders(origin) {
  return allowedOrigin(origin)
    ? { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type", Vary: "Origin" }
    : {};
}

export function json(body, status = 200, origin = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...corsHeaders(origin) },
  });
}

/** Same-origin (this relay serving its own page) or one of `ALLOWED_ORIGINS` (the page elsewhere, e.g. GitHub Pages). */
export function originGuard(request) {
  const origin = request.headers.get("origin");
  if (!origin) return { origin: null, ok: true }; // no Origin header: not a browser cross-origin call
  const sameHost = new URL(origin).host === new URL(request.url).host;
  return { origin, ok: sameHost || allowedOrigin(origin) };
}

/** Preflight for a cross-origin POST (its JSON content type makes the browser send one first). */
export function preflight(request) {
  const { origin, ok } = originGuard(request);
  return new Response(null, { status: ok ? 204 : 403, headers: corsHeaders(origin) });
}
