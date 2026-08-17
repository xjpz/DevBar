import SwiftUI
import UIKit
import DevBarCore

/// 工具页「ZCode 远控」主页：未配对显示引导，已配对进入全屏远控页。
/// 远控页隐藏导航栏、不展示任何链接地址；失效靠导航错误回调进入失效态。
struct IOSZCodeRemoteView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @StateObject private var connectionStore = IOSZCodeRemoteConnectionStore()
    // WebView 与主题/导航状态由会话控制器持有，返回其他页面后仍保留，重进免重新加载
    @ObservedObject private var session = IOSZCodeRemoteSessionController.shared
    @State private var reloadToken = 0
    @State private var isShowingScanner = false
    @State private var scannerStartsWithPaste = false
    @State private var isConfirmingDisconnect = false
    @State private var isChromeVisible = false
    @State private var chromeAutoHideTask: Task<Void, Never>?

    private var isPaired: Bool {
        connectionStore.connectionURLString != nil
    }

    /// 沉浸期间的状态栏/指示条方案：页面为系统默认模式时不干预（跟随 iPhone），
    /// 否则钉在页面实际主题上，保证状态栏文字与页面底色对比正确。
    private var immersiveColorScheme: ColorScheme? {
        guard isPaired, !session.pageUsesSystemTheme else { return nil }
        return session.pageIsDark ? .dark : .light
    }

    private var chromeForeground: Color {
        session.pageIsDark ? .white : .black
    }

    private var chromeForegroundSecondary: Color {
        session.pageIsDark ? .white.opacity(0.75) : .black.opacity(0.7)
    }

    var body: some View {
        ZStack {
            if let urlString = connectionStore.connectionURLString {
                remoteContent(urlString: urlString)
            } else {
                guideContent
            }
        }
        .navigationTitle("ios_zcode_remote_title")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(isPaired ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek ? .dark : nil, for: .navigationBar)
        // 状态栏/Home 指示条颜色跟随远控页面主题，实现整体沉浸
        .preferredColorScheme(immersiveColorScheme)
        .sheet(isPresented: $isShowingScanner) {
            IOSZCodeRemoteScannerSheet(startsWithPaste: scannerStartsWithPaste) { link in
                connectionStore.save(link.url.absoluteString)
                reloadToken += 1
            }
        }
        .confirmationDialog(
            "ios_zcode_remote_disconnect_confirm",
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("ios_zcode_remote_menu_disconnect", role: .destructive) {
                connectionStore.clear()
                session.teardown()
                reloadToken = 0
            }
            Button("ios_common_cancel", role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in
            // 回前台且上次加载失败时自动重试一次（地址可能已恢复可用）
            guard phase == .active, session.navigationState == .failed else { return }
            reloadToken += 1
        }
        .onChange(of: session.navigationState) { _, state in
            if state == .failed {
                showChrome(pinned: true)
            }
        }
        .onChange(of: session.isSubpage) { _, isSubpage in
            // 进入二级页面立即收起悬浮控制；返回一级页面恢复点按唤出
            if isSubpage {
                hideChrome()
            }
        }
        .onDisappear {
            chromeAutoHideTask?.cancel()
        }
    }

    // MARK: - 已配对（全屏远控）

    private func remoteContent(urlString: String) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack {
                    IOSZCodeRemoteWebView(
                        urlString: urlString,
                        reloadToken: reloadToken
                    )
                    .ignoresSafeArea()
                    // 点按 WebView 任意处唤出/收起悬浮控制；simultaneous 保证网页点击不被拦截
                    .simultaneousGesture(TapGesture().onEnded {
                        toggleChrome()
                    })

                    VStack(spacing: 0) {
                        if isChromeVisible {
                            HStack(alignment: .top) {
                                floatingBackButton

                                Spacer(minLength: 12)

                                floatingMenuButton
                            }
                            .padding(.horizontal, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Spacer()
                    }

                    switch session.navigationState {
                    case .connecting:
                        connectingOverlay
                    case .failed:
                        expiredOverlay
                    case .idle, .connected:
                        EmptyView()
                    }
                }

                // 底部出血带：与页面最底栏底色对齐（顶栏与最底栏不同色，需单独对色）。
                // 容器整体 ignoresSafeArea 下沉到物理底边，色带垫在 VStack 末尾即恰好覆盖安全区
                if proxy.safeAreaInsets.bottom > 0, let bottomColor = session.pageBottomBackground {
                    Rectangle()
                        .fill(Color(bottomColor))
                        .frame(height: proxy.safeAreaInsets.bottom)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background {
                // 导航栏隐藏后系统默认禁用边缘返回手势，这里重新启用
                IOSNavigationPopGestureEnabler()
                    .frame(width: 0, height: 0)
            }
        }
    }

    private func toggleChrome() {
        // 远控页内部二级页面（网页自带返回导航）不显示悬浮控制；失效态除外
        if session.isSubpage && session.navigationState != .failed {
            hideChrome()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible.toggle()
        }
        chromeAutoHideTask?.cancel()
        if isChromeVisible {
            scheduleChromeAutoHide()
        }
    }

    /// pinned = true 时不自动隐藏（如菜单打开、失效态）
    private func showChrome(pinned: Bool) {
        if session.isSubpage && session.navigationState != .failed { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible = true
        }
        chromeAutoHideTask?.cancel()
        if !pinned {
            scheduleChromeAutoHide()
        }
    }

    private func hideChrome() {
        chromeAutoHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            isChromeVisible = false
        }
    }

    private func scheduleChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible = false
            }
        }
    }

    private var floatingBackButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(chromeForeground)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ios_common_back")
    }

    private var floatingMenuButton: some View {
        Menu {
            Button {
                reloadToken += 1
            } label: {
                Label("ios_zcode_remote_menu_refresh", systemImage: "arrow.clockwise")
            }

            Button {
                scannerStartsWithPaste = false
                isShowingScanner = true
            } label: {
                Label("ios_zcode_remote_rescan", systemImage: "qrcode")
            }

            if let urlString = connectionStore.connectionURLString,
               let url = URL(string: urlString) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("ios_zcode_remote_menu_safari", systemImage: "safari")
                }
            }

            Button(role: .destructive) {
                isConfirmingDisconnect = true
            } label: {
                Label("ios_zcode_remote_menu_disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(chromeForeground)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        // 菜单打开期间钉住控制条，避免 3 秒计时把按钮藏掉
        .simultaneousGesture(TapGesture().onEnded {
            showChrome(pinned: true)
        })
        .accessibilityLabel("ios_zcode_remote_menu_more")
    }

    private var connectingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(chromeForeground)
                .scaleEffect(1.2)
            Text("ios_zcode_remote_status_connecting")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(chromeForegroundSecondary)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var expiredOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(chromeForeground.opacity(0.9))

            Text("ios_zcode_remote_expired_title")
                .font(.headline.weight(.semibold))
                .foregroundStyle(chromeForeground)

            Text("ios_zcode_remote_expired_detail")
                .font(.subheadline)
                .foregroundStyle(chromeForegroundSecondary)
                .multilineTextAlignment(.center)

            Button {
                scannerStartsWithPaste = false
                isShowingScanner = true
            } label: {
                Label("ios_zcode_remote_rescan", systemImage: "qrcode")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(session.pageIsDark ? .white.opacity(0.16) : .black.opacity(0.1), in: Capsule())
                    .foregroundStyle(chromeForeground)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(20)
    }

    // MARK: - 未配对引导

    private var guideContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 14) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(theme.brandPrimary)
                    .frame(width: 84, height: 84)
                    .background(theme.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text("ios_zcode_remote_guide_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                guideStep(number: 1, text: String(localized: "ios_zcode_remote_guide_step1"))
                guideStep(number: 2, text: String(localized: "ios_zcode_remote_guide_step2"))
                guideStep(number: 3, text: String(localized: "ios_zcode_remote_guide_step3"))
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    scannerStartsWithPaste = false
                    isShowingScanner = true
                } label: {
                    Label("ios_zcode_remote_scan_button", systemImage: "qrcode.viewfinder")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    scannerStartsWithPaste = true
                    isShowingScanner = true
                } label: {
                    Label("ios_zcode_remote_paste_button", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(theme.brandPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 26, height: 26)
                .background(theme.brandPrimary.opacity(0.12), in: Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
