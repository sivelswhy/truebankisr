# True Balance, web version for Max

A page that shows your next Max debit, upcoming debits, latest purchases and
spending by category, read from your own Max account. Max only: Leumi cannot
be read from a browser.

## How it works

- `index.html` + `app.js`: the page. Everything is computed in your browser from
  what Max returned. Nothing is saved (no `localStorage`, no cookie): closing
  the page forgets everything.
- `lib.js`: parses Max's JSON and computes the next debit (a port of the
  iPhone app's parser).
- `api/max.js`: a stateless relay. Max refuses calls coming from other websites
  (CORS: `The origin '…' is not allowed`), so a page cannot log in to Max by
  itself. The relay receives your username and password, logs in to
  `max.co.il`, returns the raw JSON and forgets everything.

## What the relay sees

Your Max username and password, in memory, for the length of one request.
It does not store them, does not log them, and answers with `Cache-Control:
no-store`.

They are also encrypted in your browser before they leave it (a one-time
AES-GCM key, wrapped with the relay's RSA public key from `GET /api/max`), so
request logs and anything between you and the relay only see ciphertext. The
relay's *answer* is encrypted too, with a second one-time key the browser
generates and sends along (never reused): a captured response is unreadable
without it either. A request older than a minute, or sent twice, is refused.
This does not hide the password from the relay itself: it has to decrypt it to
sign in to Max.

After a successful login the relay also returns a **sealed session token**:
Max's own session cookies, encrypted with a secret only the relay holds
(`SESSION_SECRET`, separate from the RSA key). The page keeps this token in
memory and sends it back to refresh the data, so it does not have to resend
your password every time — the relay opens the token, replays the cookies to
Max directly, and reseals a fresh token. The token carries its own expiry
(20 minutes) and is scoped to Max (`"max"`), so it cannot be replayed against
the other relay. It is never written to `localStorage` or `sessionStorage`:
closing or reloading the page still forgets everything and asks you to sign in
again. Read `api/max.js` (about 130 lines) before trusting it, or deploy
your own copy: the credentials then only go to a server you control.

Guards: browser calls from this site only (origin check), JSON body of 2 KB at
most, 4 attempts a minute per IP (best effort, per warm instance), no retry
after Max refuses a login.

## Leumi: a bookmark, no password

Leumi's sign-in only works in a real browser, so the page never asks for your
Leumi password. You drag a bookmark to your bookmarks bar, open Leumi from the
page's button, sign in on Leumi's own site, and click the bookmark there. It
reads the account with the session you opened and sends it to this page with
`postMessage` (only `https://*.bankleumi.co.il` is accepted). Source: `leumi.js`.
With Leumi and Max both loaded, "really available" is the Leumi balance minus
the next Max debit. This has not been tried against the real Leumi site yet.

## Test account

Username `test`, password `test` (or the sample-data button) loads made-up
Max and Leumi data. Nothing is sent anywhere.

## Run the tests

```sh
cd site
npm test
```

## Two origins: GitHub Pages for the page, Vercel for the relay

GitHub Pages serves static files only, no server code, so the relay
(`api/max.js`) stays on Vercel. The page can live on either:

- `index.html` here, served by Vercel itself (`vercel --prod`): calls to
  `/api/max` are same-origin, no CORS needed.
- A copy at `../docs/webapp/`, served by GitHub Pages at
  `https://sivelswhy.github.io/truebankisr/webapp/`: `app.js` detects this
  (`location.hostname.endsWith("github.io")`) and calls the Vercel relay by
  its full URL instead. The relay only answers cross-origin calls from an
  origin in `ALLOWED_ORIGINS` (`api/_crypto.js`) — update it, and the `RELAY`
  constant in `app.js`, if the Vercel URL or the Pages origin changes.

Run `./sync-pages.sh` after changing `index.html`, `app.js`, `lib.js`,
`demo.js`, `leumi.js` or `icons.js`, then commit and push: GitHub Pages
publishes `docs/` on push to `main`. `api/` is never copied there — it
wouldn't run.

## Deploy (your own Vercel project)

The relay's private key must be the same on every serverless instance:

```sh
cd site
node keygen.js | vercel env add RELAY_PRIVATE_KEY production
node session-keygen.js | vercel env add SESSION_SECRET production
vercel --prod
```

Locally (`node dev-server.js`, http://127.0.0.1:3100) a throwaway key is made at start.

Check once with your real account that Max does not block Vercel's IP
addresses (it may serve a bot challenge to data-centre traffic). If it does,
the relay cannot work from there.
