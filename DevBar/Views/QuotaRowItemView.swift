// QuotaRowItemView.swift
// DevBar

import SwiftUI

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

            ProgressView(value: Double(item.percentage), total: 100)
                .tint(progressColor)
            HStack {
                Text(String(format: String(localized: "used_percentage"), item.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetTime = item.resetTime {
                    Text(String(format: String(localized: "reset_at"), resetTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        switch item.percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
