import DevBarCore
import SwiftUI

struct IOSDashboardView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme
    @State private var isShowingAccounts = false
    @State private var isShowingScanner = false
    @State private var isResolvingScan = false
    @State private var pendingImportPreview: TransferImportPreview?
    @State private var pendingRelayTransferURL: URL?
    @State private var scanError: String?

    var body: some View {
        ZStack {
            Color.clear
                .iosGeekScreenBackground(theme)

            List {
                Section {
                    overviewCard
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(appViewModel.enabledProviders, id: \.self) { provider in
                        providerCard(provider)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .id("dashboard.list.\(languageManager.selectedLanguage.rawValue)")
        .navigationTitle(Text("ios_dashboard_title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingScanner = true
                } label: {
                    Label("扫一扫", systemImage: "qrcode.viewfinder")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("ios.dashboard.scan")

                NavigationLink {
                    IOSAccountsView()
                } label: {
                    Label("ios_tab_accounts", systemImage: "person.badge.key.fill")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("ios.dashboard.accounts")

                NavigationLink {
                    IOSSettingsView()
                } label: {
                    Label("ios_tab_settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("ios.dashboard.settings")
            }
        }
        .toolbarBackground(theme.backgroundPrimary, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .accessibilityIdentifier("ios.dashboard.screen")
        .navigationDestination(isPresented: $isShowingAccounts) {
            IOSAccountsView()
        }
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                IOSQRScannerView { code in
                    isShowingScanner = false
                    Task {
                        await handleScannedCode(code)
                    }
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ios_common_cancel") {
                            isShowingScanner = false
                        }
                    }
                }
            }
        }
        .sheet(item: $pendingImportPreview) { preview in
            IOSTransferImportPreviewSheet(preview: preview) {
                await importPayload(preview.payload)
            }
        }
        .alert("ios_accounts_import_failed", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("ios_common_ok", role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
        .overlay {
            if isResolvingScan {
                ProgressView("正在读取二维码...")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .refreshable {
            await appViewModel.refreshAll()
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(themeManager.developerGreeting)
                .font(theme.bodyMonoFont)
                .foregroundStyle(theme.isGeek ? theme.info : theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.isGeek ? theme.info.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .accessibilityIdentifier("ios.dashboard.overviewCard")
    }

    @ViewBuilder
    private func providerCard(_ provider: QuotaProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    providerArtwork(for: provider)
                    Text(provider.localizedName)
                        .font(theme.isGeek ? .system(.headline, design: .monospaced) : .headline)
                        .lineLimit(1)
                        .layoutPriority(1)
                    providerBadge(for: provider)
                }
                Spacer()
                Text(lastRefreshText(for: provider))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }

            switch provider {
            case .glm:
                glmContent
            case .openai:
                openAIContent
            case .mimo:
                mimoContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 18)
    }

    @ViewBuilder
    private func providerBadge(for provider: QuotaProvider) -> some View {
        let text: String? = switch provider {
        case .glm:
            appViewModel.quotaViewModel.quotaData?.level
        case .openai:
            appViewModel.openAIQuotaViewModel.planType.map { $0.capitalized }
        case .mimo:
            appViewModel.mimoQuotaViewModel.planName
        }
        if let text {
            badge(text)
        }
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.accentColor.opacity(theme.providerPlateOpacity))

            Image(provider.assetName)
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .frame(width: 36, height: 36)
    }

    private func lastRefreshText(for provider: QuotaProvider) -> String {
        let date: Date? = switch provider {
        case .glm:
            appViewModel.quotaViewModel.lastUpdated
        case .openai:
            appViewModel.openAIQuotaViewModel.lastUpdated
        case .mimo:
            appViewModel.mimoQuotaViewModel.lastUpdated
        }

        guard let date else {
            return localized("ios_dashboard_no_refresh")
        }

        return String(
            format: localized("ios_dashboard_last_updated"),
            themeManager.formatTime(date: date)
        )
    }

    @ViewBuilder
    private var glmContent: some View {
        if !appViewModel.hasAuthenticatedSession(for: .glm) {
            configurePrompt(localized("ios_dashboard_glm_configure_prompt"))
        } else if appViewModel.quotaViewModel.hasValidSubscription,
                  let limits = appViewModel.quotaViewModel.quotaData?.limits,
                  !limits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let error = appViewModel.quotaViewModel.errorMessage {
                    refreshWarning(error)
                }
                ForEach(sortedGLMLimits(limits)) { limit in
                    UsageLimitRow(
                        title: glmLimitTitle(limit),
                        percentage: limit.percentage,
                        resetText: glmLimitResetText(limit),
                        detailText: nil,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.quotaViewModel.isLoading && appViewModel.quotaViewModel.quotaData == nil {
            ProgressView("ios_dashboard_glm_loading")
        } else if let error = appViewModel.quotaViewModel.errorMessage {
            errorState(error)
        } else if !appViewModel.quotaViewModel.hasValidSubscription {
            Text("ios_dashboard_glm_no_subscription")
                .foregroundStyle(theme.textSecondary)
        } else {
            Text("ios_dashboard_glm_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var openAIContent: some View {
        if !appViewModel.hasAuthenticatedSession(for: .openai) {
            configurePrompt(localized("ios_dashboard_openai_configure_prompt"))
        } else if !appViewModel.openAIQuotaViewModel.quotaRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let error = appViewModel.openAIQuotaViewModel.errorMessage {
                    refreshWarning(error)
                }
                ForEach(openAIUsageRows) { row in
                    UsageLimitRow(
                        title: row.name,
                        percentage: row.percentage,
                        resetText: row.resetTime,
                        detailText: nil,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.openAIQuotaViewModel.isLoading && appViewModel.openAIQuotaViewModel.usageResponse == nil {
            ProgressView("ios_dashboard_openai_loading")
        } else if let error = appViewModel.openAIQuotaViewModel.errorMessage {
            errorState(error)
        } else {
            Text("ios_dashboard_openai_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var mimoContent: some View {
        if !appViewModel.hasAuthenticatedSession(for: .mimo) {
            configurePrompt(localized("ios_dashboard_mimo_configure_prompt"))
        } else if !appViewModel.mimoQuotaViewModel.quotaRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let error = appViewModel.mimoQuotaViewModel.errorMessage {
                    refreshWarning(error)
                }

                if let currentPeriodEnd = appViewModel.mimoQuotaViewModel.currentPeriodEnd {
                    Text(String(format: localized("mimo_plan_expire_at"), formattedDateTime(from: currentPeriodEnd.timeIntervalSince1970)))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }

                ForEach(appViewModel.mimoQuotaViewModel.quotaRows) { row in
                    UsageLimitRow(
                        title: row.name,
                        percentage: row.percentage,
                        resetText: row.resetTime,
                        detailText: row.unitDescription,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.mimoQuotaViewModel.isLoading && appViewModel.mimoQuotaViewModel.usageResponse == nil {
            ProgressView("ios_dashboard_mimo_loading")
        } else if let error = appViewModel.mimoQuotaViewModel.errorMessage {
            errorState(error)
        } else {
            Text("ios_dashboard_mimo_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func configurePrompt(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .foregroundStyle(theme.textSecondary)
            Button("ios_dashboard_open_accounts") {
                isShowingAccounts = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
            Button("ios_dashboard_retry") {
                Task { await appViewModel.refreshAll() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func refreshWarning(_ message: String) -> some View {
        Label(message, systemImage: "arrow.triangle.2.circlepath.circle")
            .font(theme.captionFont)
            .foregroundStyle(theme.warning)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(theme.captionWeightFont)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.surfaceSecondary, in: Capsule())
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }

    private var openAIUsageRows: [LocalizedUsageRow] {
        guard let rateLimit = appViewModel.openAIQuotaViewModel.usageResponse?.rateLimit else { return [] }

        var rows: [LocalizedUsageRow] = []

        if let primary = rateLimit.primaryWindow {
            rows.append(
                LocalizedUsageRow(
                    name: openAIWindowTitle(primary),
                    percentage: primary.usedPercent,
                    resetTime: openAIWindowResetText(primary)
                )
            )
        }

        if let secondary = rateLimit.secondaryWindow {
            rows.append(
                LocalizedUsageRow(
                    name: openAIWindowTitle(secondary),
                    percentage: secondary.usedPercent,
                    resetTime: openAIWindowResetText(secondary)
                )
            )
        }

        return rows
    }

    private func sortedGLMLimits(_ limits: [QuotaLimit]) -> [QuotaLimit] {
        limits.sorted { lhs, rhs in
            let leftPriority = glmLimitPriority(lhs)
            let rightPriority = glmLimitPriority(rhs)

            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func glmLimitPriority(_ limit: QuotaLimit) -> Int {
        switch (limit.type, limit.unit) {
        case ("TOKENS_LIMIT", 3):
            return 0
        case ("TOKENS_LIMIT", 6):
            return 1
        case ("TIME_LIMIT", _):
            return 2
        default:
            return 99
        }
    }

    private func refreshSummaryText(_ trigger: IOSAppViewModel.RefreshTrigger) -> String {
        switch trigger {
        case .launch:
            return localized("ios_refresh_initial")
        case .foreground:
            return localized("ios_refresh_auto")
        case .manual:
            return localized("ios_refresh_manual")
        case .importTransfer:
            return localized("ios_refresh_after_import")
        }
    }

    private func glmLimitTitle(_ limit: QuotaLimit) -> String {
        switch (limit.type, limit.unit) {
        case ("TOKENS_LIMIT", 3):
            return String(format: localized("glm_session_quota"), limit.number ?? 5)
        case ("TOKENS_LIMIT", 6):
            return localized("glm_weekly_quota")
        case ("TIME_LIMIT", _):
            return localized("mcp_monthly_quota")
        default:
            return limit.type
        }
    }

    private func glmLimitResetText(_ limit: QuotaLimit) -> String? {
        guard let nextResetTime = limit.nextResetTime else { return nil }
        return formattedDateTime(from: TimeInterval(nextResetTime) / 1000)
    }

    private func openAIWindowTitle(_ window: OpenAIUsageWindow) -> String {
        guard let seconds = window.limitWindowSeconds else { return "" }
        let hours = seconds / 3600

        if hours >= 168 {
            return localized("openai_weekly")
        } else if hours >= 24 {
            return localized("openai_daily")
        } else {
            return String(format: localized("openai_session"), hours)
        }
    }

    private func openAIWindowResetText(_ window: OpenAIUsageWindow) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        return formattedDateTime(from: TimeInterval(resetAt))
    }

    private func formattedDateTime(from timestamp: TimeInterval) -> String {
        themeManager.formatTime(date: Date(timeIntervalSince1970: timestamp), dateStyle: .numeric)
    }

    @MainActor
    private func handleScannedCode(_ code: String) async {
        scanError = nil
        isResolvingScan = true
        defer { isResolvingScan = false }

        do {
            switch try await appViewModel.resolveScannedCode(code) {
            case .macPaired:
                pendingRelayTransferURL = nil
            case let .providerTransfer(preview, relayURL):
                pendingRelayTransferURL = relayURL
                pendingImportPreview = preview
            }
        } catch {
            pendingRelayTransferURL = nil
            scanError = error.localizedDescription
        }
    }

    private func importPayload(_ payload: TransferPayload) async {
        do {
            try await appViewModel.importTransferPayload(payload)
            pendingImportPreview = nil
            if let pendingRelayTransferURL {
                try? await TransferRelayService.shared.deleteRelayTransfer(from: pendingRelayTransferURL)
                self.pendingRelayTransferURL = nil
            }
        } catch {
            scanError = error.localizedDescription
        }
    }
}

private struct UsageLimitRow: View {
    let title: String
    let percentage: Int
    let resetText: String?
    let detailText: String?
    let locale: Locale
    @Environment(\.themeTokens) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(theme.subheadlineWeightFont)
                Spacer()
                Text(String(format: String(localized: "ios_dashboard_percent_format", locale: locale), locale: locale, percentage))
                    .font(theme.isGeek ? .system(.subheadline, design: .monospaced).monospacedDigit().weight(.semibold) : .subheadline.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: Double(percentage), total: 100)
                .tint(progressColor)

            if let resetText {
                Text(String(format: String(localized: "ios_dashboard_reset_at", locale: locale), locale: locale, resetText))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }

            if let detailText {
                Text(detailText)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var progressColor: Color {
        switch percentage {
        case ..<50: return theme.progressSuccess
        case 50..<80: return theme.progressWarning
        default: return theme.progressDanger
        }
    }
}

private struct LocalizedUsageRow: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Int
    let resetTime: String?
}
