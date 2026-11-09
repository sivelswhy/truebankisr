import Foundation
import TrueBalanceCore

struct Credentials: Codable, Equatable, Sendable {
    var username: String
    var password: String
}

enum Provider: String, Codable, CaseIterable, Sendable {
    case leumi, max
}

enum BankError: Error, Equatable {
    case invalidCredentials
    case changePassword
    case blocked
    /// The site asked for something we can't automate (ID number, SMS code…).
    case extraVerification
    /// `step`: where it got stuck, for troubleshooting.
    case timeout(step: String)
    case unavailable(String)
    /// No network on the iPhone.
    case offline
    /// The site refused this network (firewall, abroad, VPN); what the page said.
    case refused(String)
    /// The site shows a maintenance or "service unavailable" page.
    case maintenance(String)

    /// Problems with the account itself, which no page diagnosis should hide.
    var isAboutAccount: Bool {
        switch self {
        case .invalidCredentials, .changePassword, .blocked, .extraVerification: true
        default: false
        }
    }

    /// The real reason behind a failed step: no network, a block or
    /// maintenance page on screen, or else the step that timed out.
    @MainActor
    static func diagnosing(_ error: Error, _ d: WebDriver) async -> BankError {
        if let e = error as? BankError, e.isAboutAccount { return e }
        if !Connectivity.shared.isOnline || Connectivity.isOffline(error) { return .offline }
        if let problem = await d.pageProblem() {
            switch problem {
            case .refused(let detail): return .refused(detail)
            case .maintenance(let detail): return .maintenance(detail)
            }
        }
        if let s = error as? WebDriver.HTTPStatus { return .unavailable("HTTP \(s.code) on \(s.host)") }
        if let e = error as? BankError { return e }
        if let t = error as? WebDriver.Timeout { return .timeout(step: t.what) }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut {
            return .timeout(step: "\(d.currentStep): the page didn’t load")
        }
        return .unavailable("\(d.currentStep): \(error)")
    }
}

/// One failure per site, so the UI can show each next to the right fields.
struct ScrapeFailure: Error {
    var errors: [Provider: BankError]
}

/// What Max gives besides the purchases.
struct MaxData: Sendable {
    var account: Account
    var cards: [CardInfo]
}

/// What Leumi gives besides the current account. Nil = couldn't be read this time.
struct LeumiData: Sendable {
    var account: Account
    var savings: [SavingsAccount]?
    var foreign: [ForeignAccount]?
}

// MARK: - Max (port of israeli-bank-scrapers/src/scrapers/max.ts)

@MainActor
enum MaxScraper {
    static let base = "https://www.max.co.il"
    static let api = "https://onlinelcapi.max.co.il"

    /// A year back gives the profile and merchant pages their history.
    static func scrape(_ credentials: Credentials, visible: Bool = false, monthsBack: Int = 12, monthsAhead: Int = 3) async throws(BankError) -> MaxData {
        // Direct HTTP first (fast). The visible mode is for doing the login by
        // hand, so it always uses the page.
        if !visible {
            do {
                driverStep("Max: direct connection")
                return try await MaxDirect.scrape(credentials, monthsBack: monthsBack, monthsAhead: monthsAhead)
            } catch MaxDirect.Failure.bank(let e) {
                Log.add("[error] Max direct: \(e)")
                throw e
            } catch {
                Log.add("[fallback] Max direct failed, using the page: \(error)")
            }
        }
        let driver = WebDriver(visible: visible)
        defer { driver.close() }
        do {
            return try await withDeadline(visible ? 900 : 240, "\(driver.currentStep) (gave up after 4 min)") {
                try await scrapePages(driver, credentials, monthsBack: monthsBack, monthsAhead: monthsAhead)
            }
        } catch {
            let e = await BankError.diagnosing(error, driver)
            Log.add("[error] Max: \(e) (from \(error))")
            throw e
        }
    }

    private static func driverStep(_ name: String) {
        WebDriver.onStep?(name)
        Log.add("[step] \(name)")
    }

