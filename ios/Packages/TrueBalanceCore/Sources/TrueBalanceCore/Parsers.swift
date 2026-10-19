import Foundation

public struct ParseError: Error, CustomStringConvertible {
    public var description: String
}

/// A number the API sends either as JSON number or as text ("1,234.50").
struct FlexibleNumber: Decodable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = nil
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}

/// Dates from Max/Leumi come as "2026-10-05T00:00:00" (Israel local time) or
/// with an explicit offset / "Z".
enum DateParser {
    static func parse(_ string: String?) -> Date? {
        guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            iso.formatOptions = options
            if let d = iso.date(from: s) { return d }
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = Israel.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let d = local.date(from: s) { return d }
        }
        return nil
    }
}

/// Max `getTransactionsAndGraphs` response → transactions.
/// Port of the mapping in israeli-bank-scrapers' `max.ts`.
public enum MaxParser {
    struct Response: Decodable {
        struct Result: Decodable { var transactions: [Raw]? }
        var result: Result?
    }

    struct Raw: Decodable {
        struct DealData: Decodable { var arn: String? }
        var shortCardNumber: String?
        var paymentDate: String?
        var purchaseDate: String?
        var originalAmount: FlexibleNumber?
        var originalCurrency: String?
        var actualPaymentAmount: FlexibleNumber?
        var paymentCurrency: FlexibleNumber?
        var merchantName: String?
        var comments: String?
        var planName: String?
        var categoryId: FlexibleNumber?
        var dealData: DealData?
    }

    public static func parseMonth(_ data: Data) throws -> [Txn] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let raws = response.result?.transactions ?? []
        let extras = undocumentedFields(data, count: raws.count)
        return zip(raws, extras)
            // Rows without a plan are summary rows, not purchases.
            .filter { raw, _ in !(raw.planName ?? "").isEmpty }
            .compactMap { raw, extra in
                var txn = map(raw)
                txn?.logoURL = extra.logo
                txn?.merchantAddress = extra.address
                return txn
            }
    }

    /// Max doesn't document a logo or address field; pick them up if they show
    /// up: an http(s) value under a key mentioning "logo"/"image", and text
    /// under keys mentioning "address" or "city".
    static func undocumentedFields(_ data: Data, count: Int) -> [(logo: String?, address: String?)] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = ((json?["result"] as? [String: Any])?["transactions"] as? [[String: Any]]) ?? []
        let found = rows.map { row -> (logo: String?, address: String?) in
            func text(_ keys: [String], url: Bool) -> [String] {
                row.compactMap { key, value in
                    let k = key.lowercased()
                    guard keys.contains(where: k.contains), let v = (value as? String)?.trimmingCharacters(in: .whitespaces),
                          !v.isEmpty, v.hasPrefix("http") == url else { return nil }
                    return v
                }
            }
            let logo = text(["logo", "image"], url: true).first
            // Street first, then city, e.g. "Dizengoff 50, Tel Aviv".
            let parts = text(["address"], url: false) + text(["city"], url: false)
            return (logo, parts.isEmpty ? nil : parts.joined(separator: ", "))
        }
        return found.count == count ? found : Array(repeating: (nil, nil), count: count)
    }

    static func map(_ raw: Raw) -> Txn? {
        guard let purchase = DateParser.parse(raw.purchaseDate) else { return nil }
        let payment = DateParser.parse(raw.paymentDate)
        let installments = installmentsInfo(raw.comments)
        // Pending purchases have no charged amount until Max processes them;
        // the real amount is the original one.
        let actual = raw.actualPaymentAmount?.value ?? 0
        let original = raw.originalAmount?.value
        let pendingWithoutAmount = payment == nil && actual == 0 && original != nil
        let amount = pendingWithoutAmount ? original! : actual
        let currencyCode = pendingWithoutAmount ? (raw.originalCurrency ?? "ILS") : currency(raw.paymentCurrency?.value.map { Int($0) })
        let arn = raw.dealData?.arn ?? "\(raw.merchantName ?? "")-\(raw.purchaseDate ?? "")-\(actual)"
        return Txn(
            id: installments.map { "\(arn)_\($0.number)" } ?? arn,
            date: purchase,
            processedDate: payment ?? purchase,
            chargedAmount: -amount,
            chargedCurrency: currencyCode,
            description: (raw.merchantName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            status: payment == nil ? .pending : .completed,
            installments: installments,
            category: Category.key(forMaxId: raw.categoryId?.value.map { Int($0) }),
            cardLast4: raw.shortCardNumber.flatMap { $0.isEmpty ? nil : String($0.suffix(4)) }
        )
    }

    /// "תשלום 2 מתוך 3" → 2 of 3.
    static func installmentsInfo(_ comments: String?) -> Installments? {
        guard let comments else { return nil }
        let numbers = comments.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return Installments(number: numbers[0], total: numbers[1])
    }

    /// ISO 4217 numeric → letter code (the ones Bank of Israel publishes).
    static let currencies: [Int: String] = [
        840: "USD", 978: "EUR", 826: "GBP", 756: "CHF", 392: "JPY", 124: "CAD", 36: "AUD",
        752: "SEK", 578: "NOK", 208: "DKK", 710: "ZAR", 400: "JOD", 818: "EGP", 422: "LBP",
    ]

    static func currency(_ id: Int?) -> String {
        guard let id, id != 376 else { return "ILS" }
        return currencies[id] ?? "\(id)"
    }
}

