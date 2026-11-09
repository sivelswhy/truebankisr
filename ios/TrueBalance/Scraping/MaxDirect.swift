import Foundation
import TrueBalanceCore

/// Max without a browser: the same HTTP calls the site's own pages make
/// (found with reverse-api-engineer). About 5× faster than `MaxScraper`'s
/// WebView. Anything unexpected throws `.fallback`, and the caller then uses
/// the WebView; an explicit login refusal is never retried (no second bad
/// attempt on the account).
@MainActor
enum MaxDirect {
    enum Failure: Error {
        /// Use the WebView instead.
        case fallback(String)
        /// Final answer, do not retry.
        case bank(BankError)
    }

    private static let base = "https://www.max.co.il"
    /// Site build the calls were captured on; Max ignores it today.
    private static let version = "V4.224-RC.10.260"

    static func scrape(_ credentials: Credentials, monthsBack: Int, monthsAhead: Int) async throws -> MaxData {
        let session = makeSession()
        do {
            try await login(session, credentials)
            let home = try? await get(session, "\(base)/api/registered/getHomePageData")
            let homeData = home?.status == 200 ? home?.body : nil
            var txns: [Txn] = []
            for month in MaxScraper.months(back: monthsBack, ahead: monthsAhead) {
                let (status, body) = try await get(session, transactionsURL(month))
                guard status == 200 else { throw Failure.fallback("transactions HTTP \(status)") }
                let code = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["returnCode"] as? Int
                if code == 10 { continue } // no data for this month
                guard code == 0 else { throw Failure.fallback("transactions returnCode \(code.map(String.init) ?? "?")") }
                txns += try MaxParser.parseMonth(body)
            }
            return MaxData(account: Account(accountNumber: "max", txns: txns, holderName: homeData.flatMap(HolderName.fromJSON)),
                           cards: homeData.map(ExtraParsers.maxCards) ?? [])
        } catch let e as Failure {
            throw e
        } catch {
            throw Failure.fallback("\(error)")
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral // own cookie jar, nothing kept
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Origin": base,
            "Referer": base + "/",
        ]
        return URLSession(configuration: config)
    }

    private static func get(_ session: URLSession, _ url: String) async throws -> (status: Int, body: Data) {
        let (data, response) = try await session.data(from: URL(string: url)!)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private static func login(_ session: URLSession, _ c: Credentials) async throws {
        var request = URLRequest(url: URL(string: "\(base)/api/login/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": c.username, "password": c.password, "id": NSNull()])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.fallback("login HTTP \(status)") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.fallback("login: not JSON")
        }
        let returnCode = json["ReturnCode"] as? Int
        let loginStatus = (json["Result"] as? [String: Any])?["LoginStatus"] as? Int
        if returnCode == 0, loginStatus == 0 { return }
        // Max answered and said no: do not try the same credentials again.
        throw Failure.bank(.unavailable("Max login refused (ReturnCode \(returnCode.map(String.init) ?? "?"), LoginStatus \(loginStatus.map(String.init) ?? "?"))"))
    }

    private static func transactionsURL(_ month: Date) -> String {
        let c = Israel.calendar.dateComponents([.year, .month], from: month)
        let filter = #"{"userIndex":-1,"cardIndex":-1,"monthView":true,"date":"\#(c.year!)-\#(c.month!)-01","dates":{"startDate":"0","endDate":"0"},"bankAccount":{"bankAccountIndex":-1,"cards":null}}"#
        var url = URLComponents(string: "\(base)/api/registered/transactionDetails/getTransactionsAndGraphs")!
        url.queryItems = [
            URLQueryItem(name: "filterData", value: filter),
            URLQueryItem(name: "firstCallCardIndex", value: "-1null"),
            URLQueryItem(name: "v", value: version),
        ]
        return url.url!.absoluteString
    }
}
