import Foundation

// MARK: - Accounts beyond the current account

public struct CardInfo: Codable, Hashable, Identifiable, Sendable {
    public var last4: String
    public var creditLimit: Double?
    /// Credit still available ("open to buy").
    public var available: Double?
    public var id: String { last4 }

    public init(last4: String, creditLimit: Double?, available: Double?) {
        self.last4 = last4
        self.creditLimit = creditLimit
        self.available = available
    }

    public var used: Double? {
        guard let creditLimit, let available else { return nil }
        return TrueBalance.round2(creditLimit - available)
    }
}

public struct SavingsAccount: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var balance: Double
    public var id: String { name + "\(balance)" }

    public init(name: String, balance: Double) {
        self.name = name
        self.balance = balance
    }
}

public struct ForeignAccount: Codable, Hashable, Identifiable, Sendable {
    public var currency: String
    public var balance: Double
    public var id: String { currency }

    public init(currency: String, balance: Double) {
        self.currency = currency
        self.balance = balance
    }
}

public enum ExtraParsers {
    /// Max `getHomePageData` → cards with limits (`Result.UserCards.Cards`).
    public static func maxCards(_ data: Data) -> [CardInfo] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cards = (((json?["Result"] as? [String: Any])?["UserCards"] as? [String: Any])?["Cards"] as? [[String: Any]]) ?? []
        return cards.compactMap { c in
            guard let last4 = c["Last4Digits"] as? String, !last4.isEmpty else { return nil }
            return CardInfo(last4: last4, creditLimit: number(c["CreditLimit"]), available: number(c["OpenToBuy"]))
        }
    }

    /// Leumi deposits endpoint → savings (`depositsAndSavingsItems`).
    public static func leumiSavings(_ data: Data) -> [SavingsAccount] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = (json?["depositsAndSavingsItems"] as? [[String: Any]]) ?? []
        return items.compactMap { d in
            guard let balance = number(d["currentBalance"]) else { return nil }
            return SavingsAccount(name: (d["productName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "", balance: balance)
        }
    }

    /// Bank of Israel `GetExchangeRates` → shekels for one unit of each currency.
    public static func boiRates(_ data: Data) -> [String: Double] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rates = (json?["exchangeRates"] as? [[String: Any]]) ?? []
        var out: [String: Double] = [:]
        for r in rates {
            guard let key = r["key"] as? String, let rate = number(r["currentExchangeRate"]) else { continue }
            let unit = number(r["unit"]) ?? 1
            out[key] = rate / (unit == 0 ? 1 : unit)
        }
        return out
    }

    /// Leumi shows a foreign account's currency as a Hebrew label
    /// (`דולר ארה"ב`, `אירו`…). Longest label first so `דולר קנדי` isn't USD.
    public static func leumiCurrency(_ label: String) -> String? {
        let normalized = label.replacingOccurrences(of: #"["'`׳״]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        if let exact = currencyLabels[normalized] { return exact }
        return currencyLabels.keys.sorted { $0.count > $1.count }.first { normalized.contains($0) }.flatMap { currencyLabels[$0] }
    }

    static let currencyLabels: [String: String] = [
        "דולר": "USD", "דולר ארהב": "USD", "אירו": "EUR", "יורו": "EUR", "לירה שטרלינג": "GBP",
        "פרנק שוויצרי": "CHF", "יין יפני": "JPY", "דולר קנדי": "CAD", "דולר אוסטרלי": "AUD",
        "כתר שוודי": "SEK", "כתר נורווגי": "NOK", "כתר דני": "DKK", "רנד": "ZAR", "שקל": "ILS", "שח": "ILS",
    ]

    /// "1,234.50-" / "₪ 12.00" → number (0 when empty).
    public static func amount(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: "").filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned.hasSuffix("-") ? "-" + cleaned.dropLast() : cleaned) ?? 0
    }

    /// Balance of a Leumi foreign account from its activity table (date,
    /// description, reference, debit, credit, running balance): the running
    /// balance of the most recent row, whichever end of the table it is.
    public static func leumiForeignBalance(rows: [[String]], opening: String) -> Double {
        let parsed = rows.filter { $0.count >= 6 }
        guard let first = parsed.first, let last = parsed.last else { return amount(opening) }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy"
        f.timeZone = Israel.timeZone
        let firstDate = f.date(from: first[0]) ?? .distantPast, lastDate = f.date(from: last[0]) ?? .distantPast
        return amount((firstDate > lastDate ? first : last)[5])
    }

    static func number(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: d
        case let i as Int: Double(i)
        case let s as String: Double(s.replacingOccurrences(of: ",", with: ""))
        default: nil
        }
    }
}

