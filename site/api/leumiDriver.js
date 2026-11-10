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

/** `cookies`: array of `{ name, value, domain }`, from a previous session (a refresh), or `[]` for a fresh login. */
export async function openDriver(browser, { cookies = [] } = {}) {
  const page = await browser.newPage();
  if (cookies.length) await page.setCookie(...cookies);

  return {
    async load(url) { await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 }); },
    async waitForElement(selector) { await page.waitForSelector(selector, { timeout: 30_000 }); },
    async fill(selector, value) { await page.click(selector, { clickCount: 3 }); await page.type(selector, value); },
    async click(selector) { await page.click(selector); },
    async url() { return page.url(); },
    async exists(selector) { return (await page.$(selector)) !== null; },
    async bodyText() { return page.evaluate(() => document.body?.innerText ?? ""); },

    /** A plain GET, same-origin to whatever page is loaded (the real browser's own fetch, with its cookies). */
    async fetchText(url) {
      return page.evaluate(async (u) => (await fetch(u, { credentials: "include" })).text(), url);
    },
    /** A POST with a JSON body, same-origin, same cookies — the broker calls. */
    async postJSON(url, body) {
      return page.evaluate(async (u, b) => (await fetch(u, {
        method: "POST", credentials: "include", headers: { "Content-Type": "application/json" }, body: b,
      })).text(), url, body);
    },

    /** This page's cookies for Leumi's domain, to seal into a session token. */
    async cookies() {
      const list = await page.cookies();
      return list.map((c) => ({ name: c.name, value: c.value, domain: c.domain }));
    },
    async close() { await page.close(); },
  };
}