    private static func scrapePages(_ driver: WebDriver, _ credentials: Credentials, monthsBack: Int, monthsAhead: Int) async throws -> MaxData {
        try await login(driver, credentials)
        let home = try? await driver.fetch("\(base)/api/registered/getHomePageData")
        let homeData = home?.status == 200 ? home?.body : nil
        let holder = await holderName(driver, homeData: homeData)
        var txns: [Txn] = []
        driver.step("Max: reading transactions")
        for month in months(back: monthsBack, ahead: monthsAhead) {
            let (status, body) = try await driver.fetch(transactionsURL(month))
            guard status == 200 else { continue }
            txns += try MaxParser.parseMonth(body)
        }
        return MaxData(account: Account(accountNumber: "max", txns: txns, holderName: holder),
                       cards: homeData.map(ExtraParsers.maxCards) ?? [])
    }

    private static func login(_ d: WebDriver, _ c: Credentials) async throws {
        d.step("Max: opening login page")
        try await d.load("\(base)/login")
        try await d.waitForElement(".personal-area > a.go-to-personal-area")
        try await Task.sleep(for: .seconds(3)) // let the site's own scripts finish first
        if await d.exists("#closePopup") { try await d.click("#closePopup") }
        d.step("Max: opening personal area")
        try await d.click(".personal-area > a.go-to-personal-area")
        if await d.exists(".login-link#private") { try await d.click(".login-link#private") }
        // Max now opens on "ID + SMS"; switch to the username/password tab.
        try await d.waitFor("password tab", timeout: 20, condition: "return !!document.querySelector('#login-password-link')")
        try await d.click("#login-password-link")
        try await d.waitForElement("#login-password.tab-pane.active app-user-login-form")
        d.step("Max: filling the form")
        try await d.fill("#user-name", c.username)
        try await d.fill("#password", c.password)
        try await d.click("app-user-login-form .general-button.send-me-code")

        // Success = redirected to the personal area; otherwise an error popup.
        // When visible, leave time to finish an extra step (ID, SMS) by hand.
        d.step("Max: waiting for the personal area")
        let deadline = Date.now.addingTimeInterval(d.visible ? 180 : 30)
        while Date.now < deadline {
            let url = d.url
            if url.contains("/homepage/personal") { return }
            if url.contains("/renew-password") { throw BankError.changePassword }
            if await d.exists("#popupWrongDetails") { throw BankError.invalidCredentials }
            if await d.exists("#popupCardHoldersLoginError") { throw BankError.unavailable("Max login error popup") }
            try await Task.sleep(for: .milliseconds(400))
        }
        // Still on the login page: Max is asking for an extra step (ID number, SMS…).
        throw BankError.extraVerification
    }

    /// From the personal area's data, else the page's "שלום …" greeting.
    private static func holderName(_ d: WebDriver, homeData: Data?) async -> String? {
        if let name = homeData.flatMap(HolderName.fromJSON) { return name }
        return HolderName.fromGreeting(await d.bodyText())
    }

    static func months(back: Int, ahead: Int, now: Date = .now) -> [Date] {
        let cal = Israel.calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        return (-back...ahead).map { cal.date(byAdding: .month, value: $0, to: start)! }
    }

    static func transactionsURL(_ month: Date) -> String {
        let c = Israel.calendar.dateComponents([.year, .month], from: month)
        let filter = #"{"userIndex":-1,"cardIndex":-1,"monthView":true,"date":"\#(c.year!)-\#(c.month!)-01","dates":{"startDate":"0","endDate":"0"},"bankAccount":{"bankAccountIndex":-1,"cards":null}}"#
        var url = URLComponents(string: "\(api)/api/registered/transactionDetails/getTransactionsAndGraphs")!
        url.queryItems = [URLQueryItem(name: "filterData", value: filter), URLQueryItem(name: "firstCallCardIndex", value: "-1")]
        return url.url!.absoluteString
    }
}

// MARK: - Leumi (port of israeli-bank-scrapers/src/scrapers/leumi/leumi.ts)

@MainActor
enum LeumiScraper {
    static let base = "https://hb2.bankleumi.co.il"
    static let transactionsURL = "\(base)/eBanking/SO/SPA.aspx#/ts/BusinessAccountTrx?WidgetPar=1"
    /// "אחד או יותר מפרטי ההזדהות שהוקלדו/שמסרת שגויים" (wording varies).
    static let invalidPasswordMessage = "אחד או יותר מפרטי ההזדהות"
    /// "יש להקליד 6-12 אותיות באנגלית וספרות בלבד": the form refused the format.
    static let invalidFormatMessage = "יש להקליד 6-12"
    static let blockedMessage = "המנוי חסום"

