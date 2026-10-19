import BackgroundTasks
import Foundation
import Observation
import TrueBalanceCore
import UserNotifications

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

    /// Notify when the true balance goes below this (0 = only when overdrawn).
    static var alertThreshold: Double { UserDefaults.standard.double(forKey: "alertThreshold") }

    init() {
        let demo = UserDefaults.standard.bool(forKey: "demo")
        let signedIn = demo || Keychain.load() != nil
        isDemo = demo
        phase = signedIn ? .signedIn : .signedOut
        snapshot = signedIn ? (demo ? DemoData.snapshot() : SnapshotStore.load()) : nil
        WebDriver.onStep = { [weak self] step in self?.progressStep = step }
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
        // Once per crossing, not on every refresh while it stays low.
        if new.trueBalance < threshold && !wasBelow && !isDemo { notifyLowBalance(new, threshold: threshold) }
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
