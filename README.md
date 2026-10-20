# True Balance

**Website:** [sivelswhy.github.io/truebankisr](https://sivelswhy.github.io/truebankisr/)

Your **real** available money in Israel: Leumi balance minus the Max credit card
charges that have not been debited yet (Max debits everything on the 2nd of the
month, so the bank balance alone overstates what you can spend).

```
Leumi balance            ₪163.00
Max, debited 2 Nov     − ₪964.20
Really available       − ₪801.20
```

Two clients, English and French:

- **iPhone app** (`ios/`): native SwiftUI, standalone (no server). Signs in to
  Leumi and Max on the phone itself, and can also show accounts at any
  European bank through open banking. See [ios/README.md](ios/README.md).
- **Web app** (this folder): Next.js, runs on your Mac and scrapes with
  [`israeli-bank-scrapers`](https://github.com/eshaham/israeli-bank-scrapers).

Both show the next debit by category, installments in later months, and pending
purchases.

> **Personal use only.** This logs into your bank with your own credentials and
> reads your own data. Credentials never leave your device (Keychain on iPhone,
> encrypted file on the Mac). Not affiliated with Bank Leumi or Max.

## Why not Israeli Open Banking?

Israel's open banking (Bank of Israel directive 368, Berlin Group NextGenPSD2 APIs)
is only open to licensed / certified third parties, not to an individual.
So this app uses the open-source
[`israeli-bank-scrapers`](https://github.com/eshaham/israeli-bank-scrapers),
which logs into Leumi and Max with *your* credentials in a headless Chromium,
on *your* machine.

European banks are different: PSD2 makes them reachable through aggregators,
and [Enable Banking](https://enablebanking.com) lets an individual read their
own accounts for free (restricted mode). The iPhone app uses it for European
banks (Hello Bank, Revolut, BNP Paribas, N26…), shown apart from the true
balance: [setup guide](ios/EUROPEAN-BANKS.md).

## Run the web app

```sh
npm install
npm run dev        # http://127.0.0.1:3000
```

Sign in with your Leumi and Max usernames and passwords, or tap
**Try with sample data**. Signing in performs a real login on both sites and
only saves the credentials if both succeed. They are stored encrypted
(AES-256-GCM) in `data/credentials.enc`, with the key in `data/vault.key`
(both readable only by your macOS user). **Disconnect accounts** deletes them.

Pull down (or tap ↻) to refresh; a refresh takes 30–90 s. The last result is
cached in `data/snapshot.json`. Optional settings are in `.env.example`.

## How it's computed (`lib/compute.ts`)

- Every Max transaction whose debit date (`processedDate`) is still in the future
  is grouped by debit date.
- Pending Max transactions (no debit date yet) go to the next billing day.
- On the billing day itself, the charge still counts until the Leumi account
  shows the Max debit line.
- The headline subtracts only the **next** debit; the footnote also subtracts
  future installments already committed.
- Card charges in a foreign currency are listed but not subtracted.

`npm test` runs the unit tests.

## Security

Credentials stay in `data/` (git-ignored) and the server only listens on
`127.0.0.1`. Do not deploy this to a public host.

## Troubleshooting

**"The built-in browser couldn't start"**: Puppeteer's Chromium download was
not extracted correctly (seen with Node 26). Extract it by hand:

```sh
cd ~/.cache/puppeteer/chrome
rm -rf mac_arm-*/ && npx puppeteer browsers install chrome   # re-download
# if it still fails, the .zip is left next to the folder:
mkdir -p mac_arm-<version> && ditto -x -k <version>-chrome-mac-arm64.zip mac_arm-<version>
```

Set `SHOW_BROWSER=1` in `.env.local` to watch the logins happen.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): free to use, modify and share for
personal and other noncommercial purposes. **Commercial use is not allowed.**
Copyright 2026 sivelswhy.

Built on [`israeli-bank-scrapers`](https://github.com/eshaham/israeli-bank-scrapers)
(MIT); the iPhone login flows are ports of its Leumi and Max scrapers.
