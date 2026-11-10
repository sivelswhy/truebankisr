// Reads the balance and transactions once signed in: Leumi's own data calls
// (found with reverse-api-engineer, same ones the page's own transactions
// screen makes), not the screen itself. A port of `directAccount` in the
// iPhone app (ios/TrueBalance/Scraping/BankScrapers.swift). Pure logic over a
// `driver` (see leumiDriver.js), so it is testable without a real browser.

import { BASE } from "./leumiLogin.js";

export class LeumiAccountError extends Error {}

/** The `SessionID` the page embeds, needed in every data call's body. */
function sessionIdFrom(html) {
  const m = html.match(/"SessionID"\s*:\s*"([A-Za-z0-9]+)"/);
  if (!m) throw new LeumiAccountError(`no SessionID in the account page`);
  return m[1];
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
export async function readAccount(driver) {
  const html = await driver.fetchText(`${BASE}/eBanking/SO/SPA.aspx`);
  const sessionId = sessionIdFrom(html);

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
