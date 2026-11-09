import Testing
import Foundation
@testable import TrueBalanceCore

@Suite struct SubscriptionListTests {
    static func date(_ s: String) -> Date { Israel.date(fromDay: s)! }

    static func charge(_ name: String, _ day: String, _ amount: Double) -> Txn {
        Txn(id: "\(name)-\(day)", date: date(day), processedDate: date(day), chargedAmount: amount, description: name)
    }

    let now = date("2026-11-10")

    @Test func detectedAppearsAndDismissedDisappears() {
        let history = [Self.charge("Netflix", "2026-09-05", -50), Self.charge("Netflix", "2026-10-05", -50)]
        #expect(Subscriptions.resolve(history: history, settings: .init(), now: now).map(\.source) == [.detected])
        let dismissed = SubscriptionSettings(dismissed: ["netflix"])
        #expect(Subscriptions.resolve(history: history, settings: dismissed, now: now).isEmpty)
    }

    @Test func markedMerchantWithOneChargeOnly() {
        let history = [Self.charge("Gym", "2026-10-20", -200)]
        let subs = Subscriptions.resolve(history: history, settings: .init(marked: ["gym"]), now: now)
        #expect(subs.count == 1)
        #expect(subs[0].source == .marked)
        #expect(subs[0].recurring.amount == -200)
        #expect(Israel.day(subs[0].recurring.nextDate) == "2026-11-20")
    }

    @Test func markedNextDateNeverInThePast() {
        let history = [Self.charge("Gym", "2026-08-03", -200)]
        let subs = Subscriptions.resolve(history: history, settings: .init(marked: ["gym"]), now: now)
        #expect(Israel.day(subs[0].recurring.nextDate) == "2026-12-03")
    }

    @Test func manualUsesNextOccurrenceAndShortMonths() {
        let m = ManualSubscription(name: "Rent share", amount: 90, dayOfMonth: 31)
        let subs = Subscriptions.resolve(history: [], settings: .init(manual: [m]), now: Self.date("2026-11-10"))
        #expect(Israel.day(subs[0].recurring.nextDate) == "2026-11-30")
        #expect(subs[0].recurring.amount == -90)
    }

    @Test func dueBeforeNextDebitKeepsOnlyWhatFallsInTheCycle() {
        let inCycle = ManualSubscription(name: "A", amount: 10, dayOfMonth: 15)
        let after = ManualSubscription(name: "B", amount: 20, dayOfMonth: 3) // Dec 3, after the Dec 2 debit
        let subs = Subscriptions.resolve(history: [], settings: .init(manual: [inCycle, after]), now: now)
        let next = UpcomingCharge(chargeDate: "2026-12-02", total: 100, txns: [])
        let due = Subscriptions.dueBeforeNextDebit(subs, nextCharge: next, now: now)
        #expect(due.map(\.recurring.name) == ["A"])
        #expect(Subscriptions.total(due) == 10)
    }

    @Test func alreadyChargedThisCycleIsNotCountedTwice() {
        let history = [Self.charge("Netflix", "2026-09-05", -50), Self.charge("Netflix", "2026-10-05", -50)]
        let subs = Subscriptions.resolve(history: history, settings: .init(), now: Self.date("2026-10-20"))
        let already = UpcomingCharge(chargeDate: "2026-11-02", total: 50, txns: [Self.charge("Netflix", "2026-10-05", -50)])
        #expect(Subscriptions.dueBeforeNextDebit(subs, nextCharge: already, now: Self.date("2026-10-20")).isEmpty)
    }
}
