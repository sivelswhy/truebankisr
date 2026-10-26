import Foundation

/// Bank balance minus credit card charges not yet debited.
/// Same rules as the web app's `lib/compute.ts`.
public enum TrueBalance {
    public struct MissingBalance: Error {}

    /// Leumi line for the monthly card debit, e.g. "מקס איט פיננ" / "MAX IT".
    static let cardDebitPattern = try! NSRegularExpression(pattern: "מקס|max|לאומי קארד|leumi card", options: .caseInsensitive)

    /// `fxRates` (shekels per unit) converts foreign-currency charges to an
    /// ILS estimate; charges with no known rate are reported, not subtracted.
    public static func compute(bank: Account, cards: [Account], now: Date = .now, billingDay: Int = 2,
                               fxRates: [String: Double] = [:]) throws -> Snapshot {
        guard let balance = bank.balance else { throw MissingBalance() }
        let today = Israel.day(now)

        // If the bank already shows today's card debit, that cycle is in the balance.
        let debitedToday = bank.txns.contains { Israel.day($0.date) == today && isCardDebit($0) }

        var ignoredForeign: [Txn] = []
        var byDay: [String: [Txn]] = [:]

        // Foreign charges with a known rate become ILS estimates everywhere.
        let all = cards.flatMap(\.txns).map { t in
            t.chargedCurrency == "ILS" ? t : fxRates[t.chargedCurrency].map { converted(t, rate: $0) } ?? t
        }
        for txn in all {
            if txn.chargedCurrency != "ILS" {
                ignoredForeign.append(txn)
                continue
            }
            // Pending txns have no payment date yet: they go to the next billing cycle.
            let day = txn.status == .pending ? nextBillingDay(after: today, billingDay: billingDay) : Israel.day(txn.processedDate)
            let notYetDebited = day > today || (day == today && !debitedToday)
            guard notYetDebited else { continue }
            byDay[day, default: []].append(txn)
        }

        var carried = 0.0
        let upcoming = byDay.keys.sorted().map { day in
            let txns = byDay[day]!.sorted { $0.date > $1.date }
            let net = round2(-txns.reduce(0) { $0 + $1.chargedAmount } - carried)
            carried = max(0, -net)
            return UpcomingCharge(chargeDate: day, total: max(0, net), txns: txns, credit: carried > 0 ? carried : nil)
        }
        let next = upcoming.first
        let allKnown = upcoming.reduce(0) { $0 + $1.total }

        return Snapshot(
            bankBalance: balance,
            nextCharge: next,
            trueBalance: round2(balance - (next?.total ?? 0)),
            trueBalanceAllKnown: round2(balance - allKnown),
            upcoming: upcoming,
            ignoredForeign: ignoredForeign,
            computedAt: now,
            history: all.sorted { $0.date > $1.date },
            bankTxns: bank.txns.sorted { $0.date > $1.date },
            fxRates: fxRates.isEmpty ? nil : fxRates
        )
    }

    /// Next billing day (e.g. the 2nd) after `today`, or today itself if the
    /// debit has not reached the bank account yet.
    static func nextBillingDay(after today: String, billingDay: Int) -> String {
        let p = today.split(separator: "-").compactMap { Int($0) }
        var year = p[0], month = p[1]
        if p[2] > billingDay {
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return String(format: "%04d-%02d-%02d", year, month, billingDay)
    }

    static func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

    /// The bank line for the monthly card debit.
    public static func isCardDebit(_ t: Txn) -> Bool {
        t.chargedAmount < 0
            && cardDebitPattern.firstMatch(in: t.description, range: NSRange(t.description.startIndex..., in: t.description)) != nil
    }

    /// ILS estimate of a foreign-currency charge, keeping the original amount.
    static func converted(_ t: Txn, rate: Double) -> Txn {
        var c = t
        c.originalAmount = t.chargedAmount
        c.originalCurrency = t.chargedCurrency
        c.fxEstimate = true
        c.chargedAmount = round2(t.chargedAmount * rate)
        c.chargedCurrency = "ILS"
        return c
    }

    /// Whole days from today (Israel) to a YYYY-MM-DD day; 0 on the day itself.
    public static func daysUntil(_ day: String, now: Date = .now) -> Int {
        let cal = Israel.calendar
        guard let target = Israel.date(fromDay: day), let today = Israel.date(fromDay: Israel.day(now)) else { return 0 }
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: target)).day ?? 0)
    }

    /// What can be spent per day until the next debit without going below
    /// zero once it's taken. Nil when there's nothing to spread.
    public static func dailyBudget(_ s: Snapshot, now: Date = .now) -> Double? {
        guard let next = s.nextCharge, s.trueBalance > 0 else { return nil }
        let days = daysUntil(next.chargeDate, now: now)
        guard days > 0 else { return nil }
        return round2(s.trueBalance / Double(days))
    }
}
