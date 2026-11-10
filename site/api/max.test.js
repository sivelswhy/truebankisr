import test from "node:test";
import assert from "node:assert/strict";
import { POST, GET } from "./max.js";

// Same steps as the browser: AES-GCM with a one-time key, wrapped with the relay's public key.
// The browser also generates a *second* one-time key (responseKey) the server
// encrypts its answer with, and decrypts the answer the same way.
const b64 = (bytes) => Buffer.from(bytes).toString("base64");

async function makeResponseKey() {
  const key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["decrypt"]);
  const raw = await crypto.subtle.exportKey("raw", key);
  return { key, raw: b64(raw) };
}

async function seal(fields, { ts = Date.now(), iv = crypto.getRandomValues(new Uint8Array(12)), responseKey } = {}) {
  const { publicKey } = await (await GET(new Request("https://site.example/api/max"))).json();
  const rsa = await crypto.subtle.importKey("jwk", publicKey, { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
  const aes = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt"]);
  const rk = responseKey ?? (await makeResponseKey());
  const plain = new TextEncoder().encode(JSON.stringify({ ...fields, ts, responseKey: rk.raw }));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, aes, plain);
  const k = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, rsa, await crypto.subtle.exportKey("raw", aes));
  return { body: JSON.stringify({ v: 1, k: b64(k), iv: b64(iv), ct: b64(ct) }), responseKey: rk };
}

const call = async (fields, headers = {}, ip = "1.1.1.1", options) => {
  const sealed = typeof fields === "string" ? { body: fields, responseKey: options?.responseKey } : await seal(fields, options);
  const res = await POST(new Request("https://site.example/api/max", {
    method: "POST",
    headers: { "content-type": "application/json", origin: "https://site.example", "x-forwarded-for": ip, ...headers },
    body: sealed.body,
  }));
  return { res, responseKey: sealed.responseKey };
};

/** Decrypts a successful answer with the responseKey the test generated. */
async function open(res, responseKey) {
  const { iv, ct } = await res.json();
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: Uint8Array.from(Buffer.from(iv, "base64")) },
    responseKey.key, Uint8Array.from(Buffer.from(ct, "base64")));
  return JSON.parse(new TextDecoder().decode(plain));
}

const realFetch = globalThis.fetch;
test.afterEach(() => { globalThis.fetch = realFetch; });

test("GET gives the public key, and never a private one", async () => {
  const res = GET(new Request("https://site.example/api/max"));
  assert.equal(res.status, 200);
  const { publicKey } = await res.json();
  assert.equal(publicKey.kty, "RSA");
  assert.equal(publicKey.d, undefined);
});

test("another website cannot use the relay", async () => {
  const { res } = await call({ mode: "login", username: "a", password: "b" }, { origin: "https://evil.example" }, "2.2.2.2");
  assert.equal(res.status, 403);
});

test("rejects bad content type, cleartext credentials, missing or huge fields", async () => {
  assert.equal((await call('{"username":"a","password":"b"}', { "content-type": "application/json" }, "3.3.3.1")).res.status, 400);
  assert.equal((await (await POST(new Request("https://site.example/api/max", { method: "POST", headers: { "content-type": "text/plain", origin: "https://site.example", "x-forwarded-for": "3.3.3.2" }, body: "{}" })))).status, 400);
  assert.equal((await call({ mode: "login", username: "a" }, {}, "3.3.3.3")).res.status, 400);
  assert.equal((await call({ mode: "login", username: "a", password: "x".repeat(300) }, {}, "3.3.3.4")).res.status, 400);
});

test("a refused login answers 401, never calls anything else, and is not retried", async () => {
  const urls = [];
  globalThis.fetch = async (url) => {
    urls.push(String(url));
    return new Response(JSON.stringify({ ReturnCode: 1, Result: { LoginStatus: 3 } }), { status: 200 });
  };
  const { res } = await call({ mode: "login", username: "u", password: "p" }, {}, "4.4.4.4");
  assert.equal(res.status, 401);
  assert.deepEqual(urls, ["https://www.max.co.il/api/login/login"]);
});

