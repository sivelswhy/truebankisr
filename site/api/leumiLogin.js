// Leumi's login state machine: a port of `LeumiScraper.login` in the iPhone
// app (ios/TrueBalance/Scraping/BankScrapers.swift). Pure logic over a
// `driver` (a thin page adapter, see leumiDriver.js), so it is testable
// without a real browser. A real browser is required, though: Leumi's login
// is a token signed by Transmit Security's JS SDK plus an F5 anti-bot check,
// neither of which a plain HTTP POST can satisfy.

export const BASE = "https://hb2.bankleumi.co.il";
const USER_SELECTOR = 'input[placeholder="שם משתמש"]';
const PASS_SELECTOR = 'input[placeholder="סיסמה"]';
/// "אחד או יותר מפרטי ההזדהות שהוקלדו/שמסרת שגויים" (wording varies).
export const INVALID_PASSWORD = "אחד או יותר מפרטי ההזדהות";
/// "יש להקליד 6-12 אותיות באנגלית וספרות בלבד": the form refused the format.
export const INVALID_FORMAT = "יש להקליד 6-12";
export const BLOCKED = "המנוי חסום";
export const FIREWALL_REJECTED = "was rejected";

export class LeumiLoginError extends Error {
  constructor(code, message) {
    super(message ?? code);
    this.code = code; // "refused" | "blocked" | "changePassword" | "unsupported" | "firewall" | "timeout"
  }
}

/**
 * Signs in. Resolves once the account pages' URL is reached; throws a
 * `LeumiLoginError` otherwise. `settleMs` and `sleep`/`now` are only there
 * for fast, deterministic tests — production uses the real defaults.
 */
export async function login(driver, { username, password }, {
  settleMs = 10_000, timeoutMs = 75_000, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), now = () => Date.now(),
} = {}) {
  await driver.load(`${BASE}/authenticate/logon`);
  await driver.waitForElement(USER_SELECTOR);
  await driver.waitForElement(PASS_SELECTOR);
  // Leumi's firewall rejects a login sent before its own page script has
  // finished checking the browser (seen as "The requested URL was rejected").
  await sleep(settleMs);
  await driver.fill(USER_SELECTOR, username);
  await driver.fill(PASS_SELECTOR, password);
  await driver.click("button[type='submit']");

  const start = now();
  const deadline = start + timeoutMs;
  let resubmitted = false;
  while (now() < deadline) {
    const url = await driver.url();
    if (/ebanking\/SO\/SPA\.aspx/i.test(url)) return;
    // Accounts moved to Leumi's new site, which this doesn't read yet.
    if (/digitalfront/i.test(url)) throw new LeumiLoginError("unsupported", `Leumi opened its new site (${url}), not supported yet`);
    if (await driver.exists('form input[name="newPwd"]')) throw new LeumiLoginError("changePassword");
    const text = await driver.bodyText();
    if (text.includes(INVALID_PASSWORD) || text.includes(INVALID_FORMAT)) throw new LeumiLoginError("refused");
    if (text.includes(FIREWALL_REJECTED)) throw new LeumiLoginError("firewall", "Leumi firewall rejected the login");
    if (text.includes(BLOCKED)) throw new LeumiLoginError("blocked");
    // The gate-keeper login page sometimes drops the first submit and just
    // sits there with the form: fill it and send it once more.
    if (!resubmitted && now() - start > 20_000 && await driver.exists(USER_SELECTOR) && await driver.exists(PASS_SELECTOR)) {
      resubmitted = true;
      await driver.fill(USER_SELECTOR, username);
      await driver.fill(PASS_SELECTOR, password);
      await driver.click("button[type='submit']");
    }
    await sleep(500);
  }
  throw new LeumiLoginError("timeout", "Leumi: waiting for the account page timed out");
}
