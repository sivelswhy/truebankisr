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
a donut of the next debit by category, search across upcoming charges, live
progress while signing in, an alert threshold notification, an optional Face ID
lock and a hide-amounts option in Settings.

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
    ├── Storage.swift                 Keychain (credentials) + snapshot file
    ├── AppModel.swift                State, refresh, background refresh, overdraft alert
    ├── Views/                        SwiftUI screens
    └── Resources/                    Assets, Localizable.xcstrings (en, fr)
```

## Build and install on your iPhone

1. `brew install xcodegen` (once), then from `ios/`: `xcodegen generate`
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

## Staying signed in

Credentials are stored in the Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: they never leave this
iPhone (no iCloud sync) and stay available for background refresh. The app
refreshes when you open it if the data is more than 15 minutes old, and asks
iOS for a background refresh about once an hour (iOS decides when). If the
true balance goes below zero, you get a notification.

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
