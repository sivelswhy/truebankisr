import Foundation
import Network

/// Whether the iPhone has a network path, so a refresh fails at once with
/// "no internet" instead of waiting for the banks' pages to time out, and
/// starts again by itself when the connection comes back.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true
    /// Called on the way from offline back to online.
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "il.truebalance.connectivity"))
    }

    private func update(_ online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        if online != wasOnline { Log.add("[network] \(online ? "online" : "offline")") }
        if online && !wasOnline { onReconnect?() }
    }

    /// The URL errors that mean "no network", as opposed to a slow or broken site.
    nonisolated static func isOffline(_ error: Error) -> Bool {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed,
                NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive].contains(e.code)
    }
}
