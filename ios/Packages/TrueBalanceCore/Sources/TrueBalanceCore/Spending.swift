import Foundation

/// Card spending over time, from `Snapshot.history`.
public enum Spending {
    /// Purchases made between two days (inclusive, Israel time), in ILS.
    public static func purchases(_ txns: [Txn], from start: Date, to end: Date) -> [Txn] {
        let first = Israel.day(start), last = Israel.day(end)
        return txns.filter { t in
            let day = Israel.day(t.date)
            return t.chargedCurrency == "ILS" && day >= first && day <= last
        }
    }

    public static func total(_ txns: [Txn]) -> Double {
        TrueBalance.round2(txns.reduce(0) { $0 - $1.chargedAmount })
    }

    public struct Bucket: Hashable, Identifiable, Sendable {
        /// Start of the day or month (Israel time).
        public var start: Date
        public var total: Double
        public var id: Date { start }
    }

    /// Totals per day or per month, oldest first, empty days/months included.
    public static func buckets(_ txns: [Txn], from start: Date, to end: Date, by unit: Calendar.Component) -> [Bucket] {
        let cal = Israel.calendar
        func floor(_ d: Date) -> Date {
            unit == .month ? cal.date(from: cal.dateComponents([.year, .month], from: d))! : cal.startOfDay(for: d)
        }
        var totals: [Date: Double] = [:]
        for t in txns { totals[floor(t.date), default: 0] += -t.chargedAmount }
        var out: [Bucket] = []
        var cursor = floor(start)
        let stop = floor(end)
        while cursor <= stop {
            out.append(Bucket(start: cursor, total: TrueBalance.round2(totals[cursor] ?? 0)))
            cursor = cal.date(byAdding: unit, value: 1, to: cursor)!
        }
        return out
    }

    /// Everything bought from the same merchant, newest first.
    public static func atMerchant(_ key: String, in txns: [Txn]) -> [Txn] {
        txns.filter { $0.merchantKey == key }.sorted { $0.date > $1.date }
    }
}

/// Past card purchases kept on the device, so history grows beyond what one
/// refresh downloads and refreshes only need the recent months.
public enum PurchaseCache {
    /// Cached purchases made before `refetchedFrom`, plus everything just
    /// fetched (which replaces the cached copy of those months: a pending
    /// purchase becomes completed, a cancelled one disappears). Newest first.
    public static func merge(cached: [Txn], fresh: [Txn], refetchedFrom start: Date) -> [Txn] {
        let first = Israel.day(start)
        var seen = Set<String>()
        return (fresh + cached.filter { Israel.day($0.date) < first })
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }
}
