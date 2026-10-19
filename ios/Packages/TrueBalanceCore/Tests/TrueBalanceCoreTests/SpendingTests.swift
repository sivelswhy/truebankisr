import Foundation
import Testing
@testable import TrueBalanceCore

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

private func buy(_ date: String, _ amount: Double, _ name: String = "Shop", currency: String = "ILS") -> Txn {
    Txn(id: UUID().uuidString, date: iso(date), processedDate: iso(date), chargedAmount: -amount,
        chargedCurrency: currency, description: name)
}

@Test func purchasesBetweenDaysInclusive() {
    let txns = [buy("2026-10-01T08:00:00Z", 10), buy("2026-10-15T08:00:00Z", 20), buy("2026-10-31T23:00:00Z", 5),
                buy("2026-10-10T08:00:00Z", 99, currency: "USD")]
    // Oct 31 23:00 UTC is already Nov 1 in Israel (UTC+2).
    let got = Spending.purchases(txns, from: iso("2026-10-01T12:00:00Z"), to: iso("2026-10-31T12:00:00Z"))
    #expect(Spending.total(got) == 30)
}

@Test func dailyBucketsIncludeEmptyDays() {
    let txns = [buy("2026-10-01T08:00:00Z", 10), buy("2026-10-03T08:00:00Z", 5), buy("2026-10-03T09:00:00Z", 2.5)]
    let b = Spending.buckets(txns, from: iso("2026-10-01T12:00:00Z"), to: iso("2026-10-03T12:00:00Z"), by: .day)
    #expect(b.map(\.total) == [10, 0, 7.5])
}

@Test func merchantHistoryGroupsByName() {
    let txns = [buy("2026-09-01T08:00:00Z", 10, "  Shufersal "), buy("2026-10-01T08:00:00Z", 20, "SHUFERSAL"),
                buy("2026-10-02T08:00:00Z", 30, "Wolt")]
    let shuf = Spending.atMerchant(txns[0].merchantKey, in: txns)
    #expect(shuf.count == 2)
    #expect(shuf.first?.chargedAmount == -20) // newest first
}

@Test func computeKeepsFullHistory() throws {
    let s = try TrueBalance.compute(
        bank: Account(accountNumber: "b", balance: 100, txns: []),
        cards: [Account(accountNumber: "c", txns: [buy("2026-08-01T08:00:00Z", 10), buy("2026-10-01T08:00:00Z", 20)])],
        now: iso("2026-10-19T09:00:00Z"))
    #expect(s.upcoming.isEmpty) // both already debited
    #expect(s.history?.count == 2)
}
