import test from "node:test";
import assert from "node:assert/strict";
import { leumiBookmarklet, bookmarkletHref, LEUMI_ORIGIN } from "./leumi.js";

const SITE = "https://site.example";

/** Runs the bookmark in a fake Leumi page. `reply` says how the site tab answers. */
async function run({ wait = 30, hostname = "hb2.bankleumi.co.il", viaOpener = true, reply = true, sessionHtml = '..."SessionID":"abc123"...' } = {}) {
  const calls = [];
  const alerts = [];
  const listeners = [];
  const sent = [];
  const target = { closed: false, postMessage: (data, origin) => { sent.push({ data, origin }); if (reply) for (const l of listeners) l({ origin: SITE, source: target, data: { type: "tb-ack" } }); } };
  const g = globalThis;
  const saved = { fetch: g.fetch, location: g.location, window: g.window, alert: g.alert, addEventListener: g.addEventListener, removeEventListener: g.removeEventListener };
  g.location = { hostname, origin: `https://${hostname}` };
  g.alert = (m) => alerts.push(m);
  g.addEventListener = (type, fn) => listeners.push(fn);
  g.removeEventListener = () => {};
  g.window = { opener: viaOpener ? target : null, name: viaOpener ? "tb-site" : "", open: () => null };
  g.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), body: init.body ? JSON.parse(init.body) : null });
    if (String(url).endsWith("/SPA.aspx")) return new Response(sessionHtml);
    const module = new URL(url).searchParams.get("moduleName");
    const inner = module === "UC_SO_GetAccounts" ? { AccountsItems: [{ MaskedNumber: "123/45/678" }] } : { BalanceDisplay: 10 };
    return new Response(JSON.stringify({ jsonResp: JSON.stringify(inner) }));
  };
  try {
    leumiBookmarklet(SITE);
    await new Promise((r) => setTimeout(r, wait));
  } finally {
    Object.assign(g, saved);
  }
  return { calls, alerts, sent };
}

test("refuses to run outside Leumi's site", async () => {
  const r = await run({ hostname: "evil.example" });
  assert.match(r.alerts[0], /Leumi's site/);
  assert.equal(r.calls.length, 0);
});

test("reads the account with the page's session and posts it to the site tab only", async () => {
  const r = await run();
  assert.deepEqual(r.calls.map((c) => c.url.split("?")[0].split("/").slice(-1)[0] + ":" + (c.body ? c.body.moduleName : "")), [
    "SPA.aspx:", "ProcessRequest:UC_SO_010_02_GetDefaultAccountIndex", "ProcessRequest:UC_SO_GetAccounts", "ProcessRequest:UC_SO_27_GetBusinessAccountTrx",
  ]);
  const req = JSON.parse(r.calls[3].body.reqObj);
  assert.equal(req.SessionHeader.SessionID, "abc123");
  assert.equal(req.AccountIndex, 1);
  assert.match(req.FromDateUTC, /GMT$/);
  assert.equal(r.sent.length, 1);
  assert.equal(r.sent[0].origin, SITE);
  assert.equal(r.sent[0].data.type, "tb-leumi");
  assert.equal(r.sent[0].data.number, "123_45_678");
  assert.match(r.alerts.at(-1), /sent/);
});

test("says so when the user is not signed in", async () => {
  const r = await run({ sessionHtml: "<html>login</html>" });
  assert.match(r.alerts.at(-1), /sign in/);
  assert.equal(r.sent.length, 0);
});

test("says so when the site tab does not answer", async () => {
  const r = await run({ reply: false, wait: 4300 });
  assert.equal(r.sent.length, 1);
  assert.match(r.alerts.at(-1), /did not answer/);
});

test("the bookmark address is a javascript: URL that carries the site origin", () => {
  const href = bookmarkletHref(SITE);
  assert.ok(href.startsWith("javascript:"));
  const code = decodeURIComponent(href.slice("javascript:".length));
  assert.ok(code.includes('("https://site.example")'));
  assert.doesNotThrow(() => new Function(code));
});

test("only Leumi origins are accepted by the page", () => {
  assert.ok(LEUMI_ORIGIN.test("https://hb2.bankleumi.co.il"));
  assert.ok(!LEUMI_ORIGIN.test("https://bankleumi.co.il.evil.com"));
  assert.ok(!LEUMI_ORIGIN.test("http://hb2.bankleumi.co.il"));
  assert.ok(!LEUMI_ORIGIN.test("https://evilbankleumi.co.il"));
});
