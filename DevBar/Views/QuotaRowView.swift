// QuotaRowView.swift
// DevBar

import SwiftUI
import DevBarCore

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
            QuotaProgressBar(percentage: limit.percentage)
            HStack {
                Text(String(format: String(localized: "used_percentage"), limit.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetTime = limit.formattedResetTime {
                    QuotaResetTimeText(
                        exactText: resetTime,
                        resetDate: limit.nextResetTime.map {
                            Date(timeIntervalSince1970: TimeInterval($0) / 1000)
                        }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}
