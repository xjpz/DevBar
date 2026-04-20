// QuotaRowView.swift
// DevBar

import SwiftUI

struct QuotaRowView: View {
    let limit: QuotaLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: name + unit description
            HStack {
                Text(limit.displayName)
                    .font(.headline)
                Spacer()
                if let unitDesc = limit.unitDescription {
                    Text(unitDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar with percentage
            ProgressView(value: Double(limit.percentage), total: 100)
                .tint(progressColor)
            HStack {
                Text(String(format: String(localized: "used_percentage"), limit.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetTime = limit.formattedResetTime {
                    Text(String(format: String(localized: "reset_at"), resetTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MCP usage details (only for TIME_LIMIT)
            if limit.type == "TIME_LIMIT", let details = limit.usageDetails, !details.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(details) { detail in
                        HStack {
                            Text(detail.modelCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(detail.usage)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        switch limit.percentage {
        case ..<50:
            return .green
        case 50..<80:
            return .orange
        default:
            return .red
        }
    }
}
