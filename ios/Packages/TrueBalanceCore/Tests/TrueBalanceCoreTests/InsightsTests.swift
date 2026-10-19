import Foundation
import Testing
@testable import TrueBalanceCore

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

private func t(_ date: String, _ amount: Double, _ name: String, category: String? = nil, currency: String = "ILS",
               processed: String? = nil) -> Txn {
    Txn(id: UUID().uuidString, date: iso(date), processedDate: iso(processed ?? date), chargedAmount: amount,
        chargedCurrency: currency, description: name, category: category)
}

private let now = iso("2026-10-19T09:00:00Z")

@Test func detectsSalaryAndRentButNotOneOffs() {
    let bank = [
        t("2026-08-10T08:00:00Z", 9000, "משכורת"), t("2026-09-10T08:00:00Z", 9100, "משכורת"), t("2026-10-10T08:00:00Z", 9050, "משכורת"),
        t("2026-08-01T08:00:00Z", -4500, "Rent"), t("2026-09-01T08:00:00Z", -4500, "Rent"), t("2026-10-01T08:00:00Z", -4500, "Rent"),
        t("2026-09-15T08:00:00Z", -1200, "Garage"), // once
        t("2026-08-05T08:00:00Z", -50, "Varies"), t("2026-09-05T08:00:00Z", -400, "Varies"), // amounts too different
    ]
    let found = RecurringDetector.detect(bank, now: now)
    #expect(found.map(\.name).sorted() == ["Rent", "משכורת"])
    let salary = found.first { $0.amount > 0 }!
    #expect(salary.amount == 9075) // mean of the last two
    #expect(Israel.day(salary.nextDate) == "2026-11-10")
}

@Test func forecastAddsIncomeExpectedBeforeTheDebit() throws {
    var bank = Account(accountNumber: "b", balance: 500, txns: [
        t("2026-08-25T08:00:00Z", 6000, "Salary"), t("2026-09-25T08:00:00Z", 6000, "Salary"),
        t("2026-08-28T08:00:00Z", -300, "Insurance"), t("2026-09-28T08:00:00Z", -300, "Insurance"),
        t("2026-10-02T05:00:00Z", -900, "מקס איט פיננ"), t("2026-09-02T05:00:00Z", -900, "מקס איט פיננ"), // card debit: ignored
    ])
    bank.balance = 500
    let s = try TrueBalance.compute(bank: bank, cards: [Account(accountNumber: "c", txns: [
        t("2026-10-05T10:00:00Z", -800, "Shop", processed: "2026-11-01T22:00:00Z"),
    ])], now: now)
    let f = try #require(Forecaster.forecast(s, now: now))
    #expect(s.trueBalance == -300)
    #expect(f.income.map(\.name) == ["Salary"])
    #expect(f.debits.map(\.name) == ["Insurance"])
    #expect(f.projectedBalance == 5400) // -300 + 6000 - 300
}

@Test func foreignChargesAreConvertedWhenARateIsKnown() throws {
    let s = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 1000, txns: []),
        cards: [Account(accountNumber: "c", txns: [
            t("2026-10-05T10:00:00Z", -10, "Netflix", currency: "USD", processed: "2026-11-01T22:00:00Z"),
            t("2026-10-05T10:00:00Z", -5, "Shop", currency: "CHF", processed: "2026-11-01T22:00:00Z"),
        ])],
        now: now, fxRates: ["USD": 3.11])
    #expect(s.nextCharge?.total == 31.1)
    #expect(s.ignoredForeign.count == 1) // no CHF rate
    let netflix = try #require(s.nextCharge?.txns.first)
    #expect(netflix.originalAmount == -10 && netflix.originalCurrency == "USD" && netflix.isConvertedEstimate)
}

