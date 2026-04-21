// QuotaRowView.swift
// DevBar

import SwiftUI

struct QuotaRowView: View {
    let limit: QuotaLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: name
            HStack {
                Text(limit.displayName)
                    .font(.headline)
                Spacer()
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
