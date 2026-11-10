import test from "node:test";
import assert from "node:assert/strict";
import { readAccount, LeumiAccountError } from "./leumiAccount.js";

/** A fake driver that answers each call in order and records every request. */
function fakeDriver(pages) {
  const calls = [];
  const bodies = [];
  let i = 0;
  return {
    calls,
    bodies,
    async fetchText(url) { calls.push(["fetchText", url]); return pages[i++]; },
    async postJSON(url, body) { calls.push(["postJSON", url, JSON.parse(body).moduleName]); bodies.push(body); return pages[i++]; },
  };
}

const inner = (obj) => JSON.stringify({ jsonResp: JSON.stringify(obj) });

test("reads the SessionID, the account number, then the transactions, in order", async () => {
  const d = fakeDriver([
    `var x = {"SessionID":"abc123","other":1};`, // SPA.aspx page
    inner({}), // GetDefaultAccountIndex
    inner({ AccountsItems: [{ MaskedNumber: "123/45/678" }] }), // GetAccounts
    inner({ result: { transactions: [] } }), // GetBusinessAccountTrx (raw body passed through)
  ]);
  const { number, body } = await readAccount(d);
  assert.equal(number, "123_45_678");
  assert.equal(body, inner({ result: { transactions: [] } }));
  assert.deepEqual(d.calls.map((c) => c[c.length - 1]), [
    "https://hb2.bankleumi.co.il/eBanking/SO/SPA.aspx",
    "UC_SO_010_02_GetDefaultAccountIndex", "UC_SO_GetAccounts", "UC_SO_27_GetBusinessAccountTrx",
  ]);
});

test("the SessionID is embedded in every broker call's body", async () => {
  const d = fakeDriver([
    `"SessionID":"xyz789"`,
    inner({}),
    inner({ AccountsItems: [{ MaskedNumber: "1/2/3" }] }),
    inner({}),
  ]);
  await readAccount(d);
  assert.equal(d.bodies.length, 3);
  for (const raw of d.bodies) {
    const reqObj = JSON.parse(JSON.parse(raw).reqObj);
    assert.equal(reqObj.SessionHeader.SessionID, "xyz789");
  }
});

test("no SessionID on the account page is a clear error, not a crash further down", async () => {
  const d = fakeDriver([`no session here`]);
  await assert.rejects(readAccount(d, { attempts: 1, sleep: async () => {} }), LeumiAccountError);
});

test("a SessionID missing from the first fetch (Leumi's SPA still settling) is retried, not failed immediately", async () => {
  const d = fakeDriver([
    `still loading…`, // 1st fetch: not there yet
    `"SessionID":"abc123"`, // 2nd fetch: there
    inner({}), inner({ AccountsItems: [{ MaskedNumber: "1/2/3" }] }), inner({}),
  ]);
  const waited = [];
  const { number } = await readAccount(d, { sleep: async (ms) => waited.push(ms) });
  assert.equal(number, "1_2_3");
  assert.deepEqual(waited, [1500]); // one retry only needed
});

test("still no SessionID after every retry names how many tries and what came back", async () => {
  const d = fakeDriver(["a", "b", "c"]);
  await assert.rejects(readAccount(d, { attempts: 3, sleep: async () => {} }), (e) => {
    assert.ok(e instanceof LeumiAccountError);
    assert.match(e.message, /after 3 tries/);
    return true;
  });
});

test("no account number is a clear error", async () => {
  const d = fakeDriver([`"SessionID":"abc"`, inner({}), inner({ AccountsItems: [] })]);
  await assert.rejects(readAccount(d), LeumiAccountError);
});
