#if os(iOS)
import ActivityKit
import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

struct TerminalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TerminalActivityAttributes.self) { context in
            TerminalLockScreenView(state: context.state, activityID: context.activityID)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TerminalIslandLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    TerminalIslandCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TerminalIslandTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.sessions.count <= 1 {
                        TerminalSingleIslandDetails(session: context.state.primarySession)
                    } else {
                        TerminalSessionGroupView(state: context.state, activityID: context.activityID, surface: .island)
                    }
                }
            } compactLeading: {
                if context.state.sessions.count <= 1 {
                    TerminalOSActivityIcon(session: context.state.primarySession, size: 24, imageScale: 1.28)
                } else {
                    Text("SSH")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            } compactTrailing: {
                if context.state.sessions.count <= 1 {
                    Text("SSH")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    TerminalCompactCountBadge(count: context.state.sessions.count, tint: context.state.status.tint, size: 20)
                }
            } minimal: {
                if context.state.sessions.count <= 1 {
                    TerminalOSActivityIcon(session: context.state.primarySession, size: 18, imageScale: 1.25)
                } else {
                    TerminalCompactCountBadge(count: context.state.sessions.count, tint: context.state.status.tint, size: 18)
                }
            }
            .widgetURL(URL(string: "devbar://terminal"))
            .keylineTint(context.state.status.tint)
        }
    }
}

private struct TerminalLockScreenView: View {
    let state: TerminalActivityAttributes.ContentState
    let activityID: String

    var body: some View {
        Group {
            if state.sessions.count <= 1 {
                HStack(spacing: 12) {
                    TerminalOSActivityIcon(session: state.primarySession, size: 36, imageScale: 1.18)
                    TerminalLockScreenSessionText(session: state.primarySession)
                    Spacer(minLength: 8)
                    TerminalStatusPill(status: state.status, statusText: state.statusText, compact: true)
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Terminal")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 8)
                        Text("\(state.sessions.count) SSH")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    HStack(spacing: 14) {
                        ForEach(state.visibleSessions) { session in
                            TerminalLockScreenSessionLine(session: session)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if state.hasMultiplePages {
                        TerminalSessionGroupButton(activityID: activityID, pageIndicator: state.pageIndicator, surface: .lockScreen)
                    }
                }
            }
        }
        .padding(.vertical, state.sessions.count <= 1 ? 11 : 9)
        .padding(.horizontal, 14)
    }
}

private struct TerminalLockScreenSessionLine: View {
    let session: TerminalActivitySessionSnapshot

    var body: some View {
        HStack(spacing: 8) {
            TerminalOSActivityIcon(session: session, size: 26, imageScale: 1.14)
            TerminalLockScreenSessionText(session: session)
        }
    }
}

private struct TerminalLockScreenSessionText: View {
    let session: TerminalActivitySessionSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session?.serverName ?? "Terminal")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(session?.osFamily?.title ?? "SSH")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(session?.displayAddress ?? "No active terminal")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct TerminalIslandLeading: View {
    let state: TerminalActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.sessions.count <= 1 {
                TerminalOSActivityIcon(session: state.primarySession, size: 34, imageScale: 1.22)
            } else {
                Text("Terminal")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(width: state.sessions.count <= 1 ? 40 : 104, alignment: .leading)
        .padding(.leading, state.sessions.count <= 1 ? 0 : 14)
    }
}

private struct TerminalCompactCountBadge: View {
    let count: Int
    let tint: Color
    let size: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: size * 0.64, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
            )
    }
}

private struct TerminalSingleIslandDetails: View {
    let session: TerminalActivitySessionSnapshot?

    var body: some View {
        HStack(spacing: 6) {
            Text(session?.osFamily?.title ?? "SSH")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("·")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.8))
            Text(session?.displayAddress ?? "No active terminal")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 96)
    }
}

private struct TerminalIslandTrailing: View {
    let state: TerminalActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(state.sessions.count <= 1 ? "SSH" : "\(state.sessions.count) SSH")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: state.sessions.count <= 1 ? 40 : 58, alignment: .trailing)
        .padding(.trailing, 8)
    }
}

