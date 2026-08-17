import DevBarCore
import SwiftUI

struct IOSDashboardView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    @Environment(\.themeTokens) private var theme
    @State private var isShowingAccounts = false
    @State private var isShowingScanner = false
    @State private var isResolvingScan = false
    @State private var pendingImportPreview: TransferImportPreview?
    @State private var pendingAccountBinding: DeviceAccountBindScan?
    @State private var pendingRelayTransferURL: URL?
    @State private var scanError: String?
    @State private var handledScanRequestID: UUID?

    var body: some View {
        ZStack {
            dashboardPageBackground
                .ignoresSafeArea()

            List {
                Section {
                    overviewCard
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(appViewModel.enabledProviders, id: \.self) { provider in
                        providerCard(provider)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        .navigationTitle("ios_tab_overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dashboardNavigationBackground, for: .navigationBar)
        .toolbarBackground(theme.isGeek ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek ? .dark : nil, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }

            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    IOSProfileView()
                } label: {
                    IOSProfileEntryAvatar(
                        avatarData: appViewModel.macThemeWidgetAvatarData,
                        unreadCount: accountViewModel.unreadCount
                    )
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .accessibilityIdentifier("ios.dashboard.profile")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingScanner = true
                } label: {
                    Label("ios_dashboard_scan_qr", systemImage: "qrcode.viewfinder")
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
        .toolbarBackground(theme.isGeek ? .black : theme.backgroundPrimary, for: .tabBar)
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
        .sheet(item: $pendingAccountBinding) { scan in
            IOSAccountBindingConfirmationSheet(
                scan: scan,
                relayManager: appViewModel.deviceRelayManager
            )
        }
        .alert("二维码处理失败", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("ios_common_ok", role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
        .overlay {
            if isResolvingScan {
                ProgressView("ios_dashboard_reading_qr")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .refreshable {
            await appViewModel.refreshAll()
        }
        .onAppear {
            openScannerIfRequested()
        }
        .onChange(of: appViewModel.dashboardScanRequestID) { _, _ in
            openScannerIfRequested()
        }
    }

    private var dashboardPageBackground: Color {
        theme.isGeek ? .black : theme.backgroundSecondary
    }

    private var dashboardNavigationBackground: Color {
        theme.isGeek ? .black : .clear
    }

    private var overviewCard: some View {
        Text(themeManager.developerGreeting)
            .font(theme.isGeek ? theme.bodyMonoFont : .system(.body, design: .monospaced).weight(.medium))
            .lineSpacing(theme.isGeek ? 1 : 3)
            .foregroundStyle(theme.isGeek ? theme.info : theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .dashboardOverviewSurface(theme: theme, cornerRadius: 18)
        .accessibilityIdentifier("ios.dashboard.overviewCard")
    }

    @ViewBuilder
    private func providerCard(_ provider: QuotaProvider) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeader(provider)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.isGeek ? Color.clear : theme.backgroundPrimary.opacity(0.58))

            Divider()
                .overlay(theme.borderSubtle.opacity(theme.isGeek ? 0.45 : 0.82))

            Group {
                switch provider {
                case .glm:
                    glmContent
                case .openai:
                    openAIContent
                case .mimo:
                    mimoContent
                case .deepseek:
                    deepSeekContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardProviderSurface(theme: theme, cornerRadius: 18)
    }

    private func providerHeader(_ provider: QuotaProvider) -> some View {
        HStack(spacing: 8) {
            providerArtwork(for: provider)
            Text(provider.localizedName)
                .font(theme.isGeek ? .system(.headline, design: .monospaced) : .headline)
                .lineLimit(1)
                .layoutPriority(2)
            providerBadge(for: provider)
            Spacer(minLength: 6)
            Text(lastRefreshText(for: provider))
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    @ViewBuilder
    private func providerBadge(for provider: QuotaProvider) -> some View {
        let text: String? = switch provider {
        case .glm:
            if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .glm, localLastUpdated: appViewModel.quotaViewModel.lastUpdated) {
                snapshot.level
            } else {
                appViewModel.quotaViewModel.quotaData?.level ?? appViewModel.syncedQuotaSnapshot(for: .glm)?.level
            }
        case .openai:
            if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .openai, localLastUpdated: appViewModel.openAIQuotaViewModel.lastUpdated) {
                snapshot.level
            } else {
                appViewModel.openAIQuotaViewModel.planType ?? appViewModel.syncedQuotaSnapshot(for: .openai)?.level
            }
        case .mimo:
            if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .mimo, localLastUpdated: appViewModel.mimoQuotaViewModel.lastUpdated) {
                snapshot.subscriptionName
            } else {
                appViewModel.mimoQuotaViewModel.planName ?? appViewModel.syncedQuotaSnapshot(for: .mimo)?.subscriptionName
            }
        case .deepseek:
            if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .deepseek, localLastUpdated: appViewModel.deepSeekQuotaViewModel.lastUpdated) {
                snapshot.subscriptionName
            } else {
                appViewModel.deepSeekQuotaViewModel.balanceText ?? appViewModel.syncedQuotaSnapshot(for: .deepseek)?.subscriptionName
            }
        }
        if let text {
            badge(text)
        }
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.accentColor.opacity(theme.providerPlateOpacity))

            Image(iosAssetName(for: provider))
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .frame(width: 36, height: 36)
    }

    private func iosAssetName(for provider: QuotaProvider) -> String {
        provider.assetName
    }

    private func lastRefreshText(for provider: QuotaProvider) -> String {
        let localDate: Date? = switch provider {
        case .glm:
            appViewModel.quotaViewModel.lastUpdated
        case .openai:
            appViewModel.openAIQuotaViewModel.lastUpdated
        case .mimo:
            appViewModel.mimoQuotaViewModel.lastUpdated
        case .deepseek:
            appViewModel.deepSeekQuotaViewModel.lastUpdated
        }
        let date = appViewModel.preferredSyncedQuotaSnapshot(for: provider, localLastUpdated: localDate)?.fetchedAt
            ?? localDate
            ?? appViewModel.syncedQuotaSnapshot(for: provider)?.fetchedAt

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
        if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .glm, localLastUpdated: appViewModel.quotaViewModel.lastUpdated) {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.quotaViewModel.errorMessage)
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
                        resetDate: glmLimitResetDate(limit),
                        detailText: nil,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.quotaViewModel.isLoading && appViewModel.quotaViewModel.quotaData == nil {
            ProgressView("ios_dashboard_glm_loading")
        } else if let snapshot = appViewModel.syncedQuotaSnapshot(for: .glm), !snapshot.limits.isEmpty {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.quotaViewModel.errorMessage)
        } else if !appViewModel.hasAuthenticatedSession(for: .glm) {
            configurePrompt(localized("ios_dashboard_glm_configure_prompt"))
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
        if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .openai, localLastUpdated: appViewModel.openAIQuotaViewModel.lastUpdated) {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.openAIQuotaViewModel.errorMessage)
        } else if !appViewModel.openAIQuotaViewModel.quotaRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let error = appViewModel.openAIQuotaViewModel.errorMessage {
                    refreshWarning(error)
                }
                if let availableResetCount = appViewModel.openAIQuotaViewModel.availableResetCount,
                   availableResetCount > 0 {
                    resetCreditsRow(availableResetCount)
                }
                ForEach(openAIUsageRows) { row in
                    UsageLimitRow(
                        title: localizedQuotaTitle(row.name, provider: .openai),
                        percentage: row.percentage,
                        resetText: row.resetTime,
                        resetDate: row.resetDate,
                        detailText: nil,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.openAIQuotaViewModel.isLoading && appViewModel.openAIQuotaViewModel.usageResponse == nil {
            ProgressView("ios_dashboard_openai_loading")
        } else if let snapshot = appViewModel.syncedQuotaSnapshot(for: .openai), !snapshot.limits.isEmpty {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.openAIQuotaViewModel.errorMessage)
        } else if !appViewModel.hasAuthenticatedSession(for: .openai) {
            configurePrompt(localized("ios_dashboard_openai_configure_prompt"))
        } else if let error = appViewModel.openAIQuotaViewModel.errorMessage {
            errorState(error)
        } else {
            Text("ios_dashboard_openai_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var mimoContent: some View {
        if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .mimo, localLastUpdated: appViewModel.mimoQuotaViewModel.lastUpdated) {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.mimoQuotaViewModel.errorMessage)
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
                        title: localizedQuotaTitle(row.name, provider: .mimo),
                        percentage: row.percentage,
                        resetText: compactResetText(row.resetTime),
                        detailText: row.unitDescription,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.mimoQuotaViewModel.isLoading && appViewModel.mimoQuotaViewModel.usageResponse == nil {
            ProgressView("ios_dashboard_mimo_loading")
        } else if let snapshot = appViewModel.syncedQuotaSnapshot(for: .mimo), !snapshot.limits.isEmpty {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.mimoQuotaViewModel.errorMessage)
        } else if !appViewModel.hasAuthenticatedSession(for: .mimo) {
            configurePrompt(localized("ios_dashboard_mimo_configure_prompt"))
        } else if let error = appViewModel.mimoQuotaViewModel.errorMessage {
            errorState(error)
        } else {
            Text("ios_dashboard_mimo_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var deepSeekContent: some View {
        if let snapshot = appViewModel.preferredSyncedQuotaSnapshot(for: .deepseek, localLastUpdated: appViewModel.deepSeekQuotaViewModel.lastUpdated) {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.deepSeekQuotaViewModel.errorMessage)
        } else if !appViewModel.deepSeekQuotaViewModel.quotaRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let error = appViewModel.deepSeekQuotaViewModel.errorMessage {
                    refreshWarning(error)
                }

                if let balance = appViewModel.deepSeekQuotaViewModel.balanceText {
                    Text(balance)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }

                ForEach(appViewModel.deepSeekQuotaViewModel.quotaRows) { row in
                    UsageLimitRow(
                        title: localizedQuotaTitle(row.name, provider: .deepseek),
                        percentage: row.percentage,
                        resetText: compactResetText(row.resetTime),
                        detailText: row.unitDescription,
                        locale: languageManager.currentLocale
                    )
                }
            }
        } else if appViewModel.deepSeekQuotaViewModel.isLoading && appViewModel.deepSeekQuotaViewModel.usageResponse == nil {
            ProgressView("ios_dashboard_deepseek_loading")
        } else if let snapshot = appViewModel.syncedQuotaSnapshot(for: .deepseek), !snapshot.limits.isEmpty {
            syncedQuotaContent(snapshot, errorMessage: appViewModel.deepSeekQuotaViewModel.errorMessage)
        } else if !appViewModel.hasAuthenticatedSession(for: .deepseek) {
            configurePrompt(localized("ios_dashboard_deepseek_configure_prompt"))
        } else if let error = appViewModel.deepSeekQuotaViewModel.errorMessage {
            errorState(error)
        } else {
            Text("ios_dashboard_deepseek_no_usage")
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func syncedQuotaContent(
        _ snapshot: ProviderQuotaSnapshot,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                refreshWarning(errorMessage)
            }

            if let subscriptionExpireDate = snapshot.subscriptionExpireDate {
                Text(subscriptionExpireDate)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }

            if snapshot.provider == .openai,
               let availableResetCount = snapshot.availableResetCount,
               availableResetCount > 0 {
                resetCreditsRow(availableResetCount)
            }

            ForEach(snapshot.limits) { limit in
                UsageLimitRow(
                    title: localizedQuotaTitle(for: limit, provider: snapshot.provider),
                    percentage: limit.percentage,
                    resetText: compactResetText(limit.formattedResetTime),
                    detailText: limit.unitDescription,
                    locale: languageManager.currentLocale
                )
            }
        }
    }

    private func localizedQuotaTitle(_ rawTitle: String, provider: QuotaProvider) -> String {
        localizedQuotaTitle(
            for: WidgetQuotaLimit(
                type: rawTitle,
                displayName: rawTitle,
                percentage: 0,
                unitDescription: nil,
                formattedResetTime: nil
            ),
            provider: provider
        )
    }

    private func localizedQuotaTitle(for limit: WidgetQuotaLimit, provider: QuotaProvider) -> String {
        switch provider {
        case .glm:
            if WidgetQuotaPresentation.isFiveHourLimit(limit) {
                return String(format: localized("glm_session_quota"), firstInteger(in: limit.displayName) ?? 5)
            }
            if WidgetQuotaPresentation.isWeeklyLimit(limit) {
                return localized("glm_weekly_quota")
            }
            if WidgetQuotaPresentation.isMonthlyLimit(limit) || limit.type == "TIME_LIMIT" {
                return localized("mcp_monthly_quota")
            }
            if WidgetQuotaPresentation.isTokenLimit(limit) {
                return localized("token_quota")
            }
        case .openai:
            if WidgetQuotaPresentation.isFiveHourLimit(limit) {
                return String(format: localized("openai_session"), firstInteger(in: limit.displayName) ?? 5)
            }
            if WidgetQuotaPresentation.isWeeklyLimit(limit) {
                return localized("openai_weekly")
            }
            if WidgetQuotaPresentation.isMonthlyLimit(limit) {
                return localized("mcp_monthly_quota")
            }
        case .mimo:
            if WidgetQuotaPresentation.isMonthlyLimit(limit) || WidgetQuotaPresentation.isTokenLimit(limit) {
                return localized("mimo_monthly_token_quota")
            }
        case .deepseek:
            if WidgetQuotaPresentation.isCostLimit(limit) {
                return localized("deepseek_cost_usage")
            }
            if WidgetQuotaPresentation.isTokenLimit(limit) {
                return localized("deepseek_token_usage")
            }
        }

        return limit.displayName
    }

    private func firstInteger(in text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func resetCreditsRow(_ count: Int) -> some View {
        HStack(spacing: 0) {
            Text(openAIResetCreditsLabel)
                .foregroundStyle(theme.textSecondary)
            Text("\(count)")
                .foregroundStyle(theme.success)
                .fontWeight(.semibold)
        }
        .font(theme.captionFont)
    }

    private var openAIResetCreditsLabel: String {
        localized("openai_available_resets_label")
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
                    resetTime: openAIWindowResetText(primary),
                    resetDate: openAIWindowResetDate(primary)
                )
            )
        }

        if let secondary = rateLimit.secondaryWindow {
            rows.append(
                LocalizedUsageRow(
                    name: openAIWindowTitle(secondary),
                    percentage: secondary.usedPercent,
                    resetTime: openAIWindowResetText(secondary),
                    resetDate: openAIWindowResetDate(secondary)
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
        guard let resetDate = glmLimitResetDate(limit) else { return nil }
        return formattedResetDate(resetDate)
    }

    private func glmLimitResetDate(_ limit: QuotaLimit) -> Date? {
        limit.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
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
        guard let resetDate = openAIWindowResetDate(window) else { return nil }
        return formattedResetDate(resetDate)
    }

    private func openAIWindowResetDate(_ window: OpenAIUsageWindow) -> Date? {
        window.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private func formattedDateTime(from timestamp: TimeInterval) -> String {
        formattedResetDate(Date(timeIntervalSince1970: timestamp))
    }

    private func compactResetText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let date = parsedResetDate(from: text) else { return text }
        return formattedResetDate(date)
    }

    private func formattedResetDate(_ date: Date) -> String {
        let dateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(date) ? .omitted : .numeric
        return themeManager.formatTime(date: date, dateStyle: dateStyle)
    }

    private func parsedResetDate(from text: String) -> Date? {
        QuotaResetTimePresentation.resetDate(from: text)
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
            case let .accountBinding(scan):
                pendingRelayTransferURL = nil
                pendingAccountBinding = scan
            case let .providerTransfer(preview, relayURL):
                pendingRelayTransferURL = relayURL
                pendingImportPreview = preview
            }
        } catch {
            pendingRelayTransferURL = nil
            scanError = error.localizedDescription
        }
    }

    private func openScannerIfRequested() {
        guard let requestID = appViewModel.dashboardScanRequestID,
              handledScanRequestID != requestID else {
            return
        }
        handledScanRequestID = requestID
        isShowingScanner = true
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

private struct IOSAccountBindingConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme

    let scan: DeviceAccountBindScan
    let relayManager: DeviceRelayManager

    @State private var isConfirming = false
    @State private var confirmation: DeviceAccountBindConfirmation?
    @State private var errorMessage: String?

    private var isExpired: Bool {
        scan.preview.expiresAt <= Int64(Date().timeIntervalSince1970 * 1_000)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: confirmation == nil ? "iphone.and.arrow.forward" : "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(confirmation == nil ? theme.brandPrimary : .green)

                if let confirmation {
                    VStack(spacing: 8) {
                        Text("关联成功")
                            .font(.title2.bold())
                        Text("已关联 \(confirmation.claimedSnippets) 条历史 Snippet")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("关联开发吧账号")
                            .font(.title2.bold())
                        Text("将此 iPhone 关联到账号")
                            .foregroundStyle(theme.textSecondary)
                        Text(scan.preview.accountName)
                            .font(.title3.monospaced().bold())
                        Text(isExpired ? "二维码已过期" : "确认后，该设备的 Snippet 将显示在此账号中。")
                            .font(.footnote)
                            .foregroundStyle(isExpired ? .red : theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                if confirmation == nil {
                    Button {
                        Task { await confirmBinding() }
                    } label: {
                        HStack {
                            if isConfirming {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isConfirming ? "正在关联…" : "确认关联")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming || isExpired)
                    .accessibilityIdentifier("ios.dashboard.accountBinding.confirm")
                } else {
                    Button("完成") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .navigationTitle("账号关联")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if confirmation == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ios_common_cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .accessibilityIdentifier("ios.dashboard.accountBinding.sheet")
        }
    }

    @MainActor
    private func confirmBinding() async {
        guard !isConfirming, !isExpired else { return }
        isConfirming = true
        errorMessage = nil
        defer { isConfirming = false }

        do {
            confirmation = try await relayManager.confirmAccountBinding(scan)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UsageLimitRow: View {
    let title: String
    let percentage: Int
    let resetText: String?
    let resetDate: Date?
    let detailText: String?
    let locale: Locale
    @Environment(\.themeTokens) private var theme
    @AppStorage(
        QuotaResetTimeDisplayMode.defaultsKey,
        store: QuotaResetTimeDisplayMode.sharedDefaults
    )
    private var resetTimeDisplayMode = QuotaResetTimeDisplayMode.exact.rawValue

    init(
        title: String,
        percentage: Int,
        resetText: String?,
        resetDate: Date? = nil,
        detailText: String?,
        locale: Locale
    ) {
        self.title = title
        self.percentage = percentage
        self.resetText = resetText
        self.resetDate = resetDate
        self.detailText = detailText
        self.locale = locale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            quotaHeader

            ProgressView(value: Double(percentage), total: 100)
                .progressViewStyle(.linear)
                .tint(progressColor)

            if let detailText {
                Text(detailText)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var quotaHeader: some View {
        ViewThatFits(in: .horizontal) {
            quotaHeaderRow(resetStyle: .icon)
            quotaHeaderRow(resetStyle: .compressedIcon)
        }
    }

    private func quotaHeaderRow(resetStyle: ResetPresentationStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(theme.subheadlineWeightFont)
                .lineLimit(1)
                .fixedSize(horizontal: resetStyle != .compressedIcon, vertical: false)
                .layoutPriority(2)

            Spacer(minLength: 2)

            if let resetText {
                resetLabel(resetText, style: resetStyle)
            }

            percentageLabel
        }
    }

    @ViewBuilder
    private func resetLabel(_ resetText: String, style: ResetPresentationStyle) -> some View {
        if displayMode == .countdown,
           let resetDate = resetDate ?? QuotaResetTimePresentation.resetDate(from: resetText) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                resetLabelContent(
                    QuotaResetTimePresentation.countdownText(until: resetDate, now: context.date),
                    style: style,
                    isCountdown: true
                )
            }
        } else {
            resetLabelContent(resetText, style: style, isCountdown: false)
        }
    }

    private var displayMode: QuotaResetTimeDisplayMode {
        QuotaResetTimeDisplayMode(rawValue: resetTimeDisplayMode) ?? .exact
    }

    private func resetLabelContent(
        _ text: String,
        style: ResetPresentationStyle,
        isCountdown: Bool
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(style == .compressedIcon ? 0.72 : 1)
        }
        .font(theme.captionFont)
        .foregroundStyle(theme.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: String(
                    localized: isCountdown ? "ios_dashboard_reset_in" : "ios_dashboard_reset_at",
                    locale: locale
                ),
                locale: locale,
                text
            )
        )
    }

    private var percentageLabel: some View {
        Text(String(format: String(localized: "ios_dashboard_percent_format", locale: locale), locale: locale, percentage))
            .font(theme.isGeek ? .system(.subheadline, design: .monospaced).monospacedDigit().weight(.semibold) : .subheadline.monospacedDigit().weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(3)
    }

    private var progressColor: Color {
        switch percentage {
        case ..<50: return theme.progressSuccess
        case 50..<80: return theme.progressWarning
        default: return theme.progressDanger
        }
    }
}

private enum ResetPresentationStyle: Equatable {
    case icon
    case compressedIcon
}

private struct LocalizedUsageRow: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Int
    let resetTime: String?
    let resetDate: Date?
}

private extension View {
    @ViewBuilder
    func dashboardOverviewSurface(theme: IOSThemeTokens, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if theme.isGeek {
            iosGlassContainer(theme, cornerRadius: cornerRadius)
                .overlay(shape.strokeBorder(theme.info.opacity(0.3), lineWidth: 1))
        } else {
            background(theme.surfaceSecondary, in: shape)
                .overlay(shape.strokeBorder(theme.brandPrimary.opacity(0.18), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.025), radius: 6, x: 0, y: 2)
        }
    }

    @ViewBuilder
    func dashboardProviderSurface(theme: IOSThemeTokens, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if theme.isGeek {
            iosGlassContainer(theme, cornerRadius: cornerRadius)
        } else {
            background(theme.surfacePrimary, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.borderSubtle, lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.045), radius: 8, x: 0, y: 3)
        }
    }
}
