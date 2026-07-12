// QuotaSmallView.swift
// DevBarWidget

import SwiftUI
import WidgetKit
import DevBarCore

struct QuotaSmallView: View {
    let title: String
    let limits: [WidgetQuotaLimit]
    let level: String?
    let availableResetCount: Int?
    var provider: WidgetProvider? = nil
    var visualStyle: WidgetVisualStyle = .liquidGlass

    private var visibleLimits: [WidgetQuotaLimit] {
        let sortedLimits = WidgetQuotaPresentation.sortedLimits(limits, provider: provider)
        let prioritized = sortedLimits.filter {
            WidgetQuotaPresentation.priority(for: $0, provider: provider) < 3
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

            if let detail = quotaDetail(for: limit) {
                Text(detail)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var multiLimitView: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow

            VStack(alignment: .leading, spacing: visibleLimits.count > 2 ? 7 : 12) {
                ForEach(visibleLimits) { limit in
                    QuotaSmallLimitRow(
                        limit: limit,
                        detail: quotaDetail(for: limit),
                        visualStyle: visualStyle
                    )
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

            if let availableResetCount, availableResetCount > 0 {
                ResetCreditsBadge(count: availableResetCount, size: 23, visualStyle: visualStyle)
            } else if let lvl = level {
                Text(lvl.capitalized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.65)
    }

    private var circelTrackColor: Color {
        visualStyle == .transparent ? Color.secondary.opacity(0.15) : Color.white.opacity(0.18)
    }

    private func quotaDetail(for limit: WidgetQuotaLimit) -> String? {
        if let unit = limit.unitDescription, !unit.isEmpty {
            return unit
        }
        if let reset = limit.formattedResetTime, !reset.isEmpty {
            return "\(reset) 重置"
        }
        return nil
    }

    private func progressColor(for percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

struct ResetCreditsBadge: View {
    let count: Int
    var size: CGFloat
    var visualStyle: WidgetVisualStyle = .liquidGlass

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel(resetCreditsAccessibilityText)
    }

    private var assetName: String {
        if count >= 10 {
            return "OpenAIResetCredits9Plus"
        }
        return "OpenAIResetCredits\(max(1, count))"
    }

    private var resetCreditsAccessibilityText: String {
        Locale.current.identifier.lowercased().hasPrefix("zh")
            ? "可用重置: \(count)"
            : "Available resets: \(count)"
    }
}

private struct QuotaSmallLimitRow: View {
    let limit: WidgetQuotaLimit
    let detail: String?
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

            if let detail {
                Text(detail)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
        }
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.65)
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
