import DevBarCore
import Foundation
import SwiftUI

struct IOSHomeAssistantDashboardView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themeTokens) private var theme
    @StateObject private var model = IOSHomeAssistantViewModel()
    @State private var selectedAccessory: HomeAssistantAccessory?
    @State private var editingAccessory: HomeAssistantAccessory?
    @State private var selectedStatusCategory: IOSHomeAssistantStatusCategory?
    @State private var confirmation: HomeAssistantConfirmation?
    @State private var aiPreview: HomeAssistantAIPreview?
    @State private var showsSettings = false
    @State private var showsAIPrivacyConfirmation = false
    @State private var roomOrderRequest: HomeAssistantRoomOrderRequest?
    @State private var hiddenDevicesRequest: HomeAssistantHiddenDevicesRequest?
    @State private var pendingOrganizationRequest: HomeAssistantPendingOrganizationRequest?
    @State private var wallpaperPickerRequest: HomeAssistantWallpaperPickerRequest?
    @State private var isEditingHomeView = false
    @State private var draggedAccessoryID: String?
    @State private var titleCollapseProgress: CGFloat = 0

    var body: some View {
        Group {
            if model.isConfigured {
                dashboard
            } else {
                IOSHomeAssistantOnboardingView(model: model, isSettings: false)
            }
        }
        .navigationTitle(model.isConfigured ? "" : "Home Assistant")
        .toolbarTitleDisplayMode(.inline)
        .homeAssistantTransparentNavigationBar()
        .toolbar {
            if model.isConfigured {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        collapsedDashboardTitle
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        collapsedDashboardTitle
                    }
                }

                if isEditingHomeView {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingHomeView = false
                                draggedAccessoryID = nil
                            }
                        } label: {
                            Image(systemName: "checkmark")
                                .homeAssistantToolbarIcon(theme)
                        }
                        .accessibilityLabel("完成编辑家庭视图")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        HomeAssistantDashboardMenu(
                            canReorderRooms: model.rooms.count >= 2,
                            hiddenAccessoryCount: model.hiddenAccessories.count,
                            pendingAccessoryCount: model.pendingAccessories.count,
                            aiAnalysisEnabled: model.settings.aiAnalysisEnabled,
                            isAnalyzing: model.isAnalyzing,
                            perform: performDashboardMenuAction
                        )
                        .equatable()
                    }
                }
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.resume() }
            } else if phase == .background {
                model.flushSnapshotCache()
            }
        }
        .fullScreenCover(item: $selectedAccessory) { accessory in
            IOSHomeAssistantAccessoryControlView(model: model, accessory: accessory)
                .presentationBackground(.clear)
        }
        .sheet(item: $editingAccessory) { accessory in
            NavigationStack {
                IOSHomeAssistantDeviceEditorView(model: model, accessory: accessory)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                IOSHomeAssistantOnboardingView(model: model, isSettings: true)
            }
        }
        .sheet(item: $wallpaperPickerRequest) { _ in
            NavigationStack {
                IOSHomeAssistantWallpaperPickerView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $roomOrderRequest) { _ in
            NavigationStack {
                IOSHomeAssistantRoomOrderView(model: model)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $hiddenDevicesRequest) { _ in
            NavigationStack {
                IOSHomeAssistantHiddenDevicesView(model: model)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $pendingOrganizationRequest) { _ in
            NavigationStack {
                IOSHomeAssistantPendingOrganizationView(model: model)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $aiPreview) { preview in
            NavigationStack {
                IOSHomeAssistantAIPreviewView(
                    suggestion: preview.suggestion,
                    apply: {
                        model.applyPendingLayoutSuggestion()
                        aiPreview = nil
                    },
                    cancel: {
                        model.discardPendingLayoutSuggestion()
                        aiPreview = nil
                    }
                )
            }
        }
        .alert(item: $confirmation) { item in
            Alert(
                title: Text("确认操作"),
                message: Text("此操作可能触发门锁、场景、脚本或自动化。确定继续吗？"),
                primaryButton: .destructive(Text("继续")) {
                    Task { try? await model.execute(item.call) }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Home Assistant", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "允许发送脱敏拓扑给 Hermes？",
            isPresented: $showsAIPrivacyConfirmation,
            titleVisibility: .visible
        ) {
            Button("继续分析") { runAIAnalysis() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将发送房间/实体显示名、实体 ID、Domain、Device Class 和能力枚举；不会发送 Home Assistant 地址、Token、坐标、实时传感器值或控制参数。")
        }
        .accessibilityIdentifier("ios.homeAssistant.screen")
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text(dashboardTitle)
                    .font(theme.appFont.font(.largeTitle, weight: .bold))
                    .foregroundStyle(theme.isGeek ? theme.textPrimary : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(1 - titleCollapseProgress * 0.16, anchor: .leading)
                    .opacity(1 - titleCollapseProgress)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: HomeAssistantTitleOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("homeAssistantDashboardScroll")).minY
                            )
                        }
                    }
                    .accessibilityAddTraits(.isHeader)

                IOSHomeAssistantStatusStrip(
                    items: statusItems,
                    selection: selectedStatusCategory,
                    theme: theme,
                    select: selectStatusCategory
                )

                if model.isLoading, model.snapshot == nil {
                    ProgressView("正在读取家庭设备…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if model.allVisibleAccessories.isEmpty {
                    Group {
                        if model.allVisibleAccessories.isEmpty, !model.hiddenAccessories.isEmpty {
                            ContentUnavailableView(
                                "所有设备均已隐藏",
                                systemImage: "eye.slash",
                                description: Text("可从右上角 … → 隐藏的设备中恢复")
                            )
                        } else {
                            ContentUnavailableView(
                                "没有可显示的设备",
                                systemImage: "house",
                                description: Text("请检查 Home Assistant 的区域和实体配置")
                            )
                        }
                    }
                    .frame(minHeight: 220)
                } else if selectedStatusCategory == nil, !hasDefaultDashboardAccessories {
                    ContentUnavailableView(
                        "首页没有可控制设备",
                        systemImage: "switch.2",
                        description: Text("传感器仍可通过上方状态或房间详情查看")
                    )
                    .foregroundStyle(.white)
                    .frame(minHeight: 220)
                } else if selectedStatusCategory != nil, !hasFilteredAccessories {
                    ContentUnavailableView(
                        "没有相关设备",
                        systemImage: selectedStatusCategory == .lights ? "lightbulb.slash" : "line.3.horizontal.decrease.circle",
                        description: Text("再次点击已选胶囊可返回全部房间")
                    )
                    .foregroundStyle(.white)
                    .frame(minHeight: 220)
                } else {
                    ForEach(model.rooms) { room in
                        roomSection(room)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .coordinateSpace(name: "homeAssistantDashboardScroll")
        .modifier(HomeAssistantTitleCollapseModifier(progress: $titleCollapseProgress))
        .background {
            IOSHomeAssistantPageBackground(theme: theme)
                .ignoresSafeArea()
        }
        .refreshable { await model.refresh() }
    }

    private var dashboardTitle: String {
        selectedStatusCategory?.title ?? model.homeDisplayName
    }

    private var collapsedDashboardTitle: some View {
        Text(dashboardTitle)
            .font(theme.appFont.font(.headline, weight: .semibold))
            .foregroundStyle(theme.isGeek ? theme.textPrimary : Color.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(titleCollapseProgress)
            .accessibilityHidden(titleCollapseProgress < 0.9)
    }

    @ViewBuilder
    private func roomSection(_ room: HomeAssistantRoom) -> some View {
        let accessories = displayedAccessories(in: room)
        if !accessories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    NavigationLink {
                        IOSHomeAssistantRoomView(model: model, room: room)
                    } label: {
                        HStack(spacing: 7) {
                            Text(room.name)
                                .font(theme.appFont.font(.title2, weight: .bold))
                                .foregroundStyle(theme.isGeek ? theme.textPrimary : Color.white)
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(theme.isGeek ? theme.textTertiary : Color.white.opacity(0.72))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditingHomeView)
                    Spacer()
                    if isEditingHomeView {
                        Text("拖动卡片调整位置")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.isGeek ? theme.textTertiary : Color.white.opacity(0.66))
                    }
                }

                IOSHomeAssistantRoomGrid(
                    accessories: accessories,
                    pendingEntityIDs: model.pendingEntityIDs,
                    controlsEnabled: model.canControlDevices,
                    isEditing: isEditingHomeView,
                    theme: theme,
                    draggedAccessoryID: $draggedAccessoryID,
                    roomID: room.id,
                    size: model.cardSize,
                    semanticState: model.semanticState,
                    open: { selectedAccessory = $0 },
                    edit: { editingAccessory = $0 },
                    quickAction: performQuickAction,
                    toggleSize: model.toggleCardSize,
                    hide: model.hideDevice,
                    beginLayoutEditing: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingHomeView = true
                        }
                    },
                    move: model.moveAccessory
                )
            }
        }
    }

    private var statusItems: [IOSHomeAssistantStatusItem] {
        let accessories = model.allVisibleAccessories
        var seenEntityIDs = Set<String>()
        let entities = accessories
            .flatMap(\.entities)
            .filter { seenEntityIDs.insert($0.entityID).inserted }

        var temperatures: [Double] = []
        for entity in entities where entity.isAvailable {
            if entity.deviceClass == "temperature", let value = Double(entity.state.state) {
                temperatures.append(value)
            } else if entity.domain == "climate",
                      let value = entity.state.attributes["current_temperature"]?.doubleValue {
                temperatures.append(value)
            }
        }

        let lights = accessories.filter { $0.kind == .light }
        let activeLights = lights.filter { model.semanticState(for: $0).power == .on }.count

        var securityWarnings = Set<String>()
        var activeActivities = Set<String>()
        for accessory in accessories {
            let semanticState = model.semanticState(for: accessory)
            securityWarnings.formUnion(semanticState.alerts.map(\.entityID))
            if let activity = semanticState.activity, ![.idle, .unknown].contains(activity) {
                activeActivities.insert(accessory.id)
            }
        }
        for entity in entities where entity.isAvailable {
            if isSecurityWarning(entity) { securityWarnings.insert(entity.entityID) }
            if entity.domain == "binary_sensor",
               ["motion", "occupancy", "presence", "moving"].contains(entity.deviceClass ?? ""),
               entity.state.state == "on" {
                activeActivities.insert(entity.entityID)
            }
        }

        return [
            IOSHomeAssistantStatusItem(
                category: .climate,
                title: "温控",
                detail: temperatureRangeText(temperatures),
                systemImage: "thermometer.medium",
                accent: .cyan
            ),
            IOSHomeAssistantStatusItem(
                category: .lights,
                title: "灯",
                detail: lights.isEmpty ? "暂无灯具" : (activeLights == 0 ? "全部关闭" : "\(activeLights) 盏开启"),
                systemImage: "lightbulb.fill",
                accent: .yellow
            ),
            IOSHomeAssistantStatusItem(
                category: .security,
                title: "安全",
                detail: securityWarnings.isEmpty ? "无提醒" : "\(securityWarnings.count) 项提醒",
                systemImage: "lock.fill",
                accent: .mint
            ),
            IOSHomeAssistantStatusItem(
                category: .activity,
                title: "活动",
                detail: activeActivities.isEmpty ? "无活动" : "\(activeActivities.count) 个活动",
                systemImage: "figure.walk.motion",
                accent: theme.brandPrimary
            ),
        ]
    }

    private var hasFilteredAccessories: Bool {
        model.rooms.contains { !displayedAccessories(in: $0).isEmpty }
    }

    private var hasDefaultDashboardAccessories: Bool {
        model.rooms.contains { room in
            model.accessories(inRoom: room.id).contains {
                HomeAssistantDashboardPresentationPolicy.isShownByDefault($0.kind)
            }
        }
    }

    private func displayedAccessories(in room: HomeAssistantRoom) -> [HomeAssistantAccessory] {
        let accessories = model.accessories(inRoom: room.id)
        guard let selectedStatusCategory else {
            return accessories.filter {
                HomeAssistantDashboardPresentationPolicy.isShownByDefault($0.kind)
            }
        }
        return accessories.filter { matches($0, category: selectedStatusCategory) }
    }

    private func matches(
        _ accessory: HomeAssistantAccessory,
        category: IOSHomeAssistantStatusCategory
    ) -> Bool {
        switch category {
        case .climate:
            if [.airConditioner, .airPurifier, .fan, .sensorGroup].contains(accessory.kind) {
                return accessory.entities.contains {
                    ["temperature", "humidity", "aqi", "pm1", "pm10", "pm25"].contains($0.deviceClass ?? "")
                        || $0.domain == "climate"
                } || [.airConditioner, .airPurifier].contains(accessory.kind)
            }
            return false
        case .lights:
            return accessory.kind == .light
        case .security:
            return accessory.entities.contains { entity in
                if entity.domain == "lock" { return true }
                guard entity.domain == "binary_sensor" else { return false }
                return [
                    "door", "window", "garage_door", "opening", "lock", "smoke",
                    "moisture", "gas", "problem", "safety", "tamper",
                ].contains(entity.deviceClass ?? "")
            }
        case .activity:
            if accessory.entities(for: .activity).isEmpty == false { return true }
            return accessory.entities.contains {
                $0.domain == "binary_sensor"
                    && ["motion", "occupancy", "presence", "moving"].contains($0.deviceClass ?? "")
            }
        }
    }

    private func selectStatusCategory(_ category: IOSHomeAssistantStatusCategory) {
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedStatusCategory = selectedStatusCategory == category ? nil : category
        }
    }

    private func temperatureRangeText(_ values: [Double]) -> String {
        guard let minimum = values.min(), let maximum = values.max() else { return "暂无数据" }
        if abs(maximum - minimum) < 0.05 { return String(format: "%.1f°", minimum) }
        return String(format: "%.1f–%.1f°", minimum, maximum)
    }

    private func isSecurityWarning(_ entity: HomeAssistantEntity) -> Bool {
        if entity.domain == "lock" { return entity.state.state != "locked" }
        guard entity.domain == "binary_sensor", entity.state.state == "on" else { return false }
        return [
            "door", "window", "garage_door", "opening", "lock", "smoke", "moisture",
            "gas", "problem", "safety", "tamper",
        ].contains(entity.deviceClass ?? "")
    }

    private func performQuickAction(_ accessory: HomeAssistantAccessory) {
        guard let entity = accessory.quickControlEntity else { return }
        Task {
            do {
                if let call = try await model.performQuickAction(on: entity) {
                    confirmation = HomeAssistantConfirmation(call: call)
                }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func runAIAnalysis() {
        Task {
            await model.analyzeWithHermes(
                settings: appViewModel.hermesSettings,
                apiKey: appViewModel.hermesAPIKey
            )
            if let suggestion = model.pendingLayoutSuggestion {
                aiPreview = HomeAssistantAIPreview(suggestion: suggestion)
            }
        }
    }

    private func performDashboardMenuAction(_ action: HomeAssistantDashboardMenuAction) {
        switch action {
        case .refresh:
            Task { await model.refresh() }
        case .beginEditing:
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditingHomeView = true
            }
        case .settings:
            showsSettings = true
        case .wallpaper:
            wallpaperPickerRequest = HomeAssistantWallpaperPickerRequest()
        case .roomOrder:
            roomOrderRequest = HomeAssistantRoomOrderRequest()
        case .hiddenDevices:
            hiddenDevicesRequest = HomeAssistantHiddenDevicesRequest()
        case .pendingOrganization:
            pendingOrganizationRequest = HomeAssistantPendingOrganizationRequest()
        case .aiAnalysis:
            showsAIPrivacyConfirmation = true
        case .resetDashboardLayout:
            model.resetDashboardLayout()
        case .resetLayoutSuggestion:
            model.resetLayoutSuggestion()
        }
    }

}

private enum HomeAssistantDashboardMenuAction {
    case refresh
    case beginEditing
    case settings
    case wallpaper
    case roomOrder
    case hiddenDevices
    case pendingOrganization
    case aiAnalysis
    case resetDashboardLayout
    case resetLayoutSuggestion
}

private struct HomeAssistantDashboardMenu: View, Equatable {
    @Environment(\.themeTokens) private var theme

    let canReorderRooms: Bool
    let hiddenAccessoryCount: Int
    let pendingAccessoryCount: Int
    let aiAnalysisEnabled: Bool
    let isAnalyzing: Bool
    let perform: (HomeAssistantDashboardMenuAction) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.canReorderRooms == rhs.canReorderRooms
            && lhs.hiddenAccessoryCount == rhs.hiddenAccessoryCount
            && lhs.pendingAccessoryCount == rhs.pendingAccessoryCount
            && lhs.aiAnalysisEnabled == rhs.aiAnalysisEnabled
            && lhs.isAnalyzing == rhs.isAnalyzing
    }

    var body: some View {
        Menu {
            Button { perform(.refresh) } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            Button { perform(.beginEditing) } label: {
                Label("编辑家庭视图", systemImage: "square.grid.2x2")
            }
            Button { perform(.settings) } label: {
                Label("设置", systemImage: "gearshape")
            }
            Button { perform(.wallpaper) } label: {
                Label("家庭墙纸", systemImage: "photo.on.rectangle.angled")
            }
            Button { perform(.roomOrder) } label: {
                Label("重新排序区块", systemImage: "line.3.horizontal")
            }
            .disabled(!canReorderRooms)
            Button { perform(.hiddenDevices) } label: {
                Label(
                    hiddenAccessoryCount == 0
                        ? "隐藏的设备"
                        : "隐藏的设备（\(hiddenAccessoryCount)）",
                    systemImage: "eye.slash"
                )
            }
            if pendingAccessoryCount > 0 {
                Button { perform(.pendingOrganization) } label: {
                    Label(
                        "待整理的设备（\(pendingAccessoryCount)）",
                        systemImage: "exclamationmark.circle"
                    )
                }
            }
            if aiAnalysisEnabled {
                Button { perform(.aiAnalysis) } label: {
                    Label(isAnalyzing ? "分析中…" : "AI 整理", systemImage: "sparkles")
                }
                .disabled(isAnalyzing)
            }
            Divider()
            Button { perform(.resetDashboardLayout) } label: {
                Label("恢复默认卡片布局", systemImage: "rectangle.2.swap")
            }
            Button { perform(.resetLayoutSuggestion) } label: {
                Label("恢复默认区块顺序", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .homeAssistantToolbarIcon(theme)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private extension View {
    func homeAssistantToolbarIcon(_ theme: IOSThemeTokens) -> some View {
        font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.isGeek ? theme.textSecondary : Color.white.opacity(0.92))
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }
}

private struct HomeAssistantTitleOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HomeAssistantTitleCollapseModifier: ViewModifier {
    @Binding var progress: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
            } action: { _, offset in
                progress = min(offset / 52, 1)
            }
        } else {
            content.onPreferenceChange(HomeAssistantTitleOffsetPreferenceKey.self) { offset in
                progress = min(max(-offset / 52, 0), 1)
            }
        }
    }
}

private struct HomeAssistantConfirmation: Identifiable {
    let id = UUID()
    let call: HomeAssistantServiceCall
}

private struct HomeAssistantAIPreview: Identifiable {
    let id = UUID()
    let suggestion: HomeAssistantLayoutSuggestion
}

private struct HomeAssistantRoomOrderRequest: Identifiable {
    let id = UUID()
}

private struct HomeAssistantHiddenDevicesRequest: Identifiable {
    let id = UUID()
}

private struct HomeAssistantPendingOrganizationRequest: Identifiable {
    let id = UUID()
}

private struct HomeAssistantWallpaperPickerRequest: Identifiable {
    let id = UUID()
}

private struct IOSHomeAssistantAIPreviewView: View {
    @Environment(\.themeTokens) private var theme
    let suggestion: HomeAssistantLayoutSuggestion
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        List {
            Section("变化摘要") {
                Label("重点展示 \(suggestion.featuredEntityIDs.count) 个实体", systemImage: "star")
                Label("调整 \(suggestion.roomOrder.count) 个房间的顺序", systemImage: "arrow.up.arrow.down")
                Label("设置 \(suggestion.aliases.count) 个友好别名", systemImage: "character.cursor.ibeam")
            }
            if !suggestion.aliases.isEmpty {
                Section("别名") {
                    ForEach(suggestion.aliases.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.aliases[key] ?? key)
                            Text(key).font(.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
            if !suggestion.suggestions.isEmpty {
                Section("建议") {
                    ForEach(suggestion.suggestions, id: \.self) { Text($0) }
                }
            }
            Section {
                Button("应用到 DevBar 控制台", action: apply)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("取消", role: .cancel, action: cancel)
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("只修改 DevBar 的展示顺序和别名，不会回写 Home Assistant，也不会执行设备控制。")
            }
        }
        .navigationTitle("AI 整理预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}
