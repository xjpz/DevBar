import DevBarCore
import SwiftUI

struct IOSMacRelayView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @Environment(\.iosToolEntryContext) private var toolEntryContext
    @State private var relayStatusNow = Date()
    @State private var isShowingScanner = false
    @State private var isResolvingScan = false
    @State private var scanError: String?
    @State private var controlError: String?
    @State private var sendingCommand: DeviceRelayCommandType?
    @State private var isShowingLockConfirmation = false
    @State private var lockScreenTargetPeer: DeviceRelayDevice?

    private var relayManager: DeviceRelayManager {
        appViewModel.deviceRelayManager
    }

    private var pairedMacPeers: [DeviceRelayDevice] {
        relayManager.peers.filter { $0.deviceType == .mac }
    }

    private var selectedMacPeer: DeviceRelayDevice? {
        pairedMacPeers.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 18) {
                    if let peer = selectedMacPeer {
                        macStatusCard(peer)
                        controlCard(peer)
                    } else {
                        emptyRelayCard
                    }

                    if let error = controlError ?? relayManager.lastErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refreshRelayState()
            }

            if isShowingLockConfirmation {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        cancelLockConfirmation()
                    }

                lockConfirmationPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isShowingLockConfirmation)
        .iosGeekScreenBackground(theme)
        .navigationTitle("Mac Relay")
        .iosToolTitleDisplayMode(toolEntryContext)
        .toolbar(toolEntryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: toolEntryContext.showsBackButton)
        .toolbar {
            if toolEntryContext == .pushed {
                ToolbarItem(placement: .principal) {
                    Text("Mac Relay")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        await refreshRelayState()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("刷新")

                Menu {
                    Button {
                        Task {
                            await refreshRelayState()
                        }
                    } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }

                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("扫描连接二维码", systemImage: "qrcode.viewfinder")
                    }
                    .disabled(!pairedMacPeers.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("更多")
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                IOSQRScannerView { code in
                    isShowingScanner = false
                    Task {
                        await handleScannedCode(code)
                    }
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ios_common_cancel") {
                            isShowingScanner = false
                        }
                    }
                }
            }
        }
        .alert("ios_mac_relay_scan_failed", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("ios_common_ok", role: .cancel) {}
        } message: {
            Text(scanError ?? "")
        }
        .overlay {
            if isResolvingScan {
                ProgressView("正在读取二维码...")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .accessibilityIdentifier("ios.tools.macRelay.screen")
        .task {
            await refreshRelayState()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await refreshRelayState()
            }
        }
    }

    private func macStatusCard(_ peer: DeviceRelayDevice) -> some View {
        let isReachable = relayManager.isPeerReachable(peer, now: relayStatusNow)
        return VStack(spacing: 22) {
            HStack(spacing: 22) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(isReachable ? theme.textSecondary : theme.textTertiary)
                    .frame(width: 92, height: 86)

                VStack(alignment: .leading, spacing: 10) {
                    Text(relayManager.displayName(for: peer))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(peerTransportColor(for: peer))
                            .frame(width: 10, height: 10)
                        Text("\(peerTransportText(for: peer)) · \(statusFreshnessText(for: peer))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(peerTransportColor(for: peer))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(theme.textTertiary.opacity(0.25))

            HStack(spacing: 0) {
                metricView(
                    title: "CPU",
                    value: relayManager.cpuPercent(for: peer).map { "\($0)%" } ?? "--"
                )

                metricDivider

                metricView(
                    title: "内存",
                    value: relayManager.memoryPercent(for: peer).map { "\($0)%" } ?? "--"
                )

                metricDivider

                networkMetricView(peer)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textTertiary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios.tools.macRelay.statusCard")
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func networkMetricView(_ peer: DeviceRelayDevice) -> some View {
        VStack(spacing: 6) {
            Text("网速")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .foregroundStyle(theme.info)
                Text(formattedSpeed(relayManager.networkDownBytesPerSecond(for: peer)))
                    .foregroundStyle(theme.textPrimary)
            }

            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .foregroundStyle(theme.success)
                Text(formattedSpeed(relayManager.networkUpBytesPerSecond(for: peer)))
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.72)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(theme.textTertiary.opacity(0.25))
            .frame(width: 1, height: 54)
    }

    private func controlCard(_ peer: DeviceRelayDevice) -> some View {
        HStack(spacing: 0) {
            controlButton(
                title: "锁定",
                systemImage: "lock",
                command: .lockScreen,
                peer: peer
            )

            controlDivider

            controlButton(
                title: "唤醒",
                systemImage: "sun.max",
                command: .wakeDisplay,
                peer: peer
            )

            controlDivider

            controlButton(
                title: "休眠",
                systemImage: "moon",
                command: .displaySleep,
                peer: peer
            )
        }
        .padding(.vertical, 18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textTertiary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityIdentifier("ios.tools.macRelay.controls")
    }

    private func controlButton(
        title: String,
        systemImage: String,
        command: DeviceRelayCommandType,
        peer: DeviceRelayDevice
    ) -> some View {
        let isEnabled = isControlEnabled(command, for: peer)
        let isSending = sendingCommand == command
        return Button {
            perform(command, on: peer)
        } label: {
            VStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(height: 34)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .regular))
                        .frame(height: 34)
                }

                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isEnabled ? theme.textSecondary : theme.textTertiary.opacity(0.48))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(controlAccessibilityLabel(command, for: peer))
        .accessibilityHint(isEnabled ? "双击执行" : controlDisabledReason(command, for: peer))
    }

    private var controlDivider: some View {
        Rectangle()
            .fill(theme.textTertiary.opacity(0.25))
            .frame(width: 1, height: 64)
    }

    private var emptyRelayCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(theme.brandPrimary)

            VStack(spacing: 6) {
                Text("连接你的 Mac")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("扫描 Mac DevBar 中的连接二维码后，即可查看状态并进行快捷控制。")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isShowingScanner = true
            } label: {
                Label("ios_mac_relay_scan_pair", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textTertiary.opacity(0.2), lineWidth: 1)
        }
    }

    private var lockConfirmationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.danger)
                    .frame(width: 36, height: 36)
                    .background(theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("锁定 Mac？")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text("\(lockScreenTargetPeer.map { relayManager.displayName(for: $0) } ?? "Mac") 会立即回到登录窗口。")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    cancelLockConfirmation()
                } label: {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sendingCommand != nil)

                Button(role: .destructive) {
                    if let lockScreenTargetPeer {
                        sendSystemCommand(.lockScreen, to: lockScreenTargetPeer)
                    }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if sendingCommand == .lockScreen {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "lock.fill")
                            Text("锁定")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.danger)
                .disabled(lockScreenTargetPeer.map { !isControlEnabled(.lockScreen, for: $0) } ?? true)
            }
        }
        .padding(16)
        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        .accessibilityIdentifier("ios.tools.macRelay.lockConfirmation")
    }

    private var cardBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.78) : theme.surfacePrimary
    }

    private func peerTransportColor(for peer: DeviceRelayDevice) -> Color {
        switch relayManager.connectionStatus(for: peer, now: relayStatusNow) {
        case .local:
            return theme.success
        case .remote:
            return theme.brandPrimary
        case .offline:
            return theme.textTertiary
        }
    }

    private func peerTransportText(for peer: DeviceRelayDevice) -> String {
        switch relayManager.connectionStatus(for: peer, now: relayStatusNow) {
        case .local:
            return "局域网直连"
        case .remote:
            return "远程中继"
        case .offline:
            return "离线"
        }
    }

    private func statusFreshnessText(for peer: DeviceRelayDevice) -> String {
        guard let updatedAt = relayManager.systemMetricsUpdatedAt(for: peer) else {
            return relayManager.isPeerReachable(peer, now: relayStatusNow) ? "等待状态" : "状态不可用"
        }
        let elapsed = max(0, Int(relayStatusNow.timeIntervalSince(updatedAt)))
        if elapsed < 15 {
            return "刚刚更新"
        }
        if elapsed < 60 {
            return "\(elapsed) 秒前更新"
        }
        return "\(max(1, elapsed / 60)) 分钟前更新"
    }

    private func formattedSpeed(_ bytesPerSecond: Int?) -> String {
        guard let bytesPerSecond else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func isControlEnabled(_ command: DeviceRelayCommandType, for peer: DeviceRelayDevice) -> Bool {
        guard sendingCommand == nil,
              relayManager.isPeerReachable(peer, now: relayStatusNow) else {
            return false
        }

        switch command {
        case .lockScreen:
            return relayManager.screenLocked(for: peer) != true
        case .wakeDisplay:
            return relayManager.displayAwake(for: peer) == false
        case .displaySleep:
            return relayManager.displayAwake(for: peer) == true
        }
    }

    private func controlAccessibilityLabel(_ command: DeviceRelayCommandType, for peer: DeviceRelayDevice) -> String {
        let name = relayManager.displayName(for: peer)
        switch command {
        case .lockScreen:
            return "锁定 \(name)"
        case .wakeDisplay:
            return "唤醒 \(name) 显示器"
        case .displaySleep:
            return "让 \(name) 显示器休眠"
        }
    }

    private func controlDisabledReason(_ command: DeviceRelayCommandType, for peer: DeviceRelayDevice) -> String {
        guard relayManager.isPeerReachable(peer, now: relayStatusNow) else {
            return "Mac 当前离线"
        }
        if sendingCommand != nil {
            return "另一项控制正在执行"
        }
        switch command {
        case .lockScreen:
            return "Mac 已锁定"
        case .wakeDisplay:
            return relayManager.displayAwake(for: peer) == true ? "显示器已唤醒" : "显示器状态未知"
        case .displaySleep:
            return relayManager.displayAwake(for: peer) == false ? "显示器已休眠" : "显示器状态未知"
        }
    }

    private func perform(_ command: DeviceRelayCommandType, on peer: DeviceRelayDevice) {
        guard isControlEnabled(command, for: peer) else { return }
        if command == .lockScreen {
            lockScreenTargetPeer = peer
            isShowingLockConfirmation = true
        } else {
            sendSystemCommand(command, to: peer)
        }
    }

    private func sendSystemCommand(_ command: DeviceRelayCommandType, to peer: DeviceRelayDevice) {
        guard isControlEnabled(command, for: peer) else { return }
        controlError = nil
        sendingCommand = command
        Task {
            defer {
                sendingCommand = nil
                if command == .lockScreen {
                    isShowingLockConfirmation = false
                    lockScreenTargetPeer = nil
                }
            }
            do {
                try await relayManager.sendSystemCommand(command, targetDeviceId: peer.deviceId)
                try? await Task.sleep(for: .seconds(1))
                try? await relayManager.sendSystemStatusRequest(targetDeviceId: peer.deviceId)
            } catch {
                controlError = error.localizedDescription
            }
        }
    }

    private func requestMacStatuses() async {
        let reachablePeers = pairedMacPeers.filter {
            relayManager.isPeerReachable($0, now: relayStatusNow)
        }
        for peer in reachablePeers {
            try? await relayManager.sendSystemStatusRequest(targetDeviceId: peer.deviceId)
        }
    }

    private func refreshRelayState() async {
        relayStatusNow = Date()
        await relayManager.refreshPeers()
        relayStatusNow = Date()
        await requestMacStatuses()
    }

    @MainActor
    private func handleScannedCode(_ code: String) async {
        scanError = nil
        isResolvingScan = true
        defer { isResolvingScan = false }

        do {
            switch try await appViewModel.resolveScannedCode(code) {
            case .macPaired:
                relayStatusNow = Date()
                await relayManager.refreshPeers()
                await requestMacStatuses()
            case .accountBinding:
                scanError = "请使用首页右上角的扫码按钮关联账号。"
            case .providerTransfer:
                scanError = String(localized: "ios_mac_relay_scan_provider_transfer_unsupported")
            case .zcodeRemote:
                scanError = String(localized: "ios_mac_relay_scan_zcode_remote_unsupported")
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func cancelLockConfirmation() {
        guard sendingCommand == nil else { return }
        isShowingLockConfirmation = false
        lockScreenTargetPeer = nil
    }
}
