import Foundation

// MARK: - The user's say on subscriptions

/// A subscription typed in by hand (not seen in the card history).
public struct ManualSubscription: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Positive, in ILS, per month.
    public var amount: Double
    /// Day of the month it is charged, 1...31 (short months use their last day).
    public var dayOfMonth: Int

    public init(id: String = UUID().uuidString, name: String, amount: Double, dayOfMonth: Int) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
    }
}

/// What the user decided, on top of what the history shows.
public struct SubscriptionSettings: Codable, Hashable, Sendable {
    /// Merchant keys (`Txn.merchantKey`) the user flagged as subscriptions.
    public var marked: Set<String> = []
    /// Merchant keys the user says are not subscriptions, although they look like one.
    public var dismissed: Set<String> = []
    public var manual: [ManualSubscription] = []

    public init(marked: Set<String> = [], dismissed: Set<String> = [], manual: [ManualSubscription] = []) {
        self.marked = marked
        self.dismissed = dismissed
        self.manual = manual
    }
}

public struct Subscription: Hashable, Identifiable, Sendable {
    public enum Source: String, Sendable {
        /// Found in the history: same merchant, about the same amount, every month.
        case detected
        /// A merchant the user flagged from a purchase.
        case marked
        case manual
    }

    public var source: Source
    /// Merchant key, or the manual entry's id.
    public var key: String
    /// Amount is negative (money out), like every card charge.
    public var recurring: Recurring
    public var id: String { key }
}

extension Subscriptions {
    /// Detected subscriptions minus the dismissed ones, plus the flagged
    /// merchants and the manual entries. Biggest first.
    public static func resolve(history: [Txn], settings: SubscriptionSettings, now: Date = .now) -> [Subscription] {
        let cal = Israel.calendar
        let today = cal.startOfDay(for: now)
        var out: [Subscription] = []

        for r in detect(history, now: now) where !settings.dismissed.contains(r.id) {
            out.append(Subscription(source: settings.marked.contains(r.id) ? .marked : .detected, key: r.id, recurring: r))
        }
        let known = Set(out.map(\.key))

        for key in settings.marked where !known.contains(key) {
            let charges = history
                .filter { $0.merchantKey == key && $0.chargedCurrency == "ILS" && $0.chargedAmount < 0 && $0.installments == nil }
                .sorted { $0.date < $1.date }
            guard let last = charges.last else { continue }
            // Same day next month, rolled forward if that is already past.
            var next = cal.date(byAdding: .month, value: 1, to: last.date)!
            var guardrail = 0
            while next < today, guardrail < 36 {
                next = cal.date(byAdding: .month, value: 1, to: next)!
                guardrail += 1
            }
            out.append(Subscription(source: .marked, key: key, recurring: Recurring(
                name: last.description.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: last.chargedAmount, lastDate: last.date, nextDate: next,
                occurrences: charges.count, category: last.category)))
        }

        for m in settings.manual {
            let next = nextOccurrence(dayOfMonth: m.dayOfMonth, from: today)
            out.append(Subscription(source: .manual, key: m.id, recurring: Recurring(
                name: m.name, amount: -abs(m.amount),
                lastDate: cal.date(byAdding: .month, value: -1, to: next)!, nextDate: next,
                occurrences: 0, category: nil)))
        }
        return out.sorted { abs($0.recurring.amount) > abs($1.recurring.amount) }
    }

    /// The first date on or after `from` that falls on `dayOfMonth` (Israel time).
    static func nextOccurrence(dayOfMonth: Int, from: Date) -> Date {
        let cal = Israel.calendar
        for offset in 0...2 {
            let month = cal.date(byAdding: .month, value: offset, to: from)!
            let days = cal.range(of: .day, in: .month, for: month)!.count
            var c = cal.dateComponents([.year, .month], from: month)
            c.day = min(dayOfMonth, days)
            let candidate = cal.date(from: c)!
            if candidate >= from { return candidate }
        }
        return from
    }

    /// Subscriptions that should be charged between today and the next card
    /// debit, so they will be part of it. Ones already in that debit are left out.
    public static func dueBeforeNextDebit(_ subs: [Subscription], nextCharge: UpcomingCharge?, now: Date = .now) -> [Subscription] {
        guard let nextCharge else { return [] }
        let today = Israel.day(now)
        let alreadyIn = Set((nextCharge.txns).map(\.merchantKey))
        return subs.filter { s in
            let day = Israel.day(s.recurring.nextDate)
            return day >= today && day < nextCharge.chargeDate && !alreadyIn.contains(s.key)
        }
        .sorted { $0.recurring.nextDate < $1.recurring.nextDate }
    }

    /// Positive total of the given subscriptions.
    public static func total(_ subs: [Subscription]) -> Double {
        TrueBalance.round2(-subs.reduce(0) { $0 + $1.recurring.amount })
    }
}
