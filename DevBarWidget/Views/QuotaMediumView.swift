// QuotaMediumView.swift
// DevBarWidget

import SwiftUI
import WidgetKit
import DevBarCore

struct QuotaMediumView: View {
    let title: String
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let subscriptionPrice: String?
    let subscriptionExpireDate: String?
    let lastUpdated: Date
    var visualStyle: WidgetVisualStyle = .liquidGlass

    private var featuredLimit: WidgetQuotaLimit? {
        sortedLimits.first(where: WidgetQuotaPresentation.isFiveHourLimit) ?? sortedLimits.first
    }

    private var sortedLimits: [WidgetQuotaLimit] {
        WidgetQuotaPresentation.sortedLimits(limits, provider: provider)
    }

    var body: some View {
        HStack(spacing: 13) {
            if let featuredLimit {
                remainingSphere(for: featuredLimit)
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 6)

                ForEach(Array(sortedLimits.prefix(3))) { limit in
                    quotaLine(limit)
                        .padding(.vertical, 2)
                }

                Spacer(minLength: 0)

                footer
                    .padding(.top, 4)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let lvl = level {
                Text(lvl.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelBadgeBackground, in: Capsule())
            }
        }
    }

    private func quotaLine(_ limit: WidgetQuotaLimit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(limit.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if let reset = limit.formattedResetTime {
                    Text(reset)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                ProgressView(value: Double(clampedPercentage(limit.percentage)), total: 100)
                    .tint(limitColor(forUsed: limit.percentage))
                Text("\(clampedPercentage(limit.percentage))%")
                    .font(.caption)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(limitColor(forUsed: limit.percentage))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if shouldShowSubscriptionName, let sub = subscriptionName {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            if shouldShowSubscriptionPrice, let price = subscriptionPrice {
                Text(price)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            if shouldShowSubscriptionExpireDate, let expire = subscriptionExpireDate {
                Text(expire)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(String(localized: "widget_last_updated \(lastUpdated.formatted(.dateTime.hour().minute().second()))"))
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
    }

    private func remainingSphere(for limit: WidgetQuotaLimit) -> some View {
        let remaining = remainingPercentage(for: limit)
        let accent = limitColor(forRemaining: remaining)
        let fill = CGFloat(remaining) / 100

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(visualStyle == .transparent ? 0.4 : 0.28),
                            accent.opacity(0.18),
                            Color.black.opacity(visualStyle == .transparent ? 0.05 : 0.2)
                        ],
                        center: .topLeading,
                        startRadius: 5,
                        endRadius: 82
                    )
                )

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let fillHeight = max(6, size * fill)

                VStack {
                    Spacer(minLength: 0)
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.62), accent.opacity(0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: fillHeight)
                        .blur(radius: 0.35)
                }
                .frame(width: size, height: size)
            }
            .clipShape(Circle())
            .padding(2)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(visualStyle == .transparent ? 0.58 : 0.48),
                            accent.opacity(0.48),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )

            Circle()
                .fill(.white.opacity(visualStyle == .transparent ? 0.58 : 0.46))
                .frame(width: 28, height: 15)
                .blur(radius: 1.5)
                .offset(x: -20, y: -28)
                .rotationEffect(.degrees(-28))

            VStack(spacing: 2) {
                Text("\(remaining)%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("剩余")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor.opacity(0.9))
                    .lineLimit(1)
                Text(shortLimitLabel(for: limit))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.top, 4)
        }
        .accessibilityLabel("\(limit.displayName) \(remaining)% 剩余")
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.58)
    }

    private var levelBadgeBackground: Color {
        visualStyle == .transparent ? Color.secondary.opacity(0.15) : .white.opacity(0.18)
    }

    private var shouldShowSubscriptionName: Bool {
        title != "GLM" && title != "MiMo"
    }

    private var shouldShowSubscriptionPrice: Bool {
        title != "GLM"
    }

    private var shouldShowSubscriptionExpireDate: Bool {
        title != "GLM" && title != "MiMo"
    }

    private var provider: WidgetProvider? {
        switch title.lowercased() {
        case "glm": return .glm
        case "openai": return .openai
        case "mimo": return .mimo
        case "deepseek": return .deepseek
        default: return nil
        }
    }

    private func remainingPercentage(for limit: WidgetQuotaLimit) -> Int {
        100 - clampedPercentage(limit.percentage)
    }

    private func clampedPercentage(_ percentage: Int) -> Int {
        min(max(percentage, 0), 100)
    }

    private func shortLimitLabel(for limit: WidgetQuotaLimit) -> String {
        let label = WidgetQuotaPresentation.shortLabel(for: limit, provider: provider)
        return label.count <= 8 ? label : "其他额度"
    }

    private func limitColor(forRemaining remaining: Int) -> Color {
        switch remaining {
        case 60...: return .green
        case 25..<60: return .orange
        default: return .red
        }
    }

    private func limitColor(forUsed used: Int) -> Color {
        switch clampedPercentage(used) {
        case ..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}
