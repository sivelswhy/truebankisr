import Foundation
import Security

/// A European bank reached through Enable Banking's open banking API (PSD2),
/// shown apart from Leumi and Max.
struct EuroBank: Codable, Hashable, Identifiable, Sendable {
    var name: String
    /// ISO country code: the same bank is listed once per country.
    var country: String
    /// Colour of its chip and card.
    var color: String
    /// Logo from Enable Banking's bank list.
    var logo: String?
    /// "personal" when the bank offers it, otherwise what it offers ("business").
    var psuType: String?

    init(name: String, country: String, color: String? = nil, logo: String? = nil, psuType: String? = nil) {
        self.name = name
        self.country = country
        self.color = color ?? Self.color(for: name)
        self.logo = logo
        self.psuType = psuType
    }

    var id: String { "\(country)/\(name)" }

    /// Enable Banking's logo for the bank, resized for a small chip.
    var logoURL: URL? {
        if let logo, !logo.isEmpty {
            return URL(string: logo.hasSuffix("/") ? logo + "-/resize/96x/" : logo)
        }
        let path = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://enablebanking.com/brands/\(country)/\(path)/-/resize/96x/")
    }

    /// The countries Enable Banking covers (EEA), for the country picker.
    static let countries = ["AT", "BE", "BG", "CY", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE", "IS",
                            "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO", "SE", "SI", "SK"]

    /// "🇫🇷".
    static func flag(_ country: String) -> String {
        String(country.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }.map(Character.init))
    }

    /// Brand colours for well-known banks; the others get one from a palette,
    /// always the same for a given name.
    private static let brands: [String: String] = [
        "hello bank": "#00A3E0", "revolut": "#0666EB", "n26": "#36A18B", "bnp paribas": "#00915A",
        "société générale": "#E9041E", "crédit agricole": "#009597", "boursobank": "#D4006E", "boursorama": "#D4006E",
        "lcl": "#1A3D8F", "ing": "#FF6200", "wise": "#163300", "la banque postale": "#F5A800", "bunq": "#2F9C8F",
    ]
    private static let palette = ["#0A84FF", "#30B0C7", "#34C759", "#5856D6", "#AF52DE", "#FF2D55", "#FF9500", "#A2845E"]

    static func color(for name: String) -> String {
        let key = name.lowercased()
        if let brand = brands.first(where: { key.hasPrefix($0.key) })?.value { return brand }
        // Stable across launches (String.hashValue isn't).
        let hash = key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

/// The app's key for Enable Banking: its id and the private key exported by
/// the portal (PEM).
struct EnableBankingKey: Codable, Equatable, Sendable {
    var appID: String
    var privateKeyPEM: String
}

/// An authorized session with one bank: the accounts it gave access to, until when.
struct EuroConnection: Codable, Hashable, Identifiable, Sendable {
    struct AccountRef: Codable, Hashable, Sendable {
        var uid: String
        var name: String?
        var iban: String?
        var currency: String
    }

    var bank: EuroBank
    var sessionID: String
    var accounts: [AccountRef]
    var validUntil: Date

    var id: String { bank.id }
    var isExpired: Bool { validUntil < .now }
}

struct EuroTxn: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// YYYY-MM-DD.
    var date: String
    /// Negative when money leaves the account.
    var amount: Double
    var currency: String
    var party: String?
    var details: String?
    var pending: Bool

    var title: String { party ?? details ?? String(localized: "Transaction") }
}

struct EuroAccount: Codable, Hashable, Identifiable, Sendable {
    var ref: EuroConnection.AccountRef
    var balance: Double?
    var txns: [EuroTxn]

    var id: String { ref.uid }
    var label: String { ref.name ?? ref.iban.map(EuroAccount.maskedIBAN) ?? ref.currency }

    /// "FR76 •••• 1234".
    static func maskedIBAN(_ iban: String) -> String {
        let compact = iban.replacingOccurrences(of: " ", with: "")
        guard compact.count > 8 else { return compact }
        return "\(compact.prefix(4)) •••• \(compact.suffix(4))"
    }
}

