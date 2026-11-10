// Wraps a real headless Chromium page behind the thin `driver` interface
// leumiLogin.js and leumiAccount.js expect (load/waitForElement/fill/click/
// url/exists/bodyText/fetchText/postJSON/cookies), so the login and
// account-reading logic can be unit-tested without ever launching a browser.
// This file is the only one that touches Puppeteer; it isn't unit-tested
// itself (that would mean testing Puppeteer, not this code).
//
// Needs a real browser — not a plain HTTP POST — because Leumi's login is a
// token signed by Transmit Security's JS SDK, checked by an F5 anti-bot
// layer: both require running the page's actual JavaScript.

import chromium from "@sparticuz/chromium";
import puppeteer from "puppeteer-core";

/** Launches a real, sandboxed Chromium (serverless-sized) and returns a browser. */
export async function launchBrowser() {
  return puppeteer.launch({
    args: chromium.args,
    executablePath: await chromium.executablePath(),
    headless: true,
  });
}

/** Leumi's login redirects through several pages on its own (gate-keeper,
 * SSOLogin.aspx, the account page); a check made from the polling loop can
 * land exactly while one of those is in flight and get "Execution context
 * was destroyed, most likely because of a navigation" — Puppeteer's name for
 * that race, not a sign of anything wrong. Treated as inconclusive: the loop
 * just checks again next tick. */
const isNavigationRace = (error) => /context was destroyed|detached frame|navigating frame/i.test(error?.message ?? "");

/** `cookies`: array of `{ name, value, domain }`, from a previous session (a refresh), or `[]` for a fresh login. */
export async function openDriver(browser, { cookies = [] } = {}) {
  const page = await browser.newPage();
  if (cookies.length) await page.setCookie(...cookies);

  return {
    async load(url) { await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 }); },
    async waitForElement(selector) { await page.waitForSelector(selector, { timeout: 30_000 }); },
    async fill(selector, value) {
      try {
        await page.click(selector, { clickCount: 3 });
        await page.type(selector, value);
      } catch (error) {
        if (!isNavigationRace(error)) throw error;
      }
    },
    async click(selector) {
      try {
        await page.click(selector);
      } catch (error) {
        if (!isNavigationRace(error)) throw error;
      }
    },
    async url() {
      try { return page.url(); } catch { return ""; }
    },
    async exists(selector) {
      try { return (await page.$(selector)) !== null; } catch (error) {
        if (isNavigationRace(error)) return false;
        throw error;
      }
    },
    async bodyText() {
      try { return await page.evaluate(() => document.body?.innerText ?? ""); } catch (error) {
        if (isNavigationRace(error)) return "";
        throw error;
      }
    },

    /** A plain GET, same-origin to whatever page is loaded (the real browser's own fetch, with its cookies).
     * One retry on a navigation race: unlike the login poll, this needs a real answer, not "keep checking". */
    async fetchText(url) {
      try {
        return await page.evaluate(async (u) => (await fetch(u, { credentials: "include" })).text(), url);
      } catch (error) {
        if (!isNavigationRace(error)) throw error;
        await new Promise((r) => setTimeout(r, 1000));
        return page.evaluate(async (u) => (await fetch(u, { credentials: "include" })).text(), url);
      }
    },
    /** A POST with a JSON body, same-origin, same cookies — the broker calls. Same one-time retry. */
    async postJSON(url, body) {
      const send = () => page.evaluate(async (u, b) => (await fetch(u, {
        method: "POST", credentials: "include", headers: { "Content-Type": "application/json" }, body: b,
      })).text(), url, body);
      try {
        return await send();
      } catch (error) {
        if (!isNavigationRace(error)) throw error;
        await new Promise((r) => setTimeout(r, 1000));
        return send();
      }
    },

    /** This page's cookies for Leumi's domain, to seal into a session token. */
    async cookies() {
      const list = await page.cookies();
      return list.map((c) => ({ name: c.name, value: c.value, domain: c.domain }));
    },
    async close() { await page.close(); },
  };
}
