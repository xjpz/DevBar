import Combine
import SwiftUI
import WebKit

enum IOSZCodeRemoteNavigationState: Equatable {
    case idle
    case connecting
    case connected
    case failed
}

/// 远控会话控制器：持有 WKWebView 并跨页面进出存活，
/// 返回其他页面时仅从视图层级摘下，页面与连接状态全部保留，再进入免重新加载。
/// 导航代理与主题探测回调都挂在控制器上，生命周期与 WebView 一致，无悬空闭包。
@MainActor
final class IOSZCodeRemoteSessionController: NSObject, ObservableObject {
    static let shared = IOSZCodeRemoteSessionController()

    @Published private(set) var navigationState: IOSZCodeRemoteNavigationState = .idle
    @Published private(set) var pageIsDark = true
    @Published private(set) var pageUsesSystemTheme = true
    /// 顶部/底部出血区各自的颜色（页面顶栏与最底栏底色不同，需分别对齐）
    @Published private(set) var pageTopBackground: UIColor?
    @Published private(set) var pageBottomBackground: UIColor?
    /// 远控页内部路由进入二级页面（会话详情等）时为 true，此时不显示悬浮控制
    @Published private(set) var isSubpage = false
    /// 网页内容向下滚动时为 true：作为固定 tab 根视图时隐藏底栏（系统 minimize 不识别 WKWebView 滚动）
    @Published private(set) var isWebScrolledDown = false

    private(set) var webView: WKWebView?
    private var refreshControl: UIRefreshControl?
    private var loadedURLString: String?
    private var lastHandledReloadToken = 0
    private var contentOffsetObservation: NSKeyValueObservation?
    private var lastContentOffsetY: CGFloat = 0

    static let themeMessageName = "zcodeTheme"
    static let scrollMessageName = "zcodeScroll"

