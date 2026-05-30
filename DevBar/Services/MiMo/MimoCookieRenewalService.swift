import Foundation
import WebKit
import DevBarCore

enum MimoCookieRenewalReason: String {
    case startup
    case timer
    case apiExpired
    case manual
}

enum MimoCookieRenewalResult: Equatable {
    case skipped
    case renewed(String)
    case unchanged(String)
    case needsLogin(String)
    case failed(String)

    var cookieString: String? {
        switch self {
        case .renewed(let value), .unchanged(let value):
            return value
        case .skipped, .needsLogin, .failed:
            return nil
        }
    }
}

@MainActor
final class MimoCookieRenewalService: NSObject, WKNavigationDelegate {
    private enum Constants {
        static let renewalURLs = [
            "https://platform.xiaomimimo.com/console/balance",
            "https://platform.xiaomimimo.com/console/plan-manage",
        ]
        static let minimumRenewInterval: TimeInterval = 12 * 60 * 60
        static let failureBackoffInterval: TimeInterval = 30 * 60
        static let frontendSettleDelay: UInt64 = 3_000_000_000
        static let navigationTimeout: UInt64 = 20_000_000_000
    }

    private var webView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Never>?
    private var isRenewing = false

    func renewIfNeeded(reason: MimoCookieRenewalReason) async -> MimoCookieRenewalResult {
        guard shouldRenew() else { return .skipped }
        return await renew(reason: reason)
    }

    func forceRenew(reason: MimoCookieRenewalReason) async -> MimoCookieRenewalResult {
        await renew(reason: reason)
    }

    private func shouldRenew(now: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DevBarCoreConstants.Defaults.mimoCookieAutoRenewEnabledKey) != nil,
           !defaults.bool(forKey: DevBarCoreConstants.Defaults.mimoCookieAutoRenewEnabledKey) {
            return false
        }

        if let failedAt = defaults.object(forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewFailedAtKey) as? Date,
           now.timeIntervalSince(failedAt) < Constants.failureBackoffInterval {
            return false
        }

        guard let renewedAt = defaults.object(forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewedAtKey) as? Date else {
            return true
        }

        return now.timeIntervalSince(renewedAt) >= Constants.minimumRenewInterval
    }

    private func renew(reason: MimoCookieRenewalReason) async -> MimoCookieRenewalResult {
        guard !isRenewing else { return .skipped }
        guard let savedCookie = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey),
              !savedCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .needsLogin(String(localized: "mimo_cookie_required"))
        }

        isRenewing = true
        defer { isRenewing = false }

        do {
            let webView = makeWebView()
            self.webView = webView

            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in MimoCookieBuilder.cookies(from: savedCookie) {
                await store.setCookie(cookie)
            }

            #if DEBUG
            print("[MiMo:Renewal] start reason=\(reason.rawValue)")
            #endif

            for rawURL in Constants.renewalURLs {
                guard let url = URL(string: rawURL) else {
                    return .failed(String(localized: "invalid_response"))
                }
                webView.load(URLRequest(url: url))
                await waitForNavigationOrTimeout()
                try? await Task.sleep(nanoseconds: Constants.frontendSettleDelay)
            }

            let cookies = await store.allCookies()
            let renewedCookie = MimoAPIClient.platformCookieString(from: cookies)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !renewedCookie.isEmpty else {
                markRenewalFailure()
                return .needsLogin(String(localized: "mimo_cookie_renewal_needs_login"))
            }

            UserDefaults.standard.set(Date(), forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewedAtKey)

            if MimoAPIClient.isSameRequiredCookie(renewedCookie, savedCookie) {
                return .unchanged(renewedCookie)
            }

            KeychainService.shared.save(
                key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                value: renewedCookie
            )
            return .renewed(renewedCookie)
        } catch {
            markRenewalFailure()
            return .failed(error.localizedDescription)
        }
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    private func waitForNavigationOrTimeout() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                await withCheckedContinuation { continuation in
                    self?.navigationContinuation = continuation
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Constants.navigationTimeout)
            }
            await group.next()
            group.cancelAll()
            resumeNavigationWaiter()
        }
    }

    private func markRenewalFailure() {
        UserDefaults.standard.set(Date(), forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewFailedAtKey)
    }

    private func resumeNavigationWaiter() {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeNavigationWaiter()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeNavigationWaiter()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeNavigationWaiter()
    }
}
