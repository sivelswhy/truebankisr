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
        for month in 1...5 {
            for (i, p) in past.enumerated() {
                let days = Double(month * 30 + i * 4 + 3)
                txns.append(with(Txn(id: "\(p.0)-past-\(month)-\(i)", date: ago(days), processedDate: billing(-month + 1),
                                     chargedAmount: -(p.2 + Double((month * 7 + i * 3) % 25)), description: p.0, category: p.1),
                                 card: i.isMultiple(of: 3) ? second : main))
            }
        }
        return try! TrueBalance.compute(
            bank: Account(accountNumber: "812-123456", balance: 163, txns: []),
            cards: [Account(accountNumber: "max", txns: txns)],
            now: now)
    }
}
