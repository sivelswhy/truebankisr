import AppIntents
import Foundation
import TrueBalanceCore

/// "Hey Siri, what's my true balance in True Balance?" Answers from the last
/// refresh (signing in to the banks needs the app on screen).
struct TrueBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get true balance"
    static let description = IntentDescription("Your Leumi balance minus the next Max debit, from the last update.")
    /// Amounts are private: the iPhone must be unlocked.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let s = Self.snapshot() else {
            return .result(value: 0, dialog: "Open True Balance once to connect Leumi and Max.")
        }
        let amount = s.trueBalance.formatted(.currency(code: "ILS"))
        let updated = s.computedAt.formatted(.relative(presentation: .named))
        if let next = s.nextCharge, let day = Israel.date(fromDay: next.chargeDate) {
            let date = day.formatted(.dateTime.day().month(.wide))
            return .result(value: s.trueBalance, dialog: "After Max on \(date), you’ll have \(amount). Updated \(updated).")
        }
        return .result(value: s.trueBalance, dialog: "Your true balance is \(amount). Updated \(updated).")
    }

    @MainActor
    static func snapshot() -> Snapshot? {
        UserDefaults.standard.bool(forKey: "demo") ? DemoData.snapshot() : SnapshotStore.load()
    }
}

/// How much can be spent per day until the debit.
struct DailyBudgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Get daily budget"
    static let description = IntentDescription("What you can spend per day until the next Max debit.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let s = TrueBalanceIntent.snapshot() else {
            return .result(value: 0, dialog: "Open True Balance once to connect Leumi and Max.")
        }
        guard let budget = TrueBalance.dailyBudget(s) else {
            return .result(value: 0, dialog: "Nothing left to spread until the debit.")
        }
        let amount = budget.formatted(.currency(code: "ILS").precision(.fractionLength(0)))
        return .result(value: budget, dialog: "About \(amount) a day until the debit.")
    }
}

struct TrueBalanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TrueBalanceIntent(),
            phrases: [
                "What’s my true balance in \(.applicationName)",
                "My balance in \(.applicationName)",
                "\(.applicationName) balance",
            ],
            shortTitle: "True balance",
            systemImageName: "shekelsign.circle"
        )
        AppShortcut(
            intent: DailyBudgetIntent(),
            phrases: [
                "How much can I spend per day in \(.applicationName)",
                "\(.applicationName) daily budget",
            ],
            shortTitle: "Daily budget",
            systemImageName: "calendar"
        )
    }
}
