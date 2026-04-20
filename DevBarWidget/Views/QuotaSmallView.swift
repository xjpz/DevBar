// QuotaSmallView.swift
// DevBarWidget

import SwiftUI
import WidgetKit

struct QuotaSmallView: View {
    let limits: [WidgetQuotaLimit]
    let level: String?

    private var maxPercentage: Int {
        limits.map(\.percentage).max() ?? 0
    }

    private var topLimit: WidgetQuotaLimit? {
        limits.sorted { $0.percentage > $1.percentage }.first
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("DevBar")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(maxPercentage) / 100.0)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: maxPercentage)
                Text("\(maxPercentage)%")
                    .font(.system(.title2, design: .rounded).bold())
            }
            .frame(width: 58, height: 58)

            if let limit = topLimit {
                Text(limit.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var progressColor: Color {
        switch maxPercentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