/// What was last read from one bank.
struct EuroBankData: Codable, Hashable, Identifiable, Sendable {
    var bank: EuroBank
    var accounts: [EuroAccount]
    var updatedAt: Date

    var id: String { bank.id }
    var txns: [EuroTxn] { accounts.flatMap(\.txns).sorted { $0.date > $1.date } }
}

enum EnableBankingError: Error, Equatable {
    case noKey
    case badKey(String)
    /// The bank's consent ended or was revoked: connect again.
    case expired
    /// The bank allows only a few automatic reads a day.
    case rateLimited
    /// The bank login was cancelled or refused.
    case notAuthorized(String)
    case network(String)
    case http(Int, String)

    static func from(_ error: Error) -> EnableBankingError {
        if let e = error as? EnableBankingError { return e }
        if let e = error as? URLError { return .network(e.localizedDescription) }
        return .http(0, "\(error)")
    }

    var message: String {
        switch self {
        case .noKey: String(localized: "Import your Enable Banking key first.")
        case .badKey: String(localized: "This key file can’t be read. Use the .pem file from the Enable Banking portal.")
        case .expired: String(localized: "Access has expired. Connect the bank again.")
        case .rateLimited: String(localized: "The bank limits how often it can be read. Try again later.")
        case .notAuthorized: String(localized: "The bank didn’t give access. Try connecting again.")
        case .network: String(localized: "Couldn’t reach Enable Banking. Check your connection and try again.")
        case .http(let code, _): String(localized: "Enable Banking answered with an error (\(code)).")
        }
    }

    var detail: String? {
        switch self {
        case .badKey(let d), .notAuthorized(let d), .network(let d), .http(_, let d): d
        default: nil
        }
    }
}

/// Enable Banking's API (https://enablebanking.com/docs/api/reference/).
/// Requests are signed on the phone with the app's private key: nothing goes
/// through a server of ours.
enum EnableBanking {
    static let api = URL(string: "https://api.enablebanking.com")!
    /// Enable Banking only redirects to https: this page hands the code on to
    /// truebalance://enablebanking (see docs/enablebanking.html).
    static let redirectURL = "https://sivelswhy.github.io/truebankisr/enablebanking.html"
    static let callbackHost = "enablebanking"
    /// The longest consent the banks accept (180 days).
    static let consentDays = 180

    /// Starts a bank login: returns the bank's page to open.
    static func startAuthorization(_ bank: EuroBank, state: String, key: EnableBankingKey) async throws -> URL {
        let until = Calendar.current.date(byAdding: .day, value: consentDays, to: .now)!
        let body: [String: Any] = [
            "access": ["valid_until": ISO8601DateFormatter().string(from: until)],
            "aspsp": ["name": bank.name, "country": bank.country],
            "state": state,
            "redirect_url": redirectURL,
            "psu_type": bank.psuType ?? "personal",
            "language": Locale.current.language.languageCode?.identifier ?? "en",
        ]
        let json = try await request("POST", "/auth", body: body, key: key)
        guard let url = (json["url"] as? String).flatMap(URL.init(string:)) else {
            throw EnableBankingError.http(200, "no url in /auth response")
        }
        return url
    }

