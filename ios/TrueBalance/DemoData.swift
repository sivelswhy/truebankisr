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

        let txns = [
            t(14, 412.9, "Shufersal Deal", "groceries"),
            t(11, 89, "Paz Yellow", "energy"),
            t(9, 249.9, "IKEA Rishon", "home", installments: .init(number: 1, total: 3)),
            t(9, 249.9, "IKEA Rishon", "home", month: 2, installments: .init(number: 2, total: 3)),
            t(9, 249.9, "IKEA Rishon", "home", month: 3, installments: .init(number: 3, total: 3)),
            t(6, 54, "Aroma Espresso Bar", "restaurants"),
            t(3, 119.9, "Partner Communications", "telecom"),
            t(2, 64, "Super-Pharm", "health"),
            t(0, 38.5, "Rami Levy", "groceries", status: .pending),
        ]
        return try! TrueBalance.compute(
            bank: Account(accountNumber: "812-123456", balance: 163, txns: []),
            cards: [Account(accountNumber: "max", txns: txns)],
            now: now)
    }
}
