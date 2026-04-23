// QuotaLargeView.swift
// DevBarWidget

import SwiftUI
import WidgetKit
import DevBarCore

struct QuotaLargeView: View {
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let lastUpdated: Date

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
                Spacer()
                if let lvl = level {
                    Text(lvl.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            if let sub = subscriptionName {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(sortedLimits) { limit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(limit.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let unitDesc = limit.unitDescription {
                            Text(unitDesc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: Double(limit.percentage), total: 100)
                        .tint(limitColor(limit.percentage))

                    HStack {
                        Text(String(format: String(localized: "widget_percent_used"), limit.percentage))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let reset = limit.formattedResetTime {
                            Text(String(format: String(localized: "widget_reset_at"), reset))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Text(lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func limitColor(_ percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
