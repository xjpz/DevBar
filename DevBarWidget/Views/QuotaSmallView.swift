// QuotaSmallView.swift
// DevBarWidget

import SwiftUI
import WidgetKit
import DevBarCore

struct QuotaSmallView: View {
    let title: String
    let limits: [WidgetQuotaLimit]
    let level: String?
    var visualStyle: WidgetVisualStyle = .liquidGlass

    private var visibleLimits: [WidgetQuotaLimit] {
        let prioritized = limits
            .filter { smallWidgetPriority($0) < 99 }
            .sorted { lhs, rhs in
                let leftPriority = smallWidgetPriority(lhs)
                let rightPriority = smallWidgetPriority(rhs)

                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }

                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }

        let candidates = prioritized.isEmpty
            ? limits.sorted { $0.percentage > $1.percentage }
            : prioritized

        return Array(candidates.prefix(3))
    }

    private var primaryLimit: WidgetQuotaLimit? {
        visibleLimits.first
    }

    var body: some View {
        if limits.count <= 1, let primaryLimit {
            singleLimitView(primaryLimit)
        } else {
            multiLimitView
        }
    }

    private func singleLimitView(_ limit: WidgetQuotaLimit) -> some View {
        VStack(spacing: 7) {
            titleRow

            ZStack {
                Circle()
                    .stroke(circelTrackColor, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(limit.percentage) / 100.0)
                    .stroke(progressColor(for: limit.percentage), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: limit.percentage)
                Text("\(limit.percentage)%")
                    .font(.system(.title2, design: .rounded).bold())
                    .monospacedDigit()
                    .foregroundStyle(primaryTextColor)
            }
            .frame(width: 58, height: 58)

            Text(limit.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var multiLimitView: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow

            VStack(alignment: .leading, spacing: visibleLimits.count > 2 ? 7 : 12) {
                ForEach(visibleLimits) { limit in
                    QuotaSmallLimitRow(limit: limit, visualStyle: visualStyle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var titleRow: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let lvl = level {
                Text(lvl.capitalized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.65)
    }

    private var circelTrackColor: Color {
        visualStyle == .transparent ? Color.secondary.opacity(0.15) : Color.white.opacity(0.18)
    }

    private func smallWidgetPriority(_ limit: WidgetQuotaLimit) -> Int {
        switch limit.type {
        case "OPENAI_SESSION":
            return 0
        case "OPENAI_WEEKLY":
            return 1
        case "TOKENS_LIMIT":
            return 2
        case "TIME_LIMIT":
            return 3
        default:
            return 99
        }
    }

    private func progressColor(for percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

private struct QuotaSmallLimitRow: View {
    let limit: WidgetQuotaLimit
    var visualStyle: WidgetVisualStyle = .liquidGlass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(limit.displayName)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2)

                Text("\(limit.percentage)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(progressColor)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                    Capsule()
                        .fill(progressColor)
                        .frame(width: proxy.size.width * CGFloat(limit.percentage) / 100)
                }
            }
            .frame(height: 4)
        }
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.65)
    }

    private var trackColor: Color {
        visualStyle == .transparent ? .secondary.opacity(0.12) : .white.opacity(0.15)
    }

    private var progressColor: Color {
        switch limit.percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
