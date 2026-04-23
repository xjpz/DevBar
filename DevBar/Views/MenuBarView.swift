// MenuBarView.swift
// DevBar

import SwiftUI
import DevBarCore

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
            Text("loading")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var loginView: some View {
        LoginView(isExpired: appViewModel.authState == .expired)
    }
}

private struct LoggedInContentView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel
    @EnvironmentObject private var openAIQuotaViewModel: OpenAIQuotaViewModel
    @EnvironmentObject private var updateViewModel: UpdateViewModel
    @State private var selectedProvider: QuotaProvider = .glm

    private var enabledProviders: [QuotaProvider] {
        appViewModel.enabledProviders
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Provider tabs (only show if multiple providers enabled)
            if enabledProviders.count > 1 {
                providerTabs
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            // Content area
            if selectedProvider == .glm {
                glmContent
            } else {
                openAIContent
            }

            Divider()

            footerView
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .onAppear {
            // Default to first enabled provider
            if let first = enabledProviders.first {
                selectedProvider = first
            }
        }
        .onChange(of: enabledProviders) { _, newProviders in
            if !newProviders.contains(selectedProvider), let first = newProviders.first {
                selectedProvider = first
            }
        }
    }

    // MARK: - Provider Tabs

    private var providerTabs: some View {
        HStack(spacing: 8) {
            ForEach(enabledProviders, id: \.self) { provider in
                Button(action: { selectedProvider = provider }) {
                    Text(provider.localizedName)
                        .font(.caption)
                        .fontWeight(selectedProvider == provider ? .semibold : .regular)
                        .foregroundStyle(selectedProvider == provider ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedProvider == provider ? Color.accentColor.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DevBar")
                    .font(.headline)

                if enabledProviders.count == 1 {
                    Text(selectedProvider.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if selectedProvider == .glm && quotaViewModel.isLoading
                || selectedProvider == .openai && openAIQuotaViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: {
                Task { await appViewModel.refreshQuota() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("refresh")

            Button(action: {
                appViewModel.showSettings()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                    if updateViewModel.hasUpdateAvailable {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.borderless)
            .help("settings")
        }
    }

    // MARK: - GLM Content

    private var glmContent: some View {
        Group {
            if !appViewModel.hasAuthenticatedSession(for: .glm) {
                providerConfigureView(
                    icon: nil,
                    hint: String(localized: "glm_configure_hint")
                )
            } else if quotaViewModel.isLoading && quotaViewModel.quotaData == nil {
                ProgressView("fetching_usage")
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
                Text("no_data")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - OpenAI Content

    private var openAIContent: some View {
        Group {
            if openAIQuotaViewModel.isLoading && openAIQuotaViewModel.usageResponse == nil {
                ProgressView("fetching_usage")
                    .padding()
            } else if let error = openAIQuotaViewModel.errorMessage {
                errorView(error)
            } else if !openAIQuotaViewModel.quotaRows.isEmpty {
                openAIQuotaListView
            } else {
                providerConfigureView(
                    icon: "circle.hexagon",
                    hint: String(localized: "openai_configure_hint")
                )
            }
        }
    }

    private var openAIQuotaListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let planType = openAIQuotaViewModel.planType {
                levelBadge(planType.capitalized)
            }

            if openAIQuotaViewModel.isLimitReached {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(String(localized: "openai_limit_reached"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(openAIQuotaViewModel.quotaRows) { row in
                QuotaRowItemView(item: row)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Shared Views

    private var noSubscriptionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("no_subscription")
                .font(.headline)
            Text("go_subscribe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func providerConfigureView(icon: String?, hint: String) -> some View {
        VStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "go_settings")) {
                appViewModel.showSettings(select: .accounts)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    private func quotaListView(limits: [QuotaLimit], level: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lvl = level {
                levelBadge(lvl)
            }

            let sorted = limits.sorted { a, b in
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

    private func renewalInfo(sub: DevBarCore.Subscription) -> some View {
        HStack {
            Text("subscription_ends")
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
        Text(level)
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
            Button("retry") {
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
            Button(action: { appViewModel.logout(provider: selectedProvider) }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("log_out")
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
                    Text("quit")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
