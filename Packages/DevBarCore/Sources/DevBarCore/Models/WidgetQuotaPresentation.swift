import Foundation

public enum WidgetQuotaPresentation {
    public static func sortedLimits(
        _ limits: [WidgetQuotaLimit],
        provider: WidgetProvider?
    ) -> [WidgetQuotaLimit] {
        limits.enumerated().sorted { lhs, rhs in
            let leftPriority = priority(for: lhs.element, provider: provider)
            let rightPriority = priority(for: rhs.element, provider: provider)

            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            let leftKindOrder = kindOrder(for: lhs.element, provider: provider)
            let rightKindOrder = kindOrder(for: rhs.element, provider: provider)
            if leftKindOrder != rightKindOrder {
                return leftKindOrder < rightKindOrder
            }

            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    public static func priority(
        for limit: WidgetQuotaLimit,
        provider: WidgetProvider?
    ) -> Int {
        switch provider {
        case .glm:
            if isFiveHourLimit(limit) || isWeeklyLimit(limit) {
                return 0
            }
            if isMonthlyLimit(limit) {
                return 1
            }
            return 3
        case .openai:
            if isFiveHourLimit(limit) || isWeeklyLimit(limit) {
                return 0
            }
            return 3
        case .mimo:
            if isMonthlyLimit(limit) || isTokenLimit(limit) {
                return 0
            }
            return 3
        case .deepseek:
            if isCostLimit(limit) {
                return 0
            }
            if isTokenLimit(limit) {
                return 1
            }
            return 3
        case nil:
            if isFiveHourLimit(limit) || isWeeklyLimit(limit) {
                return 0
            }
            if isMonthlyLimit(limit) || isCostLimit(limit) {
                return 1
            }
            if isTokenLimit(limit) {
                return 2
            }
            return 3
        }
    }

    public static func marker(
        for limit: WidgetQuotaLimit,
        provider: WidgetProvider?
    ) -> String {
        if isFiveHourLimit(limit) {
            return "H"
        }
        if isWeeklyLimit(limit) {
            return "W"
        }
        if provider == .deepseek, isCostLimit(limit) {
            return "¥"
        }
        if isMonthlyLimit(limit) {
            return "M"
        }
        if isTokenLimit(limit) {
            return "T"
        }
        return "Q"
    }

    public static func shortLabel(
        for limit: WidgetQuotaLimit,
        provider: WidgetProvider?
    ) -> String {
        if isFiveHourLimit(limit) {
            return "5小时额度"
        }
        if isWeeklyLimit(limit) {
            return "周额度"
        }
        if provider == .deepseek, isCostLimit(limit) {
            return "费用额度"
        }
        if isMonthlyLimit(limit) {
            return "月度额度"
        }
        if isTokenLimit(limit) {
            return "Token额度"
        }
        return limit.displayName
    }

    public static func isFiveHourLimit(_ limit: WidgetQuotaLimit) -> Bool {
        let value = searchableValue(for: limit)
        return limit.type == "OPENAI_SESSION"
            || value.contains("5h")
            || value.contains("5 h")
            || value.contains("5小时")
            || value.contains("5 小时")
            || value.contains("five hour")
    }

    public static func isWeeklyLimit(_ limit: WidgetQuotaLimit) -> Bool {
        let value = searchableValue(for: limit)
        return limit.type == "OPENAI_WEEKLY"
            || value.contains("weekly")
            || value.contains("week")
            || value.contains("每周")
            || value.contains("周额度")
            || value.contains("周")
    }

    public static func isMonthlyLimit(_ limit: WidgetQuotaLimit) -> Bool {
        let value = searchableValue(for: limit)
        return value.contains("monthly")
            || value.contains("month")
            || value.contains("每月")
            || value.contains("月度")
            || value.contains("月")
    }

    public static func isTokenLimit(_ limit: WidgetQuotaLimit) -> Bool {
        let value = searchableValue(for: limit)
        return limit.type == "TOKENS_LIMIT"
            || limit.type == "MCP_MONTHLY"
            || value.contains("token")
            || value.contains("tokens")
            || value.contains("令牌")
    }

    public static func isCostLimit(_ limit: WidgetQuotaLimit) -> Bool {
        let value = searchableValue(for: limit)
        return value.contains("cost")
            || value.contains("fee")
            || value.contains("price")
            || value.contains("amount")
            || value.contains("balance")
            || value.contains("费用")
            || value.contains("金额")
            || value.contains("余额")
    }

    private static func searchableValue(for limit: WidgetQuotaLimit) -> String {
        "\(limit.type) \(limit.displayName)".lowercased()
    }

    private static func kindOrder(
        for limit: WidgetQuotaLimit,
        provider: WidgetProvider?
    ) -> Int {
        if isFiveHourLimit(limit) {
            return 0
        }
        if isWeeklyLimit(limit) {
            return 1
        }
        if provider == .deepseek, isCostLimit(limit) {
            return 2
        }
        if isMonthlyLimit(limit) {
            return 3
        }
        if isTokenLimit(limit) {
            return 4
        }
        return 9
    }
}