@Test func parsesExtras() {
    let home = #"{"Result":{"UserCards":{"Cards":[{"Last4Digits":"4580","CreditLimit":15000,"OpenToBuy":12500.5}]}}}"#
    let cards = ExtraParsers.maxCards(Data(home.utf8))
    #expect(cards.first?.used == 2499.5)
    let savings = ExtraParsers.leumiSavings(Data(#"{"depositsAndSavingsItems":[{"productName":"פיקדון","currentBalance":"10,000.00"}]}"#.utf8))
    #expect(savings == [SavingsAccount(name: "פיקדון", balance: 10000)])
    let rates = ExtraParsers.boiRates(Data(#"{"exchangeRates":[{"key":"USD","currentExchangeRate":3.11,"unit":1},{"key":"JPY","currentExchangeRate":1.9652,"unit":100}]}"#.utf8))
    #expect(rates["USD"] == 3.11)
    #expect(abs(rates["JPY"]! - 0.019652) < 1e-9)
}

@Test func budgetsCountThisMonthOnly() {
    let history = [t("2026-10-03T08:00:00Z", -300, "Shufersal", category: "groceries"),
                   t("2026-10-12T08:00:00Z", -500, "Rami Levy", category: "groceries"),
                   t("2026-09-20T08:00:00Z", -999, "Shufersal", category: "groceries")]
    let p = Budgets.progress(limits: ["groceries": 1000, "travel": 0], history: history, now: now)
    #expect(p.count == 1)
    #expect(p[0].spent == 800 && p[0].ratio == 0.8)
}

@Test func monthComparisonUsesTheSamePeriod() {
    let history = [t("2026-10-05T08:00:00Z", -100, "A", category: "groceries"),
                   t("2026-09-05T08:00:00Z", -50, "A", category: "groceries"),
                   t("2026-09-25T08:00:00Z", -400, "B", category: "travel")] // after Sept 18: not the same period
    let c = Spending.compareMonths(history, now: now)
    #expect(c.thisMonth == 100 && c.lastMonthSamePeriod == 50 && c.lastMonthTotal == 450)
    #expect(c.change == 1.0)
    #expect(c.byCategory["groceries"] == 50)
}

@Test func csvEscapesAndIncludesNotes() {
    var a = t("2026-10-05T08:00:00Z", -12.5, "Café, \"Bar\"", category: "restaurants")
    a.cardLast4 = "4580"
    let csv = CSVExport.make([a], notes: [a.id: PurchaseNote(text: "with Dana", tags: ["work", "reimbursed"])])
    let row = csv.split(separator: "\n")[1]
    #expect(row == "2026-10-05,\"Café, \"\"Bar\"\"\",restaurants,12.50,ILS,4580,completed,,2026-10-05,,,work reimbursed,with Dana")
}

@Test func newPurchasesAreTheUnseenIds() {
    let a = t("2026-10-01T08:00:00Z", -1, "A"), b = t("2026-10-02T08:00:00Z", -1, "B")
    #expect(Spending.newPurchases(old: [a], new: [a, b]).map(\.id) == [b.id])
}

@Test func subscriptionsAreSteadyMonthlyChargesNotInstallments() {
    var ikea = [t("2026-08-03T08:00:00Z", -250, "IKEA"), t("2026-09-03T08:00:00Z", -250, "IKEA"), t("2026-10-03T08:00:00Z", -250, "IKEA")]
    for i in ikea.indices { ikea[i].installments = Installments(number: i + 1, total: 3) }
    let history = ikea + [
        t("2026-08-12T08:00:00Z", -39.9, "Netflix"), t("2026-09-12T08:00:00Z", -39.9, "Netflix"), t("2026-10-12T08:00:00Z", -39.9, "Netflix"),
        t("2026-09-07T08:00:00Z", -19.9, "Spotify"), t("2026-10-07T08:00:00Z", -19.9, "Spotify"),
        t("2026-09-01T08:00:00Z", -300, "Shufersal"), t("2026-10-01T08:00:00Z", -520, "Shufersal"), // varies: groceries
    ]
    let subs = Subscriptions.detect(history, now: now)
    #expect(subs.map(\.name) == ["Netflix", "Spotify"])
    #expect(Subscriptions.monthlyTotal(subs) == 59.8)
}

@Test func totalsPerCard() {
    var a = t("2026-10-01T08:00:00Z", -100, "A"), b = t("2026-10-02T08:00:00Z", -30, "B"), c = t("2026-10-03T08:00:00Z", -20, "C")
    a.cardLast4 = "4580"; b.cardLast4 = "1127"; c.cardLast4 = "1127"
    let totals = Spending.byCard([a, b, c])
    #expect(totals.map(\.last4) == ["4580", "1127"])
    #expect(totals[1].total == 50 && totals[1].count == 2)
}

@Test func wealthAddsSavingsAndConvertedForeignAccounts() throws {
    var s = try TrueBalance.compute(bank: Account(accountNumber: "b", balance: 1000, txns: []),
                                    cards: [Account(accountNumber: "c", txns: [t("2026-10-05T10:00:00Z", -200, "Shop", processed: "2026-11-01T22:00:00Z")])],
                                    now: now, fxRates: ["USD": 3.11])
    s.savings = [SavingsAccount(name: "Deposit", balance: 5000)]
    s.foreignAccounts = [ForeignAccount(currency: "USD", balance: 100), ForeignAccount(currency: "THB", balance: 50)]
    let w = Wealth.of(s)
    #expect(w.total == 1000 - 200 + 5000 + 311)
    #expect(w.unconverted.map(\.currency) == ["THB"])
}

@Test func leumiForeignAccountHelpers() {
    #expect(ExtraParsers.leumiCurrency("דולר ארה\"ב") == "USD")
    #expect(ExtraParsers.leumiCurrency("דולר קנדי") == "CAD")
    #expect(ExtraParsers.leumiCurrency("יורו") == "EUR")
    #expect(ExtraParsers.leumiCurrency("?") == nil)
    #expect(ExtraParsers.amount("1,234.50") == 1234.5)
    #expect(ExtraParsers.amount("12.00-") == -12)
    let rows = [["01/10/26", "a", "1", "10.00", "", "990.00"], ["15/10/26", "b", "2", "", "50.00", "1,040.00"]]
    #expect(ExtraParsers.leumiForeignBalance(rows: rows, opening: "1,000.00") == 1040)
    #expect(ExtraParsers.leumiForeignBalance(rows: rows.reversed(), opening: "0") == 1040)
    #expect(ExtraParsers.leumiForeignBalance(rows: [], opening: "1,000.00") == 1000)
}

@Test func budgetAlertLevels() {
    #expect(BudgetProgress(category: "a", limit: 100, spent: 79).alertLevel == nil)
    #expect(BudgetProgress(category: "a", limit: 100, spent: 85).alertLevel == 80)
    #expect(BudgetProgress(category: "a", limit: 100, spent: 100).alertLevel == 100)
}

@Test func maxCurrencyCodes() {
    #expect(MaxParser.currency(826) == "GBP")
    #expect(MaxParser.currency(nil) == "ILS")
    #expect(MaxParser.currency(999) == "999")
}

@Test func parsesLeumiMovementDetails() throws {
    let inner = #"{"BalanceDisplay":"163.53","TodayTransactionsItems":[{"DateUTC":"2026-10-14T21:00:00.003Z","EffectiveDateUTC":"2026-10-14T21:00:00.003Z","Description":"סכום פקת\"ש","Amount":163.53,"RunningBalance":163.53,"ReferenceNumberLong":9105601,"FITID":"202610159105601","AdditionalData":"העברה מאת: BNP PARIBAS - PARIS 10-800-02"}],"HistoryTransactionsItems":null}"#
    let envelope = try JSONSerialization.data(withJSONObject: ["jsonResp": inner])
    let account = try LeumiParser.parse(envelope, accountNumber: "x")
    let t = try #require(account.txns.first)
    #expect(t.id == "202610159105601")
    #expect(t.runningBalance == 163.53 && t.valueDate == nil)
    #expect(BankMovement.kind(t) == .transferIn)
    #expect(BankMovement.counterparty(t) == "BNP PARIBAS - PARIS 10-800-02")
}

@Test func classifiesBankMovements() {
    var out = t("2026-10-10T08:00:00Z", -500, "העברה בנקאית")
    out.memo = "העברה ל: דנה כהן 12-345-678"
    #expect(BankMovement.kind(out) == .transferOut)
    #expect(BankMovement.counterparty(out) == "דנה כהן 12-345-678")
    #expect(BankMovement.kind(t("2026-10-02T08:00:00Z", -900, "מקס איט פיננ")) == .cardDebit)
    #expect(BankMovement.kind(t("2026-10-10T08:00:00Z", 9000, "משכורת")) == .income)
    #expect(BankMovement.kind(t("2026-10-10T08:00:00Z", -50, "BIT")) == .transferOut)
    let totals = BankMovement.totals([out, t("2026-10-10T08:00:00Z", 9000, "משכורת")])
    #expect(totals.in == 9000 && totals.out == 500)
}