    /// 主题探测与出血区对色（依据 ZCode 开源源码，确定性信号优先、启发式降级）：
    /// - 深/浅判定：html[data-zcode-browser-theme-surface]（浏览器环境首帧设置、useTheme 切换维护）
    ///   → theme-zai-* 品牌类存在时读 dark class → html/body 背景亮度 → color-scheme → 采样 → 系统偏好；
    /// - 系统跟随：localStorage["zcode-theme"] === "system" → color-scheme 同时含 light/dark；
    /// - 出血区对色：getComputedStyle 读 --color-header / --color-background（theme-zai-dark 下即
    ///   #202020 / #161616）→ 采样紧邻安全区元素底色 → 实测常量兜底（深 #202020 / 浅白）。
    ///   顶色刷 WebView 底色，底色由 SwiftUI 叠加贴屏底色带（见 IOSZCodeRemoteView）。
    /// 主题切换必然翻转 html 的 class / 主题属性，MutationObserver 捕获；另监听 prefers-color-scheme
    /// 覆盖「系统默认」模式；2s 轮询仅作兜底——确定性信号命中时不执行采样（elementFromPoint 链空转）。
    private static let themeProbeScript = """
    (function() {
      function parseRGB(color) {
        if (!color) return null;
        color = color.trim();
        // 主题 token 是十六进制（--color-header: #202020），采样背景是 rgb()/rgba()
        var hex = color.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
        if (hex) {
          var h = hex[1];
          if (h.length === 3) {
            h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2);
          }
          return [
            parseInt(h.substring(0, 2), 16),
            parseInt(h.substring(2, 4), 16),
            parseInt(h.substring(4, 6), 16)
          ];
        }
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
      // ---- 确定性信号（packages/web/index.html、packages/ui/src/useTheme.ts、styles.css）----
      // 浏览器环境（含 WKWebView）下页面在 <html> 上维护 data-zcode-browser-theme-surface，
      // 首帧由 index.html 内联脚本设置、useTheme 每次切换主题时同步；
      // 品牌主题类 theme-zai-dark/theme-zai-light 与 dark class 同批翻转，可互为佐证
      function deterministicDark() {
        var el = document.documentElement;
        var surface = el.getAttribute('data-zcode-browser-theme-surface');
        if (surface === 'dark') return true;
        if (surface === 'light') return false;
        if (el.classList.contains('theme-zai-dark') || el.classList.contains('theme-zai-light')) {
          return el.classList.contains('dark');
        }
        return null;
      }
      // 主题种子 localStorage["zcode-theme"] ∈ {light,dark,zai-light,zai-dark,system}，system 为跟随系统
      function deterministicSystem() {
        try {
          var seed = localStorage.getItem('zcode-theme');
          if (seed === 'system') return true;
          if (seed === 'light' || seed === 'dark' || seed === 'zai-light' || seed === 'zai-dark') {
            return false;
          }
        } catch (e) {}
        return null;
      }
      // 出血色 token 挂在 <html> 主题类上：--color-header（顶）/ --color-background（底）
      function cssToken(name) {
        return parseRGB(getComputedStyle(document.documentElement).getPropertyValue(name));
      }
      var last = null;
      // 二级页面检测：线上移动端 web 以 history.state.zcodeMobilePage 标记会话页
      // （pushState 只写 state、不改 URL），直接读状态为权威信号；
      // push/pop 计数与路径对比兜底其他版本行为
      var initialPath = location.pathname;
      var navDepth = 0;
      function isSubpage() {
        try {
          if (window.history.state && window.history.state.zcodeMobilePage === 'chat') {
            return true;
          }
        } catch (e) {}
        return navDepth > 0 || location.pathname !== initialPath;
      }
      var origPush = history.pushState;
      if (origPush) {
        history.pushState = function() {
          navDepth++;
          var r = origPush.apply(this, arguments);
          report();
          return r;
        };
      }
      window.addEventListener('popstate', function() {
        if (navDepth > 0) navDepth--;
        report();
      });
      function report() {
        try {
          var det = deterministicDark();
          var dark = det !== null ? det : decideDark();
          // 确定性命中时直接读 token，不进入采样（elementFromPoint 链不再周期执行）
          var top = cssToken('--color-header');
          var bottom = cssToken('--color-background');
          // 降级链：token → 紧邻安全区采样 → 实测常量（深 #202020 / 浅白）
          if (!top) top = parseRGB(adjacentPaint());
          if (!bottom) bottom = parseRGB(adjacentPaint());
          if (!top) top = dark ? [32, 32, 32] : [255, 255, 255];
          if (!bottom) bottom = top;
          var system = deterministicSystem();
          if (system === null) system = systemMode();
          var sub = isSubpage();
          var key = dark + '|' + system + '|' + sub + '|' + top.join(',') + '|' + bottom.join(',');
          if (key === last) return;
          last = key;
          window.webkit.messageHandlers.zcodeTheme.postMessage({
            dark: dark,
            system: system,
            sub: sub,
            tr: top[0], tg: top[1], tb: top[2],
            br: bottom[0], bg: bottom[1], bb: bottom[2]
          });
        } catch (e) {}
      }
      report();
      var mql = window.matchMedia('(prefers-color-scheme: dark)');
      if (mql.addEventListener) mql.addEventListener('change', report);
      var observer = new MutationObserver(report);
      // 主题切换翻转 html 的 class、style（colorScheme）与主题属性，全部在此捕获
      observer.observe(document.documentElement, {
        attributes: true,
        attributeFilter: [
          'class',
          'style',
          'data-zcode-browser-theme-surface',
          'data-zcode-bootstrap-theme'
        ]
      });
      if (document.body) {
        observer.observe(document.body, { attributes: true, attributeFilter: ['class', 'style'] });
      }
      setInterval(report, 2000);
      // 滚动方向检测：捕获阶段监听 scroll 事件，覆盖 inner DOM 元素滚动
      // （此类页面 WKWebView 主 scrollView 不动，原生侧无法感知）；
      // 累积阈值判定，惯性滚动的碎片化位移也能累计触发；方向翻转时上报
      var scrollDown = false;
      var anchorY = null;
      var anchorTarget = null;
      function scrolledDown(value) {
        if (value === scrollDown) return;
        scrollDown = value;
        try {
          window.webkit.messageHandlers.zcodeScroll.postMessage({ down: value });
        } catch (e) {}
      }
      function handleScrollEvent(ev) {
        var t = ev.target;
        var y = null;
        if (t === document) {
          y = (document.scrollingElement && document.scrollingElement.scrollTop) || window.pageYOffset || 0;
        } else if (t && t.scrollTop !== undefined && t instanceof Element) {
          y = t.scrollTop;
        }
        if (y === null) return;
        if (t !== anchorTarget) {
          anchorTarget = t;
          anchorY = y;
          return;
        }
        var delta = y - anchorY;
        if (delta > 24) {
          scrolledDown(true);
          anchorY = y;
        } else if (delta < -8) {
          scrolledDown(false);
          anchorY = y;
        }
      }
      window.addEventListener('scroll', handleScrollEvent, true);
    })();
    """