    /// Turns the code from the redirect into a session with its accounts.
    static func createSession(code: String, bank: EuroBank, key: EnableBankingKey) async throws -> EuroConnection {
        let json = try await request("POST", "/sessions", body: ["code": code], key: key)
        guard let id = json["session_id"] as? String else { throw EnableBankingError.http(200, "no session_id") }
        let accounts = (json["accounts"] as? [[String: Any]] ?? []).compactMap { a -> EuroConnection.AccountRef? in
            guard let uid = a["uid"] as? String else { return nil }
            return .init(uid: uid, name: (a["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         iban: (a["account_id"] as? [String: Any])?["iban"] as? String,
                         currency: a["currency"] as? String ?? "EUR")
        }
        let until = ((json["access"] as? [String: Any])?["valid_until"] as? String).flatMap(parseDate)
            ?? Calendar.current.date(byAdding: .day, value: consentDays, to: .now)!
        return EuroConnection(bank: bank, sessionID: id, accounts: accounts, validUntil: until)
    }

    /// The banks of one country, by name.
    static func banks(country: String, key: EnableBankingKey) async throws -> [EuroBank] {
        let json = try await request("GET", "/aspsps", query: [URLQueryItem(name: "country", value: country)], key: key)
        return (json["aspsps"] as? [[String: Any]] ?? []).compactMap { a -> EuroBank? in
            guard let name = a["name"] as? String else { return nil }
            let types = a["psu_types"] as? [String] ?? []
            return EuroBank(name: name, country: a["country"] as? String ?? country, logo: a["logo"] as? String,
                            psuType: types.contains("personal") ? "personal" : types.first)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func deleteSession(_ id: String, key: EnableBankingKey) async {
        _ = try? await request("DELETE", "/sessions/\(id)", key: key)
    }

    /// Balances and the last 90 days of transactions of every account.
    static func fetch(_ connection: EuroConnection, key: EnableBankingKey) async throws -> EuroBankData {
        if connection.isExpired { throw EnableBankingError.expired }
        var accounts: [EuroAccount] = []
        for ref in connection.accounts {
            let balances = try await request("GET", "/accounts/\(ref.uid)/balances", key: key)
            let txns = try await transactions(ref, key: key)
            accounts.append(EuroAccount(ref: ref, balance: balance(balances), txns: txns))
        }
        return EuroBankData(bank: connection.bank, accounts: accounts, updatedAt: .now)
    }

    private static func transactions(_ ref: EuroConnection.AccountRef, key: EnableBankingKey) async throws -> [EuroTxn] {
        let from = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        var query = [URLQueryItem(name: "date_from", value: f.string(from: from))]
        var out: [EuroTxn] = []
        for _ in 0..<10 { // pages
            let json = try await request("GET", "/accounts/\(ref.uid)/transactions", query: query, key: key)
            out += (json["transactions"] as? [[String: Any]] ?? []).compactMap { txn($0, currency: ref.currency) }
            guard let next = json["continuation_key"] as? String, !next.isEmpty else { break }
            query = [query[0], URLQueryItem(name: "continuation_key", value: next)]
        }
        return out.sorted { $0.date > $1.date }
    }

    // MARK: Parsing

    /// Available balance first, then booked, as the banks name them.
    static func balance(_ json: [String: Any]) -> Double? {
        let balances = json["balances"] as? [[String: Any]] ?? []
        for type in ["ITAV", "CLAV", "ITBD", "CLBD", "XPCD", "OPAV", "OPBD", "OTHR", "INFO"] {
            if let b = balances.first(where: { $0["balance_type"] as? String == type }),
               let amount = number((b["balance_amount"] as? [String: Any])?["amount"]) {
                return amount
            }
        }
        return balances.first.flatMap { number(($0["balance_amount"] as? [String: Any])?["amount"]) }
    }

    static func txn(_ t: [String: Any], currency: String) -> EuroTxn? {
        let money = t["transaction_amount"] as? [String: Any]
        guard let amount = number(money?["amount"]) else { return nil }
        let debit = t["credit_debit_indicator"] as? String == "DBIT"
        guard let date = ["booking_date", "value_date", "transaction_date"].lazy.compactMap({ t[$0] as? String }).first else { return nil }
        let other = (t[debit ? "creditor" : "debtor"] as? [String: Any])?["name"] as? String
        let details = (t["remittance_information"] as? [String])?.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let signed = debit ? -abs(amount) : abs(amount)
        let id = (t["entry_reference"] as? String) ?? (t["transaction_id"] as? String)
            ?? "\(date)|\(signed)|\(other ?? details ?? "")"
        return EuroTxn(id: id, date: String(date.prefix(10)), amount: signed,
                       currency: money?["currency"] as? String ?? currency,
                       party: other.flatMap { $0.isEmpty ? nil : $0 },
                       details: details.flatMap { $0.isEmpty ? nil : $0 },
                       pending: t["status"] as? String == "PDNG")
    }

    private static func number(_ v: Any?) -> Double? {
        if let s = v as? String { return Double(s) }
        return (v as? NSNumber)?.doubleValue
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: HTTP

    private static func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil,
                                key: EnableBankingKey) async throws -> [String: Any] {
        var url = URLComponents(url: api.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query }
        var r = URLRequest(url: url.url!, timeoutInterval: 30)
        r.httpMethod = method
        r.setValue("Bearer \(try JWT.token(key))", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            let code = json["error"] as? String ?? json["code"] as? String ?? ""
            if status == 429 || code.contains("RATE_LIMIT") { throw EnableBankingError.rateLimited }
            if code.contains("EXPIRED") || code.contains("REVOKED") || code.contains("CLOSED") || code == "SESSION_DOES_NOT_EXIST" {
                throw EnableBankingError.expired
            }
            throw EnableBankingError.http(status, String(text.prefix(300)))
        }
        return json
    }
}

/// RS256 tokens for Enable Banking: kid = app id, valid one hour.
enum JWT {
    static func token(_ key: EnableBankingKey, now: Date = .now) throws -> String {
        let header = ["typ": "JWT", "alg": "RS256", "kid": key.appID]
        let iat = Int(now.timeIntervalSince1970)
        let payload: [String: Any] = ["iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": iat, "exp": iat + 3600]
        let signingInput = [header as [String: Any], payload]
            .map { base64URL(try! JSONSerialization.data(withJSONObject: $0, options: .sortedKeys)) }
            .joined(separator: ".")
        let secKey = try privateKey(key.privateKeyPEM)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(signingInput.utf8) as CFData, &error) as Data? else {
            throw EnableBankingError.badKey(error.map { "\($0.takeRetainedValue())" } ?? "signing failed")
        }
        return signingInput + "." + base64URL(signature)
    }

    /// Accepts PKCS#8 ("BEGIN PRIVATE KEY", what the portal exports) or
    /// PKCS#1 ("BEGIN RSA PRIVATE KEY").
    static func privateKey(_ pem: String) throws -> SecKey {
        let base64 = pem.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard var der = Data(base64Encoded: base64) else { throw EnableBankingError.badKey("not PEM") }
        if !pem.contains("BEGIN RSA PRIVATE KEY") {
            guard let inner = DER.pkcs8Payload(der) else { throw EnableBankingError.badKey("not a PKCS#8 RSA key") }
            der = inner
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw EnableBankingError.badKey(error.map { "\($0.takeRetainedValue())" } ?? "invalid key")
        }
        return key
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Just enough DER to unwrap a PKCS#8 key: SEQUENCE { version, algorithm, OCTET STRING key }.
enum DER {
    static func pkcs8Payload(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var i = 0
        guard let outer = element(bytes, &i), outer.tag == 0x30 else { return nil }
        var j = outer.start
        guard let version = element(bytes, &j), version.tag == 0x02,
              let algorithm = element(bytes, &j), algorithm.tag == 0x30,
              let key = element(bytes, &j), key.tag == 0x04 else { return nil }
        return Data(bytes[key.start..<key.end])
    }

    /// Reads the tag and length at `i`, moves `i` past the element.
    private static func element(_ b: [UInt8], _ i: inout Int) -> (tag: UInt8, start: Int, end: Int)? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]
        var length = Int(b[i + 1])
        var start = i + 2
        if length & 0x80 != 0 {
            let n = length & 0x7F
            guard n > 0, n <= 4, start + n <= b.count else { return nil }
            length = b[start..<start + n].reduce(0) { $0 << 8 | Int($1) }
            start += n
        }
        let end = start + length
        guard end <= b.count else { return nil }
        i = end
        return (tag, start, end)
    }
}