    static let savingsURL = "\(base)/uiapiproxy/v1/digital-retails/mobile/accounts/1/Deposits?operationList=true"
    static let foreignURL = "\(base)/eBanking/ForeignCurrency/DisplayForeignAccountsActivity.aspx"

    static func scrape(_ credentials: Credentials, since: Date, visible: Bool = false) async throws(BankError) -> LeumiData {
        let driver = WebDriver(captureURLPattern: "UC_SO_27_GetBusinessAccountTrx", visible: visible)
        defer { driver.close() }
        do {
            return try await withDeadline(visible ? 900 : 300, "\(driver.currentStep) (gave up after 5 min)") {
                try await login(driver, credentials)
                // Fast path: the site's own data calls, no clicking. Anything
                // unexpected falls back to driving the page.
                var result: Account
                do {
                    result = try await directAccount(driver, since: since)
                } catch {
                    Log.add("[fallback] Leumi direct failed, using the page: \(error)")
                    result = try await account(driver, since: since)
                }
                result.holderName = await holderName(driver)
                // Extras: a failure or a hang here never fails the refresh.
                let savings = try? await withDeadline(45, "savings") { await self.savings(driver) }
                let foreign = try? await withDeadline(visible ? 300 : 90, "foreign accounts") { try await foreignAccounts(driver, since: since) }
                return LeumiData(account: result, savings: savings ?? nil, foreign: foreign)
            }
        } catch {
            let e = await BankError.diagnosing(error, driver)
            Log.add("[error] Leumi: \(e) (from \(error))")
            throw e
        }
    }

