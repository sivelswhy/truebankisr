# True Balance for iPhone

A native SwiftUI app that runs entirely on the iPhone: no server, no Mac
needed once installed. It signs in to Leumi and Max itself, inside an
invisible `WKWebView`, the same way
[`israeli-bank-scrapers`](https://github.com/eshaham/israeli-bank-scrapers)
drives Chromium, then shows:

- the **true balance**: Leumi balance minus the Max charges not yet debited,
- the breakdown of the next debit **by category**,
- every upcoming charge, grouped by debit date (installments included).

Also: days left and daily budget until the debit, a chart of upcoming debits,
a donut of the next debit by category, search across upcoming charges, Leumi
movements, spending over any period with CSV export, budgets, subscriptions,
a forecast with salary and regular debits, net worth, notes and tags on
purchases, an alert threshold notification, an optional Face ID lock and a
hide-amounts option in Settings.

While a refresh runs, a spinner sits next to the profile button; tap it for
the current step. It turns into a warning sign when a bank failed, with the
error and a retry button.

**Other banks**: any European bank Enable Banking supports (Hello Bank,
Revolut, BNP Paribas, N26…), chosen by country with search, shown in their own
section on Home with a bank picker, in their currency with the shekel
equivalent. See [EUROPEAN-BANKS.md](EUROPEAN-BANKS.md).

English and French (String Catalog with plurals), Dynamic Type, Dark Mode, VoiceOver.

## Layout

```
ios/
├── project.yml                 XcodeGen spec (generates TrueBalance.xcodeproj)
├── Packages/TrueBalanceCore/   Pure Swift: true-balance maths, Max/Leumi parsers,
│                               categories. Unit-tested on the Mac.
└── TrueBalance/
    ├── Scraping/WebDriver.swift      Hidden WKWebView: load, wait, fill, click, fetch
    ├── Scraping/BankScrapers.swift   Leumi + Max login flows (ports of the JS scrapers)
    ├── OpenBanking/EnableBanking.swift  Enable Banking API: JWT signing, sessions,
    │                                    balances, transactions (Hello Bank, Revolut)
    ├── Storage.swift                 Keychain (credentials, keys, sessions) + data files
    ├── AppModel.swift                State, refresh, background refresh, alerts
    ├── Views/                        SwiftUI screens; Components.swift holds the
    │                                 shared hero card, chips, headers and background
    └── Resources/                    Assets, Localizable.xcstrings (en, fr)

docs/enablebanking.html             GitHub Pages redirect back into the app
```

## Build and install on your iPhone

1. `brew install xcodegen` (once). From `ios/`: `cp Local.xcconfig.example Local.xcconfig`,
   put your Apple team ID in it, then `xcodegen generate`
2. Open `TrueBalance.xcodeproj` in Xcode.
3. Target **TrueBalance → Signing & Capabilities**: pick your **Team** (your
   Apple ID). If the bundle ID `il.truebalance.app` is taken, change it to
   something unique, e.g. `com.<you>.truebalance`.
4. Plug in the iPhone, select it as the run destination, press **Run**.
   The first time, on the iPhone: Settings → General → VPN & Device
   Management → trust your developer certificate. Settings → Privacy &
   Security → Developer Mode must be on.

**Free Apple ID**: the app works for 7 days, then you press Run again.
**Paid Apple Developer account ($99/year)**: valid for 1 year, and
Product → Archive → Distribute App → *Release Testing / Ad Hoc* produces a real
`.ipa` you can install on registered devices.

## Unsigned IPA (like CI)

`ios/build-ipa.sh` builds the app unsigned and writes `dist/TrueBalance.ipa`,
to sign and install with your usual tool. CI also publishes one on `main` as
a GitHub release: it waits 10 minutes after a push and builds only the last
commit of a burst, and commits that only touch docs (`*.md`, `docs/`) or CI
settings (`.github/`) don't build at all.

## Staying signed in

Credentials are stored in the Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: they never leave this
iPhone (no iCloud sync) and stay available for background refresh. The app
refreshes when you open it if the data is more than 15 minutes old, and asks
iOS for a background refresh about once an hour (iOS decides when). If the
true balance goes below zero, you get a notification.

## European banks (Enable Banking)

Any European bank Enable Banking supports (about 2,700 in 29 countries: Hello
Bank, Revolut, BNP Paribas, N26, ING…), read only, for your own accounts, free
in Enable Banking's restricted mode. Requests are signed on the iPhone: nothing
goes through a server of ours.

**Step-by-step guide** (Enable Banking account, application and `.pem` key,
linking the accounts, importing the key, connecting a bank, troubleshooting):
[EUROPEAN-BANKS.md](EUROPEAN-BANKS.md).

## Siri, Shortcuts and widget

- **Siri / Shortcuts**: "Hey Siri, what's my true balance in True Balance?"
  (FR: « Dis Siri, quel est mon vrai solde dans True Balance ? ») and
  "… daily budget". Answers from the last refresh; the iPhone must be unlocked.
- **Widget** (home and lock screen): a separate extension that reads what the
  app writes into an App Group (`APP_GROUP_ID` in `project.yml`, default
  `group.il.truebalance.app`). If you change the bundle ID, change the group
  too. Without the App Group (signing that refuses it), the app works and the
  widget just asks to open the app.

## Tests

```sh
cd ios/Packages/TrueBalanceCore && swift test
```

## Known limits

- The login flows follow the banks' current web pages. When Leumi or Max
  change their site, the matching steps in `BankScrapers.swift` need the same
  update as upstream `israeli-bank-scrapers` (check its recent commits).
- If Max asks for an extra step (ID number, SMS code), the app says so; sign in
  once on max.co.il, then retry.
- Only the first Leumi account is read.
- Leumi is moving accounts to a new site ("digitalfront"). The app logs in
  through the new gate-keeper page (resending the form once if it stalls), but
  an account already moved to digitalfront gets a clear "not supported yet"
  error.
- Every step has a deadline (a page script, a request, the extras, and each
  bank as a whole), so a stuck bank page ends in an error instead of a
  refresh that never finishes.
