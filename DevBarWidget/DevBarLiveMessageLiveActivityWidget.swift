#if os(iOS)
import ActivityKit
import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

struct DevBarLiveMessageLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DevBarLiveMessageActivityAttributes.self) { context in
            DevBarLiveMessageLockScreenView(state: context.state, activityID: context.activityID)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DevBarLiveMessageIslandMark()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DevBarLiveMessageEndButton(activityID: context.activityID)
                }
                DynamicIslandExpandedRegion(.center) {
                    DevBarLiveMessagePrimaryText(message: context.state.message)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.teal)
            } compactTrailing: {
                Text(context.state.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            .widgetURL(URL(string: "devbar://live-message"))
            .keylineTint(.teal)
        }
    }
}

private struct DevBarLiveMessageLockScreenView: View {
    let state: DevBarLiveMessageActivityAttributes.ContentState
    let activityID: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.teal)

            Text(state.message)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            DevBarLiveMessageEndButton(activityID: activityID)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

private struct DevBarLiveMessageIslandMark: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.teal)
    }
}

private struct DevBarLiveMessagePrimaryText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .padding(.horizontal, 8)
    }
}

private struct DevBarLiveMessageEndButton: View {
    let activityID: String

    var body: some View {
        Button(intent: EndDevBarLiveMessageActivityIntent(activityID: activityID)) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.teal)
        .frame(width: 28, height: 28)
        .background(.teal.opacity(0.12), in: Circle())
        .accessibilityLabel("结束")
    }
}
#endif
