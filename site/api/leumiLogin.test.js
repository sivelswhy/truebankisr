import test from "node:test";
import assert from "node:assert/strict";
import { login, LeumiLoginError, BASE } from "./leumiLogin.js";

const LOGIN_URL = `${BASE}/authenticate/logon`;
const ACCOUNT_URL = `${BASE}/eBanking/SO/SPA.aspx#/ts/BusinessAccountTrx?WidgetPar=1`;
const DIGITALFRONT_URL = `${BASE}/digitalfront/accounts`;

/** A fake driver, scripted by what each submit should do: "ok" reaches the
 * account page; "stall" leaves the form in place (so a resubmit can be
 * observed); anything else is a named outcome (changePassword, digitalfront,
 * blocked, rejected, refused). Calls are recorded for a couple of assertions. */
function fakeDriver(script = ["account"]) {
  const calls = [];
  let state = "login";
  let step = 0;
  const formPresent = () => !["account", "changePassword", "digitalfront"].includes(state);
  return {
    calls,
    async load(url) { calls.push(["load", url]); },
    async waitForElement(sel) { calls.push(["wait", sel]); },
    async fill(sel, _value) { calls.push(["fill", sel]); },
    async click(sel) {
      calls.push(["click", sel]);
      state = script[Math.min(step, script.length - 1)];
      step++;
    },
    async url() { return state === "account" ? ACCOUNT_URL : state === "digitalfront" ? DIGITALFRONT_URL : LOGIN_URL; },
    async exists(sel) { return sel.includes("newPwd") ? state === "changePassword" : formPresent(); },
    async bodyText() {
      return { blocked: "המנוי חסום", rejected: "The requested URL was rejected", refused: "אחד או יותר מפרטי ההזדהות שהוקלדו שגויים" }[state] ?? "";
    },
  };
}

// Node's test runner can run these concurrently, so each test needs its own
// clock: a shared counter would race across tests.
const counter = (step = 1) => { let t = 0; return () => (t += step); };
const fastOpts = (overrides = {}) => ({ settleMs: 0, sleep: async () => {}, now: counter(), ...overrides });

test("a normal login reaches the account page", async () => {
  const d = fakeDriver(["account"]);
  await login(d, { username: "u", password: "p" }, fastOpts());
  assert.deepEqual(d.calls[0], ["load", LOGIN_URL]);
  assert.ok(d.calls.some((c) => c[0] === "fill"));
});

test("Leumi's new site is reported as unsupported", async () => {
  const d = fakeDriver(["digitalfront"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts()), (e) => e instanceof LeumiLoginError && e.code === "unsupported");
});

test("a forced password change is reported distinctly", async () => {
  const d = fakeDriver(["changePassword"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts()), (e) => e.code === "changePassword");
});

test("wrong credentials are reported as refused, from the page text", async () => {
  const d = fakeDriver(["refused"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts()), (e) => e.code === "refused");
});

test("the firewall's rejection is a distinct error from a plain refusal", async () => {
  const d = fakeDriver(["rejected"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts()), (e) => e.code === "firewall");
});

test("a blocked subscription is reported distinctly", async () => {
  const d = fakeDriver(["blocked"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts()), (e) => e.code === "blocked");
});

test("times out if the account page is never reached", async () => {
  const d = fakeDriver(["stall","stall","stall","stall","stall"]);
  await assert.rejects(login(d, { username: "u", password: "p" }, fastOpts({ timeoutMs: 3 })), (e) => e.code === "timeout");
});

test("resubmits once if the form is still there after 20s, then can still succeed", async () => {
  const d = fakeDriver(["stall", "account"]);
  await login(d, { username: "u", password: "p" }, fastOpts({ timeoutMs: 200_000, now: counter(15_000) }));
  assert.equal(d.calls.filter((c) => c[0] === "click").length, 2);
});

test("waits before the first submit (anti-bot settle time)", async () => {
  const d = fakeDriver(["account"]);
  let waited = null;
  await login(d, { username: "u", password: "p" }, fastOpts({ settleMs: 10_000, sleep: async (ms) => { waited = ms; } }));
  assert.equal(waited, 10_000);
});
