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
}

/// One failure per site, so the UI can show each next to the right fields.
struct ScrapeFailure: Error {
    var errors: [Provider: BankError]
}

// MARK: - Max (port of israeli-bank-scrapers/src/scrapers/max.ts)

@MainActor
enum MaxScraper {
    static let base = "https://www.max.co.il"
    static let api = "https://onlinelcapi.max.co.il"

    /// A year back gives the profile and merchant pages their history.
    static func scrape(_ credentials: Credentials, visible: Bool = false, monthsBack: Int = 12, monthsAhead: Int = 3) async throws(BankError) -> Account {
        let driver = WebDriver(visible: visible)
        defer { driver.close() }
        do {
            try await login(driver, credentials)
            let holder = await holderName(driver)
            var txns: [Txn] = []
            driver.step("Max: reading transactions")
            for month in months(back: monthsBack, ahead: monthsAhead) {
                let (status, body) = try await driver.fetch(transactionsURL(month))
                guard status == 200 else { continue }
                txns += try MaxParser.parseMonth(body)
            }
            return Account(accountNumber: "max", txns: txns, holderName: holder)
        } catch let error as BankError {
            throw error
        } catch let t as WebDriver.Timeout {
            throw .timeout(step: t.what)
        } catch {
            throw .unavailable("\(driver.currentStep): \(error)")
        }
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
    private static func holderName(_ d: WebDriver) async -> String? {
        if let (status, body) = try? await d.fetch("\(base)/api/registered/getHomePageData"), status == 200,
           let name = HolderName.fromJSON(body) {
            return name
        }
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

    static func scrape(_ credentials: Credentials, since: Date, visible: Bool = false) async throws(BankError) -> Account {
        let driver = WebDriver(captureURLPattern: "UC_SO_27_GetBusinessAccountTrx", visible: visible)
        defer { driver.close() }
        do {
            try await login(driver, credentials)
            var result = try await account(driver, since: since)
            result.holderName = await holderName(driver)
            return result
        } catch let error as BankError {
            throw error
        } catch let t as WebDriver.Timeout {
            throw .timeout(step: t.what)
        } catch {
            throw .unavailable("\(driver.currentStep): \(error)")
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
        let deadline = Date.now.addingTimeInterval(d.visible ? 180 : 60)
        while Date.now < deadline {
            if d.url.range(of: "ebanking/SO/SPA.aspx", options: .caseInsensitive) != nil { return }
            if await d.exists(#"form input[name="newPwd"]"#) { throw BankError.changePassword }
            let text = await d.bodyText()
            if text.contains(invalidPasswordMessage) || text.contains(invalidFormatMessage) { throw BankError.invalidCredentials }
            if text.contains("was rejected") { throw BankError.unavailable("Leumi firewall rejected the login") }
            if text.contains(blockedMessage) { throw BankError.blocked }
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
        try await d.waitForElement(#"button[title="חיפוש מתקדם"]"#)
        try await d.click(#"button[title="חיפוש מתקדם"]"#)
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
    static func fetchSnapshot(leumi: Credentials, max: Credentials, billingDay: Int = 2) async throws -> Snapshot {
        let since = Calendar.current.date(byAdding: .month, value: -2, to: .now)!
        let visible = UserDefaults.standard.bool(forKey: "showBankPages")
        // With older purchases cached, only the recent months need downloading.
        let cached = PurchaseCacheStore.load()
        let monthsBack = cached == nil ? 12 : 2
        let b: Result<Account, BankError>
        let c: Result<Account, BankError>
        if visible {
            // One page on screen at a time.
            b = await capture { () async throws(BankError) in try await LeumiScraper.scrape(leumi, since: since, visible: true) }
            c = await capture { () async throws(BankError) in try await MaxScraper.scrape(max, visible: true, monthsBack: monthsBack) }
        } else {
            // Both run on the main actor but spend their time awaiting the
            // sites, so they still overlap.
            let bank = Task { await capture { () async throws(BankError) in try await LeumiScraper.scrape(leumi, since: since) } }
            let card = Task { await capture { () async throws(BankError) in try await MaxScraper.scrape(max, monthsBack: monthsBack) } }
            (b, c) = (await bank.value, await card.value)
        }

        var errors: [Provider: BankError] = [:]
        if case .failure(let e) = b { errors[.leumi] = e }
        if case .failure(let e) = c { errors[.max] = e }
        guard errors.isEmpty, case .success(let bankAccount) = b, case .success(let cardAccount) = c else {
            throw ScrapeFailure(errors: errors)
        }
        let windowStart = MaxScraper.months(back: monthsBack, ahead: 0).first!
        let purchases = PurchaseCache.merge(cached: cached ?? [], fresh: cardAccount.txns, refetchedFrom: windowStart)
        PurchaseCacheStore.save(purchases)
        var snapshot = try TrueBalance.compute(bank: bankAccount, cards: [Account(accountNumber: cardAccount.accountNumber, txns: purchases)],
                                               billingDay: billingDay)
        // Leumi's header shows the name reliably; Max is the fallback.
        snapshot.holderFirstName = bankAccount.holderName ?? cardAccount.holderName
        return snapshot
    }
}

@MainActor
private func capture<T>(_ body: () async throws(BankError) -> T) async -> Result<T, BankError> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