// MARK: - Recurring money: salary, standing orders, subscriptions

public struct Recurring: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    /// Typical amount, signed (positive = money in).
    public var amount: Double
    public var lastDate: Date
    /// Next expected date (one month after the last one).
    public var nextDate: Date
    public var occurrences: Int
    public var category: String?
    public var id: String { name.lowercased() }
}

public enum RecurringDetector {
    /// Same counterparty, in at least `minMonths` different months, with amounts
    /// within `tolerance` of each other: salary, rent, subscriptions…
    public static func detect(_ txns: [Txn], minMonths: Int = 2, tolerance: Double = 0.25, now: Date = .now) -> [Recurring] {
        let cal = Israel.calendar
        let groups = Dictionary(grouping: txns.filter { $0.chargedCurrency == "ILS" && $0.chargedAmount != 0 && $0.installments == nil }) {
            "\($0.merchantKey)|\($0.chargedAmount > 0)"
        }
        var out: [Recurring] = []
        for (_, items) in groups {
            let sorted = items.sorted { $0.date < $1.date }
            let months = Set(sorted.map { cal.dateComponents([.year, .month], from: $0.date) })
            guard months.count >= minMonths, months.count >= sorted.count - 1 else { continue } // about once a month
            let amounts = sorted.map(\.chargedAmount)
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard amounts.allSatisfy({ abs($0 - mean) <= abs(mean) * tolerance }) else { continue }
            let last = sorted.last!
            // Stale: nothing for two months means it stopped.
            guard let staleLimit = cal.date(byAdding: .day, value: -62, to: now), last.date >= staleLimit else { continue }
            let recent = amounts.suffix(2)
            out.append(Recurring(
                name: last.description.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: TrueBalance.round2(recent.reduce(0, +) / Double(recent.count)),
                lastDate: last.date,
                nextDate: cal.date(byAdding: .month, value: 1, to: last.date)!,
                occurrences: sorted.count,
                category: last.category))
        }
        return out.sorted { abs($0.amount) > abs($1.amount) }
    }
}

public enum Subscriptions {
    /// Card charges that come back every month at about the same amount
    /// (Netflix, Spotify, phone…). Installment plans don't count.
    public static func detect(_ history: [Txn], now: Date = .now) -> [Recurring] {
        RecurringDetector.detect(history, minMonths: 2, tolerance: 0.1, now: now).filter { $0.amount < 0 }
    }

    /// What they cost per month, positive.
    public static func monthlyTotal(_ subs: [Recurring]) -> Double {
        TrueBalance.round2(-subs.reduce(0) { $0 + $1.amount })
    }
}

public struct Forecast: Hashable, Sendable {
    /// True balance plus expected income, minus expected bank debits, up to the debit day.
    public var projectedBalance: Double
    public var income: [Recurring]
    public var debits: [Recurring]
    public var until: String
}