private struct TerminalIslandCenter: View {
    let state: TerminalActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.sessions.count <= 1 {
                Text(state.islandTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text(state.status.badgeTitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.status.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(state.status.tint.opacity(0.16), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }
}

private struct TerminalSessionGroupView: View {
    let state: TerminalActivityAttributes.ContentState
    let activityID: String
    let surface: TerminalSessionTileSurface

    var body: some View {
        VStack(spacing: surface.groupSpacing) {
            if state.visibleSessions.count <= 1 {
                TerminalSessionTile(session: state.visibleSessions.first ?? state.primarySession, surface: surface.singleTileSurface)
                    .frame(maxWidth: surface.singleTileMaxWidth)
            } else {
                HStack(spacing: surface.tileSpacing) {
                    ForEach(state.visibleSessions) { session in
                        TerminalSessionTile(session: session, surface: surface)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if state.hasMultiplePages {
                TerminalSessionGroupButton(activityID: activityID, pageIndicator: state.pageIndicator, surface: surface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, surface.horizontalPadding)
    }
}

private struct TerminalSessionTile: View {
    let session: TerminalActivitySessionSnapshot?
    let surface: TerminalSessionTileSurface

    var body: some View {
        HStack(spacing: surface.iconSpacing) {
            TerminalOSActivityIcon(session: session, size: surface.iconSize, imageScale: 1.16)

            VStack(alignment: .leading, spacing: surface.textSpacing) {
                HStack(spacing: 5) {
                    Text(session?.serverName ?? "Terminal")
                        .font(surface.titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if surface.showsStatusDot {
                        Circle()
                            .fill((session?.status ?? .disconnected).tint)
                            .frame(width: 5, height: 5)
                    }
                }

                Text(session?.osFamily?.title ?? "SSH")
                    .font(surface.detailFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(session?.displayAddress ?? "No active terminal")
                    .font(surface.addressFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
        }
        .padding(.vertical, surface.tileVerticalPadding)
        .padding(.horizontal, surface.tileHorizontalPadding)
        .background(.primary.opacity(surface.backgroundOpacity), in: RoundedRectangle(cornerRadius: surface.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: surface.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(surface.borderOpacity), lineWidth: 0.5)
        )
    }
}

private struct TerminalSessionGroupButton: View {
    let activityID: String
    let pageIndicator: String
    let surface: TerminalSessionTileSurface

    var body: some View {
        Button(intent: CycleTerminalSessionGroupIntent(activityID: activityID)) {
            HStack(spacing: 5) {
                Text("Next")
                Text(pageIndicator)
                    .monospacedDigit()
                Image(systemName: "chevron.forward")
                    .font(.system(size: surface.buttonIconSize, weight: .semibold))
            }
            .font(surface.buttonFont)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: surface.buttonFillsWidth ? .infinity : nil)
            .padding(.vertical, surface.buttonVerticalPadding)
            .padding(.horizontal, surface.buttonHorizontalPadding)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.green)
        .background(.green.opacity(0.14), in: Capsule())
    }
}

private struct TerminalStatusPill: View {
    let status: TerminalActivityStatus
    let statusText: String
    let compact: Bool

    var body: some View {
        Text(status.lockScreenTitle(statusText: statusText))
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(status.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(status.tint.opacity(0.14), in: Capsule())
    }
}

private enum TerminalSessionTileSurface: Equatable {
    case island
    case lockScreen
    case lockScreenSingle

    var singleTileSurface: TerminalSessionTileSurface {
        self == .lockScreen ? .lockScreenSingle : self
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .island:
            return 10
        case .lockScreen:
            return 0
        case .lockScreenSingle:
            return 0
        }
    }

    var singleTileMaxWidth: CGFloat? {
        switch self {
        case .island:
            return 230
        case .lockScreen, .lockScreenSingle:
            return nil
        }
    }

    var tileSpacing: CGFloat {
        switch self {
        case .island:
            return 8
        case .lockScreen, .lockScreenSingle:
            return 7
        }
    }

    var groupSpacing: CGFloat {
        switch self {
        case .island:
            return 6
        case .lockScreen, .lockScreenSingle:
            return 5
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .island:
            return 22
        case .lockScreen, .lockScreenSingle:
            return 26
        }
    }

    var iconSpacing: CGFloat {
        switch self {
        case .island:
            return 7
        case .lockScreen, .lockScreenSingle:
            return 8
        }
    }

    var textSpacing: CGFloat {
        switch self {
        case .island:
            return 1
        case .lockScreen, .lockScreenSingle:
            return 2
        }
    }

    var titleFont: Font {
        switch self {
        case .island:
            return .system(size: 12, weight: .semibold, design: .rounded)
        case .lockScreen, .lockScreenSingle:
            return .system(size: 13, weight: .semibold, design: .rounded)
        }
    }

    var detailFont: Font {
        .system(size: self == .island ? 10 : 11, weight: .medium, design: .rounded)
    }

    var addressFont: Font {
        .system(size: self == .island ? 9 : 10, weight: .regular, design: .monospaced)
    }

    var tileVerticalPadding: CGFloat {
        switch self {
        case .island:
            return 6
        case .lockScreen, .lockScreenSingle:
            return 7
        }
    }

    var tileHorizontalPadding: CGFloat {
        switch self {
        case .island:
            return 8
        case .lockScreen, .lockScreenSingle:
            return 9
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .island:
            return 13
        case .lockScreen, .lockScreenSingle:
            return 15
        }
    }

    var backgroundOpacity: CGFloat {
        switch self {
        case .island:
            return 0.09
        case .lockScreen, .lockScreenSingle:
            return 0.08
        }
    }

    var borderOpacity: CGFloat {
        switch self {
        case .island:
            return 0.11
        case .lockScreen, .lockScreenSingle:
            return 0.09
        }
    }

    var showsStatusDot: Bool {
        self != .lockScreenSingle
    }

    var buttonFillsWidth: Bool {
        self != .island
    }

    var buttonFont: Font {
        .system(size: self == .island ? 10 : 11, weight: .semibold, design: .rounded)
    }

    var buttonIconSize: CGFloat {
        self == .island ? 9 : 10
    }

    var buttonVerticalPadding: CGFloat {
        self == .island ? 4 : 5
    }

    var buttonHorizontalPadding: CGFloat {
        self == .island ? 11 : 12
    }
}

private struct TerminalOSActivityIcon: View {
    let session: TerminalActivitySessionSnapshot?
    let size: CGFloat
    var imageScale: CGFloat = 1

    var body: some View {
        ZStack {
            if let assetName = session?.osFamily?.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(imageScale)
                    .padding(size * 0.04)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: size, height: size)
    }
}

private extension TerminalActivitySessionSnapshot {
    var osFamily: TerminalRemoteOSFamily? {
        TerminalRemoteOSFamily(rawValue: remoteOSFamilyRawValue)
    }

    var displayAddress: String {
        address.removingTerminalPort
    }
}

private extension String {
    var removingTerminalPort: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = trimmed.lastIndex(of: ":") else { return trimmed }

        let suffixStart = trimmed.index(after: colonIndex)
        let port = trimmed[suffixStart...]
        guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return trimmed }

        let prefix = String(trimmed[..<colonIndex])
        let hostPart = prefix.split(separator: "@").last.map(String.init) ?? prefix
        if hostPart.contains(":") && !hostPart.hasSuffix("]") {
            return trimmed
        }
        return prefix
    }
}

private extension TerminalActivityAttributes.ContentState {
    var islandTitle: String {
        if sessions.count > 1 {
            return "\(sessions.count) Sessions"
        }
        return primarySession?.serverName ?? "Terminal"
    }

}

private extension TerminalActivityStatus {
    var tint: Color {
        switch self {
        case .connected, .suspended:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .secondary
        case .failed:
            return .red
        }
    }

    func lockScreenTitle(statusText: String) -> String {
        switch self {
        case .connected, .suspended:
            return "SSH"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .failed:
            return statusText.isEmpty ? "Failed" : statusText
        }
    }

    var badgeTitle: String {
        switch self {
        case .connected, .suspended:
            return "Live"
        case .connecting:
            return "Wait"
        case .disconnected:
            return "Off"
        case .failed:
            return "Fail"
        }
    }
}

private extension TerminalRemoteOSFamily {
    var assetName: String? {
        switch self {
        case .almaLinux:
            return "TerminalOSAlmaLinux"
        case .android:
            return "TerminalOSAndroid"
        case .alpine:
            return "TerminalOSAlpine"
        case .arch:
            return "TerminalOSArch"
        case .elementaryOS:
            return "TerminalOSElementaryOS"
        case .feren:
            return "TerminalOSFeren"
        case .freeBSD:
            return "TerminalOSFreeBSD"
        case .garuda:
            return "TerminalOSGaruda"
        case .haiku:
            return "TerminalOSHaiku"
        case .kali:
            return "TerminalOSKali"
        case .linux:
            return "TerminalOSLinux"
        case .linuxMint:
            return "TerminalOSLinuxMint"
        case .macOS:
            return "TerminalOSMacOS"
        case .manjaro:
            return "TerminalOSManjaro"
        case .nixOS:
            return "TerminalOSNixOS"
        case .popOS:
            return "TerminalOSPopOS"
        case .redHat:
            return "TerminalOSRedHat"
        case .rocky:
            return "TerminalOSRocky"
        case .serenityOS:
            return "TerminalOSSerenityOS"
        case .windows:
            return "TerminalOSWindows"
        case .ubuntu:
            return "TerminalOSUbuntu"
        case .debian:
            return "TerminalOSDebian"
        case .centos:
            return "TerminalOSCentOS"
        case .fedora:
            return "TerminalOSFedora"
        case .gentoo:
            return "TerminalOSGentoo"
        case .openSUSE:
            return "TerminalOSOpenSUSE"
        case .auto, .unknown:
            return nil
        }
    }
}
#endif
