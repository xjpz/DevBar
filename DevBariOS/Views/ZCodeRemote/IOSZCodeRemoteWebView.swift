import SwiftUI
import WebKit

enum IOSZCodeRemoteNavigationState: Equatable {
    case idle
    case connecting
    case connected
    case failed
}

/// 远控页 WebView 封装。
/// 页面内不展示地址（无地址栏、关闭链接预览），失效靠导航错误回调上报；
/// 通过注入脚本探测页面主题（zcode 远控页自带 浅色/深色/系统默认 设置），实时回传供原生 chrome 适配。
struct IOSZCodeRemoteWebView: UIViewRepresentable {
    let urlString: String
    var reloadToken: Int = 0
    var prefersDarkChrome: Bool = true
    /// 页面采样得到的精确背景色，用于 WebView 出血底色，消除与页面的色差
    var pageBackground: UIColor?
    let onNavigationStateChange: (IOSZCodeRemoteNavigationState) -> Void
    var onPageThemeChange: (Bool, Bool, UIColor?) -> Void = { _, _, _ in }

    static let themeMessageName = "zcodeTheme"

    /// 主题探测与出血区对色：
    /// - 深/浅判定：html/body 背景 → 主题 class 令牌 → color-scheme 声明 → 跳过浮层的顶/底采样 → 系统偏好；
    /// - 出血区铺色：采样「紧邻安全区」元素（页头/页脚，含 fixed/sticky）的真实背景色，
    ///   同时回写 html/body 并把 RGB 传给原生刷 WebView 底色，保证页面出血区与原生底色都精确同色，
    ///   消除深色主题下黑/灰色差接缝。
    /// 主题切换表现为 html/body 的 class、style 或 color-scheme 变化，用 MutationObserver 捕获；
    /// 另监听 prefers-color-scheme 变化覆盖「系统默认」模式，低频轮询兜底，结果去重后回传。
    private static let themeProbeScript = """
    (function() {
      function parseRGB(color) {
        var m = color && color.match(/rgba?\\((\\d+)[, ]+(\\d+)[, ]+(\\d+)(?:[, /]+([\\d.]+))?\\)/);
        if (!m) return null;
        if (m[4] !== undefined && parseFloat(m[4]) === 0) return null;
        return [+m[1], +m[2], +m[3]];
      }
      function luminance(color) {
        var rgb = parseRGB(color);
        if (!rgb) return null;
        return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
      }
      function sampleBgAt(y, includeFloating) {
        var el = document.elementFromPoint(Math.floor(window.innerWidth / 2), y);
        while (el) {
          var cs = getComputedStyle(el);
          var floating = cs.position === 'absolute' || cs.position === 'fixed';
          // 默认跳过浮层（弹窗、下拉、遮罩）落到真实布局容器；取页头底色时含 fixed/sticky
          if (!floating || includeFloating) {
            var bg = cs.backgroundColor;
            if (luminance(bg) !== null) return bg;
          }
          el = el.parentElement;
        }
        return null;
      }
      function stripColor(y) {
        return sampleBgAt(y, false);
      }
      // 紧邻顶部安全区的元素（约 84px 处的页头），其底色就是视觉上紧挨状态栏的颜色
      function adjacentPaint() {
        return sampleBgAt(84, true)
          || sampleBgAt(window.innerHeight - 84, true)
          || stripColor(10)
          || stripColor(window.innerHeight - 10);
      }
      function classThemeDark() {
        var names = ((document.documentElement.className || '') + ' ' + ((document.body && document.body.className) || '')).toLowerCase();
        var hasDark = /(^|[\\s_-])(dark|theme-dark|dark-mode|darkmode)([\\s_-]|$)/.test(names);
        var hasLight = /(^|[\\s_-])(light|theme-light|light-mode|lightmode)([\\s_-]|$)/.test(names);
        if (hasDark !== hasLight) return hasDark;
        return null;
      }
      function decideDark() {
        var htmlBg = getComputedStyle(document.documentElement).backgroundColor;
        var bodyBg = document.body ? getComputedStyle(document.body).backgroundColor : null;
        var bg = luminance(htmlBg) !== null ? htmlBg : (luminance(bodyBg) !== null ? bodyBg : null);
        if (bg) return luminance(bg) < 0.5;
        var classDark = classThemeDark();
        if (classDark !== null) return classDark;
        var scheme = (getComputedStyle(document.documentElement).colorScheme || '').toLowerCase();
        if (scheme.indexOf('dark') >= 0 && scheme.indexOf('light') < 0) return true;
        if (scheme.indexOf('light') >= 0 && scheme.indexOf('dark') < 0) return false;
        bg = stripColor(10) || stripColor(window.innerHeight - 10);
        if (bg) return luminance(bg) < 0.5;
        return window.matchMedia('(prefers-color-scheme: dark)').matches;
      }
      function systemMode() {
        var scheme = (getComputedStyle(document.documentElement).colorScheme || '').toLowerCase();
        return scheme.indexOf('light') >= 0 && scheme.indexOf('dark') >= 0;
      }
      var last = null;
      function report() {
        try {
          // 先清掉上一轮写入的强制背景，避免探测读到自己的覆盖导致主题切换失灵
          document.documentElement.style.removeProperty('background-color');
          if (document.body) document.body.style.removeProperty('background-color');
          var dark = decideDark();
          var system = systemMode();
          // 深色底色实测为 #202020（用户确认），直接钉死保证出血区与页面零色差；
          // 浅色沿用采样值（白色本身一致）
          var paint = dark ? 'rgb(32, 32, 32)' : adjacentPaint();
          var rgb = parseRGB(paint);
          var key = dark + '|' + system + '|' + (rgb ? rgb.join(',') : '');
          if (key === last) return;
          last = key;
          if (paint) {
            document.documentElement.style.setProperty('background-color', paint, 'important');
            if (document.body) document.body.style.setProperty('background-color', paint, 'important');
          }
          window.webkit.messageHandlers.zcodeTheme.postMessage({
            dark: dark,
            system: system,
            r: rgb ? rgb[0] : null,
            g: rgb ? rgb[1] : null,
            b: rgb ? rgb[2] : null
          });
        } catch (e) {}
      }
      report();
      var mql = window.matchMedia('(prefers-color-scheme: dark)');
      if (mql.addEventListener) mql.addEventListener('change', report);
      var observer = new MutationObserver(report);
      observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'style', 'color-scheme'] });
      if (document.body) observer.observe(document.body, { attributes: true, attributeFilter: ['class', 'style'] });
      setInterval(report, 2000);
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationStateChange: onNavigationStateChange, onPageThemeChange: onPageThemeChange)
    }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Self.themeMessageName)
        contentController.addUserScript(WKUserScript(
            source: Self.themeProbeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.refreshTriggered), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        context.coordinator.refreshControl = refreshControl

        applyChrome(webView, coordinator: context.coordinator)

        // 首建即视为当前 token 已消费，避免 updateUIView 触发重复加载
        context.coordinator.lastHandledReloadToken = reloadToken
        context.coordinator.load(urlString: urlString, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigationStateChange = onNavigationStateChange
        context.coordinator.onPageThemeChange = onPageThemeChange
        applyChrome(webView, coordinator: context.coordinator)
        context.coordinator.reloadIfNeeded(reloadToken: reloadToken, urlString: urlString, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: themeMessageName)
    }

    private func applyChrome(_ webView: WKWebView, coordinator: Coordinator) {
        let background = pageBackground ?? (prefersDarkChrome ? UIColor.black : UIColor.white)
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        coordinator.refreshControl?.tintColor = prefersDarkChrome ? .white : .black
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onNavigationStateChange: (IOSZCodeRemoteNavigationState) -> Void
        var onPageThemeChange: (Bool, Bool, UIColor?) -> Void
        weak var refreshControl: UIRefreshControl?
        var lastHandledReloadToken: Int

        init(
            onNavigationStateChange: @escaping (IOSZCodeRemoteNavigationState) -> Void,
            onPageThemeChange: @escaping (Bool, Bool, UIColor?) -> Void
        ) {
            self.onNavigationStateChange = onNavigationStateChange
            self.onPageThemeChange = onPageThemeChange
            self.lastHandledReloadToken = 0
        }

        func load(urlString: String, in webView: WKWebView) {
            guard let url = URL(string: urlString) else {
                onNavigationStateChange(.failed)
                return
            }
            onNavigationStateChange(.connecting)
            // 远控页面按无缓存加载，避免失效地址命中旧缓存造成假连接
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            webView.load(request)
        }

        func reloadIfNeeded(reloadToken: Int, urlString: String, in webView: WKWebView) {
            guard reloadToken != lastHandledReloadToken else { return }
            lastHandledReloadToken = reloadToken
            load(urlString: urlString, in: webView)
        }

        @objc func refreshTriggered() {
            guard let scrollView = refreshControl?.superview as? UIScrollView,
                  let webView = scrollView.subviews.compactMap({ $0 as? WKWebView }).first,
                  let urlString = webView.url?.absoluteString else {
                refreshControl?.endRefreshing()
                return
            }
            load(urlString: urlString, in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == IOSZCodeRemoteWebView.themeMessageName,
                  let body = message.body as? [String: Any],
                  let dark = body["dark"] as? Bool,
                  let system = body["system"] as? Bool else {
                return
            }
            let paint: UIColor?
            if let r = body["r"] as? Int,
               let g = body["g"] as? Int,
               let b = body["b"] as? Int {
                paint = UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            } else {
                paint = nil
            }
            DispatchQueue.main.async {
                self.onPageThemeChange(dark, system, paint)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onNavigationStateChange(.connecting)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            refreshControl?.endRefreshing()
            onNavigationStateChange(.connected)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            refreshControl?.endRefreshing()
            onNavigationStateChange(.failed)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 用户主动取消（如重新加载打断旧请求）不算失效
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            refreshControl?.endRefreshing()
            onNavigationStateChange(.failed)
        }
    }
}