public enum Forecaster {
    /// What the account should hold right after the next card debit, counting
    /// recurring bank movements expected before then.
    public static func forecast(_ s: Snapshot, now: Date = .now) -> Forecast? {
        guard let next = s.nextCharge, let bankTxns = s.bankTxns, let end = Israel.date(fromDay: next.chargeDate) else { return nil }
        let recurring = RecurringDetector.detect(bankTxns.filter { !TrueBalance.isCardDebit($0) }, now: now)
        let due = recurring.filter { $0.nextDate > now && Israel.day($0.nextDate) <= Israel.day(end) }
        let income = due.filter { $0.amount > 0 }
        let debits = due.filter { $0.amount < 0 }
        let delta = due.reduce(0) { $0 + $1.amount }
        return Forecast(projectedBalance: TrueBalance.round2(s.trueBalance + delta), income: income, debits: debits, until: next.chargeDate)
    }
}

// MARK: - Budgets and comparisons

public struct BudgetProgress: Hashable, Identifiable, Sendable {
    public var category: String
    public var limit: Double
    public var spent: Double
    public var id: String { category }
    public var ratio: Double { limit > 0 ? spent / limit : 0 }
}

extension BudgetProgress {
    /// 100 once the budget is used up, 80 when getting close, else nil.
    public var alertLevel: Int? { ratio >= 1 ? 100 : ratio >= 0.8 ? 80 : nil }
}

public enum Budgets {
    /// Card spending this calendar month (Israel) per budgeted category.
    public static func progress(limits: [String: Double], history: [Txn], now: Date = .now) -> [BudgetProgress] {
        let cal = Israel.calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let month = Spending.purchases(history, from: start, to: now)
        return limits.filter { $0.value > 0 }.map { key, limit in
            let spent = Spending.total(month.filter { ($0.category ?? Category.uncategorized) == key })
            return BudgetProgress(category: key, limit: limit, spent: spent)
        }
        .sorted { $0.ratio > $1.ratio }
    }
}

public struct MonthComparison: Hashable, Sendable {
    public var thisMonth: Double
    /// Last month over the same number of days, for a fair comparison.
    public var lastMonthSamePeriod: Double
    public var lastMonthTotal: Double
    /// Category key → this month minus last month (same period).
    public var byCategory: [String: Double]

    public var change: Double? {
        lastMonthSamePeriod > 0 ? (thisMonth - lastMonthSamePeriod) / lastMonthSamePeriod : nil
    }
}

extension Spending {
    public static func compareMonths(_ history: [Txn], now: Date = .now) -> MonthComparison {
        let cal = Israel.calendar
        let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let lastStart = cal.date(byAdding: .month, value: -1, to: thisStart)!
        let elapsed = cal.dateComponents([.day], from: thisStart, to: cal.startOfDay(for: now)).day ?? 0
        let lastSameEnd = min(cal.date(byAdding: .day, value: elapsed, to: lastStart)!, cal.date(byAdding: .second, value: -1, to: thisStart)!)
        let this = purchases(history, from: thisStart, to: now)
        let lastSame = purchases(history, from: lastStart, to: lastSameEnd)
        let lastAll = purchases(history, from: lastStart, to: cal.date(byAdding: .second, value: -1, to: thisStart)!)
        var byCategory: [String: Double] = [:]
        for t in this { byCategory[t.category ?? Category.uncategorized, default: 0] -= t.chargedAmount }
        for t in lastSame { byCategory[t.category ?? Category.uncategorized, default: 0] += t.chargedAmount }
        return MonthComparison(thisMonth: total(this), lastMonthSamePeriod: total(lastSame), lastMonthTotal: total(lastAll),
                               byCategory: byCategory.mapValues(TrueBalance.round2))
    }

    public struct CardTotal: Hashable, Identifiable, Sendable {
        /// Nil when the card company didn't say which card.
        public var last4: String?
        public var total: Double
        public var count: Int
        public var id: String { last4 ?? "" }
    }

