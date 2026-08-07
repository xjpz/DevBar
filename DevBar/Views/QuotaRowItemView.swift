// QuotaRowItemView.swift
// DevBar

import SwiftUI
import DevBarCore

struct QuotaRowItemView: View {
    let item: QuotaRowItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)
                Spacer()
                if let unitDesc = item.unitDescription {
                    Text(unitDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            QuotaProgressBar(percentage: item.percentage)
            HStack {
                Text(String(format: String(localized: "used_percentage"), item.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetTime = item.resetTime {
                    QuotaResetTimeText(
                        exactText: resetTime,
                        resetDate: QuotaResetTimePresentation.resetDate(from: resetTime)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}
