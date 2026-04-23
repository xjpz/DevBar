import DevBarCore
import SwiftUI

struct IOSDashboardView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager

    var body: some View {
        List {
            Section {
                overviewCard
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(appViewModel.enabledProviders, id: \.self) { provider in
                    providerCard(provider)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .id("dashboard.list.\(languageManager.selectedLanguage.rawValue)")
        .navigationTitle(Text("ios_dashboard_title"))
        .accessibilityIdentifier("ios.dashboard.screen")
        .refreshable {
            await appViewModel.refreshAll()
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ios_dashboard_providers_title")
                .font(.headline)
                .accessibilityIdentifier("ios.dashboard.providersTitle")

            if let trigger = appViewModel.lastRefreshTrigger {
                Text(refreshSummaryText(trigger))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func providerCard(_ provider: QuotaProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    providerArtwork(for: provider)
                    Text(provider.localizedName)
                        .font(.headline)
                }
                Spacer()
                Text(lastRefreshText(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch provider {
            case .glm:
                glmContent
            case .openai:
                openAIContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.accentColor.opacity(0.14))

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
        }

        guard let date else {
            return localized("ios_dashboard_no_refresh")
        }

        return String(
            format: localized("ios_dashboard_last_updated"),
            date.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(languageManager.currentLocale)
            )
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
                if let level = appViewModel.quotaViewModel.quotaData?.level {
                    badge(level)
                }
                ForEach(sortedGLMLimits(limits)) { limit in
                    UsageLimitRow(
                        title: glmLimitTitle(limit),
                        percentage: limit.percentage,
                        resetText: glmLimitResetText(limit),
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
                .foregroundStyle(.secondary)
        } else {
            Text("ios_dashboard_glm_no_usage")
                .foregroundStyle(.secondary)
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
                if let planType = appViewModel.openAIQuotaViewModel.planType {
                    badge(planType.capitalized)
                }
                ForEach(openAIUsageRows) { row in
                    UsageLimitRow(
                        title: row.name,
                        percentage: row.percentage,
                        resetText: row.resetTime,
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
                .foregroundStyle(.secondary)
        }
    }

    private func configurePrompt(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .foregroundStyle(.secondary)
            Button("ios_dashboard_open_accounts") {
                appViewModel.openAccountsTab()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Button("ios_dashboard_retry") {
                Task { await appViewModel.refreshAll() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func refreshWarning(_ message: String) -> some View {
        Label(message, systemImage: "arrow.triangle.2.circlepath.circle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
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
        Date(timeIntervalSince1970: timestamp).formatted(
            Date.FormatStyle(date: .numeric, time: .shortened)
                .locale(languageManager.currentLocale)
        )
    }
}

private struct UsageLimitRow: View {
    let title: String
    let percentage: Int
    let resetText: String?
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: String(localized: "ios_dashboard_percent_format", locale: locale), locale: locale, percentage))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: Double(percentage), total: 100)
                .tint(progressColor)

            if let resetText {
                Text(String(format: String(localized: "ios_dashboard_reset_at", locale: locale), locale: locale, resetText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressColor: Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

private struct LocalizedUsageRow: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Int
    let resetTime: String?
}