    // MARK: - WebView 生命周期

    /// 取可复用的 WebView；首次调用时创建并装配探测脚本，重进页面时仅重新挂载
    func viewFor(urlString: String, reloadToken: Int) -> WKWebView {
        let view = webView ?? makeWebView()
        view.removeFromSuperview()
        lastHandledReloadToken = reloadToken
        if loadedURLString != urlString {
            scheduleLoad(urlString, in: view)
        } else {
            applyChrome()
        }
        return view
    }

    func handleUpdate(urlString: String, reloadToken: Int) {
        applyChrome()
        guard reloadToken != lastHandledReloadToken else { return }
        lastHandledReloadToken = reloadToken
        if let view = webView {
            scheduleLoad(urlString, in: view)
        }
    }

    /// makeUIView / updateUIView 处于视图更新期内，直接调用 load 发布 navigationState 会触发
    /// "Publishing changes from within view updates"；推迟到下一个 RunLoop 执行，
    /// 并挡掉重复调度与 teardown 后的迟到加载
    private func scheduleLoad(_ urlString: String, in view: WKWebView) {
        DispatchQueue.main.async {
            guard self.webView === view, self.loadedURLString != urlString else { return }
            self.load(urlString, in: view)
        }
    }

    /// 断开并清除时彻底销毁会话（WebView、脚本、探测状态全部重置）
    func teardown() {
        contentOffsetObservation?.invalidate()
        contentOffsetObservation = nil
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.themeMessageName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.scrollMessageName)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        refreshControl = nil
        loadedURLString = nil
        lastHandledReloadToken = 0
        lastContentOffsetY = 0
        navigationState = .idle
        pageIsDark = true
        pageUsesSystemTheme = true
        pageTopBackground = nil
        pageBottomBackground = nil
        isSubpage = false
        isWebScrolledDown = false
    }

    // MARK: - 装配

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: Self.themeMessageName)
        contentController.add(self, name: Self.scrollMessageName)
        contentController.addUserScript(WKUserScript(
            source: Self.themeProbeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = contentController

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = false
        view.isOpaque = false

        let refresh = UIRefreshControl()
        refresh.tintColor = .white
        refresh.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        view.scrollView.refreshControl = refresh
        refreshControl = refresh

        // 系统 tabBarMinimizeBehavior 不识别 WKWebView 的内部滚动，
        // 用 KVO 观察 contentOffset 模拟"下滑收起底栏、上滑恢复"
        contentOffsetObservation = view.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            DispatchQueue.main.async {
                self?.handleWebScroll(scrollView)
            }
        }

        webView = view
        return view
    }

    private func handleWebScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        // 只响应真实拖动/减速；程序性偏移（键盘、布局）与下拉回弹（负值）仅同步基线
        guard scrollView.isTracking || scrollView.isDecelerating, y >= 0 else {
            lastContentOffsetY = max(y, 0)
            return
        }
        let delta = y - lastContentOffsetY
        lastContentOffsetY = y
        if delta > 24 {
            if !isWebScrolledDown { isWebScrolledDown = true }
        } else if delta < -8 {
            if isWebScrolledDown { isWebScrolledDown = false }
        }
    }

    private func load(_ urlString: String, in view: WKWebView) {
        guard let url = URL(string: urlString) else {
            navigationState = .failed
            return
        }
        navigationState = .connecting
        loadedURLString = urlString
        isSubpage = false
        isWebScrolledDown = false
        lastContentOffsetY = 0
        // 远控页面按无缓存加载，避免失效地址命中旧缓存造成假连接
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        view.load(request)
    }

    @objc private func refreshTriggered() {
        guard let view = webView, let urlString = view.url?.absoluteString ?? loadedURLString else {
            refreshControl?.endRefreshing()
            return
        }
        load(urlString, in: view)
    }

    private func applyChrome() {
        // 顶部出血区由 WebView 底色承担；底部出血区由 SwiftUI 叠加色带（见 IOSZCodeRemoteView）
        let background = pageTopBackground ?? (pageIsDark ? UIColor.black : UIColor.white)
        webView?.backgroundColor = background
        webView?.scrollView.backgroundColor = background
        refreshControl?.tintColor = pageIsDark ? .white : .black
    }
}

