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
    private(set) var snapshot: Snapshot? {
        didSet { DisplayCurrency.shared.rates = Self.rates(snapshot) }
    }
    private(set) var isRefreshing = false
    private(set) var refreshErrors: [Provider: BankError] = [:]
    private(set) var isDemo: Bool
    /// Last scraper step while signing in or refreshing (see `Format.progress`).
    private(set) var progressStep: String?
    /// Notes and tags on purchases, by purchase id.
    private(set) var notes: [String: PurchaseNote] = NotesStore.load()
    /// Monthly budget per category key.
    private(set) var budgets: [String: Double] = BudgetStore.load()

    /// European banks through Enable Banking, shown apart from the true balance.
    private(set) var euroKey: EnableBankingKey? = EuroStore.key.load()
    private(set) var euroConnections: [EuroConnection] = EuroStore.connections.load() ?? []
    private(set) var euroData: [EuroBankData] = EuroStore.loadData()
    /// By bank id.
    private(set) var euroErrors: [String: EnableBankingError] = [:]
    /// The bank whose session is being created after the redirect.
    private(set) var connectingEuroBank: String?

    /// Notify when the true balance goes below this (0 = only when overdrawn).
    static var alertThreshold: Double { UserDefaults.standard.double(forKey: "alertThreshold") }

    init() {
        let demo = UserDefaults.standard.bool(forKey: "demo")
        let signedIn = demo || Keychain.load() != nil
        isDemo = demo
        phase = signedIn ? .signedIn : .signedOut
        snapshot = signedIn ? (demo ? DemoData.snapshot() : SnapshotStore.load()) : nil
        DisplayCurrency.shared.rates = Self.rates(snapshot)
        WebDriver.onStep = { [weak self] step in self?.progressStep = step }
        // Back online after a refresh failed for lack of network: try again.
        Connectivity.shared.onReconnect = { [weak self] in
            guard let self, self.phase == .signedIn,
                  self.refreshErrors.values.contains(.offline) || self.euroErrors.values.contains(.offline) else { return }
            Task { await self.refresh(manual: false) }
        }
        updateWidgets()
    }

    /// Bank of Israel rates for the second currency: the snapshot's, else the last fetched.
    private static func rates(_ snapshot: Snapshot?) -> [String: Double] {
        snapshot?.fxRates ?? UserDefaults.standard.dictionary(forKey: "fxRates") as? [String: Double] ?? [:]
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
        guard Connectivity.shared.isOnline else { return [.leumi: .offline, .max: .offline] }
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
        EuroStore.deleteAll()
        euroKey = nil
        euroConnections = []
        euroData = []
        euroErrors = [:]
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

    /// `manual`: asked for (pull to refresh), not on opening or in the background.
    func refresh(manual: Bool = true) async {
        guard !isRefreshing else { return }
        if isDemo {
            apply(DemoData.snapshot())
            return
        }
        guard let stored = Keychain.load() else { return signOut() }
        // No point waiting for pages that can't load.
        guard Connectivity.shared.isOnline else {
            Log.add("[refresh] skipped: offline")
            refreshErrors = [.leumi: .offline, .max: .offline]
            return
        }
        isRefreshing = true
        Log.add("[refresh] start (\(manual ? "manual" : "automatic"))")
        let started = Date.now
        defer {
            isRefreshing = false
            progressStep = nil
            Log.add("[refresh] end after \(Int(Date.now.timeIntervalSince(started))) s, "
                    + (refreshErrors.isEmpty ? "ok" : "errors: \(refreshErrors.keys.map(\.rawValue).sorted())"))
        }
        let euro = Task { await refreshEuro(manual: manual) }
        do {
            apply(try await Banks.fetchSnapshot(leumi: stored.leumi, max: stored.max))
            refreshErrors = [:]
        } catch let failure as ScrapeFailure {
            refreshErrors = failure.errors
        } catch {
            refreshErrors = [.leumi: .unavailable("\(error)")]
        }
        await euro.value
    }

    func refreshIfStale() async {
        guard phase == .signedIn else { return }
        if let at = snapshot?.computedAt, Date.now.timeIntervalSince(at) < Self.staleAfter { return }
        await refresh(manual: false)
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

    // MARK: European banks

    /// Automatic refreshes read these banks at most every 6 hours: PSD2 lets
    /// a bank cap reads made without you at 4 a day.
    static let euroMinInterval: TimeInterval = 6 * 60 * 60

    /// Checks the key signs before keeping it.
    func importEuroKey(pem: String, appID: String) throws {
        let key = EnableBankingKey(appID: appID.trimmingCharacters(in: .whitespacesAndNewlines), privateKeyPEM: pem)
        _ = try JWT.token(key)
        EuroStore.key.save(key)
        euroKey = key
    }

    /// The bank's page to open; its answer comes back through `handleOpenURL`.
    func startEuroConnection(_ bank: EuroBank) async throws -> URL {
        guard let key = euroKey else { throw EnableBankingError.noKey }
        let state = UUID().uuidString
        // In UserDefaults: iOS may close the app while the bank's app is open.
        UserDefaults.standard.set(state, forKey: "euroPendingState")
        UserDefaults.standard.set(try? JSONEncoder().encode(bank), forKey: "euroPendingBank")
        do {
            return try await EnableBanking.startAuthorization(bank, state: state, key: key)
        } catch {
            throw EnableBankingError.from(error)
        }
    }

    /// truebalance://enablebanking?code=…&state=… from docs/enablebanking.html.
    func handleOpenURL(_ url: URL) async {
        guard url.scheme == "truebalance", url.host == EnableBanking.callbackHost else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let defaults = UserDefaults.standard
        guard let state = defaults.string(forKey: "euroPendingState"),
              let bank = defaults.data(forKey: "euroPendingBank").flatMap({ try? JSONDecoder().decode(EuroBank.self, from: $0) })
        else { return }
        defaults.removeObject(forKey: "euroPendingState")
        defaults.removeObject(forKey: "euroPendingBank")
        guard value("state") == state, let code = value("code"), let key = euroKey else {
            euroErrors[bank.id] = .notAuthorized(value("error_description") ?? value("error") ?? "no code in the redirect")
            Log.add("[euro] \(bank.id): not authorized (\(value("error") ?? "no code"))")
            return
        }
        connectingEuroBank = bank.id
        defer { connectingEuroBank = nil }
        do {
            let connection = try await EnableBanking.createSession(code: code, bank: bank, key: key)
            // Reconnecting keeps the bank's place in the picker.
            if let i = euroConnections.firstIndex(where: { $0.id == bank.id }) {
                euroConnections[i] = connection
            } else {
                euroConnections.append(connection)
            }
            EuroStore.connections.save(euroConnections)
            euroErrors[bank.id] = nil
            Log.add("[euro] \(bank.id): connected, \(connection.accounts.count) account(s)")
            await refreshEuro(manual: true, only: bank.id)
        } catch {
            euroErrors[bank.id] = .from(error)
            Log.add("[error] \(bank.id) session: \(euroErrors[bank.id]!) (from \(error))")
        }
    }

    func disconnectEuroBank(_ bank: EuroBank) async {
        if let c = euroConnections.first(where: { $0.id == bank.id }), let key = euroKey {
            await EnableBanking.deleteSession(c.sessionID, key: key)
        }
        euroConnections.removeAll { $0.id == bank.id }
        euroData.removeAll { $0.id == bank.id }
        euroErrors[bank.id] = nil
        EuroStore.connections.save(euroConnections)
        EuroStore.saveData(euroData)
    }

    /// A failing bank keeps its last data and shows the error.
    func refreshEuro(manual: Bool, only: String? = nil) async {
        guard let key = euroKey, !isDemo, Connectivity.shared.isOnline else { return }
        for c in euroConnections where only == nil || c.id == only {
            if !manual, let last = euroData.first(where: { $0.id == c.id })?.updatedAt,
               Date.now.timeIntervalSince(last) < Self.euroMinInterval { continue }
            do {
                let data = try await EnableBanking.fetch(c, key: key)
                euroData.removeAll { $0.id == c.id }
                euroData.append(data)
                euroErrors[c.id] = nil
            } catch {
                euroErrors[c.id] = .from(error)
                Log.add("[error] \(c.id): \(euroErrors[c.id]!) (from \(error))")
            }
        }
        let order = euroConnections.map(\.id)
        euroData.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        EuroStore.saveData(euroData)
    }

    /// Bank name for an error key ("FR/Hello Bank" → "Hello Bank").
    func euroBankName(_ id: String) -> String {
        euroConnections.first { $0.id == id }?.bank.name ?? String(id.split(separator: "/", maxSplits: 1).last ?? Substring(id))
    }

    // MARK: Background

    /// A processing task, not an app refresh: signing in to both sites takes
    /// a minute or more, and an app refresh is stopped after about 30 seconds.
    /// iOS runs it when the phone is idle, usually at night while charging.
    func scheduleBackgroundRefresh() {
        guard phase == .signedIn, !isDemo else { return }
        let request = BGProcessingTaskRequest(identifier: Self.refreshTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.add("[background] not scheduled: \(error)")
        }
    }

    /// Called by iOS on the main queue (see `TrueBalanceApp.init`).
    func runBackgroundRefresh(_ task: BGProcessingTask) {
        scheduleBackgroundRefresh() // keep the chain going
        Log.add("[background] start")
        let work = Task {
            await refresh(manual: false)
            task.setTaskCompleted(success: !Task.isCancelled && refreshErrors.isEmpty)
        }
        task.expirationHandler = {
            Log.add("[background] iOS stopped it: out of time")
            work.cancel()
        }
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
