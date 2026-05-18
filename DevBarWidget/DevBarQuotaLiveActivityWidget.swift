#if os(iOS)
import ActivityKit
import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

struct DevBarQuotaLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DevBarQuotaActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state, activityID: context.activityID)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityProviderName(provider: context.state.selectedProvider)
                        .padding(.top, 2)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityProviderPlan(provider: context.state.selectedProvider)
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityExpandedBottom(state: context.state, activityID: context.activityID)
                }
            } compactLeading: {
                LiveActivityProviderIcon(provider: context.state.selectedProvider, size: 22)
            } compactTrailing: {
                Text(compactPercentage(for: context.state.selectedProvider))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            } minimal: {
                LiveActivityProviderIcon(provider: context.state.selectedProvider, size: 18)
            }
            .widgetURL(URL(string: "devbar://quota"))
            .keylineTint(.teal)
        }
    }

    private func compactPercentage(for provider: LiveActivityProviderSnapshot?) -> String {
        guard let percentage = provider?.limits.first?.percentage else { return "--" }
        return "\(percentage)%"
    }

}

private struct LiveActivityLockScreenView: View {
    let state: DevBarQuotaActivityAttributes.ContentState
    let activityID: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiveActivityProviderIcon(provider: state.selectedProvider, size: 34)

            LiveActivityProviderHeader(provider: state.selectedProvider)
                .frame(width: 76, alignment: .leading)

            LiveActivityLimitList(provider: state.selectedProvider, compact: false)

            if state.hasMultipleProviders {
                LiveActivityProviderCycleButton(activityID: activityID, fillsAvailableWidth: false)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

private struct LiveActivityAppLogo: View {
    var body: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

private struct LiveActivityProviderIcon: View {
    let provider: LiveActivityProviderSnapshot?
    let size: CGFloat

    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(assetScale)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
        } else {
            LiveActivityAppLogo()
                .frame(width: size, height: size)
        }
    }

    private var assetName: String? {
        guard let rawValue = provider?.providerRawValue,
              let provider = QuotaProvider(rawValue: rawValue) else {
            return nil
        }
        return provider.assetName
    }

    private var assetScale: CGFloat {
        assetName == "MiMO" ? 1.14 : 1
    }
}

private struct LiveActivityProviderHeader: View {
    let provider: LiveActivityProviderSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LiveActivityProviderName(provider: provider)

            if let planName = provider?.planName, !planName.isEmpty {
                Text(planName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

private struct LiveActivityProviderName: View {
    let provider: LiveActivityProviderSnapshot?

    var body: some View {
        Text(provider?.providerName ?? "DevBar")
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct LiveActivityProviderPlan: View {
    let provider: LiveActivityProviderSnapshot?

    var body: some View {
        if let planName = provider?.planName, !planName.isEmpty {
            Text(planName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LiveActivityExpandedBottom: View {
    let state: DevBarQuotaActivityAttributes.ContentState
    let activityID: String

    var body: some View {
        VStack(spacing: 4) {
            LiveActivityLimitList(provider: state.selectedProvider, compact: true)

            if state.hasMultipleProviders {
                LiveActivityProviderCycleButton(activityID: activityID, fillsAvailableWidth: true)
            }
        }
    }
}

private struct LiveActivityProviderCycleButton: View {
    let activityID: String
    let fillsAvailableWidth: Bool

    var body: some View {
        if fillsAvailableWidth {
            button
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.blue)
        } else {
            button
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
                .background(.green.opacity(0.12), in: Circle())
        }
    }

    private var button: some View {
        Button(intent: CycleLiveActivityProviderIntent(activityID: activityID)) {
            if fillsAvailableWidth {
                Text("live_activity_switch_provider")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
            } else {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
        }
    }
}

private struct LiveActivityLimitList: View {
    let provider: LiveActivityProviderSnapshot?
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 5 : 6) {
            ForEach(provider?.limits ?? []) { limit in
                LiveActivityLimitRow(limit: limit, compact: compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveActivityLimitRow: View {
    let limit: LiveActivityLimitSnapshot
    let compact: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(limit.kind.rawValue)
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
                .foregroundStyle(.white)
                .background(limitColor(limit.percentage), in: Circle())

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(limitColor(limit.percentage))
                        .frame(width: proxy.size.width * CGFloat(limit.percentage) / 100)
                }
            }
            .frame(height: compact ? 4 : 5)

            Text("\(limit.percentage)%")
                .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(limitColor(limit.percentage))
                .frame(width: compact ? 38 : 44, alignment: .trailing)
        }
    }

    private func limitColor(_ percentage: Int) -> Color {
        switch percentage {
        case 80...:
            return .red
        case 60..<80:
            return .orange
        default:
            return .green
        }
    }
}
#endif
