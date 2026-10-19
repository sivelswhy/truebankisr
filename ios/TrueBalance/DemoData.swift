import Foundation
import TrueBalanceCore

/// Sample data to try the app without bank credentials.
enum DemoData {
    static func snapshot(now: Date = .now) -> Snapshot {
        let cal = Israel.calendar
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        func billing(_ offset: Int) -> Date { cal.date(byAdding: DateComponents(month: offset, day: 1, hour: 6), to: monthStart)! }
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        func t(_ days: Double, _ amount: Double, _ name: String, _ category: String, month: Int = 1,
               installments: Installments? = nil, status: TxnStatus = .completed) -> Txn {
            Txn(id: "\(name)-\(month)", date: ago(days), processedDate: status == .pending ? ago(days) : billing(month),
                chargedAmount: -amount, description: name, status: status, installments: installments, category: category)
        }

        let main = "4580", second = "1127"
        func with(_ t: Txn, card: String) -> Txn { var t = t; t.cardLast4 = card; return t }
        var txns = [
            with(t(14, 412.9, "Shufersal Deal", "groceries"), card: main),
            with(t(11, 89, "Paz Yellow", "energy"), card: main),
            with(t(9, 249.9, "IKEA Rishon", "home", installments: .init(number: 1, total: 3)), card: main),
            with(t(9, 249.9, "IKEA Rishon", "home", month: 2, installments: .init(number: 2, total: 3)), card: main),
            with(t(9, 249.9, "IKEA Rishon", "home", month: 3, installments: .init(number: 3, total: 3)), card: main),
            with(t(6, 54, "Aroma Espresso Bar", "restaurants"), card: second),
            with(t(3, 119.9, "Partner Communications", "telecom"), card: main),
            with(t(2, 64, "Super-Pharm", "health"), card: second),
            with(t(0, 38.5, "Rami Levy", "groceries", status: .pending), card: main),
        ]
        // Past months, already debited: history for the profile and merchant pages.
        let past: [(String, String, Double)] = [
            ("Shufersal Deal", "groceries", 380), ("Aroma Espresso Bar", "restaurants", 42), ("Paz Yellow", "energy", 95),
            ("Rami Levy", "groceries", 210), ("Partner Communications", "telecom", 119.9), ("Wolt", "restaurants", 86),
        ]
        // Subscriptions: same amount every month (Netflix is billed in dollars).
        for month in 0...5 {
            let netflix = Txn(id: "netflix-\(month)", date: ago(Double(month * 30 + 5)), processedDate: billing(-month + 1),
                              chargedAmount: -15.49, chargedCurrency: "USD", description: "NETFLIX.COM", category: "leisure")
            let spotify = Txn(id: "spotify-\(month)", date: ago(Double(month * 30 + 8)), processedDate: billing(-month + 1),
                              chargedAmount: -19.9, description: "Spotify", category: "leisure")
            txns += [with(netflix, card: main), with(spotify, card: second)]
        }
        for month in 1...5 {
            for (i, p) in past.enumerated() {
                let days = Double(month * 30 + i * 4 + 3)
                txns.append(with(Txn(id: "\(p.0)-past-\(month)-\(i)", date: ago(days), processedDate: billing(-month + 1),
                                     chargedAmount: -(p.2 + Double((month * 7 + i * 3) % 25)), description: p.0, category: p.1),
                                 card: i.isMultiple(of: 3) ? second : main))
            }
        }
        // Leumi: salary and standing orders, for the forecast.
        var bank: [Txn] = []
        for month in 1...3 {
            let back = Double((month - 1) * 30)
            bank += [
                Txn(id: "salary-\(month)", date: ago(24 + back), processedDate: ago(24 + back), chargedAmount: 11_800 + Double(month * 50), description: "משכורת"),
                Txn(id: "rent-\(month)", date: ago(18 + back), processedDate: ago(18 + back), chargedAmount: -4_900, description: "שכר דירה"),
                Txn(id: "insurance-\(month)", date: ago(22 + back), processedDate: ago(22 + back), chargedAmount: -312.4, description: "הראל ביטוח"),
            ]
        }
        // A few transfers, with Leumi's detail line.
        func transfer(_ id: String, _ days: Double, _ amount: Double, _ memo: String) -> Txn {
            var t = Txn(id: id, date: ago(days), processedDate: ago(days), chargedAmount: amount,
                        description: amount > 0 ? "העברה מחשבון" : "העברה בנקאית")
            t.memo = memo
            return t
        }
        bank += [
            transfer("tr-1", 1, -250, "העברה ל: דנה כהן 12-345-678"),
            transfer("tr-2", 4, 180, "העברה מאת: יוסי לוי 10-800-02"),
            transfer("tr-3", 12, -1_200, "העברה ל: ועד הבית 20-512-334"),
        ]
        var running = 163.0
        for i in bank.indices.sorted(by: { bank[$0].date > bank[$1].date }) {
            bank[i].runningBalance = running
            running -= bank[i].chargedAmount
        }
        var snapshot = try! TrueBalance.compute(
            bank: Account(accountNumber: "812-123456", balance: 163, txns: bank),
            cards: [Account(accountNumber: "max", txns: txns)],
            now: now, fxRates: ["USD": 3.11, "EUR": 3.49])
        snapshot.cards = [CardInfo(last4: main, creditLimit: 15_000, available: 12_480),
                          CardInfo(last4: second, creditLimit: 5_000, available: 4_620)]
        snapshot.savings = [SavingsAccount(name: "פיקדון קצר מועד", balance: 25_000)]
        snapshot.foreignAccounts = [ForeignAccount(currency: "USD", balance: 1_250)]
        return snapshot
    }
}
