import Foundation

public enum TxnStatus: String, Codable, Sendable {
    case completed, pending
}

public struct Installments: Codable, Hashable, Sendable {
    public var number: Int
    public var total: Int

    public init(number: Int, total: Int) {
        self.number = number
        self.total = total
    }
}

public struct Txn: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Purchase date.
    public var date: Date
    /// For card transactions: the day it is debited from the bank account.
    public var processedDate: Date
    /// Negative = expense, in `chargedCurrency`.
    public var chargedAmount: Double
    public var chargedCurrency: String
    public var description: String
    public var status: TxnStatus
    public var installments: Installments?
    /// Stable category key (see `Category`), nil when the source has none.
    public var category: String?

    public init(
        id: String, date: Date, processedDate: Date, chargedAmount: Double, chargedCurrency: String = "ILS",
        description: String, status: TxnStatus = .completed, installments: Installments? = nil, category: String? = nil
    ) {
        self.id = id
        self.date = date
        self.processedDate = processedDate
        self.chargedAmount = chargedAmount
        self.chargedCurrency = chargedCurrency
        self.description = description
        self.status = status
        self.installments = installments
        self.category = category
    }
}

public struct Account: Codable, Hashable, Sendable {
    public var accountNumber: String
    public var balance: Double?
    public var txns: [Txn]

    public init(accountNumber: String, balance: Double? = nil, txns: [Txn]) {
        self.accountNumber = accountNumber
        self.balance = balance
        self.txns = txns
    }
}

public struct UpcomingCharge: Codable, Hashable, Identifiable, Sendable {
    /// YYYY-MM-DD, Israel time.
    public var chargeDate: String
    /// Positive amount in ILS that will leave the bank account.
    public var total: Double
    public var txns: [Txn]

    public var id: String { chargeDate }
}

public struct Snapshot: Codable, Hashable, Sendable {
    public var bankBalance: Double
    public var nextCharge: UpcomingCharge?
    /// Bank balance minus the next card debit only.
    public var trueBalance: Double
    /// Bank balance minus every card charge already known (incl. future installments).
    public var trueBalanceAllKnown: Double
    public var upcoming: [UpcomingCharge]
    /// Card transactions not in ILS: shown but not subtracted.
    public var ignoredForeign: [Txn]
    public var computedAt: Date
}

public enum Israel {
    public static let timeZone = TimeZone(identifier: "Asia/Jerusalem")!

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// YYYY-MM-DD of an instant, as seen in Israel.
    public static func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Noon in Israel on a YYYY-MM-DD day, for display.
    public static func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
