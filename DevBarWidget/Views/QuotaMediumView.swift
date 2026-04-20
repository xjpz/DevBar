// QuotaMediumView.swift
// DevBarWidget

import SwiftUI
import WidgetKit

struct QuotaMediumView: View {
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let subscriptionPrice: String?
    let subscriptionExpireDate: String?
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
        VStack(spacing: 0) {
            // Header
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
            .padding(.bottom, 8)

            // Quota items
            ForEach(sortedLimits) { limit in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(limit.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        if let reset = limit.formattedResetTime {
                            Text(reset)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(spacing: 4) {
                        ProgressView(value: Double(limit.percentage), total: 100)
                            .tint(limitColor(limit.percentage))
                        Text("\(limit.percentage)%")
                            .font(.caption)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(limitColor(limit.percentage))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 4) {
                if let sub = subscriptionName {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let price = subscriptionPrice {
                    Text(price)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let expire = subscriptionExpireDate {
                    Text(expire)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(localized: "widget_last_updated \(lastUpdated.formatted(.dateTime.hour().minute().second()))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
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
