import BackgroundTasks
import Foundation
import Observation
import TrueBalanceCore
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class AppModel {
    enum Phase { case signedOut, signedIn }

    static let refreshTaskID = "il.truebalance.refresh"
    /// Opening the app refreshes when the data is older than this.
    static let staleAfter: TimeInterval = 15 * 60

    private(set) var phase: Phase
    private(set) var snapshot: Snapshot?
    private(set) var isRefreshing = false
    private(set) var refreshErrors: [Provider: BankError] = [:]
    private(set) var isDemo: Bool
    /// Last scraper step while signing in or refreshing (see `Format.progress`).
    private(set) var progressStep: String?
    /// Notes and tags on purchases, by purchase id.
    private(set) var notes: [String: PurchaseNote] = NotesStore.load()
    /// Monthly budget per category key.
    private(set) var budgets: [String: Double] = BudgetStore.load()

    /// Notify when the true balance goes below this (0 = only when overdrawn).
    static var alertThreshold: Double { UserDefaults.standard.double(forKey: "alertThreshold") }

    init() {
        let demo = UserDefaults.standard.bool(forKey: "demo")
        let signedIn = demo || Keychain.load() != nil
        isDemo = demo
        phase = signedIn ? .signedIn : .signedOut
        snapshot = signedIn ? (demo ? DemoData.snapshot() : SnapshotStore.load()) : nil
        WebDriver.onStep = { [weak self] step in self?.progressStep = step }
        updateWidgets()
    }

    // MARK: Notes and budgets

    func setNote(_ note: PurchaseNote, for id: String) {
        notes[id] = note.isEmpty ? nil : note
        NotesStore.save(notes)
    }

    /// Tags used so far, most used first, for quick picking.
    var knownTags: [String] {
        let counts = notes.values.flatMap(\.tags).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    func setBudget(_ limit: Double, for category: String) {
        budgets[category] = limit > 0 ? limit : nil
        BudgetStore.save(budgets)
    }

    var budgetProgress: [BudgetProgress] {
        Budgets.progress(limits: budgets, history: allPurchases)
    }

    // MARK: Sign in / out

    /// Signs in to both sites. Credentials are only kept if both accept them.
    func signIn(leumi: Credentials, max: Credentials) async -> [Provider: BankError] {
        defer { progressStep = nil }
        do {
            let snapshot = try await Banks.fetchSnapshot(leumi: leumi, max: max)
            try Keychain.save(.init(leumi: leumi, max: max))
            apply(snapshot)
            phase = .signedIn
            scheduleBackgroundRefresh()
            await requestNotificationPermission()
            return [:]
        } catch let failure as ScrapeFailure {
            return failure.errors
        } catch {
            return [.leumi: .unavailable("\(error)")]
        }
    }

    func startDemo() {
        isDemo = true
        UserDefaults.standard.set(true, forKey: "demo")
        apply(DemoData.snapshot())
        phase = .signedIn
    }

    func signOut() {
        Keychain.delete()
        SnapshotStore.delete()
        PurchaseCacheStore.delete()
        NotesStore.delete()
        notes = [:]
        WidgetData.save(nil)
        WidgetCenter.shared.reloadAllTimelines()
        UserDefaults.standard.removeObject(forKey: "demo")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        isDemo = false
        snapshot = nil
        refreshErrors = [:]
        phase = .signedOut
    }

    // MARK: Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        if isDemo {
            apply(DemoData.snapshot())
            return
        }
        guard let stored = Keychain.load() else { return signOut() }
        isRefreshing = true
        defer {
            isRefreshing = false
            progressStep = nil
        }
        do {
            apply(try await Banks.fetchSnapshot(leumi: stored.leumi, max: stored.max))
            refreshErrors = [:]
        } catch let failure as ScrapeFailure {
            refreshErrors = failure.errors
        } catch {
            refreshErrors = [.leumi: .unavailable("\(error)")]
        }
    }

    func refreshIfStale() async {
        guard phase == .signedIn else { return }
        if let at = snapshot?.computedAt, Date.now.timeIntervalSince(at) < Self.staleAfter { return }
        await refresh()
    }

    private func apply(_ new: Snapshot) {
        let threshold = Self.alertThreshold
        let wasBelow = (snapshot?.trueBalance ?? .infinity) < threshold
        snapshot = new
        if !isDemo { SnapshotStore.save(new) }
        // Fill in the greeting's first name from the bank, unless already set.
        if let name = new.holderFirstName,
           (UserDefaults.standard.string(forKey: "firstName") ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            UserDefaults.standard.set(name, forKey: "firstName")
        }
        // Once per crossing, not on every refresh while it stays low.
        if new.trueBalance < threshold && !wasBelow && !isDemo { notifyLowBalance(new, threshold: threshold) }
        if !isDemo { notifyBudgets() }
        updateWidgets()
    }

    /// Shares the essentials with the widgets and asks them to redraw.
    func updateWidgets() {
        guard let s = snapshot else { return }
        WidgetData.save(WidgetData(
            trueBalance: s.trueBalance, nextChargeDay: s.nextCharge?.chargeDate, nextChargeTotal: s.nextCharge?.total,
            dailyBudget: TrueBalance.dailyBudget(s), updatedAt: s.computedAt,
            hideAmounts: UserDefaults.standard.bool(forKey: "hideAmounts"), isDemo: isDemo))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Background

    func scheduleBackgroundRefresh() {
        guard phase == .signedIn, !isDemo else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func backgroundRefresh() async {
        scheduleBackgroundRefresh() // keep the chain going
        await refresh()
    }

    // MARK: Notifications

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Once per category, level (80 %, 100 %) and month.
    private func notifyBudgets() {
        let month = String(Israel.day(.now).prefix(7))
        var sent = Set(UserDefaults.standard.stringArray(forKey: "budgetAlertsSent") ?? []).filter { $0.hasPrefix(month) }
        for p in budgetProgress {
            guard let level = p.alertLevel, sent.insert("\(month)|\(p.category)|\(level)").inserted else { continue }
            // Going straight past 100 % doesn't also send the 80 % one later.
            if level == 100 { sent.insert("\(month)|\(p.category)|80") }
            let content = UNMutableNotificationContent()
            let name = Format.categoryName(p.category)
            let limit = p.limit.formatted(.currency(code: "ILS").precision(.fractionLength(0)))
            content.title = level == 100
                ? String(localized: "\(name) budget used up")
                : String(localized: "\(name): 80% of the budget used")
            content.body = String(localized: "\(p.spent.shekels) spent this month out of \(limit).")
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "budget-\(p.category)", content: content, trigger: nil))
        }
        UserDefaults.standard.set(Array(sent), forKey: "budgetAlertsSent")
    }

    /// Warns when the true balance goes below the chosen threshold (or zero).
    private func notifyLowBalance(_ s: Snapshot, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = s.trueBalance < 0
            ? String(localized: "Heads up: you’ll be overdrawn")
            : String(localized: "Your true balance is below \(threshold.formatted(.currency(code: "ILS").precision(.fractionLength(0))))")
        let amount = s.trueBalance.formatted(.currency(code: "ILS"))
        if let day = s.nextCharge.flatMap({ Israel.date(fromDay: $0.chargeDate) }) {
            let date = day.formatted(.dateTime.day().month(.wide))
            content.body = String(localized: "After Max is debited on \(date), your balance will be \(amount).")
        } else {
            content.body = String(localized: "Your true balance is \(amount).")
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-balance", content: content, trigger: nil))
    }
}
