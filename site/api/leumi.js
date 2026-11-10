// Headless-browser relay for Leumi. Max accepts a plain HTTP login; Leumi
// does not (its login is a token signed by Transmit Security's JS SDK,
// checked by an F5 anti-bot layer), so this runs a real, sandboxed Chromium
// instead — the same idea as the iPhone app's hidden WKWebView, just on the
// server instead of the phone, which is what makes it work from any device,
// including mobile browsers that can't run the Leumi bookmarklet well.
//
// Encrypted like the Max relay (request, response, and a sealed session
// token so a refresh skips the login) — see api/_crypto.js. Not end-to-end:
// this server does see the password for the one call Leumi's login needs it
// for, same limit as Max, confirmed with the user. Nothing is stored, nothing
// is logged.
//
// A refresh restores the saved cookies into a *new* browser page and reads
// the account again, rather than replaying them with a bare HTTP request:
// Leumi's anti-bot may tie a session to the browser that created it (TLS/JS
// fingerprint), not just its cookies, so a real browser stays the safe way
// to speak to it even on a refresh. Slower than Max's refresh, not free, but
// avoids guessing at a browserless shortcut that could get flagged.

import { corsHeaders, json, makeLoginLimiter, openEnvelope, originGuard, preflight, publicKeyJWK, sealAnswer, sealSession, openSession } from "./_crypto.js";
import { login, LeumiLoginError } from "./leumiLogin.js";
import { readAccount } from "./leumiAccount.js";
import { launchBrowser, openDriver } from "./leumiDriver.js";

const SESSION_TTL_MS = 20 * 60_000;
const limited = makeLoginLimiter();

const STATUS_BY_CODE = {
  refused: 401, blocked: 403, changePassword: 409, unsupported: 502, firewall: 502, timeout: 504,
};

export const OPTIONS = preflight;

export async function POST(request, { launch = launchBrowser, open = openDriver, loginOptions = {}, accountOptions = {} } = {}) {
  const { origin, ok } = originGuard(request);
  if (!ok) return json({ error: "forbidden" }, 403, origin);
  if (!(request.headers.get("content-type") ?? "").includes("application/json")) return json({ error: "bad request" }, 400, origin);

  const ip = (request.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();

  let fields;
  try {
    const text = await request.text();
    if (text.length > 6000) return json({ error: "bad request" }, 400, origin);
    fields = openEnvelope(text);
  } catch {
    return json({ error: "bad request" }, 400, origin);
  }
  if (!fields) return json({ error: "bad request" }, 400, origin);
  const { mode, username, password, token, responseKey } = fields;

  let resumed = null; // { cookies, number } from a session token, when refreshing
  if (mode === "refresh") {
    const session = openSession(token, "leumi");
    if (!session) return json({ error: "session" }, 401, origin); // expired or invalid: the page should ask to sign in again
    resumed = session;
  } else {
    if (limited(ip)) return json({ error: "rate limited" }, 429, origin);
    if (typeof username !== "string" || typeof password !== "string" || !username || !password
        || username.length > 200 || password.length > 200) {
      return json({ error: "bad request" }, 400, origin);
    }
  }

  let browser;
  try {
    browser = await launch();
    const driver = await open(browser, { cookies: resumed?.cookies ?? [] });
    try {
      if (!resumed) {
        await login(driver, { username, password }, loginOptions);
      } else {
        await driver.load(`https://hb2.bankleumi.co.il/eBanking/SO/SPA.aspx`);
      }
      // The account page can still be settling (Leumi's SPA does its own
      // client-side redirects right after this) — a short wait here is
      // cheaper than hitting the same navigation race in readAccount.
      await new Promise((r) => setTimeout(r, loginOptions.settleMs === 0 ? 0 : 1500));
      const { number, body } = await readAccount(driver, accountOptions);
      const cookies = await driver.cookies();
      const session = sealSession({ cookies, scope: "leumi" }, SESSION_TTL_MS);
      return new Response(sealAnswer(responseKey, { number, body, session }), {
        status: 200,
        headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...corsHeaders(origin) },
      });
    } finally {
      await driver.close();
    }
  } catch (error) {
    if (error instanceof LeumiLoginError) {
      // Safe to log: a code and a message about the page/flow, never credentials, cookies or tokens.
      console.error(`[leumi] ${error.code}: ${error.message}`);
      return json({ error: error.code }, STATUS_BY_CODE[error.code] ?? 502, origin);
    }
    console.error(`[leumi] unexpected: ${error?.name ?? "error"}: ${error?.message ?? ""}`);
    return json({ error: "unavailable", detail: String(error?.name ?? "error") }, 502, origin);
  } finally {
    await browser?.close();
  }
}

/** The public key the page encrypts with — the same key pair as the Max relay (same `RELAY_PRIVATE_KEY`). */
export function GET(request) {
  const { origin, ok } = originGuard(request);
  if (!ok) return json({ error: "forbidden" }, 403, origin);
  try {
    return json({ publicKey: publicKeyJWK() }, 200, origin);
  } catch {
    return json({ error: "unavailable" }, 500, origin);
  }
}
