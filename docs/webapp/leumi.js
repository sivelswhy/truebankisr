// Leumi without a relay. Leumi's login cannot be replayed outside a real browser
// (anti-bot, device checks), so the user signs in on Leumi's own site and runs a
// bookmark there. The bookmark reads the account with the session already open,
// and hands the answer to the True Balance page with postMessage. The password
// never leaves Leumi, and nothing goes through a server.

export const LEUMI_ORIGIN = /^https:\/\/[a-z0-9-]+\.bankleumi\.co\.il$/;
export const LEUMI_URL = "https://hb2.bankleumi.co.il/h/login.html";
/** Name given to the Leumi window opened from the page, so the bookmark knows who opened it. */
export const OPENER_NAME = "tb-site";

/**
 * Runs on Leumi's page (as a bookmark). Self-contained on purpose: it is turned
 * into text with toString(), so it can use nothing from this module.
 */
export function leumiBookmarklet(siteOrigin) {
  const say = (text) => alert("True Balance: " + text);
  if (!/^[a-z0-9-]+\.bankleumi\.co\.il$/.test(location.hostname)) {
    return say("open this bookmark on Leumi's site, once you are signed in.");
  }
  // Opened from the True Balance tab: talk to it. Otherwise open a True Balance window now
  // (it has to happen in the click, before the first await, or popups are blocked).
  const viaOpener = !!window.opener && !window.opener.closed && window.name === "tb-site";
  const popup = viaOpener ? null : window.open(siteOrigin + "/#leumi=" + encodeURIComponent(location.origin), "truebalance");
  if (!viaOpener && !popup) return say("allow popups for this site, then try again.");

  const waitFor = (type, source, ms) => new Promise((resolve) => {
    const done = (value) => { clearTimeout(timer); removeEventListener("message", on); resolve(value); };
    const on = (e) => { if (e.origin === siteOrigin && e.source === source && e.data && e.data.type === type) done(true); };
    const timer = setTimeout(() => done(false), ms);
    addEventListener("message", on);
  });

  (async () => {
    try {
      const base = location.origin;
      const page = await (await fetch(base + "/eBanking/SO/SPA.aspx", { credentials: "include" })).text();
      const session = page.match(/"SessionID"\s*:\s*"([A-Za-z0-9]+)"/);
      if (!session) throw new Error("no session: sign in to Leumi first");

      const broker = async (module, fields) => {
        const obj = Object.assign({}, fields, { StateName: "BusinessAccountTrx", ModuleName: module, SessionHeader: { SessionID: session[1], FIID: "Leumi" } });
        const res = await fetch(base + "/ChannelWCF/Broker.svc/ProcessRequest?moduleName=" + module, {
          method: "POST", credentials: "include", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ moduleName: module, reqObj: JSON.stringify(obj), version: "Infra_V2.0" }),
        });
        if (!res.ok) throw new Error(module + " HTTP " + res.status);
        return res.text();
      };
      const inner = (text) => { try { return JSON.parse(JSON.parse(text).jsonResp); } catch { return null; } };

      const accountFields = { ComboMethod: "true", RequestedAccountTypes: "CHECKING", ExtAccountPermissions: "General", AccountSegments: "" };
      await broker("UC_SO_010_02_GetDefaultAccountIndex", Object.assign({}, accountFields, { AccountIndex: 1 }));
      const accounts = inner(await broker("UC_SO_GetAccounts", accountFields));
      const masked = (accounts && accounts.AccountsItems && accounts.AccountsItems[0] && accounts.AccountsItems[0].MaskedNumber) || "";
      const number = masked.replace(/\//g, "_").replace(/[^0-9_-]/g, "");
      if (!number) throw new Error("no account number");

      // Midnight in Israel, 45 days back to the end of today.
      const israelDay = (d) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jerusalem" }).format(d);
      const midnight = (d) => {
        const [y, m, day] = israelDay(d).split("-").map(Number);
        const guess = Date.UTC(y, m - 1, day);
        const zone = new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Jerusalem", timeZoneName: "longOffset" })
          .formatToParts(new Date(guess)).find((p) => p.type === "timeZoneName").value;
        const o = zone.match(/([+-])(\d\d):?(\d\d)?/);
        const offset = o ? (o[1] === "-" ? -1 : 1) * (Number(o[2]) * 60 + Number(o[3] || 0)) : 0;
        return new Date(guess - offset * 60000);
      };
      const now = new Date();
      const from = midnight(new Date(now.getTime() - 45 * 86400000));
      const to = new Date(midnight(now).getTime() + 86400000);

      const body = await broker("UC_SO_27_GetBusinessAccountTrx", {
        RequestType: "OpersB", FromDateUTC: from.toUTCString(), ToDateUTC: to.toUTCString(), OperationsNumber: "40",
        Amount: 0, AmountType1: 0, AmountType2: 0, TrxType: "1", ReferenceNumber: "0", BeneficiaryName: "0",
        BeneficiaryBankCode: "0", BeneficiaryBranch: "0", BeneficiaryAccountNumber: "0", InvoiceNumber: "0",
        PeriodType: "0", AccountIndex: 1,
      });

      const target = viaOpener ? window.opener : popup;
      if (!viaOpener && !(await waitFor("tb-ready", popup, 15000))) throw new Error("the True Balance window did not answer");
      const acknowledged = waitFor("tb-ack", target, 4000);
      target.postMessage({ type: "tb-leumi", v: 1, number, body }, siteOrigin);
      if (!(await acknowledged)) throw new Error("the True Balance page did not answer (open Leumi from its button, or allow popups)");
      say("Leumi account sent.");
    } catch (error) {
      say(String(error && error.message ? error.message : error));
    }
  })();
}

/** The bookmark's address for a page at `siteOrigin`. Drag it to the bookmarks bar. */
export const bookmarkletHref = (siteOrigin) =>
  "javascript:" + encodeURIComponent(`(${leumiBookmarklet.toString()})(${JSON.stringify(siteOrigin)})`);
