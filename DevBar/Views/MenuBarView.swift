// MenuBarView.swift
// DevBar

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel

    var body: some View {
        Group {
            if appViewModel.authState == .loggedIn {
                LoggedInContentView()
            } else if appViewModel.authState == .loading {
                loadingView
            } else {
                loginView
            }
        }
        .frame(width: Constants.UI.popoverWidth)
        .onAppear {
            appViewModel.checkForUpdatesOnFirstAppear()
            appViewModel.refreshOnPopoverOpenIfNeeded()
        }
        .onChange(of: appViewModel.authState) { _, newState in
            if newState != .loggedIn {
                appViewModel.stopAutoRefresh()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("加载中...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loginView: some View {
        LoginView(
            isExpired: appViewModel.authState == .expired,
            onLoginSuccess: { credentials in
                appViewModel.handleLoginSuccess(credentials)
            }
        )
    }
}

private struct LoggedInContentView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if quotaViewModel.isLoading && quotaViewModel.quotaData == nil {
                ProgressView("获取用量...")
                    .padding()
            } else if !quotaViewModel.hasValidSubscription {
                noSubscriptionView
            } else if let data = quotaViewModel.quotaData,
                      let limits = data.limits,
                      !limits.isEmpty {
                quotaListView(limits: limits, level: data.level)
            } else if let error = quotaViewModel.errorMessage {
                errorView(error)
            } else {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()

            footerView
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DevBar")
                    .font(.headline)
                if let sub = quotaViewModel.subscription {
                    Text("\(sub.productName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if quotaViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: {
                Task { await appViewModel.refreshQuota() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")

            Button(action: {
                appViewModel.showSettings()
            }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
    }

    // MARK: - Content Views

    private var noSubscriptionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("没有可用套餐")
                .font(.headline)
            Text("请前往 BigModel 官网订阅")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func quotaListView(limits: [QuotaLimit], level: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lvl = level {
                levelBadge(lvl)
            }

            let sorted = limits.sorted { a, b in
                // Day (unit=3) → Week (unit=6) → Month (TIME_LIMIT)
                let order = { (l: QuotaLimit) -> Int in
                    switch l.type {
                    case "TOKENS_LIMIT": return l.unit == 3 ? 0 : 1
                    case "TIME_LIMIT": return 2
                    default: return 3
                    }
                }
                return order(a) < order(b)
            }
            ForEach(sorted) { limit in
                QuotaRowView(limit: limit)
            }

            if let sub = quotaViewModel.subscription {
                renewalInfo(sub: sub)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func renewalInfo(sub: Subscription) -> some View {
        HStack {
            Text("订阅截止")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(sub.formattedNextRenewDate)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(sub.formattedRenewPrice)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func levelBadge(_ level: String) -> some View {
        Text(level.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await appViewModel.refreshQuota() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 0) {
            Button(action: { appViewModel.logout() }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("退出登录")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Divider()
                .frame(height: 20)

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("退出")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
