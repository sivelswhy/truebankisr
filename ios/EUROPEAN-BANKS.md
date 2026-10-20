# European banks in True Balance

True Balance can show your accounts at European banks (Hello Bank, Revolut,
BNP Paribas, N26, ING, Boursobank… about 2,700 banks in 29 countries) next to
Leumi and Max. They appear in their own **Other banks** section on Home and are
not added to the true balance.

This guide takes you from nothing to your first European account in the app.
It takes about 15 minutes, once.

## How it works

Israeli banks keep open banking for licensed companies, so the app reads
Leumi and Max by signing in to their websites. European banks are different:
the PSD2 directive obliges them to offer an API, reachable through aggregators.

[Enable Banking](https://enablebanking.com) is one of them. Its **restricted
mode** is free and lets an individual read **their own** accounts:

- you create an "application" in their portal and get a private key (a `.pem` file),
- you link your own accounts to that application,
- the app signs every request with the key, **on the iPhone**, and calls
  Enable Banking directly: there is no server of ours in between.

Access is **read only** (balances and transactions, never payments) and lasts
**180 days**, after which you confirm again with the bank.

## What you need

- An email address for the Enable Banking account.
- Your usual login for each bank (app or website, with its two-factor step).
- The iPhone with True Balance installed, and a way to send it a file
  (AirDrop, iCloud Drive…).

## 1. Create the Enable Banking account

1. Go to [enablebanking.com](https://enablebanking.com) and sign up, then open
   the **Control Panel**.
2. Confirm your email if asked.

## 2. Register the application

In the Control Panel, register a new application and fill in the form:

| Field | What to put |
|---|---|
| Environment | **Production**. The sandbox only has fake test banks. |
| Name | Anything, e.g. `True Balance` |
| Key | **Generate in the browser (using SubtleCrypto) and export private key** |
| Allowed redirect URLs | `https://sivelswhy.github.io/truebankisr/enablebanking.html` |
| Privacy URL | `https://github.com/sivelswhy/truebankisr/blob/main/README.md` |
| Terms URL | `https://github.com/sivelswhy/truebankisr/blob/main/LICENSE.md` |

Notes:

- **The key.** The browser creates the key pair on your Mac; Enable Banking
  only receives the public half. The private half is downloaded as a `.pem`
  file named after the application ID, e.g. `1a2b3c4d-….pem`. It can't be
  downloaded again: if you lose it, register a new application.
- **The redirect URL.** Enable Banking only accepts `https://` addresses
  (`truebalance://…` is refused with "unsupported scheme"). That page
  (`docs/enablebanking.html` in this repo, on GitHub Pages) immediately hands
  the bank's answer on to the app.
- Write down the **Application ID** shown after registering.

## 3. Link your accounts (activates restricted mode)

A new Production application must be activated. Instead of a commercial
contract, link your own accounts to it:

1. In the Control Panel, open the application and choose to activate it by
   **linking accounts**.
2. Pick the country and the bank, sign in with your usual login and confirm.
3. Repeat for every bank you want in True Balance.

The application then shows as **Restricted** but **Active**: that is the
expected state. In restricted mode, **only the accounts linked here are ever
shared** with the app, so a bank you skip here will connect but show no
account.

## 4. Send the key to the iPhone

1. AirDrop the `.pem` file to the iPhone and choose **Save to Files** (or put
   it in iCloud Drive).
2. Keep a copy somewhere safe on the Mac, **outside the project folder**, so it
   never ends up on GitHub.

## 5. Import the key in the app

1. In True Balance, tap your profile picture (top right) → **Other banks**.
2. **Import the key (.pem)** and pick the file.
3. The app fills in the Application ID from the file name: check it matches the
   one in the portal, then **Save**.

The app tries the key right away and refuses a file it can't use. The key is
then kept in the iPhone's Keychain; you can delete the file from Files.

## 6. Connect a bank

1. Still in **Other banks**, tap **Add a bank**.
2. Pick the country (France by default) and search for the bank.
3. Tap it: Safari opens the bank's page (or its app). Sign in and confirm the
   access.
4. Safari asks **Open in True Balance?** → **Open**. If nothing happens, tap
   **Open True Balance** on the page.

The bank now appears with "Connected until …", and its accounts on Home.

## Using it

- **Home → Other banks**: a chip per bank (tap to switch), the balance of each
  account in its currency with the shekel equivalent at the Bank of Israel
  rate, the latest transactions, and **See all** for the last 90 days.
- **Refreshing**: pull down on Home. Banks may limit reads made without you to
  about 4 a day, so automatic refreshes (opening the app, background) read
  these banks at most every 6 hours. Pull to refresh always reads them.
- **After 180 days**: the bank shows "Access expired". Tap **Reconnect**.
- **Removing a bank**: swipe it left in **Other banks** → **Disconnect**.
  The app also ends the session at Enable Banking.
- **Disconnect accounts** (profile) deletes everything from the iPhone,
  including the key. Re-import the `.pem` to start again.

## Troubleshooting

| What you see | What to do |
|---|---|
| "unsupported scheme" in the portal | Use only the `https://…/enablebanking.html` redirect URL. |
| The bank connects but no account appears | Link that bank's accounts in the portal (step 3). |
| "This key file can’t be read" | Pick the `.pem` downloaded from the portal (it starts with `-----BEGIN PRIVATE KEY-----`). |
| "Enable Banking answered with an error (401)" or (403) | The Application ID doesn't match the key, or the application isn't active yet. Check both in the portal. |
| "The bank didn’t give access" | The login was cancelled or refused at the bank. Try again. |
| "The bank limits how often it can be read" | Wait a few hours; the last balance stays on screen meanwhile. |
| "Access has expired" | Reconnect the bank. |
| Safari doesn't come back to the app | Tap **Open True Balance** on the page, and make sure the app is installed. |

Errors also show in the status icon next to your profile picture: tap it for
the details. The small grey text under an error is the technical detail to
send when asking for help.

## Privacy

- The key, the bank sessions and the downloaded balances stay on the iPhone
  (Keychain and app files). Nothing goes through a server of ours.
- Enable Banking sees the requests, as the regulated intermediary between the
  app and the bank.
- You can revoke the access at any time: in the app (**Disconnect**), at the
  bank, or by deleting the application in the Enable Banking portal.
