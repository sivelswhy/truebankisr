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

    static func currency(_ id: Int?) -> String {
        switch id {
        case 840: "USD"
        case 978: "EUR"
        case 376, nil: "ILS"
        default: "\(id!)"
        }
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
        var Description: String?
        var Amount: FlexibleNumber?
        var ReferenceNumberLong: FlexibleNumber?
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
        return Txn(
            id: raw.ReferenceNumberLong?.value.map { String(Int64($0)) } ?? UUID().uuidString,
            date: date,
            processedDate: date,
            chargedAmount: raw.Amount?.value ?? 0,
            description: raw.Description ?? "",
            status: status
        )
    }
}