test("success returns home and months encrypted with the browser's response key, plus a session token", async () => {
  const cookies = [];
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    cookies.push(init.headers?.Cookie ?? "");
    if (u.endsWith("/api/login/login")) {
      const headers = new Headers();
      headers.append("set-cookie", "sess=abc; Path=/; Secure");
      return new Response(JSON.stringify({ ReturnCode: 0, Result: { LoginStatus: 0 } }), { status: 200, headers });
    }
    if (u.includes("getHomePageData")) return new Response(JSON.stringify({ home: true }), { status: 200 });
    return new Response(JSON.stringify({ returnCode: 0, result: { transactions: [] } }), { status: 200 });
  };
  const { res, responseKey } = await call({ mode: "login", username: "u", password: "p" }, {}, "5.5.5.5");
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cache-control"), "no-store");
  const raw = await res.clone().json();
  assert.equal(typeof raw.iv, "string"); // the body on the wire carries no readable field
  const body = await open(res, responseKey);
  assert.deepEqual(body.home, { home: true });
  assert.equal(body.months.length, 6);
  assert.equal(typeof body.session, "string");
  assert.ok(cookies.slice(1).every((c) => c === "sess=abc"));
});

test("the response never contains the password, even on failure", async () => {
  globalThis.fetch = async () => new Response("boom", { status: 500 });
  const { res } = await call({ mode: "login", username: "u", password: "secret-pass-123" }, {}, "6.6.6.6");
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes("secret-pass-123"));
});

test("more than 4 login attempts a minute from one IP is limited", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ ReturnCode: 1, Result: { LoginStatus: 3 } }), { status: 200 });
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push((await call({ mode: "login", username: "u", password: "p" }, {}, "7.7.7.7")).res.status);
  assert.deepEqual(statuses, [401, 401, 401, 401, 429, 429]);
});

test("a session token refreshes the data without logging in again, and is not rate limited", async () => {
  let logins = 0;
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    if (u.endsWith("/api/login/login")) {
      logins++;
      const headers = new Headers();
      headers.append("set-cookie", "sess=tok; Path=/; Secure");
      return new Response(JSON.stringify({ ReturnCode: 0, Result: { LoginStatus: 0 } }), { status: 200, headers });
    }
    if (u.includes("getHomePageData")) return new Response(JSON.stringify({ home: init.headers.Cookie }), { status: 200 });
    return new Response(JSON.stringify({ returnCode: 0, result: { transactions: [] } }), { status: 200 });
  };
  const first = await call({ mode: "login", username: "u", password: "p" }, {}, "8.8.8.1");
  const body1 = await open(first.res, first.responseKey);
  assert.equal(logins, 1);

  for (let i = 0; i < 10; i++) {
    const r = await call({ mode: "refresh", token: body1.session }, {}, "8.8.8.1");
    assert.equal(r.res.status, 200);
  }
  assert.equal(logins, 1); // never logged in again, and 10 refreshes were never rate limited

  const r2 = await call({ mode: "refresh", token: body1.session }, {}, "8.8.8.1");
  const body2 = await open(r2.res, r2.responseKey);
  assert.equal(body2.home.home, "sess=tok"); // the saved cookie was replayed
});

test("a forged or wrong-scope token is refused with a distinct 'session' error, not 'refused'", async () => {
  const { res: r1 } = await call({ mode: "refresh", token: "not-a-real-token" }, {}, "9.9.9.1");
  assert.equal(r1.status, 401);
  assert.deepEqual(await r1.json(), { error: "session" });
});

test("GitHub Pages (the allowed cross-origin) gets CORS headers; a random site does not", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ ReturnCode: 1, Result: { LoginStatus: 3 } }), { status: 200 });
  const { res } = await call({ mode: "login", username: "u", password: "p" }, { origin: "https://sivelswhy.github.io" }, "10.10.10.1");
  assert.equal(res.status, 401); // still a real answer (allowed origin), not 403
  assert.equal(res.headers.get("access-control-allow-origin"), "https://sivelswhy.github.io");

  const { res: blocked } = await call({ mode: "login", username: "u", password: "p" }, { origin: "https://evil.example" }, "10.10.10.2");
  assert.equal(blocked.status, 403);
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);
});

test("preflight OPTIONS answers 204 with CORS headers for the allowed origin, 403 for others", async () => {
  const { OPTIONS } = await import("./max.js");
  const good = OPTIONS(new Request("https://site.example/api/max", { method: "OPTIONS", headers: { origin: "https://sivelswhy.github.io" } }));
  assert.equal(good.status, 204);
  assert.equal(good.headers.get("access-control-allow-origin"), "https://sivelswhy.github.io");
  const bad = OPTIONS(new Request("https://site.example/api/max", { method: "OPTIONS", headers: { origin: "https://evil.example" } }));
  assert.equal(bad.status, 403);
});