/// Leumi `UC_SO_27_GetBusinessAccountTrx` response → account with balance.
/// Port of the mapping in israeli-bank-scrapers' `leumi.ts`.
public enum LeumiParser {
    struct Envelope: Decodable { var jsonResp: String }

    struct Inner: Decodable {
        var BalanceDisplay: FlexibleNumber?
        var TodayTransactionsItems: [Raw]?
        var HistoryTransactionsItems: [Raw]?
    }

    struct Raw: Decodable {
        var DateUTC: String?
        var EffectiveDateUTC: String?
        var Description: String?
        var Amount: FlexibleNumber?
        var RunningBalance: FlexibleNumber?
        var ReferenceNumberLong: FlexibleNumber?
        var FITID: String?
        var AdditionalData: String?
    }

    public static func parse(_ data: Data, accountNumber: String) throws -> Account {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let inner = try JSONDecoder().decode(Inner.self, from: Data(envelope.jsonResp.utf8))
        guard let balance = inner.BalanceDisplay?.value else {
            throw ParseError(description: "Leumi response has no balance")
        }
        let txns = (inner.TodayTransactionsItems ?? []).compactMap { map($0, .pending) }
            + (inner.HistoryTransactionsItems ?? []).compactMap { map($0, .completed) }
        return Account(accountNumber: accountNumber, balance: balance, txns: txns)
    }

    static func map(_ raw: Raw, _ status: TxnStatus) -> Txn? {
        guard let date = DateParser.parse(raw.DateUTC) else { return nil }
        var txn = Txn(
            id: raw.FITID.flatMap { $0.isEmpty ? nil : $0 }
                ?? raw.ReferenceNumberLong?.value.map { String(Int64($0)) } ?? UUID().uuidString,
            date: date,
            processedDate: date,
            chargedAmount: raw.Amount?.value ?? 0,
            description: (raw.Description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            status: status
        )
        let memo = raw.AdditionalData?.trimmingCharacters(in: .whitespacesAndNewlines)
        txn.memo = memo?.isEmpty == false ? memo : nil
        txn.runningBalance = raw.RunningBalance?.value
        txn.valueDate = DateParser.parse(raw.EffectiveDateUTC).flatMap { Israel.day($0) == Israel.day(date) ? nil : $0 }
        return txn
    }
}

/// The account holder's first name, from whatever the sites show. Neither site
/// documents it, so this looks for likely fields and greetings.
public enum HolderName {
    /// First string under a key like "FirstName" anywhere in a JSON document.
    public static func fromJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let preferred = ["firstname", "first_name", "privatename", "givenname"]
        func search(_ value: Any) -> String? {
            if let dict = value as? [String: Any] {
                for (key, v) in dict where preferred.contains(key.lowercased()) {
                    if let name = clean(v as? String) { return name }
                }
                for v in dict.values { if let found = search(v) { return found } }
            } else if let array = value as? [Any] {
                for v in array { if let found = search(v) { return found } }
            }
            return nil
        }
        return search(json)
    }

    /// "שלום נחמיה" / "שלום, Dana" / "Hello Dana" in a page's text.
    public static func fromGreeting(_ text: String) -> String? {
        let pattern = #"(?:שלום|hello|hi)[,\s]+([\p{L}][\p{L}'\-]{1,20})"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return clean(String(text[r]))
    }

    /// Text of an element showing the name (e.g. Leumi's header): first word.
    public static func fromElementText(_ text: String?) -> String? {
        clean(text?.replacingOccurrences(of: ",", with: " "))
    }

    /// Capitalised first word; nil for empty or placeholder values.
    static func clean(_ raw: String?) -> String? {
        guard let word = raw?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first,
              word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return nil }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}
