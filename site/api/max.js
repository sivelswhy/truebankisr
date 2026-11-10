// Stateless relay to Max. Receives the credentials (encrypted in the browser),
// logs in to max.co.il with them, and returns the data (encrypted too) along
// with a sealed session token, so the next refresh can skip the login — the
// token holds Max's own cookies, never the password, and only this server can
// open it. Nothing is stored, nothing is logged (never log the request body).
// Max does not allow calls from other websites (CORS), which is why a page
// alone cannot do this.

import { corsHeaders, json, makeLoginLimiter, openEnvelope, originGuard, preflight, publicKeyJWK, sealAnswer, sealSession, openSession } from "./_crypto.js";

const BASE = "https://www.max.co.il";
const VERSION = "V4.224-RC.10.260";
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36";
const MONTHS_BACK = 3;
const MONTHS_AHEAD = 2;
const SESSION_TTL_MS = 20 * 60_000;

const limited = makeLoginLimiter();

/** "a=1; Path=/" lines → one Cookie header, keeping the newest value per name. */
function mergeCookies(jar, response) {
  for (const line of response.headers.getSetCookie?.() ?? []) {
    const pair = line.split(";")[0];
    const i = pair.indexOf("=");
    if (i > 0) jar.set(pair.slice(0, i).trim(), pair.slice(i + 1).trim());
  }
}
const cookieHeader = (jar) => [...jar].map(([k, v]) => `${k}=${v}`).join("; ");
const jarToPairs = (jar) => [...jar];
const pairsToJar = (pairs) => new Map(Array.isArray(pairs) ? pairs : []);

function headers(jar, extra = {}) {
  return {
    "User-Agent": UA,
    Accept: "application/json, text/plain, */*",
    Origin: BASE,
    Referer: BASE + "/",
    Cookie: cookieHeader(jar),
    ...extra,
  };
}

function monthsList(now = new Date()) {
  const israel = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jerusalem", year: "numeric", month: "2-digit" })
    .formatToParts(now);
  const year = Number(israel.find((p) => p.type === "year").value);
  const month = Number(israel.find((p) => p.type === "month").value);
  const out = [];
  for (let d = -MONTHS_BACK; d <= MONTHS_AHEAD; d++) {
    const index = year * 12 + (month - 1) + d;
    out.push({ year: Math.floor(index / 12), month: (index % 12) + 1 });
  }
  return out;
}

function transactionsURL({ year, month }) {
  const filter = JSON.stringify({
    userIndex: -1, cardIndex: -1, monthView: true, date: `${year}-${month}-01`,
    dates: { startDate: "0", endDate: "0" }, bankAccount: { bankAccountIndex: -1, cards: null },
  });
  const url = new URL(`${BASE}/api/registered/transactionDetails/getTransactionsAndGraphs`);
  url.searchParams.set("filterData", filter);
  url.searchParams.set("firstCallCardIndex", "-1null");
  url.searchParams.set("v", VERSION);
  return url.toString();
}

/** Logs in with a fresh cookie jar. Throws `{ status, body }` on any failure. */
async function loginJar(username, password) {
  const jar = new Map();
  const res = await fetch(`${BASE}/api/login/login`, {
    method: "POST",
    headers: headers(jar, { "Content-Type": "application/json" }),
    body: JSON.stringify({ username, password, id: null }),
    signal: AbortSignal.timeout(20_000),
  });
  mergeCookies(jar, res);
  if (res.status !== 200) throw { status: 502, body: { error: "unavailable", detail: `login HTTP ${res.status}` } };
  const result = await res.json().catch(() => null);
  if (!result) throw { status: 502, body: { error: "unavailable", detail: "login: not JSON" } };
  if (result.ReturnCode !== 0 || result.Result?.LoginStatus !== 0) {
    // Max said no: stop here, never retry the same credentials.
    throw { status: 401, body: { error: "refused" } };
  }
  return jar;
}

/** Home page data and every month's transactions, using an already-signed-in jar. */
async function fetchData(jar) {
  const get = async (url) => {
    const res = await fetch(url, { headers: headers(jar), signal: AbortSignal.timeout(20_000) });
    mergeCookies(jar, res);
    return res.status === 200 ? await res.json().catch(() => null) : null;
  };
  const home = await get(`${BASE}/api/registered/getHomePageData`);
  const months = [];
  for (const m of monthsList()) {
    const body = await get(transactionsURL(m));
    if (body === null) throw { status: 502, body: { error: "unavailable", detail: `transactions ${m.year}-${m.month}` } };
    months.push(body);
  }
  return { home, months };
}

export const OPTIONS = preflight;

export async function POST(request) {
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

  try {
    let jar;
    if (mode === "refresh") {
      const session = openSession(token, "max");
      if (!session) return json({ error: "session" }, 401, origin); // expired or invalid: the page should ask to sign in again
      jar = pairsToJar(session.cookies);
    } else {
      if (limited(ip)) return json({ error: "rate limited" }, 429, origin);
      if (typeof username !== "string" || typeof password !== "string" || !username || !password
          || username.length > 200 || password.length > 200) {
        return json({ error: "bad request" }, 400, origin);
      }
      jar = await loginJar(username, password);
    }

    const data = await fetchData(jar);
    const session = sealSession({ cookies: jarToPairs(jar), scope: "max" }, SESSION_TTL_MS);
    return new Response(sealAnswer(responseKey, { ...data, session }), {
      status: 200,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...corsHeaders(origin) },
    });
  } catch (error) {
    if (error && typeof error.status === "number") return json(error.body, error.status, origin);
    return json({ error: "unavailable", detail: String(error?.name ?? "error") }, 502, origin);
  }
}

/** The public key the page encrypts with. */
export function GET(request) {
  const { origin, ok } = originGuard(request);
  if (!ok) return json({ error: "forbidden" }, 403, origin);
  try {
    return json({ publicKey: publicKeyJWK() }, 200, origin);
  } catch {
    return json({ error: "unavailable" }, 500, origin);
  }
}
