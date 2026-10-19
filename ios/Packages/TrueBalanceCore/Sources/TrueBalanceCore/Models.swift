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
    /// Last 4 digits of the card it was paid with.
    public var cardLast4: String?
    /// Merchant logo, when the card company provides one.
    public var logoURL: String?
    /// Merchant address or city, when the card company provides one.
    public var merchantAddress: String?
    /// For a foreign-currency charge converted to ILS: the original amount
    /// (negative = expense) and currency. The ILS amount is then an estimate.
    public var originalAmount: Double?
    public var originalCurrency: String?
    /// Bank movements: Leumi's detail line (e.g. "העברה מאת: …"), the balance
    /// right after the movement, and the value date when it differs.
    public var memo: String?
    public var runningBalance: Double?
    public var valueDate: Date?

    public var isConvertedEstimate: Bool { originalCurrency != nil && originalCurrency != chargedCurrency }

    /// Groups purchases from the same merchant ("  SHUFERSAL " = "shufersal").
    public var merchantKey: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(
        id: String, date: Date, processedDate: Date, chargedAmount: Double, chargedCurrency: String = "ILS",
        description: String, status: TxnStatus = .completed, installments: Installments? = nil, category: String? = nil,
        cardLast4: String? = nil, logoURL: String? = nil, merchantAddress: String? = nil
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
        self.cardLast4 = cardLast4
        self.logoURL = logoURL
        self.merchantAddress = merchantAddress
    }
}

public struct Account: Codable, Hashable, Sendable {
    public var accountNumber: String
    public var balance: Double?
    public var txns: [Txn]
    /// The holder's first name, when the site shows it.
    public var holderName: String?

    public init(accountNumber: String, balance: Double? = nil, txns: [Txn], holderName: String? = nil) {
        self.accountNumber = accountNumber
        self.balance = balance
        self.txns = txns
        self.holderName = holderName
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
    /// Every card purchase fetched (debited or not), newest first, for
    /// merchant history and spending over a period. Nil in older snapshots.
    public var history: [Txn]?
    /// The holder's first name as shown by Max or Leumi, if found.
    public var holderFirstName: String?
    /// Leumi current-account movements (for salary and standing-order forecasts).
    public var bankTxns: [Txn]?
    public var cards: [CardInfo]?
    public var savings: [SavingsAccount]?
    public var foreignAccounts: [ForeignAccount]?
    /// Shekels per unit (Bank of Israel), used for the conversions above.
    public var fxRates: [String: Double]?
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
