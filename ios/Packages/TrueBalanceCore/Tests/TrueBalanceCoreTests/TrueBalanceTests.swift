import Foundation
import Testing
@testable import TrueBalanceCore

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

private func card(_ processed: String, _ amount: Double, status: TxnStatus = .completed, currency: String = "ILS",
                  installments: Installments? = nil, category: String? = nil) -> Txn {
    Txn(id: UUID().uuidString, date: iso("2026-10-05T10:00:00Z"), processedDate: iso(processed), chargedAmount: -amount,
        chargedCurrency: currency, description: "shop", status: status, installments: installments, category: category)
}

private let now = iso("2026-10-19T09:00:00Z")

@Test func subtractsChargesNotYetDebited() throws {
    let r = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 163, txns: []),
        cards: [Account(accountNumber: "c", txns: [
            card("2026-10-01T21:00:00Z", 500), // Oct 2 Israel time: already debited
            card("2026-11-01T22:00:00Z", 120), // Nov 2
            card("2026-11-01T22:00:00Z", 80.5),
            card("2026-12-01T22:00:00Z", 40, installments: Installments(number: 2, total: 3)),
        ])],
        now: now)
    #expect(r.nextCharge?.chargeDate == "2026-11-02")
    #expect(r.nextCharge?.total == 200.5)
    #expect(r.trueBalance == -37.5)
    #expect(r.trueBalanceAllKnown == -77.5)
    #expect(r.upcoming.count == 2)
}

@Test func statementInCreditCarriesToNextOne() throws {
    let r = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 500, txns: []),
        cards: [Account(accountNumber: "c", txns: [
            card("2026-11-01T22:00:00Z", 156.9),
            card("2026-11-01T22:00:00Z", -200, category: "transfer"), // money sent to the card from Revolut
            card("2026-12-01T22:00:00Z", 100),
        ])],
        now: now)
    #expect(r.nextCharge?.total == 0)
    #expect(r.nextCharge?.credit == 43.1)
    #expect(r.trueBalance == 500)
    #expect(r.upcoming[1].total == 56.9)
    #expect(r.upcoming[1].credit == nil)
    #expect(r.trueBalanceAllKnown == 443.1)
}

@Test func pendingGoesToNextBillingDay() throws {
    let r = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 1000, txns: []),
        cards: [Account(accountNumber: "c", txns: [card("2026-10-18T10:00:00Z", 30, status: .pending)])],
        now: now)
    #expect(r.nextCharge?.chargeDate == "2026-11-02")
    #expect(r.trueBalance == 970)
}

@Test func pendingInDecemberRollsToJanuary() {
    #expect(TrueBalance.nextBillingDay(after: "2026-12-15", billingDay: 2) == "2027-01-02")
    #expect(TrueBalance.nextBillingDay(after: "2026-12-02", billingDay: 2) == "2026-12-02")
}

@Test func billingDayCountsUntilBankShowsDebit() throws {
    let billingNow = iso("2026-11-02T08:00:00Z")
    let cards = [Account(accountNumber: "c", txns: [card("2026-11-01T22:00:00Z", 300)])]

    let before = try TrueBalance.compute(bank: Account(accountNumber: "b", balance: 500, txns: []), cards: cards, now: billingNow)
    #expect(before.trueBalance == 200)

    let debit = Txn(id: "d", date: iso("2026-11-02T05:00:00Z"), processedDate: iso("2026-11-02T05:00:00Z"),
                    chargedAmount: -300, description: "מקס איט פיננ")
    let after = try TrueBalance.compute(bank: Account(accountNumber: "b", balance: 200, txns: [debit]), cards: cards, now: billingNow)
    #expect(after.trueBalance == 200)
    #expect(after.nextCharge == nil)
}

@Test func foreignCurrencyIsReportedNotSubtracted() throws {
    let r = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 100, txns: []),
        cards: [Account(accountNumber: "c", txns: [card("2026-11-01T22:00:00Z", 10, currency: "USD")])],
        now: now)
    #expect(r.trueBalance == 100)
    #expect(r.ignoredForeign.count == 1)
}

@Test func missingBankBalanceThrows() {
    #expect(throws: TrueBalance.MissingBalance.self) {
        try TrueBalance.compute(bank: Account(accountNumber: "b", txns: []), cards: [], now: now)
    }
}

@Test func categoryTotalsBiggestFirst() {
    let totals = Category.totals([
        card("2026-11-01T22:00:00Z", 10, category: "groceries"),
        card("2026-11-01T22:00:00Z", 50, category: "restaurants"),
        card("2026-11-01T22:00:00Z", 15.5, category: "groceries"),
        card("2026-11-01T22:00:00Z", 5),
    ])
    #expect(totals.map(\.key) == ["restaurants", "groceries", "uncategorized"])
    #expect(totals[1].total == 25.5)
    #expect(totals[1].count == 2)
}

@Test func daysUntilAndDailyBudget() throws {
    #expect(TrueBalance.daysUntil("2026-11-02", now: now) == 14)
    #expect(TrueBalance.daysUntil("2026-10-19", now: now) == 0)
    let s = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 1000, txns: []),
        cards: [Account(accountNumber: "c", txns: [card("2026-11-01T22:00:00Z", 300)])],
        now: now)
    #expect(TrueBalance.dailyBudget(s, now: now) == 50) // 700 over 14 days
    let broke = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 100, txns: []),
        cards: [Account(accountNumber: "c", txns: [card("2026-11-01T22:00:00Z", 300)])],
        now: now)
    #expect(TrueBalance.dailyBudget(broke, now: now) == nil)
}