// MARK: - WKNavigationDelegate / WKScriptMessageHandler

extension IOSZCodeRemoteSessionController: WKNavigationDelegate, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Self.scrollMessageName {
            if let body = message.body as? [String: Any],
               let down = body["down"] as? Bool {
                isWebScrolledDown = down
            }
            return
        }
        guard message.name == Self.themeMessageName,
              let body = message.body as? [String: Any],
              let dark = body["dark"] as? Bool,
              let system = body["system"] as? Bool else {
            return
        }
        let top: UIColor?
        if let r = body["tr"] as? Int,
           let g = body["tg"] as? Int,
           let b = body["tb"] as? Int {
            top = UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        } else {
            top = nil
        }
        let bottom: UIColor?
        if let r = body["br"] as? Int,
           let g = body["bg"] as? Int,
           let b = body["bb"] as? Int {
            bottom = UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        } else {
            bottom = nil
        }
        pageIsDark = dark
        pageUsesSystemTheme = system
        pageTopBackground = top
        pageBottomBackground = bottom
        isSubpage = (body["sub"] as? Bool) ?? false
        applyChrome()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationState = .connecting
    }

    /// HTTP 错误状态（4xx/5xx）下 didFinish 仍会触发，空错误页会呈现为白屏。
    /// 主框架非 2xx 直接转失效态走重扫/重试引导，避免"假连接白屏"。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           !(200...399).contains(http.statusCode) {
            navigationState = .failed
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// 网页内容进程被系统回收（长时间后台、内存压力）时 WebView 会变纯白且不自恢复。
    /// 重载当前地址复活页面；无地址可载则转失效态走重扫引导。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let urlString = loadedURLString {
            load(urlString, in: webView)
        } else {
            navigationState = .failed
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl?.endRefreshing()
        navigationState = .connected
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl?.endRefreshing()
        navigationState = .failed
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 用户主动取消（如重新加载打断旧请求）不算失效
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        refreshControl?.endRefreshing()
        navigationState = .failed
    }
}

/// 远控页 WebView 封装。WebView 由 IOSZCodeRemoteSessionController 持有并跨页面进出复用；
/// 页面内不展示地址（无地址栏、关闭链接预览），失效靠导航错误回调上报。
struct IOSZCodeRemoteWebView: UIViewRepresentable {
    let urlString: String
    var reloadToken: Int = 0

    func makeUIView(context: Context) -> WKWebView {
        IOSZCodeRemoteSessionController.shared.viewFor(urlString: urlString, reloadToken: reloadToken)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        IOSZCodeRemoteSessionController.shared.handleUpdate(urlString: urlString, reloadToken: reloadToken)
    }
}