    /// Total per card, biggest first.
    public static func byCard(_ txns: [Txn]) -> [CardTotal] {
        Dictionary(grouping: txns, by: \.cardLast4)
            .map { CardTotal(last4: $0.key, total: total($0.value), count: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    /// Purchases in `new` that weren't in `old` (for "new purchase" alerts).
    public static func newPurchases(old: [Txn], new: [Txn]) -> [Txn] {
        let known = Set(old.map(\.id))
        return new.filter { !known.contains($0.id) }
    }
}

// MARK: - Wealth

public struct Wealth: Hashable, Sendable {
    public struct Line: Hashable, Identifiable, Sendable {
        public enum Kind: String, Sendable { case current, savings, foreign, card }
        public var kind: Kind
        public var name: String
        /// In ILS (an estimate for foreign accounts).
        public var amount: Double
        /// Foreign accounts: the balance in their own currency.
        public var original: Double?
        public var currency: String?
        public var id: String { "\(kind.rawValue)|\(name)|\(currency ?? "")" }
    }

    public var lines: [Line]
    /// Foreign accounts with no known rate: listed, not counted.
    public var unconverted: [ForeignAccount]
    public var total: Double { TrueBalance.round2(lines.reduce(0) { $0 + $1.amount }) }

    /// Current account after the card debits already known, plus savings and
    /// foreign-currency accounts converted at the Bank of Israel rate.
    public static func of(_ s: Snapshot) -> Wealth {
        var lines = [Line(kind: .current, name: "Leumi", amount: s.bankBalance)]
        let cardsDue = TrueBalance.round2(s.bankBalance - s.trueBalanceAllKnown)
        if cardsDue != 0 { lines.append(Line(kind: .card, name: "Max", amount: -cardsDue)) }
        lines += (s.savings ?? []).map { Line(kind: .savings, name: $0.name, amount: $0.balance) }
        var unconverted: [ForeignAccount] = []
        for f in s.foreignAccounts ?? [] {
            if let rate = s.fxRates?[f.currency] {
                lines.append(Line(kind: .foreign, name: f.currency, amount: TrueBalance.round2(f.balance * rate),
                                  original: f.balance, currency: f.currency))
            } else {
                unconverted.append(f)
            }
        }
        return Wealth(lines: lines, unconverted: unconverted)
    }
}

// MARK: - Notes

/// What the user wrote on a purchase: free text and tags ("work", "reimbursed").
public struct PurchaseNote: Codable, Hashable, Sendable {
    public var text: String
    public var tags: [String]

    public init(text: String = "", tags: [String] = []) {
        self.text = text
        self.tags = tags
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty }
}

// MARK: - Export

public enum CSVExport {
    /// One row per purchase; amounts as spent (positive), dot decimals.
    public static func make(_ txns: [Txn], notes: [String: PurchaseNote] = [:]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        iso.timeZone = Israel.timeZone
        var lines = ["date,merchant,category,amount,currency,card,status,installment,debit_date,original_amount,original_currency,tags,note"]
        for t in txns.sorted(by: { $0.date > $1.date }) {
            let fields: [String] = [
                iso.string(from: t.date), t.description, t.category ?? "", String(format: "%.2f", -t.chargedAmount),
                t.chargedCurrency, t.cardLast4 ?? "", t.status.rawValue,
                t.installments.map { "\($0.number)/\($0.total)" } ?? "", iso.string(from: t.processedDate),
                t.originalAmount.map { String(format: "%.2f", -$0) } ?? "", t.originalCurrency ?? "",
                notes[t.id]?.tags.joined(separator: " ") ?? "", notes[t.id]?.text ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : field
    }
}

// MARK: - Bank movements

public enum BankMovement {
    public enum Kind: String, Sendable { case transferIn, transferOut, cardDebit, income, expense }

    /// "העברה מאת: BNP PARIBAS - PARIS 10-800-02" → "BNP PARIBAS - PARIS 10-800-02".
    static let counterpartyPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:העברה|העב['׳]?|זיכוי|חיוב)?\s*(?:מאת|מ-|אל|ל-|לטובת|עבור|מ|ל)\s*:\s*(.+)$"#)
    static let transferPattern = try! NSRegularExpression(pattern: #"העברה|העב['׳]|bit|ביט|paybox|פייבוקס|transfer"#, options: .caseInsensitive)

    public static func isTransfer(_ t: Txn) -> Bool {
        [t.description, t.memo ?? ""].contains { s in
            transferPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    public static func kind(_ t: Txn) -> Kind {
        if TrueBalance.isCardDebit(t) { return .cardDebit }
        if isTransfer(t) { return t.chargedAmount >= 0 ? .transferIn : .transferOut }
        return t.chargedAmount >= 0 ? .income : .expense
    }

    /// Who sent or received the money, from Leumi's detail line.
    public static func counterparty(_ t: Txn) -> String? {
        guard let memo = t.memo,
              let m = counterpartyPattern.firstMatch(in: memo, range: NSRange(memo.startIndex..., in: memo)),
              let r = Range(m.range(at: 1), in: memo) else { return nil }
        let name = memo[r].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Money in and out over a list of movements (positive numbers).
    public static func totals(_ txns: [Txn]) -> (in: Double, out: Double) {
        (TrueBalance.round2(txns.filter { $0.chargedAmount > 0 }.reduce(0) { $0 + $1.chargedAmount }),
         TrueBalance.round2(-txns.filter { $0.chargedAmount < 0 }.reduce(0) { $0 + $1.chargedAmount }))
    }
}

/// The other side of a transfer, from Leumi's detail line. Leumi gives no more
/// than this line ("העברה מאת: NAME BANK-BRANCH-ACCOUNT"), even on its site.
public struct TransferParty: Hashable, Sendable {
    public var name: String
    public var bankCode: Int?
    public var branch: String?
    public var account: String?

    /// "BNP PARIBAS - PARIS 10-800-02" → name, bank 10, branch 800, account 02.
    public static func parse(_ text: String) -> TransferParty {
        let pattern = try! NSRegularExpression(pattern: #"^(.*?)[\s,]*(\d{1,3})-(\d{1,4})-(\d{1,13})\s*$"#)
        guard let m = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return TransferParty(name: text)
        }
        func group(_ i: Int) -> String { Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        let name = group(1).trimmingCharacters(in: CharacterSet(charactersIn: " -,"))
        return TransferParty(name: name.isEmpty ? text : name, bankCode: Int(group(2)), branch: group(3), account: group(4))
    }

    public var bankName: String? { bankCode.flatMap { IsraeliBanks.names[$0] } }
}

/// Israeli bank codes (Leumi's own list, `UC_SO_160_GetBankList`).
public enum IsraeliBanks {
    public static let names: [Int: String] = [
        1: "Isracard", 3: "Bank Esh Israel", 4: "Bank Yahav", 6: "Max It Finance", 7: "Industrial Development Bank",
        8: "Israel Shipping Bank", 9: "Israel Postal Bank", 10: "Bank Leumi", 11: "Discount Bank", 12: "Bank Hapoalim",
        13: "Union Bank", 14: "Otsar Ha-Hayal", 15: "Ofek Credit Union", 17: "Mercantile Discount", 18: "One Zero",
        20: "Mizrahi-Tefahot", 21: "Nima Shefa Israel", 22: "Citibank", 23: "HSBC", 24: "Israel American Bank", 26: "UBank",
        31: "First International Bank", 34: "Arab Israel Bank", 35: "Grow Payments", 39: "State Bank of India",
        46: "Bank Massad", 47: "Global Remit", 52: "Poalei Agudat Israel Bank", 54: "Bank of Jerusalem",
        58: "Rewire", 68: "Municipal Bank", 69: "GMT Tech Innovation", 79: "Monox (019)", 94: "Phoenix Gamma",
        99: "Bank of Israel",
    ]
}

extension BankMovement {
    /// Sender (money in) or recipient (money out), split into its parts.
    public static func party(_ t: Txn) -> TransferParty? {
        counterparty(t).map(TransferParty.parse)
    }
}
