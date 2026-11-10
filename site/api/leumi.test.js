import test from "node:test";
import assert from "node:assert/strict";
import { POST, GET } from "./leumi.js";
import { INVALID_PASSWORD, BLOCKED, FIREWALL_REJECTED } from "./leumiLogin.js";

const b64 = (bytes) => Buffer.from(bytes).toString("base64");

async function makeResponseKey() {
  const key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["decrypt"]);
  return { key, raw: b64(await crypto.subtle.exportKey("raw", key)) };
}

async function seal(fields, { ts = Date.now(), iv = crypto.getRandomValues(new Uint8Array(12)), responseKey } = {}) {
  const { publicKey } = await (await GET(new Request("https://site.example/api/leumi"))).json();
  const rsa = await crypto.subtle.importKey("jwk", publicKey, { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
  const aes = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt"]);
  const rk = responseKey ?? (await makeResponseKey());
  const plain = new TextEncoder().encode(JSON.stringify({ ...fields, ts, responseKey: rk.raw }));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, aes, plain);
  const k = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, rsa, await crypto.subtle.exportKey("raw", aes));
  return { body: JSON.stringify({ v: 1, k: b64(k), iv: b64(iv), ct: b64(ct) }), responseKey: rk };
}

/** A fake headless driver: `loginScript` drives the login state machine
 * (see leumiLogin.test.js), `pages` answers fetchText/postJSON in order
 * (SPA.aspx, then the three broker calls). */
function fakeOpen({ loginScript = ["account"], pages = [] } = {}) {
  return async (_browser, { cookies = [] } = {}) => {
    let state = cookies.length ? "account" : "login"; // a restored session starts already signed in
    let step = 0;
    let i = 0;
    const calls = [];
    const formPresent = () => !["account", "changePassword", "digitalfront"].includes(state);
    return {
      calls,
      async load(url) { calls.push(["load", url]); },
      async waitForElement() {},
      async fill() {},
      async click() { state = loginScript[Math.min(step, loginScript.length - 1)]; step++; },
      async url() {
        return state === "account" ? "https://hb2.bankleumi.co.il/eBanking/SO/SPA.aspx"
          : state === "digitalfront" ? "https://hb2.bankleumi.co.il/digitalfront/x" : "https://hb2.bankleumi.co.il/authenticate/logon";
      },
      async exists(sel) { return sel.includes("newPwd") ? state === "changePassword" : formPresent(); },
      async bodyText() { return ({ blocked: BLOCKED, rejected: FIREWALL_REJECTED, refused: INVALID_PASSWORD })[state] ?? ""; },
      async fetchText(url) { calls.push(["fetchText", url]); return pages[i++]; },
      async postJSON(url, body) { calls.push(["postJSON", url]); return pages[i++]; },
      async cookies() { return [{ name: "sess", value: "tok", domain: "hb2.bankleumi.co.il" }]; },
      async close() { calls.push(["close"]); },
    };
  };
}

const closedBrowser = { closed: false, async close() { this.closed = true; } };
const launch = async () => Object.assign({}, closedBrowser);

const inner = (obj) => JSON.stringify({ jsonResp: JSON.stringify(obj) });
const accountPages = (txns = []) => [
  '"SessionID":"abc"', inner({}), inner({ AccountsItems: [{ MaskedNumber: "1/2/3" }] }), inner({ result: { transactions: txns } }),
];

// `now` is a fresh counter so the login loop (which compares `now()` to a
// deadline) never relies on real wall-clock time: a bug that makes a test
// never reach its expected outcome then fails fast instead of spinning for
// the real (75s default) timeout.
const fast = () => ({ settleMs: 0, sleep: async () => {}, now: (() => { let t = 0; return () => (t += 1000); })(), timeoutMs: 30_000 });

const call = async (fields, { headers = {}, ip = "1.1.1.1", loginOptions = fast(), accountOptions = { sleep: async () => {} }, ...deps } = {}) => {
  const sealed = await seal(fields);
  const res = await POST(new Request("https://site.example/api/leumi", {
    method: "POST",
    headers: { "content-type": "application/json", origin: "https://site.example", "x-forwarded-for": ip, ...headers },
    body: sealed.body,
  }), { ...deps, loginOptions, accountOptions });
  return { res, responseKey: sealed.responseKey };
};

async function open(res, responseKey) {
  const { iv, ct } = await res.json();
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: Uint8Array.from(Buffer.from(iv, "base64")) },
    responseKey.key, Uint8Array.from(Buffer.from(ct, "base64")));
  return JSON.parse(new TextDecoder().decode(plain));
}

