import UIKit
import WebKit

/// Drives a hidden WKWebView the way Puppeteer drives Chromium in
/// israeli-bank-scrapers: load a page, wait for elements, fill, click, and run
/// `fetch` inside the page so the site's own cookies apply.
@MainActor
final class WebDriver: NSObject, WKNavigationDelegate {
    struct Timeout: Error { var what: String }
    struct ScriptError: Error { var message: String }
    /// The site answered the page with an error status (403 from a firewall or
    /// a block from abroad, 5xx when it's down).
    struct HTTPStatus: Error { var code: Int; var host: String }

    let webView: WKWebView
    /// Troubleshooting: the page is shown on screen and can be used by hand.
    let visible: Bool
    /// What we're doing right now, reported when something times out.
    private(set) var currentStep = "start"
    private var navigation: CheckedContinuation<Void, Error>?
    /// HTTP status of the last page loaded in the main frame.
    private(set) var lastStatus: Int?

    /// `captureURLPattern`: XHR/fetch responses whose URL matches are kept in
    /// `window.__tbCaptures` (used for Leumi's balance request).
    init(captureURLPattern: String? = nil, visible: Bool = false) {
        self.visible = visible
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // fresh login every time, nothing left behind
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        if let pattern = captureURLPattern {
            config.userContentController.addUserScript(WKUserScript(
                source: Self.captureScript(pattern: pattern), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // WebKit's own desktop identity plus Safari's tokens: a forged user
        // agent that doesn't match the rest of the request gets blocked by
        // Leumi's firewall.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        // The scrapers' selectors target the desktop sites at 1024×768.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        super.init()
        webView.navigationDelegate = self
        attach()
    }

    /// Pages render and run timers reliably only when in a window.
    private func attach() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }
        if visible {
            // Keep the 1024×768 desktop size and only scale it down on screen:
            // at phone width (with a touchscreen) Max switches to its mobile
            // layout and the login steps no longer match.
            let area = window.bounds.inset(by: window.safeAreaInsets)
            let scale = min(area.width / webView.bounds.width, area.height / webView.bounds.height)
            webView.transform = CGAffineTransform(scaleX: scale, y: scale)
            webView.center = CGPoint(x: area.midX, y: area.minY + webView.bounds.height * scale / 2)
            webView.layer.borderColor = UIColor.systemOrange.cgColor
            webView.layer.borderWidth = 3
            window.addSubview(webView)
        } else {
            webView.alpha = 0.01
            webView.isUserInteractionEnabled = false
            window.insertSubview(webView, at: 0)
        }
    }

    /// Called on every step, so the UI can say what's happening.
    static var onStep: ((String) -> Void)?

    func step(_ name: String) {
        currentStep = name
        Self.onStep?(name)
        Log.add("[step] \(name)")
    }

    func close() {
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    var url: String { webView.url?.absoluteString ?? "" }

    // MARK: Navigation

    /// Returns once the page starts arriving (not when every resource is
    /// done: bank sites keep loading trackers for a long time on mobile).
    /// A load that times out or loses the connection is tried once more: on a
    /// slow network the second try often gets through. An error status fails
    /// right away instead of waiting for elements that will never come.
    func load(_ urlString: String, timeout: TimeInterval = 45) async throws {
        do {
            try await loadOnce(urlString, timeout: timeout)
        } catch where Self.isTransient(error) {
            Log.add("[retry] \(currentStep): \(error)")
            try await Task.sleep(for: .seconds(2))
            try await loadOnce(urlString, timeout: timeout)
        }
        if let code = lastStatus, code == 403 || code == 451 || code >= 500 {
            Log.add("[page] HTTP \(code) on \(URL(string: urlString)?.host ?? urlString)")
            throw HTTPStatus(code: code, host: URL(string: urlString)?.host ?? urlString)
        }
    }

    private func loadOnce(_ urlString: String, timeout: TimeInterval) async throws {
        lastStatus = nil
        try await withTimeout(timeout, "loading \(URL(string: urlString)?.host ?? urlString)") {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                self.navigation?.resume(throwing: CancellationError())
                self.navigation = c
                self.webView.load(URLRequest(url: URL(string: urlString)!))
            }
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is Timeout { return true }
        let e = error as NSError
        return e.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(e.code)
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let status = navigationResponse.isForMainFrame ? (navigationResponse.response as? HTTPURLResponse)?.statusCode : nil
        MainActor.assumeIsolated {
            if let status { lastStatus = status }
            decisionHandler(.allow)
        }
    }

    // MARK: Error pages

    enum PageProblem: Equatable {
        /// A firewall or geo-block page: the site refuses this network.
        case refused(String)
        case maintenance(String)
    }

    /// What the page on screen says, when a step failed: a block page, a
    /// maintenance notice... Nil when it looks like an ordinary page.
    func pageProblem() async -> PageProblem? {
        let seen = (try? await eval("return [document.title, document.body ? document.body.innerText : ''].join(' | ');",
                                    timeout: 5) as? String) ?? ""
        let text = seen.lowercased()
        let excerpt = String(seen.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(160))
        if let code = lastStatus, code == 403 || code == 451 {
            return .refused("HTTP \(code) on \(URL(string: url)?.host ?? url): \(excerpt)")
        }
        let refused = ["access denied", "you don't have permission", "you do not have permission", "request unsuccessful",
                       "incapsula", "you have been blocked", "attention required", "not available in your country",
                       "not available in your region", "unavailable in your country", "הגישה נחסמה", "הגישה לאתר חסומה"]
        if refused.contains(where: text.contains) { return .refused(excerpt) }
        let maintenance = ["maintenance", "תחזוקה", "temporarily unavailable", "service unavailable", "שירות אינו זמין"]
        if maintenance.contains(where: text.contains) || (lastStatus ?? 0) >= 500 { return .maintenance(excerpt) }
        return nil
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishNavigation(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishNavigation(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishNavigation(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishNavigation(error) }
    }

    private func finishNavigation(_ error: Error?) {
        guard let c = navigation else { return }
        navigation = nil
        // A redirect or a JS navigation cancelling the first load is not a failure.
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            c.resume(throwing: error)
        } else {
            c.resume()
        }
    }

    // MARK: Scripts

    /// Runs `body` as an async JS function; `args` become its parameters.
    /// WebKit doesn't always answer (a page replaced mid-call, a promise that
    /// never settles), so it gives up after `timeout`.
    @discardableResult
    func eval(_ body: String, _ args: [String: Any] = [:], timeout: TimeInterval = 60) async throws -> Any? {
        let result = try await withDeadline(timeout, "\(self.currentStep): page script didn’t answer") { [webView] in
            do {
                return ScriptResult(value: try await webView.callAsyncJavaScript(body, arguments: args, contentWorld: .page))
            } catch {
                throw ScriptError(message: (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? "\(error)")
            }
        }
        return result.value
    }

    /// What scripts return: plain JSON-like values, read on the main actor only.
    private struct ScriptResult: @unchecked Sendable { var value: Any? }

    func exists(_ selector: String) async -> Bool {
        (try? await eval("return !!document.querySelector(s)", ["s": selector])) as? Bool ?? false
    }

    /// Polls `condition` (JS returning a truthy value) until it holds.
    func waitFor(_ what: String, timeout: TimeInterval = 30, condition: String, _ args: [String: Any] = [:]) async throws {
        let timeout = visible ? max(timeout, 120) : timeout // leave time to act by hand
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let ok = try? await eval(condition, args) as? Bool, ok { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw Timeout(what: "\(currentStep): \(what)")
    }

    /// Waits until `selector` is in the page and visible.
    func waitForElement(_ selector: String, timeout: TimeInterval = 30) async throws {
        try await waitFor(selector, timeout: timeout, condition: """
            const e = document.querySelector(s);
            return !!e && !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
            """, ["s": selector])
    }

    func click(_ selector: String) async throws {
        try await eval("""
            const e = document.querySelector(s);
            if (!e) throw new Error('missing ' + s);
            e.scrollIntoView({ block: 'center' });
            e.click();
            """, ["s": selector])
    }

    /// Sets an input the way typing would, so Angular/React forms see it.
    func fill(_ selector: String, _ value: String) async throws {
        try await eval("""
            const e = document.querySelector(s);
            if (!e) throw new Error('missing ' + s);
            e.focus();
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            setter.call(e, '');
            e.dispatchEvent(new Event('input', { bubbles: true }));
            setter.call(e, v);
            e.dispatchEvent(new Event('input', { bubbles: true }));
            e.dispatchEvent(new Event('change', { bubbles: true }));
            e.dispatchEvent(new Event('blur', { bubbles: true }));
            """, ["s": selector, "v": value])
    }

    func bodyText() async -> String {
        (try? await eval("return document.body ? document.body.innerText : ''")) as? String ?? ""
    }

    /// GET inside the page (site cookies apply). Returns status + body.
    func fetch(_ url: String) async throws -> (status: Int, body: Data) {
        let result = try await eval("""
            const r = await fetch(u, { credentials: 'include', signal: AbortSignal.timeout(45000) });
            return [r.status, await r.text()];
            """, ["u": url], timeout: 60) as? [Any]
        guard let result, let status = result.first as? Int, let text = result.last as? String else {
            throw ScriptError(message: "fetch returned nothing for \(url)")
        }
        return (status, Data(text.utf8))
    }

    func clearCaptures() async {
        _ = try? await eval("window.__tbCaptures = []")
    }

    /// Waits for a captured response (see `captureURLPattern`).
    func waitForCapture(timeout: TimeInterval = 30) async throws -> Data {
        try await waitFor("captured response", timeout: timeout, condition: "return (window.__tbCaptures || []).length > 0")
        let text = try await eval("return window.__tbCaptures[window.__tbCaptures.length - 1]") as? String ?? ""
        return Data(text.utf8)
    }

    private static func captureScript(pattern: String) -> String {
        """
        (() => {
          // Only on the account pages: patched network functions on the login
          // page can look like tampering to the bank's firewall.
          if (!/\\/ebanking\\//i.test(location.pathname)) return;
          const re = new RegExp(\(String(reflecting: pattern)));
          window.__tbCaptures = [];
          const keep = (url, body) => { if (re.test(String(url))) window.__tbCaptures.push(body); };
          const origFetch = window.fetch;
          window.fetch = async (...args) => {
            const res = await origFetch(...args);
            try {
              const u = typeof args[0] === 'string' ? args[0] : args[0].url;
              if (re.test(u)) res.clone().text().then((t) => keep(u, t));
            } catch {}
            return res;
          };
          const open = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (m, u, ...rest) { this.__tbUrl = u; return open.call(this, m, u, ...rest); };
          const send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send = function (...a) {
            this.addEventListener('load', () => { try { keep(this.__tbUrl, this.responseText); } catch {} });
            return send.apply(this, a);
          };
        })();
        """
    }

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ what: String, _ op: @escaping @MainActor () async throws -> T) async throws -> T {
        let what = "\(currentStep): \(what)"
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw Timeout(what: what)
            }
            defer { group.cancelAll() }
            do {
                return try await group.next()!
            } catch {
                // Unblock the pending load so the group can finish.
                navigation?.resume(throwing: error)
                navigation = nil
                throw error
            }
        }
    }
}

/// Runs `op`, throwing `WebDriver.Timeout` after `seconds`. Unlike a task
/// group it returns right away instead of waiting for a stuck `op` to notice
/// the cancellation, so a page that never answers can't hold up a refresh.
@MainActor
func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ what: @autoclosure @escaping @MainActor () -> String,
                               _ op: @escaping @MainActor () async throws -> T) async throws -> T {
    let race = Race<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            race.continuation = c
            race.work = Task { @MainActor in
                do { race.finish(.success(try await op())) } catch { race.finish(.failure(error)) }
            }
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { race.finish(.failure(WebDriver.Timeout(what: what()))) }
            }
        }
    } onCancel: {
        Task { @MainActor in race.finish(.failure(CancellationError())) }
    }
}

/// The first of `op` and the timer to finish resumes the caller; the other is cancelled.
@MainActor
private final class Race<T: Sendable>: Sendable {
    var continuation: CheckedContinuation<T, Error>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(_ result: Result<T, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        work?.cancel()
        timer?.cancel()
        c.resume(with: result)
    }
}
