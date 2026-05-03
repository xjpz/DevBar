import SwiftUI
import WebKit

struct IOSWebViewLoginSheet: UIViewControllerRepresentable {
    let loginURL: URL
    let targetCookieName: String
    let onTokenExtracted: (String, [HTTPCookie]) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()
        let cookieName = targetCookieName
        let script = WKUserScript(
            source: """
            (function() {
                function checkCookie() {
                    var cookies = document.cookie;
                    if (cookies.indexOf('\(cookieName)=') !== -1) {
                        window.webkit.messageHandlers.loginDetector.postMessage('found');
                    }
                }
                setInterval(checkCookie, 1000);
                checkCookie();
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        contentController.addUserScript(script)
        contentController.add(context.coordinator, name: "loginDetector")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: loginURL))

        let viewController = UIViewController()
        viewController.view = webView

        let navController = UINavigationController(rootViewController: viewController)
        navController.navigationBar.prefersLargeTitles = false

        let cancelItem = UIBarButtonItem(
            title: String(localized: "cancel"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.cancelTapped)
        )
        viewController.navigationItem.leftBarButtonItem = cancelItem
        viewController.navigationItem.title = String(localized: "login_mimo_platform")

        context.coordinator.webView = webView
        context.coordinator.parent = self

        context.coordinator.startPolling()

        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: IOSWebViewLoginSheet
        var webView: WKWebView?
        private var pollTimer: Timer?

        init(parent: IOSWebViewLoginSheet) {
            self.parent = parent
        }

        deinit {
            pollTimer?.invalidate()
        }

        func startPolling() {
            let cookieTarget = parent.targetCookieName
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let webView = self.webView else { return }

                    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

                    if let token = cookies.first(where: { $0.name == cookieTarget }),
                       !token.value.isEmpty {
                        self.handleLoginSuccess(token: token.value, cookies: cookies)
                    }
                }
            }
        }

        @objc func cancelTapped() {
            pollTimer?.invalidate()
            pollTimer = nil
            parent.onCancelled()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "loginDetector" else { return }

            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView else { return }

                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

                if let token = cookies.first(where: { $0.name == self.parent.targetCookieName }),
                   !token.value.isEmpty {
                    self.handleLoginSuccess(token: token.value, cookies: cookies)
                }
            }
        }

        private func handleLoginSuccess(token: String, cookies: [HTTPCookie]) {
            pollTimer?.invalidate()
            pollTimer = nil
            webView?.configuration.userContentController.removeAllUserScripts()
            webView?.stopLoading()
            parent.onTokenExtracted(token, cookies)
        }
    }
}