    private static func login(_ d: WebDriver, _ c: Credentials) async throws {
        d.step("Leumi: opening login page")
        try await d.load("\(base)/authenticate/logon")
        let user = #"input[placeholder="שם משתמש"]"#
        let pass = #"input[placeholder="סיסמה"]"#
        d.step("Leumi: waiting for the login form")
        try await d.waitForElement(user)
        try await d.waitForElement(pass)
        // Leumi's firewall rejects a login sent before its own page script has
        // finished checking the browser (seen as "The requested URL was rejected").
        d.step("Leumi: letting the page settle")
        try await Task.sleep(for: .seconds(10))
        d.step("Leumi: filling the form")
        try await d.fill(user, c.username)
        try await d.fill(pass, c.password)
        try await d.click("button[type='submit']")

        d.step("Leumi: waiting for the account page")
        let start = Date.now
        let deadline = start.addingTimeInterval(d.visible ? 180 : 75)
        var resubmitted = false
        while Date.now < deadline {
            if d.url.range(of: "ebanking/SO/SPA.aspx", options: .caseInsensitive) != nil { return }
            // Accounts moved to Leumi's new site, which this scraper doesn't read yet.
            if d.url.range(of: "digitalfront", options: .caseInsensitive) != nil {
                throw BankError.unavailable("Leumi opened its new site (\(URL(string: d.url)?.path ?? d.url)), not supported yet")
            }
            if await d.exists(#"form input[name="newPwd"]"#) { throw BankError.changePassword }
            let text = await d.bodyText()
            if text.contains(invalidPasswordMessage) || text.contains(invalidFormatMessage) { throw BankError.invalidCredentials }
            if text.contains("was rejected") { throw BankError.unavailable("Leumi firewall rejected the login") }
            if text.contains(blockedMessage) { throw BankError.blocked }
            // The gate-keeper login page sometimes drops the first submit and
            // just sits there with the form: fill it and send it once more.
            if !resubmitted, Date.now.timeIntervalSince(start) > 20, await d.exists(user), await d.exists(pass) {
                resubmitted = true
                d.step("Leumi: sending the login form again")
                try await d.fill(user, c.username)
                try await d.fill(pass, c.password)
                try await d.click("button[type='submit']")
                d.step("Leumi: waiting for the account page")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw BankError.timeout(step: "Leumi: waiting for the account page (still on \(URL(string: d.url)?.path ?? d.url))")
    }

    /// The welcome message in the account pages' header ("שלום <name>").
    private static func holderName(_ d: WebDriver) async -> String? {
        let text = try? await d.eval("""
            const e = document.querySelector('app-welcome-user span.name');
            return e ? e.textContent : '';
            """) as? String
        if let name = HolderName.fromElementText(text) { return name }
        return HolderName.fromGreeting(await d.bodyText())
    }

    /// The "חיפוש מתקדם" button can take a while to appear on the phone, or sit
    /// behind an interstitial: wait longer, find it by title or text, reload
    /// once, and say what the page showed if it never comes.
    private static func openAdvancedSearch(_ d: WebDriver) async throws {
        let find = """
            const label = 'חיפוש מתקדם';
            const b = Array.from(document.querySelectorAll('button')).find(e =>
                !e.hidden && (e.title === label || (e.innerText || '').trim() === label));
            """
        for attempt in 0..<2 {
            if attempt > 0 {
                d.step("Leumi: reloading transactions")
                _ = try? await d.eval("location.reload()")
                try await Task.sleep(for: .seconds(8))
            }
            if (try? await d.waitFor("advanced search button", timeout: 45, condition: find + "return !!b;")) != nil {
                try await d.eval(find + "b.scrollIntoView({ block: 'center' }); b.click();")
                return
            }
        }
        let seen = (try? await d.eval("""
            return document.title + ' | ' + location.hash + ' | ' + (document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').slice(0, 160);
            """) as? String) ?? ""
        throw WebDriver.Timeout(what: "Leumi: advanced search button not found. Page: \(seen)")
    }

    /// Deposits and savings (same endpoint as the JS scraper).
    private static func savings(_ d: WebDriver) async -> [SavingsAccount]? {
        d.step("Leumi: reading savings")
        guard let (status, body) = try? await d.fetch(savingsURL), status == 200 else { return nil }
        return ExtraParsers.leumiSavings(body)
    }

    /// Foreign-currency accounts: an older ASP.NET page with one account per
    /// option of a drop-down (port of leumi-forex.ts, balances only).
    private static func foreignAccounts(_ d: WebDriver, since: Date) async throws -> [ForeignAccount] {
        d.step("Leumi: reading foreign-currency accounts")
        try await d.load(foreignURL)
        try await Task.sleep(for: .seconds(4))
        let select = "#ddlAccounts_m_ddl"
        guard (try? await d.waitForElement(select, timeout: 15)) != nil else { return [] } // none
        let values = try await d.eval("""
            return Array.from(document.querySelectorAll(s + ' option'), o => o.value).filter(v => !!v);
            """, ["s": select]) as? [String] ?? []
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy"
        f.timeZone = Israel.timeZone
        var out: [ForeignAccount] = []
        for value in values {
            // Mark the page: the submit reloads it, which clears the mark.
            try await d.eval("""
                const set = (sel, v) => { const e = document.querySelector(sel); e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); };
                set('#ddlAccounts_m_ddl', a);
                set('#ddlTransactionPeriod', '3');
                window.__tbMark = Date.now();
                """, ["a": value])
            try await d.fill("#dtFromDate_textBox", f.string(from: since))
            try await d.click("#btnDisplayDates")
            try await d.waitFor("foreign activity", timeout: 30, condition: """
                const done = !window.__tbMark || Date.now() - window.__tbMark > 8000;
                return done && !!document.querySelector('#ctlActivityTable, #NOINFORMATIONREGIONSERVERSIDEERROR');
                """)
            let page = try await d.eval("""
                const text = s => { const e = document.querySelector(s); return e ? e.innerText.trim() : ''; };
                const rows = Array.from(document.querySelectorAll('#ctlActivityTable tr:not(.header)'),
                    tr => Array.from(tr.querySelectorAll('td'), td => td.innerText.trim()));
                return { currency: text('#lblCurrencyVal'), opening: text('#lblOpeningBalanceVal'), rows };
                """) as? [String: Any]
            guard let page, let currency = ExtraParsers.leumiCurrency(page["currency"] as? String ?? ""), currency != "ILS" else { continue }
            let balance = ExtraParsers.leumiForeignBalance(rows: page["rows"] as? [[String]] ?? [], opening: page["opening"] as? String ?? "")
            if balance != 0 { out.append(ForeignAccount(currency: currency, balance: balance)) }
        }
        return out
    }

    /// The data calls the transactions page makes (found with
    /// reverse-api-engineer), sent from the logged-in page: balance and
    /// transactions without opening the screen or using the search form.
    private static func directAccount(_ d: WebDriver, since: Date) async throws -> Account {
        d.step("Leumi: reading the account")
        struct Direct: Error { var what: String }
        // The SessionID the page embeds is needed in every call's body.
        let (pageStatus, page) = try await d.fetch("\(base)/eBanking/SO/SPA.aspx")
        let html = String(decoding: page, as: UTF8.self)
        guard pageStatus == 200,
              let match = html.range(of: #""SessionID"\s*:\s*"([A-Za-z0-9]+)""#, options: .regularExpression),
              let id = html[match].split(separator: "\"").dropLast().last else { throw Direct(what: "no SessionID (HTTP \(pageStatus))") }

        func broker(_ module: String, _ fields: [String: Any]) async throws -> Data {
            var obj = fields
            obj["StateName"] = "BusinessAccountTrx"
            obj["ModuleName"] = module
            obj["SessionHeader"] = ["SessionID": String(id), "FIID": "Leumi"]
            let reqObj = String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
            let payload = String(decoding: try JSONSerialization.data(withJSONObject:
                ["moduleName": module, "reqObj": reqObj, "version": "Infra_V2.0"]), as: UTF8.self)
            let (status, body) = try await d.postJSON("\(base)/ChannelWCF/Broker.svc/ProcessRequest?moduleName=\(module)", payload)
            guard status == 200 else { throw Direct(what: "\(module) HTTP \(status)") }
            return body
        }
        func inner(_ body: Data) -> [String: Any]? {
            guard let outer = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let text = outer["jsonResp"] as? String else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        }
        let accountFields: [String: Any] = [
            "ComboMethod": "true", "RequestedAccountTypes": "CHECKING",
            "ExtAccountPermissions": "General", "AccountSegments": "",
        ]
        // The server needs this pair first to know which account is meant.
        _ = try await broker("UC_SO_010_02_GetDefaultAccountIndex", accountFields.merging(["AccountIndex": 1]) { $1 })
        let accounts = inner(try await broker("UC_SO_GetAccounts", accountFields))
        let masked = ((accounts?["AccountsItems"] as? [[String: Any]])?.first?["MaskedNumber"] as? String) ?? ""
        let number = masked.replacingOccurrences(of: "/", with: "_").filter { $0.isNumber || $0 == "-" || $0 == "_" }
        guard !number.isEmpty else { throw Direct(what: "no account number") }

        // Same window as the search form: from the start of `since` to the end of today (Israel time).
        let cal = Israel.calendar
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let from = cal.startOfDay(for: since)
        let to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let body = try await broker("UC_SO_27_GetBusinessAccountTrx", [
            "RequestType": "OpersB", "FromDateUTC": f.string(from: from), "ToDateUTC": f.string(from: to),
            "OperationsNumber": "40", "Amount": 0, "AmountType1": 0, "AmountType2": 0, "TrxType": "1",
            "ReferenceNumber": "0", "BeneficiaryName": "0", "BeneficiaryBankCode": "0", "BeneficiaryBranch": "0",
            "BeneficiaryAccountNumber": "0", "InvoiceNumber": "0", "PeriodType": "0", "AccountIndex": 1,
        ])
        // Same parser as the captured page response (same envelope).
        return try LeumiParser.parse(body, accountNumber: number)
    }

    /// Opens the transactions screen and filters from `since`; the balance comes
    /// with the filtered transactions response.
    private static func account(_ d: WebDriver, since: Date) async throws -> Account {
        d.step("Leumi: opening transactions")
        try await d.load(transactionsURL)
        // Leumi rewrites the account number shortly after load.
        try await Task.sleep(for: .seconds(4))
        let number = (try? await d.eval("""
            const e = document.querySelector('app-masked-number-combo span.display-number-li');
            return e ? e.textContent : '';
            """) as? String)?.replacingOccurrences(of: "/", with: "_")
            .filter { $0.isNumber || $0 == "-" || $0 == "_" } ?? ""

        d.step("Leumi: opening advanced search")
        try await openAdvancedSearch(d)
        try await d.waitForElement("bll-radio-button")
        try await d.click("bll-radio-button:not([checked])")
        let from = #"input[formcontrolname="txtInputFrom"]"#
        try await d.waitForElement(from)
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        f.timeZone = Israel.timeZone
        try await d.fill(from, f.string(from: since))

        d.step("Leumi: waiting for the balance")
        await d.clearCaptures()
        try await d.click(#"button[aria-label="סנן"]"#)
        let body = try await d.waitForCapture(timeout: 45)
        return try LeumiParser.parse(body, accountNumber: number)
    }
}

// MARK: - Both

@MainActor
enum Banks {
    /// Logs into both sites and computes the true balance.
    /// `previous` + `onMaxReady`: Max is quick, so once its purchases are in,
    /// a first snapshot is handed out right away (last known bank side, fresh
    /// card side) while Leumi is still loading.
    static func fetchSnapshot(leumi: Credentials, max: Credentials, billingDay: Int = 2,
                              previous: Snapshot? = nil, onMaxReady: ((Snapshot) -> Void)? = nil) async throws -> Snapshot {
        let since = Calendar.current.date(byAdding: .month, value: -2, to: .now)!
        let visible = UserDefaults.standard.bool(forKey: "showBankPages")
        // With older purchases cached, only the recent months need downloading.
        let cached = PurchaseCacheStore.load()
        let monthsBack = cached == nil ? 12 : 2
        // The official rates don't need a login: fetched alongside.
        let rates = Task { await FXRates.current() }
        let b: Result<LeumiData, BankError>
        let c: Result<MaxData, BankError>
        if visible {
            // One page on screen at a time.
            b = await capture { () async throws(BankError) in try await LeumiScraper.scrape(leumi, since: since, visible: true) }
            c = await capture { () async throws(BankError) in try await MaxScraper.scrape(max, visible: true, monthsBack: monthsBack) }
        } else {
            // Both run on the main actor but spend their time awaiting the
            // sites, so they still overlap.
            let bank = Task { await capture { () async throws(BankError) in try await LeumiScraper.scrape(leumi, since: since) } }
            let card = Task { await capture { () async throws(BankError) in try await MaxScraper.scrape(max, monthsBack: monthsBack) } }
            let maxResult = await card.value
            if let previous, let onMaxReady, case .success(let m) = maxResult {
                let purchases = PurchaseCache.merge(cached: cached ?? [], fresh: m.account.txns,
                                                    refetchedFrom: MaxScraper.months(back: monthsBack, ahead: 0).first!)
                let bankSide = Account(accountNumber: "leumi", balance: previous.bankBalance, txns: previous.bankTxns ?? [])
                if var interim = try? TrueBalance.compute(bank: bankSide, cards: [Account(accountNumber: m.account.accountNumber, txns: purchases)],
                                                          billingDay: billingDay, fxRates: previous.fxRates ?? [:]) {
                    interim.holderFirstName = previous.holderFirstName
                    interim.cards = m.cards.isEmpty ? previous.cards : m.cards
                    interim.savings = previous.savings
                    interim.foreignAccounts = previous.foreignAccounts
                    onMaxReady(interim)
                }
            }
            (b, c) = (await bank.value, maxResult)
        }

        var errors: [Provider: BankError] = [:]
        if case .failure(let e) = b { errors[.leumi] = e }
        if case .failure(let e) = c { errors[.max] = e }
        guard errors.isEmpty, case .success(let leumiData) = b, case .success(let maxData) = c else {
            throw ScrapeFailure(errors: errors)
        }
        let bankAccount = leumiData.account, cardAccount = maxData.account
        let windowStart = MaxScraper.months(back: monthsBack, ahead: 0).first!
        let purchases = PurchaseCache.merge(cached: cached ?? [], fresh: cardAccount.txns, refetchedFrom: windowStart)
        PurchaseCacheStore.save(purchases)
        var snapshot = try TrueBalance.compute(bank: bankAccount, cards: [Account(accountNumber: cardAccount.accountNumber, txns: purchases)],
                                               billingDay: billingDay, fxRates: await rates.value)
        // Leumi's header shows the name reliably; Max is the fallback.
        snapshot.holderFirstName = bankAccount.holderName ?? cardAccount.holderName
        snapshot.cards = maxData.cards.isEmpty ? nil : maxData.cards
        snapshot.savings = leumiData.savings
        snapshot.foreignAccounts = leumiData.foreign
        return snapshot
    }
}

@MainActor
private func capture<T>(_ body: () async throws(BankError) -> T) async -> Result<T, BankError> {
    do { return .success(try await body()) } catch { return .failure(error) }
}

/// Bank of Israel official rates (shekels per unit), kept for when it's unreachable.
enum FXRates {
    static let url = URL(string: "https://boi.org.il/PublicApi/GetExchangeRates")!

    static func current() async -> [String: Double] {
        if let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            let rates = ExtraParsers.boiRates(data)
            if !rates.isEmpty {
                UserDefaults.standard.set(rates, forKey: "fxRates")
                return rates
            }
        }
        return UserDefaults.standard.dictionary(forKey: "fxRates") as? [String: Double] ?? [:]
    }
}
