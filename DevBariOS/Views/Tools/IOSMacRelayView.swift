import DevBarCore
import SwiftUI

struct IOSMacRelayView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @Environment(\.iosToolEntryContext) private var toolEntryContext
    @State private var relayPrompt = ""
    @State private var relaySendError: String?
    @State private var isSendingRelayPrompt = false
    @State private var isSendingLockScreenCommand = false
    @State private var isShowingLockConfirmation = false
    @State private var lockScreenTargetPeer: DeviceRelayDevice?
    @State private var relayStatusNow = Date()
    @State private var isShowingScanner = false
    @State private var isResolvingScan = false
    @State private var scanError: String?
    @State private var listTopOffset: CGFloat = 0
    @State private var isMacStatusCardCollapsed = false

    private var relayManager: DeviceRelayManager {
        appViewModel.deviceRelayManager
    }

    private var firstOnlineMacPeer: DeviceRelayDevice? {
        pairedMacPeers.first { relayManager.isPeerReachable($0, now: relayStatusNow) }
    }

    private var pairedMacPeers: [DeviceRelayDevice] {
        relayManager.peers.filter { $0.deviceType == .mac }
    }

    private var shouldHideMacStatusCard: Bool {
        !pairedMacPeers.isEmpty && isMacStatusCardCollapsed
    }

    private var titleConnectionStatus: DeviceRelayPeerConnectionStatus {
        let statuses = pairedMacPeers.map { relayManager.connectionStatus(for: $0, now: relayStatusNow) }
        if statuses.contains(.local) {
            return .local
        }
        if statuses.contains(.remote) {
            return .remote
        }
        return .offline
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MacRelayListTopOffsetKey.self,
                                value: proxy.frame(in: .named("macRelayList")).minY
                            )
                        }
                    )

                VStack(spacing: 16) {
                    if !shouldHideMacStatusCard {
                        relayStatusCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !pairedMacPeers.isEmpty {
                        relayPromptEditor
                    }

                    if !relayManager.agentTasks.isEmpty {
                        agentTaskList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
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
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: shouldHideMacStatusCard)
        .coordinateSpace(name: "macRelayList")
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    updateMacStatusCardVisibility(translation: value.translation.height)
                }
        )
        .onPreferenceChange(MacRelayListTopOffsetKey.self) { offset in
            listTopOffset = offset
            updateMacStatusCardVisibility(offset: offset)
        }
        .scrollDismissesKeyboard(.interactively)
        .iosGeekScreenBackground(theme)
        .navigationTitle("Mac Relay")
        .iosToolTitleDisplayMode(toolEntryContext)
        .toolbar(toolEntryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: toolEntryContext.showsBackButton)
        .toolbar {
            if toolEntryContext == .pushed {
                ToolbarItem(placement: .principal) {
                    titleStatusView
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await refreshRelayState()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("刷新")
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

    private var titleStatusView: some View {
        HStack(spacing: 6) {
            if shouldHideMacStatusCard {
                Circle()
                    .fill(titleConnectionColor)
                    .frame(width: 7, height: 7)
            }
            Text("Mac Relay")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titleAccessibilityLabel)
    }

    private var titleConnectionColor: Color {
        switch titleConnectionStatus {
        case .local:
            return .green
        case .remote:
            return theme.brandPrimary
        case .offline:
            return theme.textTertiary
        }
    }

    private var titleAccessibilityLabel: Text {
        switch titleConnectionStatus {
        case .local:
            return Text("Mac Relay, \(String(localized: "device_relay_status_local"))")
        case .remote:
            return Text("Mac Relay, \(String(localized: "device_relay_status_remote"))")
        case .offline:
            return Text("Mac Relay, \(String(localized: "device_relay_status_offline"))")
        }
    }

    private var relayStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let macPeers = pairedMacPeers
            if macPeers.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.brandPrimary)
                        .frame(width: 36, height: 36)
                        .background(theme.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mac Relay")
                            .font(.headline)
                        relayConnectionLabel
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 0)
                }

                Text("扫描 Mac DevBar 里的连接二维码后，这里会显示已绑定 Mac。")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)

                Button {
                    isShowingScanner = true
                } label: {
                    Text("ios_mac_relay_scan_pair")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                ForEach(macPeers) { peer in
                    peerRow(peer)
                }
            }

            if let error = relaySendError ?? relayManager.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.danger)
            }
        }
        .padding(16)
        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var relayConnectionLabel: some View {
        switch relayManager.activeTransport {
        case .local:
            Text("本地连接")
        case .relay:
            Text("远程中继")
        case .none:
            switch relayManager.connectionState {
            case .connected:
                Text("远程中继")
            case .connecting:
                Text("连接中")
            case .disconnected:
                Text("中继未连接")
            case .failed:
                Text("中继连接失败")
            }
        }
    }

    private func peerTransportColor(for peer: DeviceRelayDevice) -> Color {
        switch relayManager.connectionStatus(for: peer, now: relayStatusNow) {
        case .local:
            return Color.green
        case .remote:
            return theme.brandPrimary
        case .offline:
            return theme.textTertiary
        }
    }

    private func peerTransportTitle(for peer: DeviceRelayDevice) -> LocalizedStringKey {
        switch relayManager.connectionStatus(for: peer, now: relayStatusNow) {
        case .local:
            return "device_relay_status_local"
        case .remote:
            return "device_relay_status_remote"
        case .offline:
            return "device_relay_status_offline"
        }
    }

    private func peerRow(_ peer: DeviceRelayDevice) -> some View {
        let isReachable = relayManager.isPeerReachable(peer, now: relayStatusNow)
        let isScreenLocked = relayManager.screenLocked(for: peer) == true
        return HStack(spacing: 10) {
            Image(systemName: "macbook")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 36, height: 36)
                .background(theme.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(relayManager.displayName(for: peer))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(isReachable ? peerTransportColor(for: peer) : theme.textTertiary)
                    Text(peerTransportTitle(for: peer))
                        .font(.caption)
                        .foregroundStyle(peerTransportColor(for: peer))
                }
            }
            Spacer()
            Button(role: .destructive) {
                lockScreenTargetPeer = peer
                isShowingLockConfirmation = true
            } label: {
                if isSendingLockScreenCommand && lockScreenTargetPeer?.deviceId == peer.deviceId {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(isScreenLocked ? "device_relay_lock_locked" : "锁定", systemImage: isScreenLocked ? "lock.circle.fill" : "lock.fill")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!isReachable || isScreenLocked || isSendingLockScreenCommand)
            .accessibilityLabel(isScreenLocked ? "device_relay_lock_locked" : "锁定 \(relayManager.displayName(for: peer))")
        }
        .padding(10)
        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var relayPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("发送任务到在线 Mac", text: $relayPrompt, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                sendRelayPrompt()
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    if isSendingRelayPrompt {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("发送")
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSendingRelayPrompt || relayPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || firstOnlineMacPeer == nil)
        }
        .padding(16)
        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var agentTaskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ios_mac_relay_tasks_title")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            ForEach(relayManager.agentTasks) { task in
                agentTaskRow(task)
            }
        }
        .padding(16)
        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func agentTaskRow(_ task: DeviceRelayAgentTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: agentTaskIcon(task.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(agentTaskColor(task.status))
                    .frame(width: 18)

                Text(agentTaskTitle(task.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(agentTaskColor(task.status))

                Spacer(minLength: 0)

                Text(task.agent == "default" ? "Default" : task.agent)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Text(task.prompt)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)

            if let detail = agentTaskDetail(task) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(task.status == .failed ? theme.danger : theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func agentTaskTitle(_ status: DeviceRelayAgentTaskStatus) -> LocalizedStringKey {
        switch status {
        case .pending:
            return "ios_mac_relay_task_pending"
        case .running:
            return "ios_mac_relay_task_running"
        case .succeeded:
            return "ios_mac_relay_task_succeeded"
        case .failed:
            return "ios_mac_relay_task_failed"
        }
    }

    private func agentTaskIcon(_ status: DeviceRelayAgentTaskStatus) -> String {
        switch status {
        case .pending:
            return "clock"
        case .running:
            return "bolt.horizontal.circle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func agentTaskColor(_ status: DeviceRelayAgentTaskStatus) -> Color {
        switch status {
        case .pending:
            return theme.textSecondary
        case .running:
            return theme.brandPrimary
        case .succeeded:
            return .green
        case .failed:
            return theme.danger
        }
    }

    private func agentTaskDetail(_ task: DeviceRelayAgentTask) -> String? {
        switch task.status {
        case .pending, .running:
            return task.progressMessage
        case .succeeded:
            return task.resultSummary ?? task.progressMessage
        case .failed:
            return task.errorMessage ?? task.progressMessage
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
                .disabled(isSendingLockScreenCommand)

                Button(role: .destructive) {
                    if let lockScreenTargetPeer {
                        sendLockScreenCommand(to: lockScreenTargetPeer)
                    }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isSendingLockScreenCommand {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "lock.fill")
                            Text(lockScreenTargetPeer.map { relayManager.screenLocked(for: $0) == true } == true ? "device_relay_lock_locked" : "锁定")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.danger)
                .disabled(isSendingLockScreenCommand || lockScreenTargetPeer.map { relayManager.isPeerReachable($0, now: relayStatusNow) && relayManager.screenLocked(for: $0) != true } != true)
            }
        }
        .padding(16)
        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        .accessibilityIdentifier("ios.tools.macRelay.lockConfirmation")
    }

    private func sendRelayPrompt() {
        guard let peer = firstOnlineMacPeer else {
            relaySendError = "没有在线 Mac 可发送"
            return
        }
        let prompt = relayPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        relaySendError = nil
        isSendingRelayPrompt = true
        Task {
            defer { isSendingRelayPrompt = false }
            do {
                try await relayManager.sendAgentCommand(
                    prompt: prompt,
                    targetDeviceId: peer.deviceId
                )
                relayPrompt = ""
            } catch {
                relaySendError = error.localizedDescription
            }
        }
    }

    private func sendLockScreenCommand(to peer: DeviceRelayDevice) {
        guard relayManager.isPeerReachable(peer, now: relayStatusNow) else {
            relaySendError = "没有在线 Mac 可锁定"
            return
        }
        guard relayManager.screenLocked(for: peer) != true else {
            relaySendError = nil
            isShowingLockConfirmation = false
            lockScreenTargetPeer = nil
            return
        }

        relaySendError = nil
        isSendingLockScreenCommand = true
        Task {
            defer {
                isSendingLockScreenCommand = false
                isShowingLockConfirmation = false
                lockScreenTargetPeer = nil
            }
            do {
                try await relayManager.sendLockScreenCommand(targetDeviceId: peer.deviceId)
                try? await Task.sleep(for: .seconds(1))
                try? await relayManager.sendSystemStatusRequest(targetDeviceId: peer.deviceId)
            } catch {
                relaySendError = error.localizedDescription
            }
        }
    }

    private func requestMacStatuses() async {
        let macPeers = relayManager.peers.filter { $0.deviceType == .mac && relayManager.isPeerReachable($0, now: relayStatusNow) }
        for peer in macPeers {
            try? await relayManager.sendSystemStatusRequest(targetDeviceId: peer.deviceId)
        }
    }

    private func refreshRelayState() async {
        relayStatusNow = Date()
        await relayManager.refreshPeers()
        relayStatusNow = Date()
        await requestMacStatuses()
    }

    private func updateMacStatusCardVisibility(offset: CGFloat) {
        guard !pairedMacPeers.isEmpty else {
            isMacStatusCardCollapsed = false
            return
        }

        if offset < -72, !isMacStatusCardCollapsed {
            isMacStatusCardCollapsed = true
        } else if offset > -16, isMacStatusCardCollapsed {
            isMacStatusCardCollapsed = false
        }
    }

    private func updateMacStatusCardVisibility(translation: CGFloat) {
        guard !pairedMacPeers.isEmpty else {
            isMacStatusCardCollapsed = false
            return
        }

        if translation < -24, !isMacStatusCardCollapsed {
            isMacStatusCardCollapsed = true
        } else if translation > 24, isMacStatusCardCollapsed {
            isMacStatusCardCollapsed = false
        }
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
            case .providerTransfer:
                scanError = String(localized: "ios_mac_relay_scan_provider_transfer_unsupported")
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func cancelLockConfirmation() {
        guard !isSendingLockScreenCommand else { return }
        isShowingLockConfirmation = false
        lockScreenTargetPeer = nil
    }
}

private struct MacRelayListTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
