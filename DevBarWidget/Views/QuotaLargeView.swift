// QuotaLargeView.swift
// DevBarWidget

import SwiftUI
import WidgetKit
import DevBarCore

struct QuotaLargeView: View {
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let availableResetCount: Int?
    let lastUpdated: Date
    var visualStyle: WidgetVisualStyle = .liquidGlass

    private var sortedLimits: [WidgetQuotaLimit] {
        limits.sorted { a, b in
            let order = { (l: WidgetQuotaLimit) -> Int in
                switch l.type {
                case "TOKENS_LIMIT": return 0
                case "TIME_LIMIT": return 1
                default: return 2
                }
            }
            return order(a) < order(b)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DevBar")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                if let availableResetCount, availableResetCount > 0 {
                    ResetCreditsBadge(count: availableResetCount, size: 26, visualStyle: visualStyle)
                }
                if let lvl = level {
                    Text(lvl.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(levelBadgeBackground, in: Capsule())
                }
            }

            if let sub = subscriptionName {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }

            Divider()

            ForEach(sortedLimits) { limit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(limit.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(primaryTextColor)
                        Spacer()
                        if let unitDesc = limit.unitDescription {
                            Text(unitDesc)
                                .font(.caption2)
                                .foregroundStyle(secondaryTextColor)
                        }
                    }

                    ProgressView(value: Double(limit.percentage), total: 100)
                        .tint(limitColor(limit.percentage))

                    HStack {
                        Text(String(format: String(localized: "widget_percent_used"), limit.percentage))
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                        Spacer()
                        if let reset = limit.formattedResetTime {
                            Text(String(format: String(localized: "widget_reset_at"), reset))
                                .font(.caption2)
                                .foregroundStyle(secondaryTextColor)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Text(lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.58)
    }

    private var levelBadgeBackground: Color {
        visualStyle == .transparent ? Color.secondary.opacity(0.15) : .white.opacity(0.18)
    }

    private func limitColor(_ percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