test("GET gives the public key (same key pair as the Max relay, since RELAY_PRIVATE_KEY is shared)", async () => {
  const res = GET(new Request("https://site.example/api/leumi"));
  const { publicKey } = await res.json();
  assert.equal(publicKey.kty, "RSA");
});

test("a successful login returns the account, encrypted, with a session token, and closes the browser", async () => {
  const browser = Object.assign({}, closedBrowser);
  const { res, responseKey } = await call(
    { mode: "login", username: "u", password: "p" },
    { launch: async () => browser, open: fakeOpen({ pages: accountPages([{ id: 1 }]) }) });
  assert.equal(res.status, 200);
  const body = await open(res, responseKey);
  assert.equal(body.number, "1_2_3");
  assert.deepEqual(JSON.parse(JSON.parse(body.body).jsonResp).result.transactions, [{ id: 1 }]);
  assert.equal(typeof body.session, "string");
  assert.equal(browser.closed, true);
});

test("a refused login answers 401 with a distinct code, not 'session'", async () => {
  const { res } = await call(
    { mode: "login", username: "u", password: "p" },
    { launch, open: fakeOpen({ loginScript: ["refused"] }), ip: "2.2.2.2" });
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: "refused" });
});

test("a blocked subscription and a forced password change get their own status and error code", async () => {
  const r1 = await call({ mode: "login", username: "u", password: "p" }, { launch, open: fakeOpen({ loginScript: ["blocked"] }), ip: "3.3.3.1" });
  assert.equal(r1.res.status, 403);
  assert.deepEqual(await r1.res.json(), { error: "blocked" });

  const r2 = await call({ mode: "login", username: "u", password: "p" }, { launch, open: fakeOpen({ loginScript: ["changePassword"] }), ip: "3.3.3.2" });
  assert.equal(r2.res.status, 409);
  assert.deepEqual(await r2.res.json(), { error: "changePassword" });
});

test("the browser is still closed when the login throws", async () => {
  const browser = Object.assign({}, closedBrowser);
  const { res } = await call({ mode: "login", username: "u", password: "p" }, { launch: async () => browser, open: fakeOpen({ loginScript: ["refused"] }), ip: "4.4.4.1" });
  assert.equal(res.status, 401);
  assert.equal(browser.closed, true);
});

test("a session token restores cookies into a fresh driver and skips the login entirely", async () => {
  const first = await call({ mode: "login", username: "u", password: "p" }, { launch, open: fakeOpen({ pages: accountPages() }), ip: "5.5.5.1" });
  const body1 = await open(first.res, first.responseKey);

  let loginCalled = false;
  const open2 = fakeOpen({ pages: accountPages([{ id: 2 }]) });
  const wrapped = async (browser, opts) => {
    const d = await open2(browser, opts);
    const origClick = d.click;
    d.click = async (...a) => { loginCalled = true; return origClick(...a); };
    return d;
  };
  const second = await call({ mode: "refresh", token: body1.session }, { launch, open: wrapped, ip: "5.5.5.1" });
  assert.equal(second.res.status, 200);
  const body2 = await open(second.res, second.responseKey);
  assert.deepEqual(JSON.parse(JSON.parse(body2.body).jsonResp).result.transactions, [{ id: 2 }]);
  assert.equal(loginCalled, false); // no click() happened: the login form was never touched
});

test("a forged or wrong-scope token (e.g. a Max one) is refused with 'session', not silently accepted", async () => {
  const { res } = await call({ mode: "refresh", token: "not-a-real-token" }, { launch, open: fakeOpen() });
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: "session" });
});

test("more than 4 fresh-login attempts a minute from one IP is limited (refreshes are not)", async () => {
  const statuses = [];
  for (let i = 0; i < 6; i++) {
    const { res } = await call({ mode: "login", username: "u", password: "p" }, { launch, open: fakeOpen({ loginScript: ["refused"] }), ip: "6.6.6.1" });
    statuses.push(res.status);
  }
  assert.deepEqual(statuses, [401, 401, 401, 401, 429, 429]);
});

test("another website cannot use the relay", async () => {
  const { res } = await call({ mode: "login", username: "u", password: "p" }, { headers: { origin: "https://evil.example" }, launch, open: fakeOpen(), ip: "7.7.7.1" });
  assert.equal(res.status, 403);
});
