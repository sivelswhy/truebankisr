// Reads the balance and transactions once signed in: Leumi's own data calls
// (found with reverse-api-engineer, same ones the page's own transactions
// screen makes), not the screen itself. A port of `directAccount` in the
// iPhone app (ios/TrueBalance/Scraping/BankScrapers.swift). Pure logic over a
// `driver` (see leumiDriver.js), so it is testable without a real browser.

import { BASE } from "./leumiLogin.js";

export class LeumiAccountError extends Error {}

/** The `SessionID` a fetch of the account page embeds, or null when this answer doesn't have one. */
function sessionIdFrom(html) {
  return html.match(/"SessionID"\s*:\s*"([A-Za-z0-9]+)"/)?.[1] ?? null;
}

/**
 * Fetches the account page and reads its SessionID, retrying a few times:
 * Leumi's own SPA can still be settling right after login (or right after
 * restoring a session), and a fetch sent a moment too soon gets a page
 * without it yet — seen in production, not just a theoretical race.
 */
async function fetchSessionId(driver, { attempts = 4, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
  let lastHtmlLength = null;
  for (let i = 0; i < attempts; i++) {
    if (i > 0) await sleep(1500);
    const html = await driver.fetchText(`${BASE}/eBanking/SO/SPA.aspx`);
    const id = sessionIdFrom(html);
    if (id) return id;
    lastHtmlLength = html.length;
  }
  throw new LeumiAccountError(`no SessionID in the account page after ${attempts} tries (last answer: ${lastHtmlLength} bytes)`);
}

function brokerBody(module, sessionId, fields) {
  const reqObj = JSON.stringify({ ...fields, StateName: "BusinessAccountTrx", ModuleName: module, SessionHeader: { SessionID: sessionId, FIID: "Leumi" } });
  return JSON.stringify({ moduleName: module, reqObj, version: "Infra_V2.0" });
}

/** "123/45/678" → "123_45_678", the id the iPhone app uses for the account. */
function accountNumber(masked) {
  return String(masked ?? "").replace(/\//g, "_").replace(/[^0-9_-]/g, "");
}

/**
 * Reads the account after `driver` already has a signed-in session (either
 * just logged in, or restored from a sealed session token). Returns
 * `{ number, body }`: `body` is the raw transactions answer, parsed on the
 * page itself with the same `parseLeumi` the bookmark already uses.
 */
export async function readAccount(driver, options) {
  const sessionId = await fetchSessionId(driver, options);

  const broker = async (module, fields) => {
    const text = await driver.postJSON(`${BASE}/ChannelWCF/Broker.svc/ProcessRequest?moduleName=${module}`, brokerBody(module, sessionId, fields));
    return text;
  };
  const inner = (text) => {
    try { return JSON.parse(JSON.parse(text).jsonResp); } catch { return null; }
  };

  const accountFields = { ComboMethod: "true", RequestedAccountTypes: "CHECKING", ExtAccountPermissions: "General", AccountSegments: "" };
  await broker("UC_SO_010_02_GetDefaultAccountIndex", { ...accountFields, AccountIndex: 1 });
  const accounts = inner(await broker("UC_SO_GetAccounts", accountFields));
  const number = accountNumber(accounts?.AccountsItems?.[0]?.MaskedNumber);
  if (!number) throw new LeumiAccountError("no account number");

  const now = new Date();
  const from = new Date(now.getTime() - 45 * 86_400_000);
  const to = new Date(now.getTime() + 86_400_000);
  const body = await broker("UC_SO_27_GetBusinessAccountTrx", {
    RequestType: "OpersB", FromDateUTC: from.toUTCString(), ToDateUTC: to.toUTCString(), OperationsNumber: "40",
    Amount: 0, AmountType1: 0, AmountType2: 0, TrxType: "1", ReferenceNumber: "0", BeneficiaryName: "0",
    BeneficiaryBankCode: "0", BeneficiaryBranch: "0", BeneficiaryAccountNumber: "0", InvoiceNumber: "0",
    PeriodType: "0", AccountIndex: 1,
  });
  return { number, body };
}
